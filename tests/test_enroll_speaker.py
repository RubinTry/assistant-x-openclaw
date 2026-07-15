import sys
import unittest
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import enroll_speaker


class _Result:
    text = " Is JARVIS here "


class _Stream:
    result = _Result()

    def __init__(self):
        self.accepted = None

    def accept_waveform(self, sample_rate, samples):
        self.accepted = (sample_rate, samples)


class _Recognizer:
    def __init__(self):
        self.stream = _Stream()

    def create_stream(self):
        return self.stream

    def decode_stream(self, stream):
        self.decoded = stream


class EnrollmentAsrTests(unittest.TestCase):
    def test_offline_recognition_normalizes_result(self):
        recognizer = _Recognizer()
        samples = np.ones(16000, dtype=np.float32)
        self.assertEqual(
            enroll_speaker.recognize_audio(recognizer, samples),
            "Is JARVIS here",
        )
        self.assertEqual(recognizer.stream.accepted[0], 16000)

    def test_short_noise_is_not_sent_to_recognizer(self):
        recognizer = _Recognizer()
        self.assertEqual(
            enroll_speaker.recognize_audio(
                recognizer, np.ones(100, dtype=np.float32)
            ),
            "",
        )
        self.assertIsNone(recognizer.stream.accepted)

    def test_completed_segments_keep_live_tail_until_final_flush(self):
        sample_rate = 16000
        audio = np.zeros(sample_rate * 2, dtype=np.float32)
        audio[: sample_rate] = 0.2
        live = enroll_speaker.completed_speech_segments(
            audio[:sample_rate], sample_rate, final=False
        )
        final = enroll_speaker.completed_speech_segments(
            audio[:sample_rate], sample_rate, final=True
        )
        self.assertEqual(live, [])
        self.assertTrue(final)


if __name__ == "__main__":
    unittest.main()
