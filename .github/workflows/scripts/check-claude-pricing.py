#!/usr/bin/env python3
"""Fetch upstream Claude pricing; rewrite the RATES dict in claude/model_pricing.py.

Exits 0 whether or not anything changed. The workflow detects file changes via
`git diff` and opens a PR if there are any. Exits 2 only on parsing failure.
"""
from __future__ import annotations

import ast
import re
import sys
import urllib.request
from pathlib import Path

URL = "https://platform.claude.com/docs/en/about-claude/pricing"
TARGET = (
    Path(__file__).resolve().parents[3]
    / "plugin/hooks/hosts/claude/model_pricing.py"
)
FIELDS = ("ri", "ro", "rw_5m", "rw_1h", "rc")
MIN_MODELS = 8

# Matches one model-pricing row after HTML has been stripped. $ order in the
# docs table: base input, 5m write, 1h write, cache read, output.
ROW_RE = re.compile(
    r"Claude\s+(Opus|Sonnet|Haiku|Fable|Mythos)\s+(\d+(?:\.\d+)?)"
    r"[^$]{0,200}?\$(\d+(?:\.\d+)?)\s*/\s*MTok"
    r"[^$]{0,200}?\$(\d+(?:\.\d+)?)\s*/\s*MTok"
    r"[^$]{0,200}?\$(\d+(?:\.\d+)?)\s*/\s*MTok"
    r"[^$]{0,200}?\$(\d+(?:\.\d+)?)\s*/\s*MTok"
    r"[^$]{0,200}?\$(\d+(?:\.\d+)?)\s*/\s*MTok",
)


def fetch_text() -> str:
    req = urllib.request.Request(URL, headers={"User-Agent": "ai-plugins-pricing-check"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        html = resp.read().decode("utf-8")
    text = re.sub(r"<[^>]+>", " ", html)
    text = text.replace("&nbsp;", " ").replace("&amp;", "&")
    return re.sub(r"\s+", " ", text)


def parse_rates(text: str) -> dict[str, dict[str, float]]:
    rates: dict[str, dict[str, float]] = {}
    for m in ROW_RE.finditer(text):
        tier, ver, ri, rw5, rw1, rc, ro = m.groups()
        slug = f"claude-{tier.lower()}-{ver.replace('.', '-')}"
        # Same model appears again in Batch / Fast-mode tables; keep first hit.
        if slug in rates:
            continue
        rates[slug] = {
            "ri": float(ri), "ro": float(ro),
            "rw_5m": float(rw5), "rw_1h": float(rw1), "rc": float(rc),
        }
    return rates


def fmt_num(x: float) -> str:
    if x == int(x):
        return str(int(x))
    return f"{x:g}"


def format_rates_block(rates: dict[str, dict[str, float]]) -> str:
    key_width = max(len(f'"{k}":') for k in rates)
    formatted = [(s, {f: fmt_num(r[f]) for f in FIELDS}) for s, r in rates.items()]
    widths = {f: max(len(row[f]) for _, row in formatted) for f in FIELDS}

    lines = ["RATES = {"]
    for slug, row in formatted:
        key = f'"{slug}":'.ljust(key_width)
        cells = []
        for i, f in enumerate(FIELDS):
            sep = "," if i < len(FIELDS) - 1 else ""
            cells.append(f'"{f}": {(row[f] + sep).ljust(widths[f] + 1)}')
        lines.append(f"    {key} {{{' '.join(cells).rstrip()}}},")
    lines.append("}")
    return "\n".join(lines)


def parse_current_rates(src: str) -> dict[str, dict[str, float]] | None:
    m = re.search(r"^RATES\s*=\s*(\{.*?^\})", src, re.DOTALL | re.MULTILINE)
    if not m:
        return None
    try:
        return ast.literal_eval(m.group(1))
    except (SyntaxError, ValueError):
        return None


def main() -> int:
    text = fetch_text()
    new_rates = parse_rates(text)
    if len(new_rates) < MIN_MODELS:
        print(
            f"ERROR: parsed only {len(new_rates)} models (min {MIN_MODELS}); "
            "refusing to overwrite",
            file=sys.stderr,
        )
        return 2

    src = TARGET.read_text()
    block_re = re.compile(r"^RATES = \{.*?^\}", re.DOTALL | re.MULTILINE)
    if not block_re.search(src):
        print("ERROR: RATES block not found", file=sys.stderr)
        return 2

    current = parse_current_rates(src)
    if current == new_rates:
        print("No pricing changes.")
        return 0

    TARGET.write_text(block_re.sub(format_rates_block(new_rates), src, count=1))

    added = sorted(set(new_rates) - set(current or {}))
    removed = sorted(set(current or {}) - set(new_rates))
    changed = sorted(
        k for k in set(new_rates) & set(current or {}) if new_rates[k] != current[k]
    )
    print(f"Updated. added={added} removed={removed} changed={changed}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
