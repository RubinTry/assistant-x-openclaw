import io
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))
sys.path.insert(0, str(ROOT / "scripts"))

import assistant_lifecycle
import local_api_auth
import voice_context_store


class FakeHandler:
    def __init__(self, headers):
        self.headers = headers
        self.status = None
        self.response_headers = {}
        self.wfile = io.BytesIO()

    def send_response(self, status):
        self.status = status

    def send_header(self, name, value):
        self.response_headers[name] = value

    def end_headers(self):
        pass


class LocalApiAuthTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.runtime = Path(self.tmp.name) / "runtime"
        self.token_path = self.runtime / "local_api.token"
        self.patches = [
            mock.patch.object(local_api_auth, "RUNTIME_DIR", self.runtime),
            mock.patch.object(local_api_auth, "TOKEN_PATH", self.token_path),
        ]
        for patch in self.patches:
            patch.start()
        self.token = local_api_auth.rotate_runtime_token()

    def tearDown(self):
        local_api_auth._active_token = ""
        for patch in reversed(self.patches):
            patch.stop()
        self.tmp.cleanup()

    def test_token_and_directory_are_owner_only(self):
        if os.name != "nt":
            self.assertEqual(stat.S_IMODE(self.runtime.stat().st_mode), 0o700)
            self.assertEqual(stat.S_IMODE(self.token_path.stat().st_mode), 0o600)

    def test_missing_or_wrong_token_is_rejected(self):
        missing = FakeHandler({"Host": "127.0.0.1:18790"})
        self.assertFalse(local_api_auth.authorize_request(missing))
        self.assertEqual(missing.status, 401)
        wrong = FakeHandler({"Host": "127.0.0.1:18790", local_api_auth.HEADER_NAME: "wrong"})
        self.assertFalse(local_api_auth.authorize_request(wrong))
        self.assertEqual(wrong.status, 401)

    def test_valid_token_is_accepted(self):
        handler = FakeHandler({"Host": "127.0.0.1:18790", local_api_auth.HEADER_NAME: self.token})
        self.assertTrue(local_api_auth.authorize_request(handler))

    def test_client_sends_token_in_header_not_url(self):
        response = mock.MagicMock()
        with mock.patch.object(local_api_auth, "urlopen", return_value=response) as opener:
            self.assertIs(local_api_auth.post_local_api("exit"), response)
        request = opener.call_args.args[0]
        self.assertEqual(request.full_url, "http://127.0.0.1:18790/exit")
        headers = {name.lower(): value for name, value in request.header_items()}
        self.assertEqual(headers[local_api_auth.HEADER_NAME.lower()], self.token)
        self.assertNotIn(self.token, request.full_url)

    def test_browser_origin_and_invalid_host_are_rejected(self):
        browser = FakeHandler({"Host": "127.0.0.1:18790", "Origin": "https://evil.example", local_api_auth.HEADER_NAME: self.token})
        self.assertFalse(local_api_auth.authorize_request(browser))
        self.assertEqual(browser.status, 403)
        host = FakeHandler({"Host": "evil.example", local_api_auth.HEADER_NAME: self.token})
        self.assertFalse(local_api_auth.authorize_request(host))
        self.assertEqual(host.status, 403)


class VoiceContextPermissionsTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.store = Path(self.tmp.name) / "voice_context"
        self.patch = mock.patch.object(voice_context_store, "_STORE_DIR", str(self.store))
        self.patch.start()

    def tearDown(self):
        self.patch.stop()
        self.tmp.cleanup()

    def test_new_store_and_log_are_owner_only(self):
        voice_context_store.append_turn("jarvis", "fast_router", "user", "private")
        path = self.store / "jarvis.jsonl"
        self.assertTrue(path.exists())
        if os.name != "nt":
            self.assertEqual(stat.S_IMODE(self.store.stat().st_mode), 0o700)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)

    def test_existing_permissive_log_is_repaired(self):
        self.store.mkdir(mode=0o755)
        path = self.store / "jarvis.jsonl"
        path.write_text("", encoding="utf-8")
        if os.name != "nt":
            path.chmod(0o644)
        voice_context_store.append_turn("jarvis", "fast_router", "user", "private")
        if os.name != "nt":
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)

    def test_symlinked_log_is_not_written(self):
        if not hasattr(os, "symlink"):
            self.skipTest("symlinks unavailable")
        self.store.mkdir(mode=0o700)
        target = Path(self.tmp.name) / "target.txt"
        target.write_text("unchanged", encoding="utf-8")
        os.symlink(target, self.store / "jarvis.jsonl")
        voice_context_store.append_turn("jarvis", "fast_router", "user", "secret")
        self.assertEqual(target.read_text(encoding="utf-8"), "unchanged")


class CameraRemovalTests(unittest.TestCase):
    def test_camera_module_and_permission_declaration_are_removed(self):
        self.assertFalse((ROOT / "src" / "camera.py").exists())
        plist = (ROOT / "control_center" / "macos" / "Runner" / "Info.plist").read_text(encoding="utf-8")
        self.assertNotIn("NSCameraUsageDescription", plist)
        project = (ROOT / "control_center" / "macos" / "Runner.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8")
        self.assertNotIn("RESOURCE_ACCESS_CAMERA", project)
        main = (ROOT / "src" / "main.py").read_text(encoding="utf-8")
        self.assertNotIn("/camera/snapshot", main)


class AssistantLifecycleTests(unittest.TestCase):
    def test_stand_down_uses_authenticated_client_and_validates_response(self):
        response = mock.MagicMock()
        response.read.return_value = b'{"status":"ok"}'
        response.__enter__.return_value = response
        with mock.patch.object(assistant_lifecycle, "post_local_api", return_value=response) as post:
            result = assistant_lifecycle.stand_down(0)
        self.assertEqual(result, {"ok": True, "action": "stand-down", "delay_seconds": 0.0})
        post.assert_called_once_with("exit", timeout=5)

    def test_stand_down_rejects_unbounded_delay_before_calling_api(self):
        with mock.patch.object(assistant_lifecycle, "post_local_api") as post:
            with self.assertRaises(ValueError):
                assistant_lifecycle.stand_down(301)
        post.assert_not_called()

    def test_display_sleep_uses_fixed_argv_without_shell(self):
        with mock.patch.object(assistant_lifecycle.sys, "platform", "darwin"), mock.patch.object(
            assistant_lifecycle, "_run"
        ) as run:
            self.assertTrue(assistant_lifecycle.display_sleep()["ok"])
        run.assert_called_once_with(["/usr/bin/pmset", "displaysleepnow"])

    def test_skill_uses_fixed_workspace_path(self):
        skill = (ROOT / "skills" / "assistant-lifecycle" / "SKILL.md").read_text(encoding="utf-8")
        expected = "$HOME/.openclaw/workspace/voice-assistant/assistant-x-openclaw/scripts/assistant_lifecycle.py"
        self.assertIn(expected, skill)
        self.assertNotIn("curl", skill)


if __name__ == "__main__":
    unittest.main()
