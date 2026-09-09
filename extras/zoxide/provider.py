#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
DEFAULT_CORE = 'zoxide'
TITLE = 'Folders'
ICON = 'md_folder'

import json
import os
import subprocess
import shutil
import sys
from pathlib import Path

CORE = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_CORE

def run(*args):
    result = subprocess.run([CORE, *args], text=True, capture_output=True, timeout=4, check=True)
    return json.loads(result.stdout)

def segment(text, role):
    return {"text": str(text), "role": role}

def paths():
    result = subprocess.run([CORE, "query", "--list"], text=True, capture_output=True, timeout=4, check=True)
    return result.stdout.splitlines()

def items():
    return [{"id": path, "search": path, "segments": [segment(path, "path"), segment("rank " + str(rank), "detail")]}
            for rank, path in enumerate(paths(), 1) if Path(path).is_dir()]

def resolve(item):
    if item not in paths() or not Path(item).is_absolute() or not Path(item).is_dir():
        raise ValueError("indexed directory no longer exists")
    return {"kind": "spawn", "label": Path(item).name, "cwd": item, "command": [], "environment": {}}

def main():
    request = json.load(sys.stdin)
    frame = {"version": "provider/v1", "kind": "result", "requestId": request.get("requestId", "invalid")}
    try:
        if request.get("version") != "provider/v1" or request.get("kind") != "request":
            raise ValueError("expected a provider/v1 request")
        capability = request["capability"]
        if capability == "provider.validate":
            if not shutil.which(CORE):
                raise FileNotFoundError("core executable is unavailable: " + CORE)
            subprocess.run([CORE, "--help"], text=True, capture_output=True, timeout=4, check=True)
            output = {"ok": True}
        elif capability == "picker.describe":
            output = {"title": TITLE, "icon": ICON}
        elif capability == "picker.list":
            output = {"items": items()}
        elif capability == "picker.open":
            output = resolve(request["input"]["id"])
        else:
            raise ValueError("unsupported capability: " + capability)
        frame.update(status="ok", output=output)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        frame.update(status="error", message=str(error))
    print(json.dumps(frame))

if __name__ == "__main__":
    main()
