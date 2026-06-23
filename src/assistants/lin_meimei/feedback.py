#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
林妹妹风格反馈系统
音效 + HUD 动画 + 桌面通知
"""

import os
import platform
import subprocess
import threading
import time
from typing import Optional

from assistants.feedback import AssistantFeedback

try:
    import audio
except ImportError:
    audio = None

VOICES_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "..", "data", "voices")

# 林妹妹复用同一套音效文件，后续可替换为专属音效
_SOUNDS = {
    "init": "system_ready.wav",
    "wake": "wake.wav",
    "processing": "processing_linmeimei.wav",
    "thinking": "thinking.wav",
    "execute": "execute.wav",
    "success": "success.wav",
    "error": "error.wav",
    "exit": "exit.wav",
    "blaster": "blaster.wav",
    "waiting": "processing_linmeimei.wav",
    "continue": "continue.wav",
}

_HUD_FRAMES = {
    "init": [
        "～～～～～～～～～～～～～～～～～～～～",
        "　　　　🌸 林妹妹驾到 🌸",
        "～～～～～～～～～～～～～～～～～～～～",
    ],
    "exit": [
        "妹妹歇着了...",
        "有事再唤妹妹...",
    ],
    "error": [
        "哎呀，出岔子了...",
        "这可不妙...",
    ],
    "thinking": [
        "容妹妹想想...",
        "且慢，让我琢磨琢磨...",
    ],
    "waiting": [
        "妹妹在听呢...",
        "哥哥请讲...",
    ],
}


class LinMeimeiFeedback(AssistantFeedback):
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
        if not self.sound_enabled or audio is None:
            return

        sound_file = os.path.join(VOICES_DIR, _SOUNDS.get(sound_name, ""))
        if not os.path.exists(sound_file):
            print(f"[林妹妹] 音效文件不存在: {sound_file}")
            return

        try:
            current_time = time.time()
            last_time = self._last_sound_time.get(sound_name, 0)
            if current_time - last_time < 0.5:
                return
            self._last_sound_time[sound_name] = current_time

            print(f"[林妹妹] 播放音效: {sound_name}")
            audio.play_audio_file(sound_file, volume=0.5)
        except Exception as e:
            print(f"[林妹妹] 播放音效失败 {sound_name}: {type(e).__name__}: {e}")

    def _send_notification(self, title: str, text: str, sound: bool = True):
        if not self.notification_enabled:
            return
        try:
            # 优先让 control_center 弹通知（图标为其自身 bundle 图标，更美观）
            from notify_bridge import notify_control_center

            if notify_control_center(title, text, sound):
                return

            # 回退：control_center 未运行时用原生通知
            if platform.system() == "Windows":
                print(f"[林妹妹 通知] {title}: {text}")
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
        for line in _HUD_FRAMES.get("init", ["妹妹来了"]):
            print(line)
            time.sleep(0.05)

        self._send_notification("林妹妹", "妹妹已就位，随时听候差遣", True)

        if blocking:
            self.play_sound("init")
            time.sleep(0.3)
        else:
            self.play_sound("init")

    def on_error(self, msg: str = ""):
        self.play_sound("error")

        def animate():
            frames = _HUD_FRAMES.get("error", ["出错了..."])
            for frame in frames:
                print(f"\r{50 * ' '}\r✗ {frame}", end="", flush=True)
                time.sleep(0.2)
            print(f"\r{50 * ' '}\r", end="", flush=True)

        t = threading.Thread(target=animate, daemon=True)
        t.start()

        if msg:
            self._send_notification("林妹妹 - 出错了", msg, True)

    def on_exit(self):
        self.play_sound("exit")

        def animate():
            frames = _HUD_FRAMES.get("exit", ["告退了..."])
            for frame in frames:
                print(f"\r{50 * ' '}\r{frame}", end="", flush=True)
                time.sleep(0.4)
            print(f"\r{50 * ' '}\r", end="", flush=True)

        t = threading.Thread(target=animate, daemon=True)
        t.start()
        self._send_notification("林妹妹", "妹妹先歇着了", True)
