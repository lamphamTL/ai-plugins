#!/usr/bin/env python3
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

data       = json.loads(sys.stdin.read())
session_id = data.get("session_id") or "unknown"
transcript = data.get("transcript_path") or ""
model      = data.get("model") or "unknown"
cwd        = data.get("cwd") or os.environ.get("PWD") or ""

# ── Project name ──────────────────────────────────────────────────────────────
def project_from_cwd(cwd: str) -> str:
    if not cwd:
        return "unknown"
    cwd = cwd.rstrip("/")
    home = str(Path.home())
    codex_wt = home + "/.codex/worktrees/"
    if cwd.startswith(codex_wt):
        parts = cwd[len(codex_wt):].split("/", 1)
        return parts[1] if len(parts) == 2 else "unknown"
    junk = [home + "/Library/", home + "/.codex", home + "/Documents/Codex/"]
    if cwd == home or any(cwd.startswith(p) for p in junk):
        return "unknown"
    if "/worktree/" in cwd:
        return os.path.basename(cwd[:cwd.index("/worktree/")])
    base = os.path.basename(cwd)
    if base.startswith("worktree_") or base.startswith("worktree-"):
        parent = os.path.dirname(cwd)
        return os.path.basename(parent) if parent != home else "unknown"
    return base if base else "unknown"

project = project_from_cwd(cwd)

# ── Find transcript if not provided ──────────────────────────────────────────
if not transcript or not Path(transcript).exists():
    today_dir = Path.home() / ".codex/sessions" / datetime.now().strftime("%Y/%m/%d")
    if today_dir.is_dir():
        for f in today_dir.iterdir():
            try:
                if session_id in f.read_text():
                    transcript = str(f)
                    break
            except Exception:
                pass

if not transcript or not Path(transcript).exists():
    sys.exit(0)

# ── Read last token_count totals from transcript ──────────────────────────────
last_count = None
try:
    with open(transcript, encoding="utf-8") as f:
        for line in f:
            try:
                d = json.loads(line)
                p = d.get("payload") or {}
                if d.get("type") == "event_msg" and p.get("type") == "token_count" and p.get("info") is not None:
                    last_count = p["info"]["total_token_usage"]
            except Exception:
                pass
except Exception:
    pass

if not last_count:
    sys.exit(0)

total_input     = last_count.get("input_tokens", 0)
total_output    = last_count.get("output_tokens", 0)
total_cached    = last_count.get("cached_input_tokens", 0)
total_reasoning = last_count.get("reasoning_output_tokens", 0)
total_fresh     = total_input - total_cached

# ── Compute incremental delta since last Stop ─────────────────────────────────
usage_dir  = Path.home() / ".codex/token-usage"
usage_dir.mkdir(parents=True, exist_ok=True)
state_file = usage_dir / "state.json"

prev_input = prev_output = prev_cached = prev_reasoning = 0
state = {}

if state_file.exists():
    try:
        state = json.loads(state_file.read_text())
        prev  = state.get(session_id) or {}
        prev_input     = prev.get("input", 0)
        prev_output    = prev.get("output", 0)
        prev_cached    = prev.get("cached", 0)
        prev_reasoning = prev.get("reasoning", 0)
    except Exception:
        pass

prev_fresh        = prev_input - prev_cached
delta_fresh_input = total_fresh     - prev_fresh
delta_output    = total_output    - prev_output
delta_cached    = total_cached    - prev_cached
delta_reasoning = total_reasoning - prev_reasoning

if delta_fresh_input == 0 and delta_output == 0:
    sys.exit(0)

# ── Persist updated cumulative totals ─────────────────────────────────────────
state[session_id] = {
    "input":     total_input,
    "output":    total_output,
    "cached":    total_cached,
    "reasoning": total_reasoning,
}
state_file.write_text(json.dumps(state))

# ── Credits + cost ─────────────────────────────────────────────────────────────
RATES = {
    "gpt-5.5":       {"ri": 125,    "ro": 750,  "rc": 12.50},
    "gpt-5.4":       {"ri": 62.50,  "ro": 375,  "rc": 6.25},
    "gpt-5.4-mini":  {"ri": 18.75,  "ro": 113,  "rc": 1.875},
    "gpt-5.3-codex": {"ri": 43.75,  "ro": 350,  "rc": 4.375},
    "gpt-5.2":       {"ri": 43.75,  "ro": 350,  "rc": 4.375},
}
DEFAULT_RATE  = {"ri": 62.50, "ro": 375, "rc": 6.25}
CREDIT_TO_USD = 0.04

r       = RATES.get(model.lower(), DEFAULT_RATE)
credits = round((delta_fresh_input * r["ri"] + (delta_output + delta_reasoning) * r["ro"] + delta_cached * r["rc"]) / 1_000_000, 6)
cost    = round(credits * CREDIT_TO_USD, 6)

# ── Append JSONL entry ────────────────────────────────────────────────────────
ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
entry = {
    "ts":         ts,
    "session_id": session_id,
    "model":      model,
    "project":    project,
    "isSubAgent": False,
    "tokens": {
        "input":      delta_fresh_input,
        "output":     delta_output,
        "cache_read": delta_cached,
        "reasoning":  delta_reasoning,
    },
    "credits":  credits,
    "cost_usd": cost,
}

with open(usage_dir / "usage.jsonl", "a", encoding="utf-8") as f:
    f.write(json.dumps(entry) + "\n")

# ── Alert: cache hit rate dropped below 90% ───────────────────────────────────
delta_raw_in = delta_fresh_input + delta_cached
if prev_cached > 0 and delta_raw_in >= 1000:
    hit_pct = int(delta_cached * 100 / delta_raw_in)
    if hit_pct < 90:
        safe_project = project.replace("\\", "\\\\").replace('"', '\\"')
        msg = f"Cache hit {hit_pct}% in {safe_project}"
        subprocess.Popen(
            ["osascript", "-e",
             f'display notification "{msg}" with title "Codex" subtitle "Low cache hit" sound name "Submarine"'],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
