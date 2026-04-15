#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Assistant 反馈抽象接口

所有 Assistant 的反馈系统必须实现此接口。
统一标准：
  1. 音效播放  — 唤醒、退出、错误、等待等场景
  2. 初始化    — 启动时的欢迎反馈
  3. 错误通知  — 出错时的提示
  4. 退出反馈  — 进入待机时的提示
"""

from abc import ABC, abstractmethod


class AssistantFeedback(ABC):
    """Assistant 反馈系统的统一抽象接口"""

    # ── 音效 ──────────────────────────────────────────────
    @abstractmethod
    def play_sound(self, sound_type: str):
        """播放指定类型的音效（异步，不阻塞）"""

    # ── 生命周期事件 ──────────────────────────────────────
    @abstractmethod
    def system_ready(self, blocking: bool = False):
        """系统初始化完成时的反馈（动画 + 通知 + 音效）"""

    @abstractmethod
    def on_error(self, msg: str = ""):
        """出错时的反馈"""

    @abstractmethod
    def on_exit(self):
        """进入待机时的反馈"""


class NullAssistantFeedback(AssistantFeedback):
    """空实现 — 反馈禁用时使用，避免到处判 None"""

    def play_sound(self, sound_type: str): pass
    def system_ready(self, blocking: bool = False): pass
    def on_error(self, msg: str = ""): pass
    def on_exit(self): pass
