#!/usr/bin/env python3
"""One-time: strip isSubAgent=True rows from usage.jsonl after tracker fix."""
import json, shutil
from pathlib import Path

src = Path.home() / ".claude/token-usage/usage.jsonl"
bak = src.with_suffix(".jsonl.bak")
shutil.copy2(src, bak)
print(f"backup -> {bak}")

kept = dropped = 0
out_lines = []
with open(src) as f:
    for line in f:
        try:
            d = json.loads(line)
        except Exception:
            out_lines.append(line); kept += 1; continue
        if d.get("isSubAgent"):
            dropped += 1
        else:
            out_lines.append(line); kept += 1

src.write_text("".join(out_lines))
print(f"kept {kept}, dropped {dropped}")
