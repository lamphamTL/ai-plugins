#!/usr/bin/env python3
"""Drop stale `<session_id>:<agent_id>` keys from state.json after tracker fix."""
import json
from pathlib import Path

p = Path.home() / ".claude/token-usage/state.json"
s = json.loads(p.read_text())
before = len(s)
s = {k: v for k, v in s.items() if ":" not in k}
p.write_text(json.dumps(s))
print(f"state.json: {before} -> {len(s)} keys")
