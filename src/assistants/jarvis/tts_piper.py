#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Piper TTS 后端 — Jarvis 英音语音合成
模型: jgkawell/jarvis (Piper VITS, en-GB-x-rp, 22050Hz)
"""

import logging
import os
import tempfile
import threading

import numpy as np
import soundfile as sf

logger = logging.getLogger(__name__)

_PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)
))))

MODEL_DIR = os.path.join(
    _PROJECT_DIR, "models", "jarvis", "en", "en_GB", "jarvis", "high"
)
MODEL_PATH = os.path.join(MODEL_DIR, "jarvis-high.onnx")
CONFIG_PATH = os.path.join(MODEL_DIR, "jarvis-high.onnx.json")

_voice = None


def _create_voice():
    global _voice
    if _voice is not None:
        return _voice

    from piper import PiperVoice
    _voice = PiperVoice.load(MODEL_PATH, config_path=CONFIG_PATH)
    logger.info(f"Piper voice loaded, sample_rate={_voice.config.sample_rate}")
    return _voice


def is_available() -> bool:
    return os.path.isfile(MODEL_PATH) and os.path.isfile(CONFIG_PATH)


def _trim_silence(audio_samples, sample_rate, threshold=0.003, keep_ms=200):
    if len(audio_samples) == 0:
        return audio_samples

    keep_samples = int(sample_rate * keep_ms / 1000)
    abs_audio = np.abs(audio_samples)
    last_idx = len(audio_samples)
    for i in range(len(audio_samples) - 1, -1, -1):
        if abs_audio[i] > threshold:
            last_idx = min(len(audio_samples), i + keep_samples)
            break

    return audio_samples[:last_idx]


def _synthesize_raw(text: str) -> tuple[np.ndarray, int] | None:
    """合成文本为 float32 音频数组"""
    voice = _create_voice()
    all_audio = []
    for chunk in voice.synthesize(text):
        all_audio.append(chunk.audio_float_array)

    if not all_audio:
        return None

    audio = np.concatenate(all_audio)
    sr = voice.config.sample_rate
    audio = _trim_silence(audio, sr)
    return (audio, sr)


def synthesize(text: str, output_path: str = None, **kwargs) -> str | None:
    if not is_available():
        logger.error("Piper TTS 不可用")
        return None
    if not text or not text.strip():
        return None

    if output_path is None:
        fd, output_path = tempfile.mkstemp(suffix=".wav")
        os.close(fd)

    try:
        result = _synthesize_raw(text)
        if result is None:
            logger.error("合成失败，音频为空")
            return None

        audio, sr = result
        sf.write(output_path, audio, samplerate=sr, subtype="PCM_16")
        logger.info(f"合成成功: {output_path} ({len(audio)/sr:.2f}s)")
        return output_path
    except Exception as e:
        logger.error(f"合成异常: {e}")
        return None


def synthesize_to_array(text: str, **kwargs) -> tuple[np.ndarray, int] | None:
    if not is_available():
        logger.error("Piper TTS 不可用")
        return None
    if not text or not text.strip():
        return None

    try:
        return _synthesize_raw(text)
    except Exception as e:
        logger.error(f"预合成异常: {e}")
        return None


def synthesize_streaming(text: str, stop_event: threading.Event = None,
                         volume: float = 1.5) -> bool:
    if not is_available():
        logger.error("Piper TTS 不可用")
        return False
    if not text or not text.strip():
        return False

    try:
        import sounddevice as sd

        result = _synthesize_raw(text)
        if stop_event and stop_event.is_set():
            return False
        if result is None:
            return False

        audio, sr = result
        if len(audio) == 0:
            return False

        sd.play(audio * volume, samplerate=sr)
        sd.wait()
        return True
    except Exception as e:
        logger.warning(f"合成播放失败: {e}")
        return False
