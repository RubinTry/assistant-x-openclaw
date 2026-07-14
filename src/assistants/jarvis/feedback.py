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

from assistants.feedback import AssistantFeedback

# 假设同目录下有 audio.py 处理底层音频播放
try:
    import audio
except ImportError:
    # 防止由于环境问题导致导入失败
    audio = None

VOICES_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "..", "data", "voices")

_JAWESOME_SOUNDS = {
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
        "STANDBY...",
        "STANDING BY...",
        "READY FOR COMMANDS...",
    ],
    "error": [
        "SYSTEM FAILURE",
        "CRITICAL ERROR",
        "ATTENTION REQUIRED",
        "UNABLE TO PROCESS"
    ],
    "thinking": [
        "ANALYZING...",
        "ACCESSING CORE...",
        "PROCESSING DATA..."
    ],
    "waiting": [
        "LISTENING...",
        "IDLE...",
        "AWAITING INPUT..."
    ]
}


class JarvisFeedback(AssistantFeedback):
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
            
        sound_file = os.path.join(VOICES_DIR, _JAWESOME_SOUNDS.get(sound_name, ""))
        if not os.path.exists(sound_file):
            print(f"[JARVIS] 音效文件不存在: {sound_file}")
            return
            
        try:
            current_time = time.time()
            last_time = self._last_sound_time.get(sound_name, 0)
            # 简单的防抖：同一种音效 0.5 秒内不重复播放
            if current_time - last_time < 0.5:
                return
            self._last_sound_time[sound_name] = current_time
            
            print(f"[JARVIS] 播放音效: {sound_name}")
            audio.play_audio_file(sound_file, volume=0.5)
        except Exception as e:
            print(f"[JARVIS] 播放音效失败 {sound_name}: {type(e).__name__}: {e}")

    def _send_notification(self, title: str, text: str, sound: bool = True):
        if not self.notification_enabled:
            return
        try:
            # 优先让 control_center 弹通知（图标为其自身 bundle 图标，更美观）
            from notify_bridge import notify_control_center

            if notify_control_center(title, text, sound):
                return

            # 回退：control_center 未运行时用原生通知（图标是终端的，但保证有通知）
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
        # 初始动画
        for line in _HUD_FRAMES.get("init", ["SYSTEM READY"]):
            print(line)
            time.sleep(0.05)
            
        self._send_notification("JARVIS", "系统初始化完成，随时待命", True)
        
        if blocking:
            self.play_sound("init")
            time.sleep(0.3)
        else:
            self.play_sound("init")

    def on_error(self, msg: str = ""):
        self.play_sound("error")

        def animate():
            # 使用 .get() 兜底，防止 KeyError
            frames = _HUD_FRAMES.get("error", ["ERROR DETECTED"])
            for frame in frames:
                # 打印动画帧，\r 回到行首实现原地刷新
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
            frames = _HUD_FRAMES.get("exit", ["EXITING..."])
            for frame in frames:
                print(f"\r{50 * ' '}\r{frame}", end="", flush=True)
                time.sleep(0.4)
            print(f"\r{50 * ' '}\r", end="", flush=True)

        t = threading.Thread(target=animate, daemon=True)
        t.start()
