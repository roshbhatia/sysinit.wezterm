import json
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
               "capability": capability, "input": {"id": item} if item is not None else {}}
    action = manifest["actions"][capability]
    argv = manifest["command"] + action.get("argv", [])
    result = subprocess.run(argv, input=json.dumps(request) + "\n", text=True,
                            capture_output=True, timeout=5, check=False)
    if result.returncode:
        raise ValueError(result.stderr.strip() or "provider exited " + str(result.returncode))
    answer = None
    for line in result.stdout.splitlines():
        frame = json.loads(line)
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


if __name__ == "__main__":
    try:
        print(json.dumps(call(*sys.argv[1:])))
    except (OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
