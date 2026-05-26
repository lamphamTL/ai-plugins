#!/usr/bin/env python3
import json
import sys
from pathlib import Path

data       = json.loads(sys.stdin.read())
session_id = data.get("session_id") or "unknown"

last_stop = Path.home() / ".claude/compaction/last-stop.json"
if not last_stop.exists():
    sys.exit(0)

try:
    ctx_tokens = json.loads(last_stop.read_text()).get("context_tokens", 0)
except Exception:
    sys.exit(0)

compaction_dir = Path.home() / ".claude/compaction"
compaction_dir.mkdir(parents=True, exist_ok=True)
(compaction_dir / "pre.json").write_text(
    json.dumps({"session_id": session_id, "tokens_before": ctx_tokens})
)
