import json, os, shutil, sys
from pathlib import Path

SETTINGS = Path.home() / ".claude" / "settings.json"
MARKER = "plugins/cache/ai-plugins/claude-assistant/"


def plugin_root() -> Path:
    env = os.environ.get("CLAUDE_PLUGIN_ROOT")
    if env:
        return Path(env)
    here = Path(__file__).resolve()
    for parent in here.parents:
        if (parent / ".claude-plugin" / "plugin.json").exists():
            return parent
    raise RuntimeError("plugin root not located")


def statusline_cmd() -> str:
    script = plugin_root() / "hooks" / "scripts" / "statusline.py"
    return f'python3 "{script}"'


def load_settings() -> dict:
    if not SETTINGS.exists():
        return {}
    return json.loads(SETTINGS.read_text())


def atomic_write(data: dict) -> None:
    SETTINGS.parent.mkdir(parents=True, exist_ok=True)
    if SETTINGS.exists():
        shutil.copy2(SETTINGS, SETTINGS.with_suffix(".json.bak"))
    tmp = SETTINGS.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n")
    os.replace(tmp, SETTINGS)


def is_ours(entry: dict | None) -> bool:
    return bool(entry) and MARKER in entry.get("command", "")


def install(force: bool = False) -> int:
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
    data = load_settings()
    if not is_ours(data.get("statusLine")):
        print("no plugin statusLine to remove")
        return 0
    data.pop("statusLine")
    atomic_write(data)
    print("removed plugin statusLine")
    return 0


def status() -> int:
    data = load_settings()
    entry = data.get("statusLine")
    if not entry:
        print("statusLine: unset")
    else:
        owner = "plugin" if is_ours(entry) else "external"
        print(f"statusLine ({owner}): {entry.get('command', '')}")
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
