import json
import os
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from edwin.memory import EdwinMemoryStore
from edwin.security import ApprovalRequest, RiskLevel, requires_confirmation
from edwin.skills import load_skills
from edwin.tools import default_registry
from edwin.tools.base import Tool, ToolResult, ToolSpec
from edwin.tools.registry import ToolRegistry
from edwin.runtime import AgentRuntime, ApprovalRequired
from edwin.model import ModelTurn
from edwin_bridge import EdwinBridge
from fast_router import FastRouterClient, _routing_system_prompt
import voice_context_store


class EdwinMemoryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.store = EdwinMemoryStore(Path(self.tmp.name) / "edwin.db", idle_gap=1800)

    def tearDown(self): self.tmp.cleanup()

    def test_sessions_are_isolated_and_clear_is_non_destructive(self):
        jarvis = self.store.session("jarvis")
        lin = self.store.session("lin_meimei")
        self.assertNotEqual(jarvis, lin)
        self.store.add_message(jarvis, "r1", "user", "hello")
        self.assertEqual(self.store.recent("jarvis")[-1]["content"], "hello")
        self.store.clear("jarvis")
        self.assertEqual(self.store.recent("jarvis"), [])

    def test_explicit_memory_fts(self):
        self.store.add_memory("jarvis", "Sir prefers concise technical answers")
        self.assertIn("concise", self.store.search("jarvis", "concise technical")[0])
        self.assertEqual(self.store.search("lin_meimei", "concise technical"), [])

    def test_reconstructed_store_recovers_active_session_within_idle_gap(self):
        sid = self.store.session("jarvis")
        self.store.add_message(sid, "r1", "user", "first turn")
        reconstructed = EdwinMemoryStore(self.store.path, idle_gap=1800)
        self.assertEqual(reconstructed.session("jarvis"), sid)
        self.assertEqual(reconstructed.recent("jarvis")[-1]["content"], "first turn")

    def test_reconstructed_store_rolls_session_after_idle_gap(self):
        sid = self.store.session("jarvis")
        with self.store._connect() as db:
            db.execute("UPDATE sessions SET last_activity=? WHERE id=?", (time.time() - 1900, sid))
        reconstructed = EdwinMemoryStore(self.store.path, idle_gap=1800)
        self.assertNotEqual(reconstructed.session("jarvis"), sid)

    def test_message_completion_refreshes_session_idle_clock(self):
        sid = self.store.session("jarvis")
        with self.store._connect() as db:
            db.execute("UPDATE sessions SET last_activity=? WHERE id=?", (time.time() - 1900, sid))
        self.store.add_message(sid, "r1", "assistant", "finished")
        reconstructed = EdwinMemoryStore(self.store.path, idle_gap=1800)
        self.assertEqual(reconstructed.session("jarvis"), sid)


class EdwinSecurityTests(unittest.TestCase):
    def test_fast_router_assistant_id_cannot_be_overridden_by_mixed_role_text(self):
        prompt = _routing_system_prompt("林妹妹", "称呼用户为哥哥，自称妹妹", "jarvis")
        self.assertIn("Always reply in English", prompt)
        self.assertNotIn("称呼用户为「哥哥」", prompt)

    def test_cross_persona_shared_context_is_quarantined(self):
        self.assertTrue(voice_context_store._obvious_cross_persona_leak("jarvis", "assistant", "哥哥，妹妹在这儿呢"))
        self.assertFalse(voice_context_store._obvious_cross_persona_leak("jarvis", "user", "叫我哥哥"))
        self.assertFalse(voice_context_store._obvious_cross_persona_leak("lin_meimei", "assistant", "哥哥，妹妹在这儿呢"))

    def test_fast_router_context_excludes_other_engines(self):
        router = FastRouterClient(agent_id="jarvis", engine="edwin")
        with mock.patch("fast_router.voice_context_store.recent_turns", return_value=[]) as recent:
            router._prior_messages("hello")
        self.assertEqual(recent.call_args.kwargs["lanes"], {"fast_router", "fast", "edwin"})

    def test_skill_python_dependencies_import(self):
        import openai  # noqa: F401
        import requests  # noqa: F401
        import websocket  # noqa: F401

    def test_digest_binds_arguments(self):
        a = ApprovalRequest("r", "c", "run_command", {"command": "echo ok"}, RiskLevel.DESTRUCTIVE, "x")
        b = ApprovalRequest("r", "c", "run_command", {"command": "rm x"}, RiskLevel.DESTRUCTIVE, "x")
        self.assertNotEqual(a.digest, b.digest)
        self.assertTrue(requires_confirmation(RiskLevel.DESTRUCTIVE))
        self.assertFalse(requires_confirmation(RiskLevel.READ))

    def test_registry_has_core_tools_and_shell_needs_approval(self):
        registry = default_registry()
        self.assertTrue({"read_file", "search_files", "run_command", "web_search", "read_screen", "list_applications", "open_application", "display_sleep", "lock_screen", "stand_down", "system_health", "list_processes", "disk_usage", "network_status", "power_status"} <= registry.names())
        self.assertEqual(registry.get("run_command").spec.risk_level, RiskLevel.DESTRUCTIVE)
        self.assertEqual(registry.get("open_application").spec.risk_level, RiskLevel.WRITE)
        self.assertEqual(registry.get("display_sleep").spec.risk_level, RiskLevel.WRITE)
        self.assertEqual(registry.get("lock_screen").spec.risk_level, RiskLevel.WRITE)
        self.assertEqual(registry.get("stand_down").spec.risk_level, RiskLevel.WRITE)
        self.assertFalse(requires_confirmation(registry.get("lock_screen").spec.risk_level))
        self.assertEqual(registry.get("system_health").spec.risk_level, RiskLevel.READ)
        self.assertEqual(registry.get("runtime_identity").spec.risk_level, RiskLevel.READ)
        identity = registry.get("runtime_identity").handler({}, threading.Event())
        self.assertEqual(json.loads(identity.content)["engine"], "edwin")

    def test_read_only_shell_capabilities_are_redirected_before_approval(self):
        cases = {
            "top -l 1 -n 0 | head -20": "system_health",
            "ps aux": "list_processes",
            "df -h": "disk_usage",
            "pmset -g batt": "power_status",
            "scutil --nwi": "network_status",
            "pmset displaysleepnow": "display_sleep",
        }
        for command, expected in cases.items():
            call = {"name": "run_command", "arguments": {"command": command}}
            self.assertEqual(AgentRuntime._preferred_tool_for_command(call), expected)
        self.assertIsNone(AgentRuntime._preferred_tool_for_command({"name": "run_command", "arguments": {"command": "rm -rf target"}}))

    @unittest.skipUnless(sys.platform == "darwin", "macOS application discovery")
    def test_builtin_application_discovery_finds_netease(self):
        result = default_registry().get("list_applications").handler({}, threading.Event())
        self.assertTrue(result.ok)
        self.assertIn("NeteaseMusic", result.content)

    @unittest.skipUnless(sys.platform == "darwin", "macOS application launch resolution")
    def test_netease_english_name_does_not_match_system_music(self):
        from edwin.tools.builtin import _resolve_macos_application
        result = _resolve_macos_application("NetEase Cloud Music")
        self.assertIsNotNone(result)
        self.assertEqual(result.name, "NeteaseMusic.app")

    def test_ordinary_desktop_click_is_write_but_submit_is_external(self):
        ordinary = {"name": "desktop_control", "arguments": {"action": "click", "arguments": ["play"]}}
        submit = {"name": "desktop_control", "arguments": {"action": "click", "arguments": ["submit order"]}}
        self.assertEqual(AgentRuntime._effective_risk(RiskLevel.WRITE, ordinary), RiskLevel.WRITE)
        self.assertEqual(AgentRuntime._effective_risk(RiskLevel.WRITE, submit), RiskLevel.EXTERNAL)

    def test_stand_down_uses_bounded_delay_and_local_exit_endpoint(self):
        registry = default_registry()
        response = mock.MagicMock()
        with mock.patch("local_api_auth.post_local_api", return_value=response) as post:
            result = registry.get("stand_down").handler({"delay_seconds": 0}, threading.Event())
        self.assertTrue(result.ok)
        post.assert_called_once_with("exit", timeout=5)

    def test_soft_stop_does_not_discard_pending_approval(self):
        bridge = object.__new__(EdwinBridge)
        bridge._lock = threading.RLock()
        bridge._current_request_id = None
        bridge._soft_stopped = set()
        bridge._pending = object()
        bridge._unclear_count = 0
        self.assertFalse(bridge.send_stop_command())
        self.assertIsNotNone(bridge._pending)
        bridge.clear_pending_approval()
        self.assertIsNone(bridge._pending)

    def test_read_screen_removes_owned_temporary_capture(self):
        captured = {}

        class FakeImage:
            def save(self, path, format=None):
                captured["path"] = path
                Path(path).write_bytes(b"png")

        def fake_ocr(path):
            self.assertTrue(os.path.exists(path))
            return ["visible text"]

        with mock.patch("edwin.screen_reader._request_macos_screen_permission", return_value=True), \
             mock.patch("PIL.ImageGrab.grab", return_value=FakeImage()), \
             mock.patch("edwin.screen_reader._vision_ocr", side_effect=fake_ocr):
            from edwin.screen_reader import read_screen
            result = read_screen(threading.Event())
        self.assertTrue(result.ok)
        self.assertEqual(result.content, "visible text")
        self.assertFalse(os.path.exists(captured["path"]))

    def test_explicit_screen_capture_path_is_preserved(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = os.path.join(tmp, "keep.png")

            def fake_run(argv, _cancel, timeout=30, cwd=None):
                Path(target).write_bytes(b"png")
                return ToolResult(True, target)

            with mock.patch("edwin.tools.builtin._ensure_peekaboo_permissions", return_value=None), \
                 mock.patch("edwin.tools.builtin._run", side_effect=fake_run):
                default_registry().get("desktop_observe").handler(
                    {"action": "image", "arguments": ["--path", target]},
                    threading.Event(),
                )
            self.assertTrue(os.path.exists(target))

    def test_existing_skills_are_discovered(self):
        skills = {s.name: s for s in load_skills(ROOT / "skills", default_registry().names())}
        self.assertIn("desktop-control", skills)
        self.assertIn("browser-cdp", skills)


class ModelSlotTests(unittest.TestCase):
    def test_agent_slot_is_separate(self):
        import model_store
        with tempfile.TemporaryDirectory() as tmp, \
             mock.patch.object(model_store, "MODEL_TABLE_PATH", os.path.join(tmp, "models.json")), \
             mock.patch.object(model_store, "_KEY_PATH", os.path.join(tmp, ".key")):
            model_store._fernet = None
            first = model_store.upsert_model({"label": "router", "provider": "test", "base_url": "http://localhost/v1", "model": "router", "api_key": "x"})
            second = model_store.upsert_model({"label": "agent", "provider": "test", "base_url": "http://localhost/v1", "model": "agent", "api_key": "x"})
            model_store.set_agent_current(second["id"])
            table = model_store.list_models()
            self.assertEqual(table["current"], first["id"])
            self.assertEqual(table["agent_current"], second["id"])
            self.assertEqual(model_store.get_agent_decrypted()["model"], "agent")
            model_store._fernet = None


class RuntimeTests(unittest.TestCase):
    def test_external_tool_pauses_then_resumes_once(self):
        tmp = tempfile.TemporaryDirectory()
        store = EdwinMemoryStore(Path(tmp.name) / "edwin.db")
        calls = []
        registry = ToolRegistry()
        registry.register(Tool(
            ToolSpec("send_action", "send", {"type": "object", "properties": {}}, RiskLevel.EXTERNAL),
            lambda _a, _c: calls.append("ran") or ToolResult(True, "sent"),
        ))
        runtime = AgentRuntime("jarvis", memory=store, registry=registry)

        class Provider:
            count = 0
            def generate(self, _messages, _tools, _cancel, on_text=None, on_tool=None):
                self.count += 1
                if self.count == 1:
                    return ModelTurn("", [{"id": "c1", "name": "send_action", "arguments": {}, "arguments_json": "{}"}])
                if on_text: on_text("Done")
                return ModelTurn("Done", [])

        provider = Provider()
        runtime._provider = lambda: provider
        cancel = threading.Event()
        with mock.patch("edwin.runtime.voice_context_store.append_turn"), \
             mock.patch("edwin.runtime.voice_context_store.recent_fast_router_context", return_value=[]):
            with self.assertRaises(ApprovalRequired) as caught:
                runtime.run("send it", cancel, request_id="r1")
            self.assertEqual(calls, [])
            result = runtime.run("yes", cancel, request_id="r1", resume=caught.exception.state, approved=True)
        self.assertEqual(result, "Done")
        self.assertEqual(calls, ["ran"])
        tmp.cleanup()


if __name__ == "__main__": unittest.main()
