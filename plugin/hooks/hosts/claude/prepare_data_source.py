import json
from pathlib import Path

from .model_pricing import COMPACTION_DIR, STATE_JSON, USAGE_DIR


def _derive_project(cwd: str) -> str:
    if not cwd:
        cwd = str(Path.cwd())
    if "/.claude/worktrees/" in cwd:
        cwd = cwd[:cwd.index("/.claude/worktrees/")]
    return Path(cwd).name or "unknown"


def _record_compaction(session_id: str, ctx_tokens: int) -> None:
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
    parent_dir = Path(transcript).parent
    parent_name = Path(transcript).name
    candidates = sorted(parent_dir.glob("*.jsonl"),
                        key=lambda p: p.stat().st_mtime, reverse=True)
    for c in candidates:
        if c.name == parent_name:
            continue
        try:
            if agent_id in c.read_text():
                return str(c)
        except Exception:
            continue
    return None


def _read_transcript_totals(transcript: str):
    total_input = total_output = total_cache_write = total_cache_read = 0
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
                total_input       += usage.get("input_tokens", 0)
                total_output      += usage.get("output_tokens", 0)
                total_cache_write += usage.get("cache_creation_input_tokens", 0)
                total_cache_read  += usage.get("cache_read_input_tokens", 0)
            except Exception:
                pass
    return total_input, total_output, total_cache_write, total_cache_read, transcript_model


def prepare_data_source(stdin_data: dict):
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
        found = _resolve_subagent_transcript(transcript, agent_id)
        if found:
            transcript = found
        else:
            return None

    if not transcript or not Path(transcript).exists():
        return None

    total_input, total_output, total_cache_write, total_cache_read, transcript_model = \
        _read_transcript_totals(transcript)

    USAGE_DIR.mkdir(parents=True, exist_ok=True)
    state_key = f"{session_id}:{agent_id}" if agent_id else session_id
    state, prev = {}, {}
    if STATE_JSON.exists():
        try:
            state = json.loads(STATE_JSON.read_text())
            prev  = state.get(state_key) or {}
        except Exception:
            pass

    delta_input       = total_input       - prev.get("input", 0)
    delta_output      = total_output      - prev.get("output", 0)
    delta_cache_write = total_cache_write - prev.get("cache_write", 0)
    delta_cache_read  = total_cache_read  - prev.get("cache_read", 0)

    if delta_input == 0 and delta_output == 0:
        return None

    state[state_key] = {
        "input":       total_input,
        "output":      total_output,
        "cache_write": total_cache_write,
        "cache_read":  total_cache_read,
    }
    STATE_JSON.write_text(json.dumps(state))

    return {
        "session_id": session_id,
        "model":      transcript_model or model,
        "project":    project,
        "agent_id":   agent_id,
        "agent_type": agent_type,
        "deltas": {
            "input":       delta_input,
            "output":      delta_output,
            "cache_write": delta_cache_write,
            "cache_read":  delta_cache_read,
        },
        "_prev": prev,
    }
