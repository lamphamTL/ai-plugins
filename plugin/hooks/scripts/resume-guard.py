#!/usr/bin/env python3
"""Block stale resume prompts unless user confirms in a macOS dialog."""
from __future__ import annotations

import json
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable, Iterable


HOSTS = {"claude", "codex"}
THRESHOLD = timedelta(minutes=55)
DIALOG_MESSAGE = (
    "It seems like you are resuming an old session whose cache is likely expired. "
    "Do you want to continue?"
)
BLOCK_MESSAGE = (
    "Stale resume blocked because the session cache is likely expired. "
    "Submit again and choose Continue, or start a fresh session."
)
TIMESTAMP_KEYS = {"timestamp", "ts", "time"}


def _normalize_iso(value: str) -> str:
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    match = re.match(r"^(.*?T\d{2}:\d{2}:\d{2})\.(\d{6})\d+(.+)?$", text)
    if match:
        text = f"{match.group(1)}.{match.group(2)}{match.group(3) or ''}"
    return text


def parse_iso_timestamp(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value.strip():
        return None
    try:
        parsed = datetime.fromisoformat(_normalize_iso(value))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _timestamp_values(node: Any) -> Iterable[Any]:
    if isinstance(node, dict):
        for key, value in node.items():
            if key in TIMESTAMP_KEYS:
                yield value
            yield from _timestamp_values(value)
    elif isinstance(node, list):
        for item in node:
            yield from _timestamp_values(item)


def latest_transcript_timestamp(transcript_path: str | None) -> datetime | None:
    if not transcript_path:
        return None

    latest: datetime | None = None
    try:
        with Path(transcript_path).open(encoding="utf-8") as transcript:
            for line in transcript:
                if not line.strip():
                    continue
                try:
                    row = json.loads(line)
                except json.JSONDecodeError:
                    continue
                for value in _timestamp_values(row):
                    parsed = parse_iso_timestamp(value)
                    if parsed is not None and (latest is None or parsed > latest):
                        latest = parsed
    except OSError:
        return None

    return latest


def is_stale_session(
    latest_timestamp: datetime | None,
    *,
    now: datetime | None = None,
    threshold: timedelta = THRESHOLD,
) -> bool:
    if latest_timestamp is None:
        return False
    if now is None:
        now = datetime.now(timezone.utc)
    if now.tzinfo is None:
        now = now.replace(tzinfo=timezone.utc)
    if latest_timestamp.tzinfo is None:
        latest_timestamp = latest_timestamp.replace(tzinfo=timezone.utc)

    age = now.astimezone(timezone.utc) - latest_timestamp.astimezone(timezone.utc)
    return age > threshold


def confirm_stale_resume(
    runner: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
) -> bool:
    script = (
        f'display dialog "{_applescript_quote(DIALOG_MESSAGE)}" '
        'buttons {"Cancel", "Continue"} '
        'default button "Cancel" '
        'cancel button "Cancel"'
    )
    try:
        result = runner(
            ["osascript", "-e", script],
            capture_output=True,
            text=True,
            timeout=60,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return result.returncode == 0 and "button returned:Continue" in (result.stdout or "")


def _applescript_quote(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def block_response(host: str, reason: str = BLOCK_MESSAGE) -> dict[str, Any]:
    if host == "claude":
        return {"decision": "block", "reason": reason}
    if host == "codex":
        return {"continue": False, "systemMessage": reason}
    raise ValueError(f"unsupported host: {host}")


def should_block(
    data: dict[str, Any],
    *,
    now: datetime | None = None,
    dialog_runner: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
) -> bool:
    latest = latest_transcript_timestamp(data.get("transcript_path"))
    if not is_stale_session(latest, now=now):
        return False
    return not confirm_stale_resume(dialog_runner)


def run(
    host: str | None,
    stdin_text: str,
    *,
    now: datetime | None = None,
    dialog_runner: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
) -> tuple[int, str]:
    if host not in HOSTS:
        sys.stderr.write(
            f"resume-guard: first arg must be 'claude' or 'codex' (got {host!r})\n"
        )
        return 1, ""

    try:
        data = json.loads(stdin_text or "{}")
    except json.JSONDecodeError:
        return 0, ""
    if not isinstance(data, dict):
        return 0, ""

    if should_block(data, now=now, dialog_runner=dialog_runner):
        return 0, json.dumps(block_response(host)) + "\n"
    return 0, ""


def main() -> int:
    host = sys.argv[1] if len(sys.argv) > 1 else None
    code, output = run(host, sys.stdin.read())
    if output:
        sys.stdout.write(output)
    return code


if __name__ == "__main__":
    raise SystemExit(main())
