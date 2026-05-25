#!/usr/bin/env python3
"""Shared track-tokens driver. Host picked from sys.argv[1] ('claude' or 'codex')."""
import importlib
import json
import subprocess
import sys
from pathlib import Path

HOSTS = {
    "claude": {
        "module":             "hosts.claude",
        "usage_jsonl":        Path.home() / ".claude/token-usage/usage.jsonl",
        "state_json":         Path.home() / ".claude/token-usage/state.json",
        "notification_title": "Claude Code",
    },
    "codex": {
        "module":             "hosts.codex",
        "usage_jsonl":        Path.home() / ".codex/token-usage/usage.jsonl",
        "state_json":         Path.home() / ".codex/token-usage/state.json",
        "notification_title": "Codex",
    },
}

host = sys.argv[1] if len(sys.argv) > 1 else None
if host not in HOSTS:
    sys.stderr.write(
        f"track-tokens: first arg must be 'claude' or 'codex' (got {host!r})\n"
    )
    sys.exit(1)

cfg = HOSTS[host]
sys.path.insert(0, str(Path(__file__).parent))

def _load(name):
    return getattr(importlib.import_module(f"{cfg['module']}.{name}"), name)

prepare_data_source = _load("prepare_data_source")
compute_spend       = _load("compute_spend")
build_entry         = _load("build_entry")
post_persist        = _load("post_persist")
cache_hit_pct       = _load("cache_hit_pct")

stdin_data = json.loads(sys.stdin.read())
result = prepare_data_source(stdin_data)
if result is None:
    sys.exit(0)

spend = compute_spend(result["model"], result["deltas"])
entry = build_entry(result, spend)

with open(cfg["usage_jsonl"], "a", encoding="utf-8") as f:
    f.write(json.dumps(entry) + "\n")

post_persist(entry, result)

hit = cache_hit_pct(result)
if hit is not None and hit < 90:
    safe_project = result["project"].replace("\\", "\\\\").replace('"', '\\"')
    msg = f"Cache hit {hit}% in {safe_project}"
    subprocess.Popen(
        ["osascript", "-e",
         f'display notification "{msg}" with title "{cfg["notification_title"]}" subtitle "Low cache hit" sound name "Submarine"'],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
