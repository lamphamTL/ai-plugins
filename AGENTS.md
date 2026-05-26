# ai-plugins

Plugins for Claude Code and Codex CLI, plus a native macOS token usage widget.


## Token usage logs

### Claude

Written by `plugin/hooks/track-tokens.py` (host package `plugin/hooks/hosts/claude/`) on every `Stop` event.

**Location:** `~/.claude/token-usage/usage.jsonl`
**State file:** `~/.claude/token-usage/state.json` (per-session cumulative totals for delta computation)

```json
{
  "ts": "2026-05-07T10:00:00Z",
  "session_id": "uuid",
  "model": "claude-sonnet-4-6",
  "project": "ai-plugins",
  "tokens": { "input": 45, "output": 1823, "cache_write": 8420, "cache_read": 112074 },
  "cost_usd": 0.048312,
  "isSubAgent": false
}
```

- `project` is the **basename** of `cwd`, with worktree paths (`/.claude/worktrees/<name>`) resolved to the parent project name.
- Values are **incremental deltas** per Stop event, not cumulative session totals.
- Cost rates: input $3/M, output $15/M, cache_write $3.75/M, cache_read $0.30/M (claude-sonnet-4-6).

### Codex

Written by `plugin/hooks/track-tokens.py` (host package `plugin/hooks/hosts/codex/`) on every `Stop` event.

**Location:** `~/.codex/token-usage/usage.jsonl`
**State file:** `~/.codex/token-usage/state.json` (per-session cumulative totals for delta computation)

```json
{
  "ts": "2026-05-07T10:00:00Z",
  "session_id": "uuid",
  "model": "gpt-5.5",
  "project": "ai-plugins",
  "tokens": { "input": 45, "output": 1823, "cache_read": 112074, "reasoning": 342 },
  "cost_usd": 0.062100,
  "isSubAgent": false
}
```

- Token data comes from `token_count` events in the session transcript JSONL (`~/.codex/sessions/`).
- `tokens.input` is fresh non-cached input only; cached input is stored separately as `tokens.cache_read`.
- Reasoning tokens billed at output rate.
- Cost rates per model (USD/million): see `plugin/hooks/hosts/codex/model_pricing.py`.

## Token usage widget

Native macOS floating panel built with SwiftUI + Swift Charts. Reads from both Claude and Codex logs.

**Build & run:**
```bash
cd token-usage-app
./build.sh       # compile
./build.sh run   # compile + open
```

> SPM (`swift build`) is broken on macOS 26 beta — `build.sh` uses `swiftc` directly.

**Key behaviours:**
- Floats at bottom-right corner, always on top, shows on all spaces.
- Source picker: All / Claude / Codex — filters chart and project list.
- Day = 7 daily bars, Week = 5 weekly bars, Month = 5 monthly bars.
- Drag chart left/right to slide the time window.
- Tap a bar to show its cost in the footer; tap again to deselect.
- File-watches both `usage.jsonl` files — updates live without restart.
- Registers as a login item via `SMAppService` on first launch.

## Plugin installation

**Claude Code:**
```bash
claude plugin marketplace add lamphamTL/ai-plugins --sparse .claude-plugin plugin
claude plugin install claude-assistant@ai-plugins
```

**Codex:**
```bash
codex plugin marketplace add lamphamTL/ai-plugins
codex plugin add codex-assistant@ai-plugins
```

## Updating plugins after hook changes

The marketplace sparse clone does not auto-pull on reinstall.

**Claude Code:**
```bash
git -C ~/.claude/plugins/marketplaces/ai-plugins pull
claude plugins uninstall claude-assistant@ai-plugins
claude plugins install claude-assistant@ai-plugins
```

**Codex:**
```bash
codex plugin marketplace upgrade ai-plugins
```
