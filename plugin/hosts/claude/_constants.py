from pathlib import Path

NOTIFICATION_TITLE = "Claude Code"
USAGE_DIR = Path.home() / ".claude/token-usage"
USAGE_JSONL = USAGE_DIR / "usage.jsonl"
STATE_JSON = USAGE_DIR / "state.json"
COMPACTION_DIR = Path.home() / ".claude/compaction"
