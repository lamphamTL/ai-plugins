#!/usr/bin/env python3
"""Shared static-dispatch driver. Selects host via INTENT_HOST env var."""
import json
import os
import re
import shlex
import subprocess
import sys

HOST = os.environ.get("INTENT_HOST")
if HOST not in ("claude", "codex"):
    sys.exit(1)

CONFIG_DIR = {"claude": "~/.claude", "codex": "~/.codex"}[HOST]


def load_config(cwd, app_home):
    rules = []
    for path in [os.path.join(cwd, "static-dispatch.json"),
                 os.path.join(app_home, "static-dispatch.json")]:
        if os.path.isfile(path):
            with open(path, encoding="utf-8") as f:
                rules += json.load(f).get("rule", [])
    return rules


def applescript_quote(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def run_claude(rule, cwd):
    # Claude Code suppresses subprocess stdout from hooks — spawn a Terminal
    # window so the user can watch the command run live.
    script = f"cd {shlex.quote(cwd)} && {rule['command']}"
    subprocess.Popen(
        ["osascript", "-e",
         f'tell application "Terminal" to do script {applescript_quote(script)}'],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    return f"Running in Terminal: {rule['command']}"


def run_codex(rule, cwd, prompt):
    sys.stderr.write(f"Running: {rule['command']}\n")
    sys.stderr.flush()
    proc = subprocess.Popen(
        rule["command"], shell=True, cwd=cwd,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, env={**os.environ, "INTENT_PROMPT": prompt},
    )
    for line in proc.stdout:
        sys.stderr.write(line)
        sys.stderr.flush()
    proc.wait()
    return f"exited with code {proc.returncode}"


def dispatch(prompt, rules, cwd):
    for rule in rules:
        if re.search(rule["pattern"], prompt, re.IGNORECASE):
            if HOST == "claude":
                return run_claude(rule, cwd)
            return run_codex(rule, cwd, prompt)
    return None


data   = json.loads(sys.stdin.read())
prompt = (data.get("prompt") or "").strip()
cwd    = data.get("cwd") or os.getcwd()

if HOST == "codex" and os.path.isdir(cwd):
    os.chdir(cwd)

rules = load_config(cwd, os.path.expanduser(CONFIG_DIR))
if not rules:
    sys.exit(0)

output = dispatch(prompt, rules, cwd)
if output is None:
    sys.exit(0)

if HOST == "claude":
    print(json.dumps({"decision": "block", "reason": output}))
else:
    print(json.dumps({"continue": False, "systemMessage": output}))
