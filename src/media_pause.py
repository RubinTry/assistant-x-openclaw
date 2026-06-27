#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
媒体暂停/恢复（macOS）

用途：唤醒时暂停电脑正在播放的影视/音乐，避免与用户说话重叠干扰识别；
验证失败或回到待机时恢复原状态。

实现：依赖 ungive 的 `media-control` CLI（兼容到最新 macOS，含 Tahoe）。
  安装：brew install media-control
  - media-control get   → 查询当前 Now Playing（含播放状态）
  - media-control pause  → 暂停
  - media-control play   → 播放

设计原则：**软失败 + 只恢复我暂停的**。
  - 未安装 media-control / 非 macOS / 调用异常 → 全部静默跳过，绝不阻塞或崩溃。
  - 只有"暂停前确实在播、且是本程序暂停的"才会在之后恢复，绝不擅自开始播放。
"""

import json
import logging
import os
import platform
import shutil
import subprocess
import threading

logger = logging.getLogger(__name__)


class MediaController:
    def __init__(self):
        self._bin = self._find_bin()
        self._paused_by_us = False
        self._lock = threading.Lock()
        self._available = self._bin is not None and platform.system() == "Darwin"

        if self._available:
            print(f"[媒体] media-control 可用: {self._bin}")
        else:
            if platform.system() != "Darwin":
                logger.info("[媒体] 非 macOS，媒体暂停功能不启用")
            else:
                print("[媒体] 未找到 media-control，媒体自动暂停降级为关闭（软失败）")
                print("[媒体] 安装即可启用: brew install media-control")

    def _find_bin(self):
        cand = shutil.which("media-control")
        if cand:
            return cand
        for p in (
            "/opt/homebrew/bin/media-control",  # Apple Silicon
            "/usr/local/bin/media-control",     # Intel
        ):
            if os.path.exists(p):
                return p
        return None

    def is_available(self) -> bool:
        return self._available

    def _run(self, *args, timeout: float = 2.0):
        if not self._bin:
            return None
        try:
            return subprocess.run(
                [self._bin, *args],
                capture_output=True,
                text=True,
                timeout=timeout,
            )
        except Exception as e:
            logger.warning(f"[媒体] 调用 media-control {args} 失败: {e}")
            return None

    def _is_playing(self) -> bool:
        """查询当前是否有媒体正在播放。无法确定时返回 False（保守，避免误恢复）。"""
        r = self._run("get")
        if not r or r.returncode != 0:
            return False
        out = (r.stdout or "").strip()
        if not out:
            return False
        try:
            data = json.loads(out)
        except Exception:
            return False
        if not isinstance(data, dict):
            return False
        # 兼容 get 顶层或 payload 包裹
        info = data.get("payload") if isinstance(data.get("payload"), dict) else data
        playing = info.get("playing")
        if isinstance(playing, bool):
            return playing
        rate = info.get("playbackRate")
        if isinstance(rate, (int, float)):
            return rate > 0
        # 无明确状态字段但有正在播放的曲目信息 → 视为在播
        return bool(info.get("title") or info.get("bundleIdentifier"))

    def _do(self, primary: str):
        """执行 primary 子命令，失败则回退 toggle-play-pause。"""
        r = self._run(primary)
        if r is not None and r.returncode == 0:
            return True
        r2 = self._run("toggle-play-pause")
        return r2 is not None and r2.returncode == 0

    def pause(self):
        """唤醒时调用：若当前在播则暂停，并记下'是我暂停的'。幂等。"""
        if not self._available:
            return
        with self._lock:
            if self._paused_by_us:
                return  # 已暂停，避免重复
            if self._is_playing():
                if self._do("pause"):
                    self._paused_by_us = True
                    print("[媒体] 检测到正在播放，已暂停")
            # 未在播则什么都不做，也不置标志（之后不会擅自播放）

    def resume(self):
        """回到待机/验证失败时调用：仅恢复本程序暂停的媒体。幂等。"""
        if not self._available:
            return
        with self._lock:
            if not self._paused_by_us:
                return
            self._do("play")
            self._paused_by_us = False
            print("[媒体] 已恢复播放")


# ── 单例 ──────────────────────────────────────────────────
_controller = None
_controller_lock = threading.Lock()


def get_media_controller() -> MediaController:
    global _controller
    with _controller_lock:
        if _controller is None:
            _controller = MediaController()
        return _controller


# ── 激活联动钩子 ──────────────────────────────────────────
try:
    from lifecycle import LifecycleHook
except ImportError:  # 允许 media_pause 被单独导入/测试
    LifecycleHook = object


class MediaPauseHook(LifecycleHook):
    """激活时暂停在播媒体，退回待机时恢复（仅恢复本程序暂停的）。"""

    def on_wake(self):
        get_media_controller().pause()

    def on_standby(self):
        get_media_controller().resume()
