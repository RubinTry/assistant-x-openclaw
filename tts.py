#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
TTS 模块 - 基于 Edge TTS
支持中英文自动切换，JARVIS 风格男声
"""

import asyncio
import logging
import os
import re
import threading
import tempfile

import edge_tts
import pygame

logger = logging.getLogger(__name__)

_tts_playing = threading.Event()

# 中英文声音配置
_VOICE_EN = "en-US-GuyNeural"
_VOICE_ZH = "zh-CN-YunjianNeural"
_RATE = "+15%"


def is_tts_playing():
    return _tts_playing.is_set()


def _detect_lang(text: str) -> str:
    zh_count = len(re.findall(r'[\u4e00-\u9fff]', text))
    return "zh" if zh_count / max(len(text), 1) > 0.3 else "en"


def _init_pygame():
    if not pygame.mixer.get_init():
        pygame.mixer.init(frequency=24000, size=-16, channels=2, buffer=1024)


async def _synthesize(text: str, voice: str) -> str | None:
    try:
        tmp = tempfile.NamedTemporaryFile(suffix=".mp3", delete=False)
        tmp.close()
        communicate = edge_tts.Communicate(text, voice, rate=_RATE)
        await communicate.save(tmp.name)
        logger.info(f"合成成功 [{voice}]: {text[:50]}")
        return tmp.name
    except Exception as e:
        logger.error(f"合成失败: {e}")
        return None


def _play_audio(file_path: str, delete_after: bool = True):
    try:
        _init_pygame()
        pygame.mixer.music.load(file_path)
        pygame.mixer.music.play()
        while pygame.mixer.music.get_busy():
            pygame.time.wait(50)
    except Exception as e:
        logger.error(f"播放失败: {e}")
    finally:
        if delete_after:
            try:
                os.unlink(file_path)
            except Exception:
                pass


def _play_prebuilt_voice_sync(name: str) -> bool:
    voices_dir = os.path.join(os.path.dirname(__file__), "voices")
    file_path = os.path.join(voices_dir, f"{name}.mp3")

    if not os.path.exists(file_path):
        return False

    try:
        _tts_playing.set()
        _init_pygame()
        sound = pygame.mixer.Sound(file_path)
        sound.set_volume(1.0)
        sound.play()
        while pygame.mixer.get_busy():
            pygame.time.wait(50)
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
    if not text:
        return

    voice = _VOICE_ZH if _detect_lang(text) == "zh" else _VOICE_EN

    def _speak():
        try:
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            file_path = loop.run_until_complete(_synthesize(text, voice))
            loop.close()
            if file_path:
                _play_audio(file_path)
            else:
                print(f"[TTS] 合成失败，无音频输出")
        except Exception as e:
            print(f"[TTS] 异常: {type(e).__name__}: {e}")
        finally:
            _tts_playing.clear()

    _tts_playing.set()
    t = threading.Thread(target=_speak, daemon=True)
    t.start()
    t.join()
