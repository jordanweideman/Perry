#!/usr/bin/env python3
"""Add or remove Perry's Claude Code hooks in ~/.claude/settings.json.
Only touches entries tagged 'perry-hook'; everything else is preserved. Writes a .bak first."""
import json, os, shutil, sys

PATH = os.path.expanduser("~/.claude/settings.json")
TAG = "perry-hook"
ROUTES = {                      # Claude Code event -> Perry route
    "UserPromptSubmit": "start",
    "PostToolUse": "start",     # heartbeat: keeps Perry working after a permission prompt
    "Notification": "complete", # Claude is waiting on you
    "Stop": "complete",
    "SessionEnd": "end",
}

def command(route):
    return (f"curl -s -m 1 -X POST --data-binary @- http://127.0.0.1:7717/{route} "
            f">/dev/null 2>&1 || true  # {TAG}")

def is_ours(h): return TAG in h.get("command", "")

def main(action):
    data = json.load(open(PATH)) if os.path.exists(PATH) else {}
    if os.path.exists(PATH): shutil.copy(PATH, PATH + ".bak")
    hooks = data.setdefault("hooks", {})
    for event, route in ROUTES.items():
        groups = hooks.get(event, [])
        kept = []
        for g in groups:
            had = any(is_ours(h) for h in g.get("hooks", []))
            g["hooks"] = [h for h in g.get("hooks", []) if not is_ours(h)]
            if g["hooks"] or not had: kept.append(g)
        if action == "install":
            kept.append({"hooks": [{"type": "command", "command": command(route)}]})
        if kept: hooks[event] = kept
        else: hooks.pop(event, None)
    if not hooks: data.pop("hooks", None)
    with open(PATH, "w") as f:
        json.dump(data, f, indent=2); f.write("\n")
    print(f"hooks {action}ed in {PATH} (backup: {PATH}.bak)")

if __name__ == "__main__":
    a = sys.argv[1] if len(sys.argv) > 1 else "install"
    if a not in ("install", "remove"): sys.exit("usage: hooks.py install|remove")
    main(a)
