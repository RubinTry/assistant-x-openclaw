#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Dock 自动隐藏联动（macOS）

用途：助手激活期间把系统 Dock 切到自动隐藏，腾出屏幕、减少视觉干扰；
退回待机时还原。作为激活联动钩子接入 lifecycle 注册表。

实现：走 AppleScript 切 System Events 的 `autohide of dock preferences`。
  - 平滑无闪烁、即时可逆（不像 `killall Dock` 会让 Dock 闪一下重建）。
  - 注意：autohide 只是"鼠标离开屏幕边缘就收起"，怼到边缘 Dock 仍会冒出来。
    若要彻底不露需用 overlay 窗口层级遮挡，另行实现。

设计原则（与 media_pause 一致）：**软失败 + 只还原我改的**。
  - 非 macOS / osascript 不可用 / 调用异常（含未授予自动化权限）→ 静默跳过。
  - 用户本来就开着 Dock 自动隐藏 → 不动它、也不记标志，之后绝不擅自改回。
  - 只有"激活时确实是本程序把它从常显切到隐藏"的，退待机时才还原。
"""

import logging
import platform
import shutil
import subprocess
import threading

logger = logging.getLogger(__name__)

_GET_SCRIPT = 'tell application "System Events" to get autohide of dock preferences'
_SET_TMPL = 'tell application "System Events" to set autohide of dock preferences to {}'


class DockController:
    def __init__(self):
        self._hidden_by_us = False
        self._lock = threading.Lock()
        self._bin = shutil.which("osascript")
        self._available = self._bin is not None and platform.system() == "Darwin"

        if self._available:
            print(f"[Dock] osascript 可用，激活时将自动隐藏 Dock: {self._bin}")
        elif platform.system() != "Darwin":
            logger.info("[Dock] 非 macOS，Dock 自动隐藏联动不启用")
        else:
            print("[Dock] 未找到 osascript，Dock 联动降级为关闭（软失败）")

    def is_available(self) -> bool:
        return self._available

    def _run(self, script: str, timeout: float = 2.0):
        if not self._bin:
            return None
        try:
            return subprocess.run(
                [self._bin, "-e", script],
                capture_output=True,
                text=True,
                timeout=timeout,
            )
        except Exception as e:
            logger.warning(f"[Dock] osascript 调用失败: {e}")
            return None

    def _get_autohide(self):
        """查询当前 Dock 是否已自动隐藏。无法确定时返回 None。"""
        r = self._run(_GET_SCRIPT)
        if not r or r.returncode != 0:
            return None
        out = (r.stdout or "").strip().lower()
        if out == "true":
            return True
        if out == "false":
            return False
        return None

    def _set_autohide(self, on: bool) -> bool:
        r = self._run(_SET_TMPL.format("true" if on else "false"))
        return r is not None and r.returncode == 0

    def hide(self):
        """激活时调用：若 Dock 当前为常显则切到自动隐藏，并记下'是我隐藏的'。幂等。"""
        if not self._available:
            return
        with self._lock:
            if self._hidden_by_us:
                return
            cur = self._get_autohide()
            if cur is None:
                return  # 查不到状态（可能未授权），保守不动
            if cur is True:
                return  # 用户本就自动隐藏，不接管、不记标志
            if self._set_autohide(True):
                self._hidden_by_us = True
                print("[Dock] 已切到自动隐藏")

    def show(self):
        """退回待机时调用：仅还原本程序隐藏的 Dock。幂等。"""
        if not self._available:
            return
        with self._lock:
            if not self._hidden_by_us:
                return
            self._set_autohide(False)
            self._hidden_by_us = False
            print("[Dock] 已还原常显")


# ── 单例 ──────────────────────────────────────────────────
_controller = None
_controller_lock = threading.Lock()


def get_dock_controller() -> DockController:
    global _controller
    with _controller_lock:
        if _controller is None:
            _controller = DockController()
        return _controller


# ── 激活联动钩子 ──────────────────────────────────────────
try:
    from lifecycle import LifecycleHook
except ImportError:  # 允许本模块被单独导入/测试
    LifecycleHook = object


class DockAutohideHook(LifecycleHook):
    """激活时把 Dock 切到自动隐藏，退回待机时还原（仅还原本程序改的）。"""

    def on_wake(self):
        get_dock_controller().hide()

    def on_standby(self):
        get_dock_controller().show()
