from pathlib import Path

NOTIFICATION_TITLE = "Claude Code"
USAGE_DIR = Path.home() / ".claude/token-usage"
USAGE_JSONL = USAGE_DIR / "usage.jsonl"
STATE_JSON = USAGE_DIR / "state.json"
COMPACTION_DIR = Path.home() / ".claude/compaction"

# USD per million tokens. rw_5m = 5m-cache write rate (1.25x base input);
# rw_1h = 1h-cache write rate (2x base input).
# Source: https://platform.claude.com/docs/en/about-claude/pricing
RATES = {
    "claude-opus-4-8":   {"ri": 5,    "ro": 25, "rw_5m": 6.25,  "rw_1h": 10,   "rc": 0.50},
    "claude-opus-4-7":   {"ri": 5,    "ro": 25, "rw_5m": 6.25,  "rw_1h": 10,   "rc": 0.50},
    "claude-opus-4-6":   {"ri": 5,    "ro": 25, "rw_5m": 6.25,  "rw_1h": 10,   "rc": 0.50},
    "claude-opus-4-5":   {"ri": 5,    "ro": 25, "rw_5m": 6.25,  "rw_1h": 10,   "rc": 0.50},
    "claude-opus-4-1":   {"ri": 15,   "ro": 75, "rw_5m": 18.75, "rw_1h": 30,   "rc": 1.50},
    "claude-opus-4":     {"ri": 15,   "ro": 75, "rw_5m": 18.75, "rw_1h": 30,   "rc": 1.50},
    "claude-sonnet-4-6": {"ri": 3,    "ro": 15, "rw_5m": 3.75,  "rw_1h": 6,    "rc": 0.30},
    "claude-sonnet-4-5": {"ri": 3,    "ro": 15, "rw_5m": 3.75,  "rw_1h": 6,    "rc": 0.30},
    "claude-sonnet-4":   {"ri": 3,    "ro": 15, "rw_5m": 3.75,  "rw_1h": 6,    "rc": 0.30},
    "claude-haiku-4-5":  {"ri": 1,    "ro": 5,  "rw_5m": 1.25,  "rw_1h": 2,    "rc": 0.10},
    "claude-haiku-3-5":  {"ri": 0.80, "ro": 4,  "rw_5m": 1.00,  "rw_1h": 1.60, "rc": 0.08},
}
DEFAULT_RATE = RATES["claude-sonnet-4-6"]
