from pathlib import Path

NOTIFICATION_TITLE = "Claude Code"
USAGE_DIR = Path.home() / ".claude/token-usage"
USAGE_JSONL = USAGE_DIR / "usage.jsonl"
STATE_JSON = USAGE_DIR / "state.json"
COMPACTION_DIR = Path.home() / ".claude/compaction"

# USD per million tokens. cache_write uses 5m-cache rate (1.25x base input).
# Source: https://platform.claude.com/docs/en/about-claude/pricing
RATES = {
    "claude-opus-4-7":   {"ri": 5,    "ro": 25, "rw": 6.25,  "rc": 0.50},
    "claude-opus-4-6":   {"ri": 5,    "ro": 25, "rw": 6.25,  "rc": 0.50},
    "claude-opus-4-5":   {"ri": 5,    "ro": 25, "rw": 6.25,  "rc": 0.50},
    "claude-opus-4-1":   {"ri": 15,   "ro": 75, "rw": 18.75, "rc": 1.50},
    "claude-opus-4":     {"ri": 15,   "ro": 75, "rw": 18.75, "rc": 1.50},
    "claude-sonnet-4-6": {"ri": 3,    "ro": 15, "rw": 3.75,  "rc": 0.30},
    "claude-sonnet-4-5": {"ri": 3,    "ro": 15, "rw": 3.75,  "rc": 0.30},
    "claude-sonnet-4":   {"ri": 3,    "ro": 15, "rw": 3.75,  "rc": 0.30},
    "claude-haiku-4-5":  {"ri": 1,    "ro": 5,  "rw": 1.25,  "rc": 0.10},
    "claude-haiku-3-5":  {"ri": 0.80, "ro": 4,  "rw": 1.00,  "rc": 0.08},
}
DEFAULT_RATE = RATES["claude-sonnet-4-6"]
