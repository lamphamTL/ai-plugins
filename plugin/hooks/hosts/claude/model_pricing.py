from datetime import date
from pathlib import Path

NOTIFICATION_TITLE = "Claude Code"
USAGE_DIR = Path.home() / ".claude/token-usage"
USAGE_JSONL = USAGE_DIR / "usage.jsonl"
STATE_JSON = USAGE_DIR / "state.json"
COMPACTION_DIR = Path.home() / ".claude/compaction"

# Sonnet 5 introductory pricing ($2/$10) applies through 2026-08-31,
# standard pricing ($3/$15) from 2026-09-01.
# TODO(2026-09): intro period over — drop this condition and inline the
# standard rate ({"ri": 3, "ro": 15, "rw_5m": 3.75, "rw_1h": 6, "rc": 0.30})
# directly into RATES["claude-sonnet-5"].
_SONNET_5 = (
    {"ri": 2, "ro": 10, "rw_5m": 2.50, "rw_1h": 4, "rc": 0.20}
    if date.today() <= date(2026, 8, 31)
    else {"ri": 3, "ro": 15, "rw_5m": 3.75, "rw_1h": 6, "rc": 0.30}
)
# USD per million tokens. rw_5m = 5m-cache write rate (1.25x base input);
# rw_1h = 1h-cache write rate (2x base input).
# Source: https://platform.claude.com/docs/en/about-claude/pricing
RATES = {
    "claude-fable-5":    {"ri": 10,   "ro": 50, "rw_5m": 12.50, "rw_1h": 20,   "rc": 1.00},
    "claude-sonnet-5":   _SONNET_5,
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
