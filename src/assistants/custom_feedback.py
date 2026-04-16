#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
通用配置驱动 Feedback — 音效 + HUD + 桌面通知
由 assistants.json 的 feedback_config 驱动
"""

import os
import platform
import subprocess
import threading
import time

from assistants.feedback import AssistantFeedback

try:
    import audio
except ImportError:
    audio = None

_PROJECT_DIR = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
VOICES_DIR = os.path.join(_PROJECT_DIR, "data", "voices")

_DEFAULT_SOUNDS = {
    "init": "system_ready.wav",
    "wake": "wake.wav",
    "processing": "processing_jarvis.wav",
    "thinking": "thinking.wav",
    "execute": "execute.wav",
    "success": "success.wav",
    "error": "error.wav",
    "exit": "exit.wav",
    "blaster": "blaster.wav",
    "waiting": "processing_jarvis.wav",
    "continue": "continue.wav",
}

_DEFAULT_HUD = {
    "init": ["System Online"],
    "exit": ["Standing by..."],
    "error": ["Error"],
    "thinking": ["Thinking..."],
    "waiting": ["Listening..."],
}


class ConfigurableFeedback(AssistantFeedback):
    def __init__(
        self,
        config: dict,
        sound_enabled: bool = True,
        hud_enabled: bool = True,
        notification_enabled: bool = True,
    ):
        self.config = config
        self.sound_enabled = sound_enabled
        self.hud_enabled = hud_enabled
        self.notification_enabled = notification_enabled
        self._lock = threading.Lock()
        self._last_sound_time = {}

        sounds_override = config.get("sounds", {})
        self._sounds = {**_DEFAULT_SOUNDS, **sounds_override}

        self._hud = {}
        for key in ("init", "exit", "error", "thinking", "waiting"):
            self._hud[key] = config.get("hud", {}).get(
                key, _DEFAULT_HUD.get(key, [key.title()])
            )

        self._notification_prefix = config.get("notification_prefix", "Assistant")

    def _play_system_sound(self, sound_name: str):
        if not self.sound_enabled or audio is None:
            return

        sound_file = os.path.join(VOICES_DIR, self._sounds.get(sound_name, ""))
        if not os.path.exists(sound_file):
            print(f"[{self._notification_prefix}] 音效文件不存在: {sound_file}")
            return

        try:
            current_time = time.time()
            last_time = self._last_sound_time.get(sound_name, 0)
            if current_time - last_time < 0.5:
                return
            self._last_sound_time[sound_name] = current_time

            print(f"[{self._notification_prefix}] 播放音效: {sound_name}")
            audio.play_audio_file(sound_file, volume=0.5)
        except Exception as e:
            print(
                f"[{self._notification_prefix}] 播放音效失败 {sound_name}: {type(e).__name__}: {e}"
            )

    def _send_notification(self, title: str, text: str, sound: bool = True):
        if not self.notification_enabled:
            return
        try:
            if platform.system() == "Windows":
                print(f"[{self._notification_prefix} 通知] {title}: {text}")
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
        for line in self._hud.get("init", ["System Online"]):
            print(line)
            time.sleep(0.05)

        self._send_notification(
            self._notification_prefix,
            f"{self._notification_prefix}已就位，随时听候差遣",
            True,
        )

        if blocking:
            self.play_sound("init")
            time.sleep(0.3)
        else:
            self.play_sound("init")

    def on_error(self, msg: str = ""):
        self.play_sound("error")

        def animate():
            frames = self._hud.get("error", ["Error"])
            for frame in frames:
                print(f"\r{50 * ' '}\r✗ {frame}", end="", flush=True)
                time.sleep(0.2)
            print(f"\r{50 * ' '}\r", end="", flush=True)

        t = threading.Thread(target=animate, daemon=True)
        t.start()

        if msg:
            self._send_notification(f"{self._notification_prefix} - 出错了", msg, True)

    def on_exit(self):
        self.play_sound("exit")

        def animate():
            frames = self._hud.get("exit", ["Standing by..."])
            for frame in frames:
                print(f"\r{50 * ' '}\r{frame}", end="", flush=True)
                time.sleep(0.4)
            print(f"\r{50 * ' '}\r", end="", flush=True)

        t = threading.Thread(target=animate, daemon=True)
        t.start()
        self._send_notification(
            self._notification_prefix, f"{self._notification_prefix}已进入待机", True
        )
