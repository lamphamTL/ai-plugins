#!/usr/bin/env python3
import json
import sys
from pathlib import Path

data = json.loads(sys.stdin.read())

model_raw = data.get("model") or {}
model     = model_raw if isinstance(model_raw, str) else (model_raw.get("display_name") or "?")

cw      = (data.get("context_window") or {}).get("current_usage") or {}
in_tok  = cw.get("input_tokens", 0)
out_tok = cw.get("output_tokens", 0)
cache_r = cw.get("cache_read_input_tokens", 0)
cache_w = cw.get("cache_creation_input_tokens", 0)
ctx_pct_raw = float((data.get("context_window") or {}).get("used_percentage") or 0)
ctx_pct = int(round(ctx_pct_raw))

total_in = in_tok + cache_r + cache_w
hit_pct  = int(cache_r * 100 / total_in) if total_in else 0

session_id = data.get("session_id") or ""

# Per-turn cost from track-tokens.py
cost = 0.0
last_turn_file = Path.home() / ".claude/token-usage/last-turn.json"
if last_turn_file.exists():
    try:
        lt = json.loads(last_turn_file.read_text())
        if lt.get("session_id") == session_id:
            cost = lt.get("cost_usd", 0.0)
    except Exception:
        pass

RESET   = "\033[0m"
BOLD    = "\033[1m"
WHITE   = "\033[37m"
CYAN    = "\033[36m"
GREEN   = "\033[32m"
YELLOW  = "\033[33m"
MAGENTA = "\033[35m"
RED     = "\033[31m"
BLUE    = "\033[34m"

ctx_color  = RED if ctx_pct >= 80 else (YELLOW if ctx_pct >= 50 else GREEN)
cost_color = RED if cost >= 0.50  else (YELLOW if cost >= 0.10  else GREEN)
hit_color  = GREEN if hit_pct >= 80 else (YELLOW if hit_pct >= 50 else RED)

compact_info = ""
compact_file = Path.home() / ".claude/compaction/result.json"
if compact_file.exists():
    try:
        c = json.loads(compact_file.read_text())
        if c.get("session_id") == session_id:
            reduced = c.get("reduced", 0)
            before  = c.get("tokens_before", 0)
            pct     = int(reduced * 100 / before) if before else 0
            compact_info = (
                f" {YELLOW}compact{RESET}:{WHITE}-{reduced}tok(-{pct}%){RESET}"
            )
    except Exception:
        pass

sid = session_id if session_id else "?"

def fmt_tok(n):
    if n >= 1_000_000:
        v = n / 1_000_000
        return f"{v:.0f}M" if v == int(v) else f"{v:.1f}M"
    if n >= 1_000:
        v = n / 1_000
        return f"{v:.0f}K" if v == int(v) else f"{v:.1f}K"
    return str(n)

sys.stdout.write(
    f"{BOLD}{CYAN}[{model}]{RESET} "
    f"{GREEN}sid{RESET}:{WHITE}{sid}{RESET} "
    f"{BLUE}in{RESET}:{WHITE}{in_tok}{RESET}({WHITE}{total_in}{RESET}) "
    f"{MAGENTA}out{RESET}:{WHITE}{out_tok}{RESET} "
    f"{CYAN}cache(r/w){RESET}:{WHITE}{cache_r}/{cache_w}{RESET} "
    f"{CYAN}hit{RESET}:{hit_color}{hit_pct}%{RESET} "
    f"{ctx_color}ctx{RESET}:{WHITE}{ctx_pct}%{RESET}({WHITE}{fmt_tok(total_in)}{RESET}) "
    f"{cost_color}cost{RESET}:{WHITE}${cost:.4f}{RESET}"
    f"{compact_info}\n"
)
