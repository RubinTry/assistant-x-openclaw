#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Assistant 特效抽象接口

所有 Assistant 的可视化特效必须实现此接口。
统一标准：
  1. 用户终端区 — 展示用户说的话
  2. AI 终端区   — 展示 AI 回复的话
  3. 其他特效区  — Canvas 动画、桌宠等（由各 Agent 自行实现）
"""

from abc import ABC, abstractmethod


class AssistantVisual(ABC):
    """Assistant 可视化特效的统一抽象接口"""

    # ── 生命周期 ──────────────────────────────────────────
    @abstractmethod
    def start(self):
        """启动特效连接/渲染"""

    @abstractmethod
    def stop(self):
        """停止特效并释放资源"""

    # ── 用户终端区 ────────────────────────────────────────
    @abstractmethod
    def show_user_text(self, text: str):
        """显示/更新用户输入文本（流式追加）"""

    # ── AI 终端区 ─────────────────────────────────────────
    @abstractmethod
    def show_ai_text(self, text: str):
        """显示/更新 AI 回复文本（流式追加）"""

    # ── 终端区公共操作 ────────────────────────────────────
    @abstractmethod
    def clear_texts(self):
        """清空用户和 AI 终端区的文本"""

    # ── 特效区 ────────────────────────────────────────────
    @abstractmethod
    def show_wake_effect(self):
        """唤醒特效（进入活跃状态）"""

    @abstractmethod
    def hide_effects(self):
        """隐藏所有特效（进入待机状态）"""

    def send_audio_level(self, level: float):
        """推送音频电平 (0.0~1.0) 给 Flutter overlay，默认空实现"""
        pass


class NullAssistantVisual(AssistantVisual):
    """空实现 — 特效禁用时使用，避免到处判 None"""

    def start(self):
        pass

    def stop(self):
        pass

    def show_user_text(self, text: str):
        pass

    def show_ai_text(self, text: str):
        pass

    def clear_texts(self):
        pass

    def show_wake_effect(self):
        pass

    def hide_effects(self):
        pass

    def send_audio_level(self, level: float):
        pass
