import sys
import types
import unittest
from pathlib import Path


SRC = Path(__file__).resolve().parents[1] / "src"
sys.path.insert(0, str(SRC))

import routing


class RoutingLiveDataTests(unittest.TestCase):
    def setUp(self):
        self.previous_light_store = sys.modules.get("light_store")
        sys.modules["light_store"] = types.SimpleNamespace(
            contains=lambda _text: True,
            should_handoff=lambda _text: False,
            matched_agent_intent=lambda _text: "",
        )

    def tearDown(self):
        if self.previous_light_store is None:
            sys.modules.pop("light_store", None)
        else:
            sys.modules["light_store"] = self.previous_light_store

    def test_wake_prefixed_live_sports_request_bypasses_fast_path(self):
        text = "voice-assistant-wake-up-2026-07-14 11:07:17\n目前世界杯的情况怎么样"
        self.assertFalse(routing.is_obviously_light(text))
        self.assertEqual(routing.handoff_intent(text), "live_data")

    def test_plain_greeting_can_still_use_fast_path(self):
        self.assertTrue(routing.is_obviously_light("你好 Jarvis"))
        self.assertEqual(routing.handoff_intent("你好 Jarvis"), "")


if __name__ == "__main__":
    unittest.main()
