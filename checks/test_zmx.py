import importlib.util
import pathlib
import subprocess
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("zmx_picker", ROOT / "extras/zmx/provider.py")
provider = importlib.util.module_from_spec(spec)
spec.loader.exec_module(provider)
provider.CORE = "/runtime/zmx"


class ZmxTest(unittest.TestCase):
    def request(self, capability, name="review build"):
        return {"version": "provider/v1", "kind": "request", "capability": capability, "input": {"id": name}}

    @patch.object(provider.subprocess, "run")
    def test_lists_names_without_splitting_spaces(self, run):
        run.return_value.stdout = "review build\ninfra\n"
        output = provider.respond(self.request("picker.list"))
        self.assertEqual([item["id"] for item in output["items"]], ["review build", "infra"])
        self.assertEqual(run.call_args.args[0], ["/runtime/zmx", "list", "--short"])

    @patch.object(provider.shutil, "which", return_value="/runtime/env")
    @patch.object(provider.subprocess, "run")
    def test_attach_unsets_inherited_session(self, run, _which):
        run.return_value.stdout = "review build\n"
        output = provider.respond(self.request("picker.open"))
        self.assertEqual(output["command"], ["/runtime/env", "-u", "ZMX_SESSION", "/runtime/zmx", "attach", "review build"])
        self.assertEqual(output["label"], "review build")

    @patch.object(provider.subprocess, "run")
    def test_stale_session_is_not_created(self, run):
        run.return_value.stdout = ""
        with self.assertRaisesRegex(ValueError, "no longer exists"):
            provider.respond(self.request("picker.open"))

    @patch.object(provider.subprocess, "run", side_effect=subprocess.TimeoutExpired("zmx", 4))
    def test_timeout_is_not_an_empty_list(self, _run):
        with self.assertRaises(subprocess.TimeoutExpired):
            provider.respond(self.request("picker.list"))
