#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
TTS 模块 - 基于 Sherpa-onnx 本地离线语音合成 (中英文支持)
"""

import logging
import os
import subprocess
import threading
import time
from pathlib import Path

import audio
import sherpa_onnx_tts

_env_file = Path(__file__).parent.parent / ".env"
if _env_file.exists():
    for line in _env_file.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip())

logger = logging.getLogger(__name__)

_tts_playing = threading.Event()


def is_tts_playing():
    return _tts_playing.is_set()


def stop_tts():
    """停止当前正在播放的 TTS"""
    _tts_playing.clear()
    audio.stop_audio()


def _clean_text_for_tts(text: str) -> str:
    """清理文本，跳过 emoji"""
    import emoji

    cleaned = emoji.replace_emoji(text, "")

    cleaned = cleaned.strip()

    if not cleaned:
        logger.warning(f"文本清理后为空，使用原始文本: {text}")
        cleaned = text.strip()

    return cleaned


def _play_prebuilt_voice_sync(name: str) -> bool:
    voices_dir = os.path.join(os.path.dirname(__file__), "..", "data", "voices")
    file_path = os.path.join(voices_dir, f"{name}.mp3")

    if not os.path.exists(file_path):
        return False

    try:
        _tts_playing.set()
        audio.play_audio_file(file_path, volume=1.0, blocking=True)
        return True
    except Exception as e:
        logger.error(f"播放预生成音频失败: {e}")
        return False
    finally:
        _tts_playing.clear()


def play_prebuilt_voice(name: str, fallback_text: str = None):
    if _play_prebuilt_voice_sync(name):
        return

    if fallback_text:
        logger.info(f"预生成音频不可用，使用实时合成: {fallback_text}")
        text_to_speech_play(fallback_text)
    else:
        logger.error(f"预生成音频不存在且无后备文本: {name}")


def text_to_speech_play(text: str, speed: float = 1.0, **kwargs):
    print(f"[DEBUG tts] text_to_speech_play called: {text[:30]}...")
    if not text:
        print("[TTS] 文本为空")
        return

    cleaned_text = _clean_text_for_tts(text)
    if not cleaned_text:
        print(f"[TTS] 文本清理后为空: {text[:50]}")
        return

    print(f"[TTS] 开始合成 {len(cleaned_text)} 字...", flush=True)

    def _speak():
        try:
            print(f"[DEBUG tts] _speak called, text={cleaned_text[:20]}...")
            if not sherpa_onnx_tts.is_available():
                print("[TTS] Sherpa-onnx TTS 不可用")
                return

            sherpa_onnx_tts.text_to_speech_play(cleaned_text)
            print("[TTS] 播放完成")
        except Exception as e:
            print(f"[TTS] 异常: {type(e).__name__}: {e}")
        finally:
            _tts_playing.clear()

    _tts_playing.set()
    t = threading.Thread(target=_speak, daemon=True)
    t.start()
    t.join()
