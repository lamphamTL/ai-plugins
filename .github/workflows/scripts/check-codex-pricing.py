#!/usr/bin/env python3
"""Fetch upstream Codex rate card; rewrite the RATES dict in codex/model_pricing.py.

Exits 0 whether or not anything changed. The workflow detects file changes via
`git diff` and opens a PR if there are any. Exits 2 only on parsing failure.
"""
from __future__ import annotations

import ast
import re
import sys
import urllib.request
from pathlib import Path

URL = "https://developers.openai.com/codex/pricing"
TARGET = (
    Path(__file__).resolve().parents[3]
    / "plugin/hooks/hosts/codex/model_pricing.py"
)
FIELDS = ("ri", "ro", "rc")
MIN_MODELS = 3

# Rate-card row: "GPT-5.5 125 credits 12.50 credits 750 credits".
# Cell order in the docs table: input, cached input, output.
# Anchoring on "credits" filters out the usage-limit tables that share the
# same model names elsewhere on the page.
ROW_RE = re.compile(
    r"GPT-(\d+(?:\.\d+)?(?:-(?:mini|codex))?)\s+"
    r"(\d+(?:\.\d+)?)\s+credits\s+"
    r"(\d+(?:\.\d+)?)\s+credits\s+"
    r"(\d+(?:\.\d+)?)\s+credits",
    re.IGNORECASE,
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
        version, ri, rc, ro = m.groups()
        slug = f"gpt-{version.lower()}"
        if slug in rates:
            continue
        rates[slug] = {"ri": float(ri), "ro": float(ro), "rc": float(rc)}
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
