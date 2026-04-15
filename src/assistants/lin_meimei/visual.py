#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
林妹妹可视化特效

复用 JarvisVisual（TCP → Flutter overlay），
但会先发送 agent 切换命令。
"""

from assistants.jarvis.visual import JarvisVisual


class LinMeimeiVisual(JarvisVisual):
    """林妹妹视觉特效 — 发送 agent 切换命令后复用贾维斯的 TCP overlay 实现"""

    def show_wake_effect(self):
        """唤醒特效 — 先切换 agent，再唤醒"""
        # 先发送 agent 切换命令
        self.send("agent:lin-meimei")
        # 直接发送唤醒（不要调用父类，避免重复发送 agent 切换）
        self.send("wake")

    def hide_effects(self):
        """隐藏特效"""
        super().hide_effects()
