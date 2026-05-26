# claude-assistant

A Claude Code plugin providing token usage tracking, a live statusline, compaction analysis, and configurable prompt dispatch.

Hook scripts are shared with the Codex plugin and live in [`../plugin/`](../plugin/) at the repo root. This folder only carries the Claude marketplace manifest and the hooks.json wiring.

## Features

### 1. Token Usage Log

**Script:** [`../plugin/hooks/track-tokens.py`](../plugin/hooks/track-tokens.py) (via host package [`../plugin/hooks/hosts/claude/`](../plugin/hooks/hosts/claude/))
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

**Script:** [`../plugin/hooks/statusline.py`](../plugin/hooks/statusline.py)
**Config:** `statusLine` in `~/.claude/settings.json`

Displays a colour-coded statusline after each response showing real-time token and cost metrics.

```text
[claude-sonnet-4-6] in:37(330529) out:4278 cache(r/w):293471/31058 ctx:0% cost:$0.2687
```

Wire it via the bundled skill (writes `~/.claude/settings.json` idempotently):

```
/statusLine-wizard install
```

Re-run after every plugin version bump — settings.json hardcodes the cached version path. `/statusLine-wizard status` reports current state; `/statusLine-wizard uninstall` removes it. Skill source: [`skills/statusLine-wizard/`](skills/statusLine-wizard/).

### 3. Compaction Analysis

**Scripts:** [`../plugin/hooks/pre-compact.py`](../plugin/hooks/pre-compact.py), [`../plugin/hooks/post-compact.py`](../plugin/hooks/post-compact.py)
**Hooks:** `PreCompact`, `PostCompact`

Snapshots context usage before compaction and computes the delta in the next `Stop` hook using `~/.claude/compaction/*.json` state files.

### 4. Prompt Dispatch

**Script:** [`../plugin/hooks/static-dispatch.py`](../plugin/hooks/static-dispatch.py)
**Hook:** `UserPromptSubmit`

Intercepts prompts matching regex rules defined in `static-dispatch.json`, runs the corresponding shell command, and suppresses Claude inference.

Config is loaded from the first file found (project takes precedence):
1. `{cwd}/static-dispatch.json`
2. `~/.claude/static-dispatch.json`

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

### 5. Cache Hit Alert

**Script:** [`../plugin/hooks/track-tokens.py`](../plugin/hooks/track-tokens.py)
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
├── .claude-plugin/plugin.json
└── hooks/hooks.json          # wires the shared scripts in ../plugin/
```
