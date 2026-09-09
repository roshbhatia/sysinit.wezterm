import importlib.util
import json
import pathlib
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("picker_call", ROOT / "scripts/picker-call.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class PickerTest(unittest.TestCase):
    def provider(self, directory, body):
        executable = pathlib.Path(directory) / "provider.py"
        executable.write_text("import json,sys\nr=json.load(sys.stdin)\n" + body)
        manifest = pathlib.Path(directory) / "provider.json"
        manifest.write_text(json.dumps({"version": "provider/v1", "command": [sys.executable, str(executable)],
                                        "actions": {"picker.list": {}}}))
        return str(manifest)

    def test_correlated_result(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest = self.provider(directory, 'print(json.dumps({"version":"provider/v1","kind":"result","requestId":r["requestId"],"status":"ok","output":{"items":[]}}))')
            self.assertEqual(runner.call(manifest, "picker.list"), {"items": []})

    def test_rejects_unrelated_result(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest = self.provider(directory, 'print(json.dumps({"version":"provider/v1","kind":"result","requestId":"other","status":"ok","output":{}}))')
            with self.assertRaisesRegex(ValueError, "unrelated"):
                runner.call(manifest, "picker.list")

    def test_no_result_is_an_error(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest = self.provider(directory, 'print(json.dumps({"version":"provider/v1","kind":"event","requestId":r["requestId"],"event":"progress"}))')
            with self.assertRaisesRegex(ValueError, "no result"):
                runner.call(manifest, "picker.list")
