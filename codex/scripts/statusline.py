#!/usr/bin/env python3
import json
import sys
from datetime import datetime
from pathlib import Path

data       = json.loads(sys.stdin.read())
session_id = data.get("session_id") or "unknown"
transcript = data.get("transcript_path") or ""
model      = data.get("model") or "unknown"

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

# ── Read last token_count from transcript ─────────────────────────────────────
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

raw_input = last_count.get("input_tokens", 0)
out_tok   = last_count.get("output_tokens", 0)
cached    = last_count.get("cached_input_tokens", 0)
reasoning = last_count.get("reasoning_output_tokens", 0)
in_tok    = raw_input - cached
hit_pct   = int(cached * 100 / raw_input) if raw_input else 0

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
credits = (in_tok * r["ri"] + (out_tok + reasoning) * r["ro"] + cached * r["rc"]) / 1_000_000
cost    = credits * CREDIT_TO_USD

RESET   = "\033[0m"
BOLD    = "\033[1m"
WHITE   = "\033[37m"
CYAN    = "\033[36m"
GREEN   = "\033[32m"
YELLOW  = "\033[33m"
MAGENTA = "\033[35m"
RED     = "\033[31m"
BLUE    = "\033[34m"

cost_color = RED if cost >= 0.50 else (YELLOW if cost >= 0.10 else GREEN)
hit_color  = GREEN if hit_pct >= 80 else (YELLOW if hit_pct >= 50 else RED)

sys.stdout.write(
    f"{BOLD}{CYAN}[{model}]{RESET} "
    f"{BLUE}in{RESET}:{WHITE}{in_tok}{RESET} "
    f"{MAGENTA}out{RESET}:{WHITE}{out_tok}{RESET} "
    f"{CYAN}cache{RESET}:{WHITE}{cached}{RESET} "
    f"{CYAN}hit{RESET}:{hit_color}{hit_pct}%{RESET} "
    f"{YELLOW}reason{RESET}:{WHITE}{reasoning}{RESET} "
    f"{cost_color}credits{RESET}:{WHITE}{credits:.2f}{RESET} "
    f"{cost_color}cost{RESET}:{WHITE}${cost:.4f}{RESET}\n"
)
