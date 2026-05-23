# claude-assistant

A Claude Code plugin providing token usage tracking, a live statusline, compaction analysis, and configurable prompt dispatch.

## Features

### 1. Token Usage Log

**Script:** [`hooks/track-tokens.py`](hooks/track-tokens.py)
**Hook:** `Stop`

Appends an incremental JSONL entry to `~/.claude/token-usage/usage.jsonl` at the end of every turn.

```json
{"ts": "2026-05-07T10:00:00Z", "session_id": "uuid", "model": "claude-sonnet-4-6", "project": "ai-plugins", "tokens": {"input": 45, "output": 1823, "cache_write": 8420, "cache_read": 112074}, "cost_usd": 0.048312}
```

Cost rates for `claude-sonnet-4-6`:

| Token type | Rate per million |
|---|---|
| Input | $3.00 |
| Output | $15.00 |
| Cache write | $3.75 |
| Cache read | $0.30 |

### 2. Live Statusline

**Script:** [`hooks/statusline.py`](hooks/statusline.py)
**Config:** `statusLine` in `~/.claude/settings.json`

Displays a colour-coded statusline after each response showing real-time token and cost metrics.

```text
[claude-sonnet-4-6] in:37(330529) out:4278 cache(r/w):293471/31058 ctx:0% cost:$0.2687
```

Wire it manually in `~/.claude/settings.json`:

```json
"statusLine": {
  "type": "command",
  "command": "python3 /path/to/claude/hooks/statusline.py"
}
```

### 3. Compaction Analysis

**Scripts:** [`hooks/pre-compact.py`](hooks/pre-compact.py), [`hooks/post-compact.py`](hooks/post-compact.py)
**Hooks:** `PreCompact`, `PostCompact`

Snapshots context usage before compaction and computes the delta in the next `Stop` hook using `~/.claude/compaction/*.json` state files.

### 4. Prompt Dispatch

**Script:** [`hooks/static-dispatch.py`](hooks/static-dispatch.py)
**Hook:** `UserPromptSubmit`

Intercepts prompts matching regex rules defined in `static-dispatch.toml`, runs the corresponding shell command, and suppresses Claude inference.

Config is loaded from the first file found (project takes precedence):
1. `{cwd}/static-dispatch.toml`
2. `~/.claude/static-dispatch.toml`

Example config:

```toml
# matches: "commit and push", "commit, push"
[[rule]]
pattern = "^commit[,.]?\\s+(and\\s+)?push[.!]?$"
command = "git add -A && git diff --staged --stat | tail -1 | xargs -I{} git commit -m '{}' && git push"

# matches: "commit", "commit.", "commit!"
[[rule]]
pattern = "^commit[.!]?$"
command = "git add -A && git diff --staged --stat | tail -1 | xargs -I{} git commit -m '{}'"

# matches: "push", "push.", "push!"
[[rule]]
pattern = "^push[.!]?$"
command = "git push"
```

Rules are matched top-to-bottom; first match wins. The matched prompt is available as `INTENT_PROMPT` env var in the command.

### 5. Cache Hit Alert

**Script:** [`hooks/track-tokens.py`](hooks/track-tokens.py)
**Hook:** `Stop`

Fires a macOS notification when prompt-cache reuse drops below 90% on a turn — a leading indicator that workflow changes (new files in context, edits invalidating cached prefixes, model switches) are about to spike cost-per-event.

Cache hit rate per turn:

```
cache_read / (input + cache_read + cache_write)
```

Triggered once per turn, after the JSONL entry is written. Alert dispatched via `osascript display notification` with the Submarine sound.

**Gates** (suppress noise):
- prior turn had cache activity (`cache_read + cache_write > 0`) — skip first turn where nothing is cached yet
- turn input ≥ 1000 tokens — skip trivial turns
- hit < 90%

**Statusline** also shows live `hit:<pct>%` (green ≥80%, yellow ≥50%, red below) so you can watch the rate without waiting for an alert.

> **macOS permission:** banners appear only if **System Settings → Notifications → Script Editor → Alert style** is set to `Banners` or `Alerts`. Otherwise sound plays but the message is routed silently into Notification Center.

## File Structure

```text
claude/
├── .claude-plugin/
│   ├── plugin.json
│   └── marketplace.json
└── hooks/
    ├── hooks.json
    ├── static-dispatch.py
    ├── track-tokens.py
    ├── statusline.py
    ├── pre-compact.py
    ├── post-compact.py
    ├── migrate-token-log.py
    └── backfill-projects.py
```
