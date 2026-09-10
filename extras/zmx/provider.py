#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
import json
from pathlib import Path
import shutil
import subprocess
import sys

CORE = sys.argv[1] if len(sys.argv) > 1 else "zmx"


def sessions():
    result = subprocess.run(
        [CORE, "list", "--short"], text=True, capture_output=True, timeout=4, check=True
    )
    return result.stdout.splitlines()


def respond(request):
    if request.get("version") != "provider/v1" or request.get("kind") != "request":
        raise ValueError("expected a provider/v1 request")
    capability = request["capability"]
    if capability == "picker.describe":
        return {"title": "Zmx sessions", "icon": "md_console"}
    if capability == "provider.validate":
        if not shutil.which(CORE):
            raise FileNotFoundError("zmx executable is unavailable")
        sessions()
        return {"ok": True}
    if capability == "picker.list":
        return {"items": [
            {"id": name, "search": name, "segments": [
                {"text": name, "role": "name"},
                {"text": "persistent", "role": "detail"},
            ]}
            for name in sessions()
        ]}
    if capability == "picker.open":
        name = request["input"]["id"]
        if name not in sessions():
            raise ValueError("zmx session no longer exists")
        env = shutil.which("env")
        if not env:
            raise FileNotFoundError("env executable is unavailable")
        return {
            "kind": "spawn", "label": name, "cwd": str(Path.home()),
            "command": [env, "-u", "ZMX_SESSION", CORE, "attach", name],
            "environment": {},
        }
    raise ValueError("unsupported capability: " + capability)


def main():
    request = {}
    try:
        request = json.load(sys.stdin)
        output = respond(request)
        result = {"status": "ok", "output": output}
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        result = {"status": "error", "message": str(error)}
    result.update(version="provider/v1", kind="result", requestId=request.get("requestId", "invalid"))
    print(json.dumps(result))


if __name__ == "__main__":
    main()
