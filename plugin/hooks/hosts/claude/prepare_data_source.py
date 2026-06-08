import json
import time
from pathlib import Path

from .model_pricing import COMPACTION_DIR, STATE_JSON, USAGE_DIR

RETRY_DELAYS = (0.1, 0.15, 0.2, 0.25)


def _derive_project(cwd: str) -> str:
    """Return project name from Claude hook cwd, normalizing worktree paths."""
    if not cwd:
        cwd = str(Path.cwd())
    if "/.claude/worktrees/" in cwd:
        cwd = cwd[:cwd.index("/.claude/worktrees/")]
    return Path(cwd).name or "unknown"


def _record_compaction(session_id: str, ctx_tokens: int) -> None:
    """Persist latest compaction token counts and result when pre-state exists."""
    COMPACTION_DIR.mkdir(parents=True, exist_ok=True)
    (COMPACTION_DIR / "last-stop.json").write_text(
        json.dumps({"session_id": session_id, "context_tokens": ctx_tokens})
    )
    pre_file = COMPACTION_DIR / "pre.json"
    if pre_file.exists():
        try:
            pre = json.loads(pre_file.read_text())
            if pre.get("session_id") == session_id:
                tokens_before = pre.get("tokens_before", 0)
                (COMPACTION_DIR / "result.json").write_text(json.dumps({
                    "session_id":    session_id,
                    "tokens_before": tokens_before,
                    "tokens_after":  ctx_tokens,
                    "reduced":       tokens_before - ctx_tokens,
                }))
                pre_file.unlink()
        except Exception:
            pass


def _resolve_subagent_transcript(transcript: str, agent_id: str):
    """Find matching subagent transcript for an agent id near parent transcript."""
    transcript_path = Path(transcript)
    parent_dir = transcript_path.parent
    parent_name = transcript_path.name

    direct_paths = [
        parent_dir / "subagents" / f"agent-{agent_id}.jsonl",
        parent_dir / transcript_path.stem / "subagents" / f"agent-{agent_id}.jsonl",
    ]
    for direct in direct_paths:
        if direct.exists():
            return str(direct)

    if transcript_path.exists() and parent_name == f"agent-{agent_id}.jsonl":
        return str(transcript_path)

    candidates = sorted(
        list(parent_dir.glob("*.jsonl"))
        + list((parent_dir / "subagents").glob("agent-*.jsonl"))
        + list((parent_dir / transcript_path.stem / "subagents").glob("agent-*.jsonl")),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    for c in candidates:
        if c.name == parent_name:
            continue
        try:
            if agent_id in c.read_text():
                return str(c)
        except Exception:
            continue
    return None


def _resolve_subagent_transcript_with_retry(transcript: str, agent_id: str):
    """Retry subagent transcript lookup while Claude flushes stop-hook files."""
    for attempt in range(len(RETRY_DELAYS) + 1):
        found = _resolve_subagent_transcript(transcript, agent_id)
        if found:
            return found
        if attempt < len(RETRY_DELAYS):
            time.sleep(RETRY_DELAYS[attempt])
    return None


def _read_transcript_totals(transcript: str):
    """Read cumulative token totals and model name from a Claude transcript."""
    total_input = total_output = total_cache_write_5m = total_cache_write_1h = total_cache_read = 0
    transcript_model = None
    with open(transcript, encoding="utf-8") as f:
        for line in f:
            try:
                d = json.loads(line)
                msg = d.get("message") or {}
                if msg.get("model"):
                    transcript_model = msg["model"]
                usage = msg.get("usage")
                if not usage:
                    continue
                total_input  += usage.get("input_tokens", 0)
                total_output += usage.get("output_tokens", 0)
                total_cache_read += usage.get("cache_read_input_tokens", 0)
                cc = usage.get("cache_creation") or {}
                if cc:
                    total_cache_write_5m += cc.get("ephemeral_5m_input_tokens", 0)
                    total_cache_write_1h += cc.get("ephemeral_1h_input_tokens", 0)
                else:
                    # Legacy transcript without per-TTL breakdown — treat as 5m
                    total_cache_write_5m += usage.get("cache_creation_input_tokens", 0)
            except Exception:
                pass
    return total_input, total_output, total_cache_write_5m, total_cache_write_1h, total_cache_read, transcript_model


def _compute_deltas(totals, prev: dict):
    """Convert cumulative transcript totals into incremental usage deltas."""
    total_input, total_output, total_cache_write_5m, total_cache_write_1h, total_cache_read, _ = totals

    prev_5m = prev.get("cache_write_5m") if "cache_write_5m" in prev else prev.get("cache_write", 0)
    prev_1h = prev.get("cache_write_1h", 0)

    return {
        "input":          total_input - prev.get("input", 0),
        "output":         total_output - prev.get("output", 0),
        "cache_write_5m": total_cache_write_5m - prev_5m,
        "cache_write_1h": total_cache_write_1h - prev_1h,
        "cache_read":     total_cache_read - prev.get("cache_read", 0),
    }


def _read_transcript_totals_with_retry(transcript: str, prev: dict):
    """Retry transcript reads until fresh input or output deltas appear."""
    for attempt in range(len(RETRY_DELAYS) + 1):
        if transcript and Path(transcript).exists():
            totals = _read_transcript_totals(transcript)
            deltas = _compute_deltas(totals, prev)
            if deltas["input"] != 0 or deltas["output"] != 0:
                return totals, deltas
        if attempt < len(RETRY_DELAYS):
            time.sleep(RETRY_DELAYS[attempt])
    return None


def prepare_data_source(stdin_data: dict):
    """Build normalized Claude token usage data from stop-hook stdin."""
    session_id = stdin_data.get("session_id") or "unknown"
    transcript = stdin_data.get("transcript_path") or ""
    model_raw  = stdin_data.get("model") or {}
    model      = model_raw if isinstance(model_raw, str) else (model_raw.get("display_name") or "unknown")
    agent_id   = stdin_data.get("agent_id")
    agent_type = stdin_data.get("agent_type")

    project = _derive_project(stdin_data.get("cwd") or "")

    cw_usage = (stdin_data.get("context_window") or {}).get("current_usage") or {}
    ctx_tokens = (cw_usage.get("input_tokens", 0)
                  + cw_usage.get("cache_read_input_tokens", 0)
                  + cw_usage.get("cache_creation_input_tokens", 0))
    _record_compaction(session_id, ctx_tokens)

    if agent_id and transcript:
        found = _resolve_subagent_transcript_with_retry(transcript, agent_id)
        if found:
            transcript = found
        else:
            return None

    USAGE_DIR.mkdir(parents=True, exist_ok=True)
    state_key = f"{session_id}:{agent_id}" if agent_id else session_id
    state, prev = {}, {}
    if STATE_JSON.exists():
        try:
            state = json.loads(STATE_JSON.read_text())
            prev  = state.get(state_key) or {}
        except Exception:
            pass

    read_result = _read_transcript_totals_with_retry(transcript, prev)
    if read_result is None:
        return None

    totals, deltas = read_result
    total_input, total_output, total_cache_write_5m, total_cache_write_1h, total_cache_read, transcript_model = totals

    state[state_key] = {
        "input":          total_input,
        "output":         total_output,
        "cache_write_5m": total_cache_write_5m,
        "cache_write_1h": total_cache_write_1h,
        "cache_read":     total_cache_read,
    }
    STATE_JSON.write_text(json.dumps(state))

    return {
        "session_id": session_id,
        "model":      transcript_model or model,
        "project":    project,
        "agent_id":   agent_id,
        "agent_type": agent_type,
        "deltas": {
            "input":          deltas["input"],
            "output":         deltas["output"],
            "cache_write_5m": deltas["cache_write_5m"],
            "cache_write_1h": deltas["cache_write_1h"],
            "cache_read":     deltas["cache_read"],
        },
        "_prev": prev,
    }
