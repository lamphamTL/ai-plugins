#!/usr/bin/env python3
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

data = json.loads(sys.stdin.read())

session_id = data.get("session_id") or "unknown"
transcript  = data.get("transcript_path") or ""
model_raw   = data.get("model") or {}
model       = model_raw if isinstance(model_raw, str) else (model_raw.get("display_name") or "unknown")
agent_id    = data.get("agent_id")
agent_type  = data.get("agent_type")

cwd = data.get("cwd") or ""
if not cwd:
    cwd = str(Path.cwd())
if "/.claude/worktrees/" in cwd:
    cwd = cwd[:cwd.index("/.claude/worktrees/")]
project = Path(cwd).name or "unknown"

# ── Compaction tracking ───────────────────────────────────────────────────────
cw_usage    = (data.get("context_window") or {}).get("current_usage") or {}
in_tok      = cw_usage.get("input_tokens", 0)
cache_r     = cw_usage.get("cache_read_input_tokens", 0)
cache_w     = cw_usage.get("cache_creation_input_tokens", 0)
ctx_tokens  = in_tok + cache_r + cache_w

compaction_dir = Path.home() / ".claude/compaction"
compaction_dir.mkdir(parents=True, exist_ok=True)

(compaction_dir / "last-stop.json").write_text(
    json.dumps({"session_id": session_id, "context_tokens": ctx_tokens})
)

pre_file = compaction_dir / "pre.json"
if pre_file.exists():
    try:
        pre = json.loads(pre_file.read_text())
        if pre.get("session_id") == session_id:
            tokens_before = pre.get("tokens_before", 0)
            reduced = tokens_before - ctx_tokens
            (compaction_dir / "result.json").write_text(json.dumps({
                "session_id":    session_id,
                "tokens_before": tokens_before,
                "tokens_after":  ctx_tokens,
                "reduced":       reduced,
            }))
            pre_file.unlink()
    except Exception:
        pass

# Subagent Stop hooks receive the PARENT transcript path. Redirect to the
# subagent's own transcript by scanning sibling jsonl files for the agent_id.
if agent_id and transcript:
    parent_dir = Path(transcript).parent
    parent_name = Path(transcript).name
    found = None
    candidates = sorted(parent_dir.glob("*.jsonl"),
                        key=lambda p: p.stat().st_mtime, reverse=True)
    for c in candidates:
        if c.name == parent_name:
            continue
        try:
            if agent_id in c.read_text():
                found = str(c)
                break
        except Exception:
            continue
    if found:
        transcript = found
    else:
        # Subagent transcript not located — drop the event instead of
        # double-logging parent cumulative.
        sys.exit(0)

if not transcript or not Path(transcript).exists():
    sys.exit(0)

# ── Accumulate cumulative session totals from transcript ──────────────────────
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

# ── Compute incremental delta since last Stop ─────────────────────────────────
usage_dir  = Path.home() / ".claude/token-usage"
usage_dir.mkdir(parents=True, exist_ok=True)
state_file = usage_dir / "state.json"

prev_input = prev_output = prev_cache_write = prev_cache_read = 0
state = {}
state_key = f"{session_id}:{agent_id}" if agent_id else session_id

if state_file.exists():
    try:
        state = json.loads(state_file.read_text())
        prev  = state.get(state_key) or {}
        prev_input       = prev.get("input", 0)
        prev_output      = prev.get("output", 0)
        prev_cache_write = prev.get("cache_write", 0)
        prev_cache_read  = prev.get("cache_read", 0)
    except Exception:
        pass

delta_input       = total_input       - prev_input
delta_output      = total_output      - prev_output
delta_cache_write = total_cache_write - prev_cache_write
delta_cache_read  = total_cache_read  - prev_cache_read

if delta_input == 0 and delta_output == 0:
    sys.exit(0)

# ── Persist updated cumulative totals ─────────────────────────────────────────
state[state_key] = {
    "input":       total_input,
    "output":      total_output,
    "cache_write": total_cache_write,
    "cache_read":  total_cache_read,
}
state_file.write_text(json.dumps(state))

# ── Cost (USD/million: input $3, output $15, cache_write $3.75, cache_read $0.30)
cost = round(
    (delta_input * 3 + delta_output * 15 + delta_cache_write * 3.75 + delta_cache_read * 0.30)
    / 1_000_000,
    6,
)

# ── Append JSONL entry ────────────────────────────────────────────────────────
model = transcript_model or model
ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
entry = {
    "ts":         ts,
    "session_id": session_id,
    "model":      model,
    "project":    project,
    "tokens": {
        "input":       delta_input,
        "output":      delta_output,
        "cache_write": delta_cache_write,
        "cache_read":  delta_cache_read,
    },
    "cost_usd":   cost,
    "isSubAgent": bool(agent_id),
    "agent_type": agent_type,
}

with open(usage_dir / "usage.jsonl", "a", encoding="utf-8") as f:
    f.write(json.dumps(entry) + "\n")

(usage_dir / "last-turn.json").write_text(json.dumps({
    "session_id": session_id,
    "input":       delta_input,
    "output":      delta_output,
    "cache_write": delta_cache_write,
    "cache_read":  delta_cache_read,
    "cost_usd":    cost,
}))

# ── Alert: cache hit rate dropped below 90% ───────────────────────────────────
delta_total_in = delta_input + delta_cache_read + delta_cache_write
prior_cache    = prev_cache_read + prev_cache_write
if prior_cache > 0 and delta_total_in >= 1000:
    hit_pct = int(delta_cache_read * 100 / delta_total_in)
    if hit_pct < 90:
        safe_project = project.replace("\\", "\\\\").replace('"', '\\"')
        msg = f"Cache hit {hit_pct}% in {safe_project}"
        subprocess.Popen(
            ["osascript", "-e",
             f'display notification "{msg}" with title "Claude Code" subtitle "Low cache hit" sound name "Submarine"'],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
