# ai-plugins shared plugin

One plugin source shared by two installers: Claude Code reads `.claude-plugin/plugin.json` (wires `hooks/claude.json`); Codex reads `.codex-plugin/plugin.json` (wires `hooks/codex.json`). All hook scripts live in this directory — no symlinks, no cross-dir references.

## Layout

```text
plugin/
├── .claude-plugin/plugin.json    # claude-assistant
├── .codex-plugin/plugin.json     # codex-assistant
├── skills/                       # Claude-only skills (e.g. statusLine-wizard)
└── hooks/
    ├── claude.json               # Claude events, ${CLAUDE_PLUGIN_ROOT}
    ├── codex.json                # Codex events, ${PLUGIN_ROOT}
    ├── track-tokens.py           # Stop hook (both hosts)
    ├── static-dispatch.py        # UserPromptSubmit (both hosts)
    ├── pre-compact.py            # PreCompact (Claude only)
    ├── post-compact.py           # PostCompact (Claude only)
    ├── statusline.py             # Claude statusline command
    ├── cleanup-state.py          # one-off state.json cleanup
    └── hosts/{claude,codex}/     # host-specific packages used by the drivers
```

Each `hooks.json` sets `INTENT_HOST=claude` or `INTENT_HOST=codex` on the script command so the shared driver imports the right `hosts/<host>/` package.

## Features

### 1. Token Usage Log

**Availability**: Claude + Codex

**Script:** `hooks/track-tokens.py`
**Hook:** `Stop` (+ `SubagentStop` for Claude)

Claude → appends incremental JSONL entry to `~/.claude/token-usage/usage.jsonl`.
Codex → appends to `~/.codex/token-usage/usage.jsonl`. `tokens.input` is fresh non-cached input only; cached input is stored separately as `tokens.cache_read`.

Claude cost rates (`claude-sonnet-4-6`):

| Token type | Rate per million |
|---|---|
| Input | $3.00 |
| Output | $15.00 |
| Cache write | $3.75 |
| Cache read | $0.30 |

Codex rates per model: see `hooks/hosts/codex/model_pricing.py`.

### 2. Live Statusline

**Availability**: Claude only

**Script:** `hooks/statusline.py`
**Config:** `statusLine` in `~/.claude/settings.json`

```text
[claude-sonnet-4-6] in:37(330529) out:4278 cache(r/w):293471/31058 ctx:0% cost:$0.2687
```

Wire via the bundled skill (idempotent):

```
/statusLine-wizard install
```

Re-run after every plugin version bump — `settings.json` hardcodes the cached version path. `/statusLine-wizard status` reports state; `/statusLine-wizard uninstall` removes it. Source: `skills/statusLine-wizard/`.

### 3. Compaction Analysis

**Availability**: Claude only

**Scripts:** `hooks/pre-compact.py`, `hooks/post-compact.py`
**Hooks:** `PreCompact`, `PostCompact`

Snapshots context before compaction, computes delta on next `Stop` via `~/.claude/compaction/*.json`.

### 4. Prompt Dispatch

**Availability**: Claude + Codex

**Script:** `hooks/static-dispatch.py`
**Hook:** `UserPromptSubmit`

Intercepts prompts matching regex rules and runs corresponding shell commands, suppressing inference.

Config search order (project first):
1. `{cwd}/static-dispatch.json`
2. `~/.claude/static-dispatch.json` (Claude) or `~/.codex/static-dispatch.json` (Codex)

```json
{
  "rule": [
    {"pattern": "^commit[,.]?\\s+(and\\s+)?push[.!]?$", "command": "git add -A && git diff --staged --stat | tail -1 | xargs -I{} git commit -m '{}' && git push"},
    {"pattern": "^commit[.!]?$", "command": "git add -A && git diff --staged --stat | tail -1 | xargs -I{} git commit -m '{}'"},
    {"pattern": "^push[.!]?$", "command": "git push"}
  ]
}
```

Rules match top-to-bottom; first wins. Matched prompt available as `INTENT_PROMPT` env var.

### 5. Cache Hit Alert

**Availability**: Claude + Codex

**Script:** `hooks/track-tokens.py`
**Hook:** `Stop`

Fires macOS notification when prompt-cache reuse drops below 90% — leading indicator of context/edit changes about to spike cost-per-event.

Cache hit rate per turn:

```
Claude: cache_read / (input + cache_read + cache_write)
Codex:  cached_input / (fresh_input + cached_input)
```

Alert via `osascript display notification` with the Submarine sound.

**Gates** (suppress noise):
- prior turn had cache activity — skip the first turn
- turn input ≥ 1000 tokens — skip trivial turns
- hit < 90%

Claude statusline also shows live `hit:<pct>%` (green ≥80%, yellow ≥50%, red below).

> **macOS permission:** banners appear only if **System Settings → Notifications → Script Editor → Alert style** is set to `Banners` or `Alerts`. Otherwise sound plays but message routes silently into Notification Center.
