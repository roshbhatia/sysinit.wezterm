#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
import json
import concurrent.futures
import os
import tempfile
import subprocess
import sys
import uuid


def call(manifest_path, capability, item=None):
    with open(manifest_path, encoding="utf-8") as source:
        manifest = json.load(source)
    if manifest.get("version") != "provider/v1" or capability not in manifest["actions"]:
        raise ValueError("provider does not support " + capability)
    request_id = str(uuid.uuid4())
    request = {"version": "provider/v1", "kind": "request", "requestId": request_id,
               "capability": capability, "input": {"name" if capability == "picker.create" else "id": item} if item is not None else {}}
    action = manifest["actions"][capability]
    argv = manifest["command"] + action.get("argv", [])
    result = subprocess.run(argv, input=json.dumps(request) + "\n", text=True,
                            capture_output=True, timeout=5, check=False)
    if result.returncode:
        raise ValueError(result.stderr.strip() or "provider exited " + str(result.returncode))
    answer = None
    for line in result.stdout.splitlines():
        frame = json.loads(line)
        if not isinstance(frame, dict):
            raise ValueError("provider returned an invalid frame")
        if frame.get("version") != "provider/v1" or frame.get("requestId") != request_id:
            raise ValueError("provider returned an unrelated frame")
        if answer is not None:
            raise ValueError("provider wrote after its result")
        if frame.get("kind") == "result":
            answer = frame
        elif frame.get("kind") != "event":
            raise ValueError("provider returned an invalid frame")
    if answer is None or answer.get("status") != "ok":
        raise ValueError((answer or {}).get("message", "provider returned no result"))
    return answer["output"]


def catalog(manifest_path):
    with open(manifest_path, encoding="utf-8") as source:
        manifest = json.load(source)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        description = pool.submit(call, manifest_path, "picker.describe")
        items = pool.submit(call, manifest_path, "picker.list")
        return {"descriptor": description.result(), "listed": items.result(),
                "can_create": "picker.create" in manifest.get("actions", {})}


def write_catalog(manifest_path, destination):
    try:
        result = {"ok": True, "catalog": catalog(manifest_path)}
    except (OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
        result = {"ok": False, "error": str(error)}
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=os.path.dirname(destination), delete=False, encoding="utf-8") as output:
            temporary = output.name
            json.dump(result, output)
        if os.path.exists(destination):
            os.replace(temporary, destination)
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == "__main__":
    try:
        if sys.argv[1] == "--catalog":
            write_catalog(*sys.argv[2:])
        else:
            print(json.dumps(call(*sys.argv[1:])))
    except (OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
