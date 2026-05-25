# codex-assistant

A Codex plugin providing token usage tracking and configurable prompt dispatch.

Hook scripts are shared with the Claude plugin and live in [`../plugin/`](../plugin/) at the repo root.

## Features

### 1. Token Usage Log

**Script:** [`../plugin/hooks/track-tokens.py`](../plugin/hooks/track-tokens.py) (via host package [`../plugin/hooks/hosts/codex/`](../plugin/hooks/hosts/codex/))
**Hook:** `Stop`

Appends an incremental JSONL entry to `~/.codex/token-usage/usage.jsonl` at the end of every turn.
`tokens.input` stores fresh non-cached input only; cached input is stored separately as `tokens.cache_read`.

### 2. Prompt Dispatch

**Script:** [`../plugin/hooks/static-dispatch.py`](../plugin/hooks/static-dispatch.py)
**Hook:** `UserPromptSubmit`

Intercepts prompts matching regex rules defined in `static-dispatch.json`, runs the corresponding shell command, and suppresses Codex inference.

Config is loaded from the first file found (project takes precedence):
1. `{cwd}/static-dispatch.json`
2. `~/.codex/static-dispatch.json`

Example config:

```json
{
  "rule": [
    {"pattern": "^commit[,.]?\\s+(and\\s+)?push[.!]?$", "command": "git add -A && git diff --staged --stat | tail -1 | xargs -I{} git commit -m '{}' && git push"},
    {"pattern": "^commit[.!]?$", "command": "git add -A && git diff --staged --stat | tail -1 | xargs -I{} git commit -m '{}'"},
    {"pattern": "^push[.!]?$", "command": "git push"}
  ]
}
```

Rules are matched top-to-bottom; first match wins. The matched prompt is available as `INTENT_PROMPT` env var in the command.

### 3. Cache Hit Alert

**Script:** [`../plugin/hooks/track-tokens.py`](../plugin/hooks/track-tokens.py)
**Hook:** `Stop`

Fires a macOS notification when prompt-cache reuse drops below 90% on a turn — a leading indicator that workflow changes (new files in context, edits invalidating cached prefixes, model switches) are about to spike cost-per-event.

Cache hit rate per turn:

```
cached_input / (fresh_input + cached_input)
```

Triggered once per turn, after the JSONL entry is written. Alert dispatched via `osascript display notification` with the Submarine sound.

**Gates** (suppress noise):
- prior turn had cached input activity — skip first turn where nothing is cached yet
- turn fresh input ≥ 1000 tokens — skip trivial turns
- hit < 90%

> **macOS permission:** banners appear only if **System Settings → Notifications → Script Editor → Alert style** is set to `Banners` or `Alerts`. Otherwise sound plays but the message is routed silently into Notification Center.

## File Structure

```text
codex/
├── .codex-plugin/plugin.json
└── hooks/hooks.json          # wires the shared scripts in ../plugin/
```
