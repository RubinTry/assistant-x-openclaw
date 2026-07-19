import json
import os
import sys
import unittest
from unittest.mock import Mock, patch


sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

import hermes_bridge


class _Response:
    def __init__(self, lines=None, *, status_code=200, data=None):
        self.status_code = status_code
        self._lines = lines or []
        self._data = data or {}
        self.text = json.dumps(self._data)

    def iter_lines(self, decode_unicode=True):
        return iter(self._lines)

    def json(self):
        return self._data

    def close(self):
        pass


def _sse(payload):
    return "data: " + json.dumps(payload)


class HermesBridgeStreamTests(unittest.TestCase):
    def setUp(self):
        self.bridge = hermes_bridge.HermesBridge(gateway_url="http://hermes", agent_id="main")
        self.bridge.key = "test-key"
        self.bridge._record_voice_turn = Mock()

    @patch("hermes_bridge.requests.get")
    @patch("hermes_bridge.requests.post")
    def test_recovers_persisted_reply_when_success_stream_has_no_content(self, post, get):
        post.return_value = _Response([
            _sse({"choices": [{"delta": {"role": "assistant"}, "finish_reason": None}]}),
            _sse({"choices": [{"delta": {}, "finish_reason": "stop"}]}),
            "data: [DONE]",
        ])
        get.return_value = _Response(data={"data": [
            {"role": "assistant", "content": "old answer"},
            {"role": "user", "content": "扫描我哪些软件开着"},
            {"role": "assistant", "content": "Finder and Terminal are open."},
        ]})
        chunks = []

        reply = self.bridge.send_and_wait_stream("扫描我哪些软件开着", on_chunk=chunks.append)

        self.assertEqual(reply, "Finder and Terminal are open.")
        self.assertEqual(chunks, ["Finder and Terminal are open."])
        self.assertEqual(post.call_count, 1)
        self.bridge._record_voice_turn.assert_called_once_with(
            "扫描我哪些软件开着", "Finder and Terminal are open."
        )

    @patch("hermes_bridge.requests.get")
    @patch("hermes_bridge.requests.post")
    def test_does_not_recover_stale_answer_without_matching_user_turn(self, post, get):
        post.return_value = _Response([
            _sse({"choices": [{"delta": {}, "finish_reason": "stop"}]}),
            "data: [DONE]",
        ])
        get.return_value = _Response(data={"data": [
            {"role": "user", "content": "different request"},
            {"role": "assistant", "content": "stale answer"},
        ]})

        self.assertIsNone(self.bridge.send_and_wait_stream("current request"))
        self.bridge._record_voice_turn.assert_not_called()

    @patch("hermes_bridge.requests.get")
    @patch("hermes_bridge.requests.post")
    def test_error_finish_does_not_attempt_session_recovery(self, post, get):
        post.return_value = _Response([
            _sse({
                "choices": [{"delta": {}, "finish_reason": "error"}],
                "error": {"message": "provider failed"},
            }),
            "data: [DONE]",
        ])

        self.assertIsNone(self.bridge.send_and_wait_stream("hello"))
        get.assert_not_called()


if __name__ == "__main__":
    unittest.main()
