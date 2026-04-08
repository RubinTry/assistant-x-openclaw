#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
JARVIS 风格反馈系统
音效 + HUD 动画 + 桌面通知
"""

import os
import platform
import subprocess
import threading
import time
from typing import Optional

import audio

VOICES_DIR = os.path.join(os.path.dirname(__file__), "..", "data", "voices")

_JAWESOME_SOUNDS = {
    "init": "system_ready.wav",
    "wake": "wake.wav",
    "processing": "processing.wav",
    "thinking": "thinking.wav",
    "execute": "execute.wav",
    "success": "success.wav",
    "error": "error.wav",
    "exit": "exit.wav",
    "blaster": "blaster.wav",
    "waiting": "processing.wav",
    "continue": "continue.wav",
}

_HUD_FRAMES = {
    "init": [
        "━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
        "◢███████████████◣",
        "◢█████████████████████◣",
        "◢█████████████████████◣",
        "◢███████████████████████◣",
        "◢███████████████████████████◣",
        " JARVIS CORE INITIALIZED",
        "━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
    ],
    "exit": [
        "\rstandby...",
        "\rstanding by...",
        "\rready for commands...",
    ],
}


class JarvisFeedback:
    def __init__(
        self,
        sound_enabled: bool = True,
        hud_enabled: bool = True,
        notification_enabled: bool = True,
    ):
        self.sound_enabled = sound_enabled
        self.hud_enabled = hud_enabled
        self.notification_enabled = notification_enabled
        self._lock = threading.Lock()
        self._last_sound_time = {}

    def _play_system_sound(self, sound_name: str):
        if not self.sound_enabled:
            print(f"[JARVIS] 音效未启用，跳过: {sound_name}")
            return
        sound_file = os.path.join(VOICES_DIR, _JAWESOME_SOUNDS.get(sound_name, ""))
        if not os.path.exists(sound_file):
            print(f"[JARVIS] 音效文件不存在: {sound_file}")
            return
        try:
            current_time = time.time()
            last_time = self._last_sound_time.get(sound_name, 0)
            if current_time - last_time < 0.5:
                return
            self._last_sound_time[sound_name] = current_time
            audio.play_audio_file(sound_file, volume=0.5)
            print(f"[JARVIS] 播放音效: {sound_name}")
        except Exception as e:
            print(f"[JARVIS] 播放音效失败 {sound_name}: {type(e).__name__}: {e}")

    def _send_notification(self, title: str, text: str, sound: bool = True):
        if not self.notification_enabled:
            return
        try:
            if platform.system() == "Windows":
                print(f"[JARVIS 通知] {title}: {text}")
                return
            script = f'display notification "{text}" with title "{title}"'
            if sound:
                script += ' sound name "Glass"'
            subprocess.run(["osascript", "-e", script], capture_output=True, timeout=2)
        except Exception:
            pass

    def play_sound(self, sound_type: str):
        t = threading.Thread(
            target=self._play_system_sound, args=(sound_type,), daemon=True
        )
        t.start()

    def system_ready(self, blocking=False):
        print("\n")
        for line in _HUD_FRAMES["init"]:
            print(line)
            time.sleep(0.05)
        self._send_notification("JARVIS", "系统初始化完成，随时待命", True)
        if blocking:
            time.sleep(0.3)
            self.play_sound("init")
        else:
            self.play_sound("init")

    def on_error(self, msg: str = ""):
        self.play_sound("error")

        def animate():
            for frame in _HUD_FRAMES["error"]:
                print(f"\r{50 * ' '}\r✗ {frame}", end="", flush=True)
                time.sleep(0.2)
            print(f"\r{50 * ' '}\r", end="", flush=True)

        t = threading.Thread(target=animate, daemon=True)
        t.start()
        if msg:
            self._send_notification("JARVIS - ERROR", msg, True)

    def on_exit(self):
        self.play_sound("exit")

        def animate():
            for frame in _HUD_FRAMES["exit"]:
                print(f"\r{50 * ' '}\r{frame}", end="", flush=True)
                time.sleep(0.4)
            print(f"\r{50 * ' '}\r", end="", flush=True)

        t = threading.Thread(target=animate, daemon=True)
        t.start()
        self._send_notification("JARVIS", "已进入待机模式", True)


_feedback_instance: Optional[JarvisFeedback] = None


def get_feedback(
    sound_enabled: bool = True,
    hud_enabled: bool = True,
    notification_enabled: bool = True,
) -> JarvisFeedback:
    global _feedback_instance
    if _feedback_instance is None:
        _feedback_instance = JarvisFeedback(
            sound_enabled, hud_enabled, notification_enabled
        )
    return _feedback_instance
