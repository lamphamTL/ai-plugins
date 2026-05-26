# ai-plugins

Plugins for Claude Code and Codex CLI, plus a native macOS token usage widget.

- [`plugin/`](plugin/) — shared hook scripts (drivers + per-host modules)
- [`claude/`](claude/) — Claude Code plugin manifest + hooks.json wiring
- [`codex/`](codex/) — Codex CLI plugin manifest + hooks.json wiring
- [`token-usage-app/`](token-usage-app/) — macOS floating widget to visualise AI spend


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
codex plugin add codex-assistant@ai-plugins
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
