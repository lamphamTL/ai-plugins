# ai-plugins

Plugins for Claude Code and Codex CLI, plus a native macOS token usage widget.

- [`plugin/`](plugin/) — shared hook scripts (drivers + per-host modules)
- [`claude/`](claude/) — Claude Code plugin manifest + hooks.json wiring
- [`codex/`](codex/) — Codex CLI plugin manifest + hooks.json wiring
- [`token-usage-app/`](token-usage-app/) — macOS floating widget to visualise AI spend

## Repository Layout

```text
ai-plugins/
├── .claude-plugin/
│   └── marketplace.json          # Claude Code marketplace manifest
├── .agents/
│   └── plugins/marketplace.json  # Codex marketplace manifest
├── plugin/                       # shared script source (single source of truth)
│   └── hooks/                    # both plugins symlink here
│       ├── track-tokens.py       # shared driver — picks host module via INTENT_HOST
│       ├── static-dispatch.py    # shared driver — prompt dispatch
│       ├── pre-compact.py        # Claude-only: snapshot context pre-compaction
│       ├── post-compact.py       # Claude-only: PostCompact placeholder
│       ├── statusline.py         # Claude-only: live token/cost statusline
│       ├── cleanup-state.py      # Claude-only: one-off state.json cleanup
│       └── hosts/                # per-host packages
│           ├── claude/
│           │   ├── prepare_data_source.py
│           │   ├── compute_spend.py
│           │   ├── build_entry.py
│           │   ├── model_pricing.py
│           │   ├── cache_hit_pct.py
│           │   └── post_persist.py
│           └── codex/            # same surface, Codex-shaped
├── claude/
│   ├── README.md
│   ├── .claude-plugin/plugin.json
│   └── hooks/
│       ├── hooks.json            # paths point at ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/...
│       └── scripts -> ../../plugin/hooks   # symlink; installer follows during copy
├── codex/
│   ├── README.md
│   ├── .codex-plugin/plugin.json
│   └── hooks/
│       ├── hooks.json            # paths point at ${PLUGIN_ROOT}/hooks/scripts/...
│       └── scripts -> ../../plugin/hooks   # symlink; installer follows during copy
└── token-usage-app/
    ├── README.md
    ├── Package.swift             # SPM manifest (SPM broken on macOS 26 beta — use build.sh)
    ├── build.sh                  # swiftc build script
    ├── resources/                # screenshots
    └── Sources/TokenUsageApp/
        ├── App/TokenUsageApp.swift          # NSPanel floating widget, login item
        ├── Models/
        │   ├── UsageEntry.swift             # Decodable JSONL row
        │   └── TimeRange.swift              # TimeRangeKind + TimeWindow
        ├── Services/
        │   ├── UsageStore.swift             # @MainActor store, dual file watcher
        │   └── FileWatcher.swift            # DispatchSource tail watcher
        └── Views/
            ├── ContentView.swift
            ├── BarChartView.swift
            └── NavigationBar.swift
```

## Components

### Claude Code plugin

Token usage logging, live statusline, compaction tracking, git intent shortcuts.

Hooks fire on `Stop`, `UserPromptSubmit`, `PreCompact`, and `PostCompact`. Each `Stop` appends an incremental JSONL entry to `~/.claude/token-usage/usage.jsonl` with timestamp, session ID, model, project name, per-type token deltas, and cost in USD.

### Codex plugin

Token usage logging and git intent shortcuts.

Hooks fire on `Stop` and `UserPromptSubmit`. Each `Stop` reads the session transcript JSONL, computes incremental token deltas, and appends an entry to `~/.codex/token-usage/usage.jsonl`.

### Token Usage App

Native macOS floating widget built with SwiftUI + Swift Charts. Reads from both `~/.claude/token-usage/usage.jsonl` and `~/.codex/token-usage/usage.jsonl` and renders cost over time as a bar chart with source filtering (All / Claude / Codex).

![Token Usage App](token-usage-app/resources/all-usage.png)

See [`token-usage-app/README.md`](token-usage-app/README.md) for details and build instructions.

## Marketplace Installation

**Claude Code:** sparse paths must include `plugin/` so the `scripts` symlink target is present in the marketplace clone before install copies it into the plugin cache.
```bash
claude plugin marketplace add lamphamTL/ai-plugins --sparse .claude-plugin claude plugin
claude plugin install claude-assistant@ai-plugins
```

**Codex:**
```bash
codex plugin marketplace add lamphamTL/ai-plugins
```

Bundled plugin hooks in Codex still experimental. Enable feature flags in `~/.codex/config.toml`:

```toml
[features]
hooks = true
plugin_hooks = true
```

Hooks installed from plugin not enabled by default. Turn them on either by updating `~/.codex/config.toml` or from Codex Desktop App.

## Updating plugins after hook changes

The marketplace sparse clone doesn't auto-pull on reinstall.

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
