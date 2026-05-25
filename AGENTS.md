# ai-plugins

Plugins for Claude Code and Codex CLI, plus a native macOS token usage widget.

## Repo structure

```
ai-plugins/
├── plugin/                       # Shared hook scripts (used by both plugins)
│   ├── track-tokens.py           # Driver — appends JSONL entry per Stop event
│   ├── static-dispatch.py        # Driver — UserPromptSubmit prompt dispatch
│   ├── pre-compact.py            # Claude-only: snapshot context before compaction
│   ├── post-compact.py           # Claude-only: PostCompact placeholder
│   ├── statusline.py             # Claude-only: live token/cost statusline
│   ├── cleanup-state.py          # Claude-only: one-off state.json cleanup
│   ├── cleanup-subagent-rows.py  # Claude-only: one-off usage.jsonl cleanup
│   └── hosts/                    # Per-host modules consumed by the drivers
│       ├── claude.py             # prepare_data_source, compute_spend, paths…
│       └── codex.py              # same surface, Codex-shaped
├── claude/                       # Claude Code plugin (wires shared scripts)
│   ├── .claude-plugin/plugin.json
│   └── hooks/hooks.json          # Points at ${CLAUDE_PLUGIN_ROOT}/../plugin/...
├── codex/                        # Codex CLI plugin (wires shared scripts)
│   ├── .codex-plugin/plugin.json
│   └── hooks/hooks.json          # Points at ${PLUGIN_ROOT}/../plugin/...
└── token-usage-app/              # Native macOS SwiftUI widget
    ├── build.sh                  # Build script (uses swiftc directly — SPM broken on macOS 26 beta)
    ├── resources/                # Screenshots and assets
    └── Sources/TokenUsageApp/
        ├── App/TokenUsageApp.swift      # NSPanel floating widget, SMAppService login item
        ├── Models/UsageEntry.swift      # Decodable JSONL row
        ├── Models/TimeRange.swift       # TimeRangeKind + TimeWindow
        ├── Services/UsageStore.swift    # @MainActor store, dual file watcher (Claude + Codex)
        ├── Services/FileWatcher.swift   # DispatchSource tail watcher
        └── Views/                       # ContentView, BarChartView, NavigationBar
```

Each hooks.json sets `INTENT_HOST=claude` or `INTENT_HOST=codex` on the script command so the shared driver imports the right `plugin/hosts/<host>.py` module.

## Token usage logs

### Claude

Written by `plugin/track-tokens.py` (host module `plugin/hosts/claude.py`) on every `Stop` event.

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

Written by `plugin/track-tokens.py` (host module `plugin/hosts/codex.py`) on every `Stop` event.

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
- Cost rates per model (USD/million): see `plugin/hosts/codex.py`.

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

**Claude Code:** the sparse paths must include `plugin/` so the shared scripts get fetched.
```bash
claude plugin marketplace add lamphamTL/ai-plugins --sparse .claude-plugin claude plugin
claude plugin install claude-assistant@ai-plugins
```

**Codex:**
```bash
codex plugin marketplace add lamphamTL/ai-plugins
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
