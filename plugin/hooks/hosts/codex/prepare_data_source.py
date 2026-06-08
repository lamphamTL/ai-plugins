import json
import os
import time
from datetime import datetime
from pathlib import Path

from .model_pricing import STATE_JSON, USAGE_DIR

_STOP_HOOK_FLUSH_RETRY_DELAYS = (0.1, 0.15, 0.2, 0.25)


def _derive_project(cwd: str) -> str:
    if not cwd:
        return "unknown"
    cwd = cwd.rstrip("/")
    home = str(Path.home())
    codex_wt = home + "/.codex/worktrees/"
    if cwd.startswith(codex_wt):
        parts = cwd[len(codex_wt):].split("/", 1)
        return parts[1] if len(parts) == 2 else "unknown"
    junk = [home + "/Library/", home + "/.codex", home + "/Documents/Codex/"]
    if cwd == home or any(cwd.startswith(p) for p in junk):
        return "unknown"
    if "/worktree/" in cwd:
        return os.path.basename(cwd[:cwd.index("/worktree/")])
    base = os.path.basename(cwd)
    if base.startswith("worktree_") or base.startswith("worktree-"):
        parent = os.path.dirname(cwd)
        return os.path.basename(parent) if parent != home else "unknown"
    return base if base else "unknown"


def _find_transcript(session_id: str):
    today_dir = Path.home() / ".codex/sessions" / datetime.now().strftime("%Y/%m/%d")
    if not today_dir.is_dir():
        return None
    for f in today_dir.iterdir():
        try:
            if session_id in f.read_text():
                return str(f)
        except Exception:
            pass
    return None


def _read_last_token_count(transcript: str):
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
    return last_count


def _resolve_transcript(provided_transcript: str, session_id: str) -> str:
    if provided_transcript and Path(provided_transcript).exists():
        return provided_transcript
    return _find_transcript(session_id) or ""


def prepare_data_source(stdin_data: dict):
    session_id = stdin_data.get("session_id") or "unknown"
    provided_transcript = stdin_data.get("transcript_path") or ""
    model      = stdin_data.get("model") or "unknown"
    cwd        = stdin_data.get("cwd") or os.environ.get("PWD") or ""

    project = _derive_project(cwd)

    for attempt in range(len(_STOP_HOOK_FLUSH_RETRY_DELAYS) + 1):
        transcript = _resolve_transcript(provided_transcript, session_id)
        if transcript and Path(transcript).exists():
            last_count = _read_last_token_count(transcript)
            if last_count:
                total_input     = last_count.get("input_tokens", 0)
                total_output    = last_count.get("output_tokens", 0)
                total_cached    = last_count.get("cached_input_tokens", 0)
                total_reasoning = last_count.get("reasoning_output_tokens", 0)
                total_fresh     = total_input - total_cached

                USAGE_DIR.mkdir(parents=True, exist_ok=True)
                state, prev = {}, {}
                if STATE_JSON.exists():
                    try:
                        state = json.loads(STATE_JSON.read_text())
                        prev  = state.get(session_id) or {}
                    except Exception:
                        pass

                prev_fresh        = prev.get("input", 0) - prev.get("cached", 0)
                delta_fresh_input = total_fresh     - prev_fresh
                delta_output      = total_output    - prev.get("output", 0)
                delta_cached      = total_cached    - prev.get("cached", 0)
                delta_reasoning   = total_reasoning - prev.get("reasoning", 0)

                if delta_fresh_input != 0 or delta_output != 0:
                    state[session_id] = {
                        "input":     total_input,
                        "output":    total_output,
                        "cached":    total_cached,
                        "reasoning": total_reasoning,
                    }
                    STATE_JSON.write_text(json.dumps(state))

                    return {
                        "session_id": session_id,
                        "model":      model,
                        "project":    project,
                        "deltas": {
                            "input":      delta_fresh_input,
                            "output":     delta_output,
                            "cache_read": delta_cached,
                            "reasoning":  delta_reasoning,
                        },
                        "_prev": prev,
                    }

        if attempt < len(_STOP_HOOK_FLUSH_RETRY_DELAYS):
            time.sleep(_STOP_HOOK_FLUSH_RETRY_DELAYS[attempt])

    return None
