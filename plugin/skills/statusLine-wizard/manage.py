import json, os, shutil, sys
from pathlib import Path

SETTINGS = Path.home() / ".claude" / "settings.json"
INSTALLED = Path.home() / ".claude" / "plugins" / "installed_plugins.json"
PLUGIN_KEY = "claude-assistant@ai-plugins"
MARKER = "plugins/cache/ai-plugins/claude-assistant/"


def plugin_root() -> Path:
    """Resolve the install dir of the active plugin version (per Claude Code's registry, with env/__file__ fallbacks)."""
    if INSTALLED.exists():
        try:
            entries = json.loads(INSTALLED.read_text()).get("plugins", {}).get(PLUGIN_KEY, [])
        except json.JSONDecodeError:
            entries = []
        for entry in entries:
            path = entry.get("installPath")
            if path and Path(path).is_dir():
                return Path(path)
    env = os.environ.get("CLAUDE_PLUGIN_ROOT")
    if env:
        return Path(env)
    here = Path(__file__).resolve()
    for parent in here.parents:
        if (parent / ".claude-plugin" / "plugin.json").exists():
            return parent
    raise RuntimeError("plugin root not located")


def statusline_cmd() -> str:
    """Build the `python3 "<path>"` command string that settings.json should hold."""
    script = plugin_root() / "hooks" / "scripts" / "statusline.py"
    return f'python3 "{script}"'


def load_settings() -> dict:
    """Read ~/.claude/settings.json, returning {} if missing."""
    if not SETTINGS.exists():
        return {}
    return json.loads(SETTINGS.read_text())


def atomic_write(data: dict) -> None:
    """Persist settings.json via a .tmp + os.replace swap, keeping a .bak of the previous file."""
    SETTINGS.parent.mkdir(parents=True, exist_ok=True)
    if SETTINGS.exists():
        shutil.copy2(SETTINGS, SETTINGS.with_suffix(".json.bak"))
    tmp = SETTINGS.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n")
    os.replace(tmp, SETTINGS)


def is_ours(entry: dict | None) -> bool:
    """True iff the statusLine entry's command points into the claude-assistant plugin cache."""
    return bool(entry) and MARKER in entry.get("command", "")


def install(force: bool = False) -> int:
    """Write our statusLine into settings.json; exit 2 on conflict with a foreign entry unless --force."""
    data = load_settings()
    existing = data.get("statusLine")
    if existing and not is_ours(existing) and not force:
        # Exit 2 signals conflict; slash command body prompts user via AskUserQuestion
        print("CONFLICT: existing statusLine points elsewhere.", file=sys.stderr)
        print(f"current: {existing.get('command', '')}", file=sys.stderr)
        return 2
    data["statusLine"] = {"type": "command", "command": statusline_cmd()}
    atomic_write(data)
    print(f"installed: {data['statusLine']['command']}")
    return 0


def uninstall() -> int:
    """Remove the statusLine entry only if it's ours; leave foreign entries alone."""
    data = load_settings()
    if not is_ours(data.get("statusLine")):
        print("no plugin statusLine to remove")
        return 0
    data.pop("statusLine")
    atomic_write(data)
    print("removed plugin statusLine")
    return 0


def status() -> int:
    """Report the current statusLine; auto-upgrade an ours-but-stale path to the active plugin version."""
    data = load_settings()
    entry = data.get("statusLine")
    if not entry:
        print("statusLine: unset")
        return 0
    if is_ours(entry):
        current = statusline_cmd()
        if entry.get("command") != current:
            data["statusLine"] = {"type": "command", "command": current}
            atomic_write(data)
            print(f"statusLine (plugin): upgraded → {current}")
            return 0
        print(f"statusLine (plugin): {entry.get('command', '')}")
    else:
        print(f"statusLine (external): {entry.get('command', '')}")
    return 0


if __name__ == "__main__":
    args = sys.argv[1:] or ["status"]
    cmd = args[0]
    force = "--force" in args
    handlers = {
        "install": lambda: install(force),
        "uninstall": uninstall,
        "status": status,
    }
    if cmd not in handlers:
        print(f"unknown command: {cmd}. usage: <install|uninstall|status> [--force]", file=sys.stderr)
        sys.exit(64)
    sys.exit(handlers[cmd]())
