import importlib.util
import json
import pathlib
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("picker_call", ROOT / "scripts/picker-call.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class PickerTest(unittest.TestCase):
    def test_create_sends_name_without_shell_interpolation(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest = self.provider(directory, 'print(json.dumps({"version":"provider/v1","kind":"result","requestId":r["requestId"],"status":"ok","output":r["input"]}))')
            path = pathlib.Path(manifest)
            document = json.loads(path.read_text())
            document["actions"]["picker.create"] = {}
            path.write_text(json.dumps(document))
            self.assertEqual(runner.call(manifest, "picker.create", "name with spaces; $HOME"), {"name": "name with spaces; $HOME"})

    def test_catalog_advertises_creation_only_from_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest = pathlib.Path(directory) / "provider.json"
            manifest.write_text(json.dumps({"actions": {"picker.create": {}}}))
            with patch.object(runner, "call", side_effect=lambda _, capability: {"capability": capability}):
                result = runner.catalog(str(manifest))
                self.assertTrue(result["can_create"])
                self.assertEqual(result["listed"], {"capability": "picker.list"})
                manifest.write_text(json.dumps({"actions": {}}))
                self.assertFalse(runner.catalog(str(manifest))["can_create"])

    def test_background_result_is_private_and_reports_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            output = pathlib.Path(directory) / "result"
            output.touch()
            runner.write_catalog(str(pathlib.Path(directory) / "missing"), str(output))
            self.assertFalse(json.loads(output.read_text())["ok"])
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)
            output.unlink()
            runner.write_catalog(str(pathlib.Path(directory) / "missing"), str(output))
            self.assertFalse(output.exists(), "cancelled job recreated its output")

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
