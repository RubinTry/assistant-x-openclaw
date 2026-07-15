import json
import queue
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import sys
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

import main


class WakeModeConfigTests(unittest.TestCase):
    def _load(self, value=...):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "assistants.json"
            config = {}
            if value is not ...:
                config["kwsMode"] = value
            path.write_text(json.dumps(config), encoding="utf-8")
            with mock.patch.object(main, "_ASSISTANTS_CFG_PATH", str(path)):
                return main._load_kws_mode()

    def test_true_selects_traditional_kws(self):
        self.assertTrue(self._load(True))

    def test_false_selects_continuous_wake_asr(self):
        self.assertFalse(self._load(False))

    def test_missing_field_preserves_current_mode(self):
        self.assertFalse(self._load())

    def test_non_boolean_value_is_rejected(self):
        with self.assertRaises(ValueError):
            self._load("true")

    def test_traditional_kws_collects_tail_before_verification(self):
        assistant = object.__new__(main.VoiceAssistant)
        assistant._asr_rate = 16000
        assistant.audio_queue = queue.Queue()
        assistant.verification_audio_queue = queue.Queue()
        assistant._resample_for_asr = lambda samples: np.asarray(
            samples, dtype=np.float32
        )
        for value in (2.0, 3.0, 4.0):
            assistant.audio_queue.put(
                np.full((8000, 1), value, dtype=np.float32)
            )
            assistant.verification_audio_queue.put(
                np.full((8000, 1), value + 10, dtype=np.float32)
            )

        clean, raw = assistant._collect_kws_verification_tail(
            np.ones(16000, dtype=np.float32),
            np.full(16000, 11.0, dtype=np.float32),
            target_seconds=2.5,
            max_wait_seconds=0.5,
        )
        self.assertEqual(len(clean), 40000)
        self.assertEqual(len(raw), 40000)
        self.assertEqual(clean[-1], 4.0)
        self.assertEqual(raw[-1], 14.0)

    def test_long_kws_window_does_not_consume_more_audio(self):
        assistant = object.__new__(main.VoiceAssistant)
        assistant._asr_rate = 16000
        assistant.audio_queue = queue.Queue()
        assistant.verification_audio_queue = queue.Queue()
        clean, raw = assistant._collect_kws_verification_tail(
            np.ones(48000, dtype=np.float32),
            np.ones(48000, dtype=np.float32),
            target_seconds=2.5,
            max_wait_seconds=0.5,
        )
        self.assertEqual(len(clean), 40000)
        self.assertEqual(len(raw), 40000)
        self.assertTrue(assistant.audio_queue.empty())


if __name__ == "__main__":
    unittest.main()
