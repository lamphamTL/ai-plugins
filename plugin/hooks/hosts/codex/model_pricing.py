from pathlib import Path

NOTIFICATION_TITLE = "Codex"
USAGE_DIR = Path.home() / ".codex/token-usage"
USAGE_JSONL = USAGE_DIR / "usage.jsonl"
STATE_JSON = USAGE_DIR / "state.json"

# Credits per million tokens. Multiply by CREDIT_TO_USD for USD.
# Source: https://developers.openai.com/api/docs/pricing
RATES = {
    "gpt-5.5":       {"ri": 125,    "ro": 750,  "rc": 12.50},
    "gpt-5.4":       {"ri": 62.50,  "ro": 375,  "rc": 6.25},
    "gpt-5.4-mini":  {"ri": 18.75,  "ro": 113,  "rc": 1.875},
    "gpt-5.3-codex": {"ri": 43.75,  "ro": 350,  "rc": 4.375},
    "gpt-5.2":       {"ri": 43.75,  "ro": 350,  "rc": 4.375},
}
DEFAULT_RATE = {"ri": 62.50, "ro": 375, "rc": 6.25}
CREDIT_TO_USD = 0.04
