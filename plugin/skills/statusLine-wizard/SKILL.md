---
name: statusLine-wizard
description: Manage claude-assistant statusLine entry in ~/.claude/settings.json (install, uninstall, status)
argument-hint: <install|uninstall|status> [--force]
allowed-tools: [Bash, AskUserQuestion]
disable-model-invocation: true
---

# statusLine wizard

User argument: $ARGUMENTS (default: `status` if empty)

## Dispatch

Run: `python3 "${CLAUDE_PLUGIN_ROOT}/skills/statusLine-wizard/manage.py" $ARGUMENTS`

- `install` → run helper. If exit 2 (foreign statusLine conflict), parse stderr for the `current: …` line, call `AskUserQuestion` with the existing command shown and options `[Override, Cancel]`.
  - Override → re-run `manage.py install --force`.
  - Cancel → report "no changes made" and stop.
- `uninstall` → run helper, report result.
- `status` → run helper, print current state.

After running, summarize exit status and resulting statusLine command to the user.
