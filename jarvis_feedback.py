#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
JARVIS 风格反馈系统
音效 + HUD 动画 + 桌面通知
"""

import asyncio
import os
import subprocess
import threading
import time
from typing import Optional

try:
    import pygame
except ImportError:
    pygame = None

try:
    from edge_tts import Communicate
except ImportError:
    Communicate = None

VOICES_DIR = os.path.join(os.path.dirname(__file__), "voices")

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
    "waiting": "waiting.wav",
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
    "awake": [
        "\r▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓",
        "\r░░░░░░░░░░░░░░░░░░░░░░░░░░░",
        "\r▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒",
        "\r░░░░░░░░░░░░░░░░░░░░░░░░░░░",
        "\r▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓",
    ],
    "listening": [
        "\r●                     ",
        "\r ●                    ",
        "\r  ●                   ",
        "\r   ●                  ",
        "\r    ●                 ",
        "\r     ●                ",
        "\r      ●               ",
        "\r       ●              ",
        "\r        ●             ",
        "\r         ●            ",
        "\r          ●           ",
        "\r           ●          ",
        "\r            ●         ",
        "\r             ●        ",
        "\r              ●       ",
        "\r               ●      ",
        "\r                ●     ",
        "\r                 ●    ",
        "\r                  ●   ",
        "\r                   ●  ",
        "\r                    ● ",
    ],
    "processing": [
        "\r[■■············] {0}%",
        "\r[■■■···········] {0}%",
        "\r[■■■■··········] {0}%",
        "\r[■■■■■·········] {0}%",
        "\r[■■■■■■········] {0}%",
        "\r[■■■■■■■·······] {0}%",
        "\r[■■■■■■■■······] {0}%",
        "\r[■■■■■■■■■·····] {0}%",
        "\r[■■■■■■■■■■····] {0}%",
        "\r[■■■■■■■■■■■···] {0}%",
        "\r[■■■■■■■■■■■■··] {0}%",
        "\r[■■■■■■■■■■■■■·] {0}%",
        "\r[■■■■■■■■■■■■■■] 100%",
    ],
    "thinking": [
        "\r◌ 分析中",
        "\r◍ 整合数据",
        "\r◉ 检索信息",
        "\r◈ 处理中",
    ],
    "executing": [
        "\r⚡ EXECUTING",
        "\r⚡⚡ PROCESSING",
        "\r⚡⚡⚡ COMPLETING",
    ],
    "success": [
        "\r✓ 任务完成",
        "\r✓✓ 执行成功",
        "\r✓✓✓ 就绪",
    ],
    "error": [
        "\r✗ 错误",
        "\r✗✗ 失败",
        "\r✗✗✗ 异常",
    ],
    "exit": [
        "\rstandby...",
        "\rstanding by...",
        "\rready for commands...",
    ],
}


class JarvisFeedback:
    def __init__(self, sound_enabled: bool = True, hud_enabled: bool = True, notification_enabled: bool = True):
        self.sound_enabled = sound_enabled and pygame is not None
        self.hud_enabled = hud_enabled
        self.notification_enabled = notification_enabled
        self._pygame_inited = False
        self._lock = threading.Lock()
        self._init_pygame()

    def _init_pygame(self):
        if self.sound_enabled and not self._pygame_inited:
            try:
                pygame.mixer.init(frequency=22050, size=-16, channels=2, buffer=512)
                self._pygame_inited = True
                print(f"[JARVIS] pygame mixer 初始化成功")
            except Exception as e:
                print(f"[JARVIS] pygame mixer 初始化失败: {e}")
                self.sound_enabled = False

    def _play_system_sound(self, sound_name: str):
        if not self.sound_enabled:
            print(f"[JARVIS] 音效未启用，跳过: {sound_name}")
            return
        sound_file = os.path.join(VOICES_DIR, _JAWESOME_SOUNDS.get(sound_name, ""))
        if not os.path.exists(sound_file):
            print(f"[JARVIS] 音效文件不存在: {sound_file}")
            return
        try:
            self._init_pygame()
            sound = pygame.mixer.Sound(sound_file)
            sound.set_volume(0.5)
            sound.play()
            print(f"[JARVIS] 播放音效: {sound_name}")
        except Exception as e:
            print(f"[JARVIS] 播放音效失败 {sound_name}: {type(e).__name__}: {e}")

    def _send_notification(self, title: str, text: str, sound: bool = True):
        if not self.notification_enabled:
            return
        try:
            script = f'display notification "{text}" with title "{title}"'
            if sound:
                script += ' sound name "Glass"'
            subprocess.run(["osascript", "-e", script], capture_output=True, timeout=2)
        except Exception:
            pass

    def play_sound(self, sound_type: str):
        t = threading.Thread(target=self._play_system_sound, args=(sound_type,), daemon=True)
        t.start()

    def animate_hud(self, anim_type: str, duration: float = 2.0, callback=None):
        t = threading.Thread(target=self._hud_animation_worker, args=(anim_type, duration, callback), daemon=True)
        t.start()

    def _hud_animation_worker(self, anim_type: str, duration: float, callback):
        frames = _HUD_FRAMES.get(anim_type, [])
        if not frames:
            return
        start_time = time.time()
        frame_idx = 0
        while time.time() - start_time < duration:
            if frames:
                print(frames[frame_idx % len(frames)], end="", flush=True)
                time.sleep(0.15)
                print("\r" + " " * 60 + "\r", end="", flush=True)
            frame_idx += 1
        if callback:
            callback()

    def hud_text(self, text: str, duration: float = 1.5):
        if not self.hud_enabled:
            return
        print(f"\r▸ {text}", end="", flush=True)
        time.sleep(duration)
        print("\r" + " " * 60 + "\r", end="", flush=True)

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

    def on_wake(self, text: str = "At your service, sir."):
        self.play_sound("wake")
        self.hud_text("◈ 唤醒激活 ◈", 0.5)
        self._send_notification("JARVIS", "已激活，等待指令", True)

    def on_listening(self):
        def animate():
            for frame in _HUD_FRAMES["listening"]:
                print(f"\r{50*' '}\r{frame} ◉ LISTENING", end="", flush=True)
                time.sleep(0.2)
            print(f"\r{50*' '}\r", end="", flush=True)
        t = threading.Thread(target=animate, daemon=True)
        t.start()

    def on_processing(self, text: str = "处理中"):
        self.play_sound("processing")

        def animate():
            for i, frame in enumerate(_HUD_FRAMES["processing"]):
                pct = (i + 1) * 100 // len(_HUD_FRAMES["processing"])
                print(f"\r{50*' '}\r{frame.format(pct)}", end="", flush=True)
                time.sleep(0.12)
            print(f"\r{50*' '}\r", end="", flush=True)
        t = threading.Thread(target=animate, daemon=True)
        t.start()

    def on_thinking(self):
        self.play_sound("thinking")
        t = threading.Thread(target=self._thinking_worker, daemon=True)
        t.start()

    def _thinking_worker(self):
        for _ in range(3):
            for frame in _HUD_FRAMES["thinking"]:
                print(f"\r{50*' '}\r{frame}", end="", flush=True)
                time.sleep(0.3)
        print(f"\r{50*' '}\r", end="", flush=True)

    def on_executing(self):
        self.play_sound("execute")

        def animate():
            for frame in _HUD_FRAMES["executing"]:
                print(f"\r{50*' '}\r⚡ {frame}", end="", flush=True)
                time.sleep(0.25)
            print(f"\r{50*' '}\r", end="", flush=True)
        t = threading.Thread(target=animate, daemon=True)
        t.start()

    def on_success(self):
        self.play_sound("success")

        def animate():
            for frame in _HUD_FRAMES["success"]:
                print(f"\r{50*' '}\r✓ {frame}", end="", flush=True)
                time.sleep(0.2)
            print(f"\r{50*' '}\r", end="", flush=True)
        t = threading.Thread(target=animate, daemon=True)
        t.start()

    def on_error(self, msg: str = ""):
        self.play_sound("error")

        def animate():
            for frame in _HUD_FRAMES["error"]:
                print(f"\r{50*' '}\r✗ {frame}", end="", flush=True)
                time.sleep(0.2)
            print(f"\r{50*' '}\r", end="", flush=True)
        t = threading.Thread(target=animate, daemon=True)
        t.start()
        if msg:
            self._send_notification("JARVIS - ERROR", msg, True)

    def on_exit(self):
        self.play_sound("exit")

        def animate():
            for frame in _HUD_FRAMES["exit"]:
                print(f"\r{50*' '}\r{frame}", end="", flush=True)
                time.sleep(0.4)
            print(f"\r{50*' '}\r", end="", flush=True)
        t = threading.Thread(target=animate, daemon=True)
        t.start()
        self._send_notification("JARVIS", "已进入待机模式", True)

    def data_stream_effect(self, text: str, delay: float = 0.02):
        if not self.hud_enabled:
            print(text, end="", flush=True)
            return
        chars = list(text)
        for i, char in enumerate(chars):
            if char.strip():
                print(f"\r{50*' '}\r", end="", flush=True)
            print(char, end="", flush=True)
            if char in "，。！？；：" or (i > 0 and chars[i-1] in "，。！？；："):
                time.sleep(delay * 8)
            elif char in ",.!?;:":
                time.sleep(delay * 6)
            elif char == " ":
                time.sleep(delay * 2)
            else:
                time.sleep(delay)
        print()

    def blaster_effect(self):
        self.play_sound("blaster")
        for _ in range(3):
            print("\r" + "█" * 50, end="", flush=True)
            time.sleep(0.05)
            print("\r" + "░" * 50, end="", flush=True)
            time.sleep(0.05)


_feedback_instance: Optional[JarvisFeedback] = None


def get_feedback(sound_enabled: bool = True, hud_enabled: bool = True, notification_enabled: bool = True) -> JarvisFeedback:
    global _feedback_instance
    if _feedback_instance is None:
        _feedback_instance = JarvisFeedback(sound_enabled, hud_enabled, notification_enabled)
    return _feedback_instance
