#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Assistant TTS 抽象接口

所有 Assistant 的语音合成必须实现此接口。
从 TTS 引擎选型（sherpa-onnx、云端 API 等）到具体模型配置，
由各 Assistant 自行决定，统一对外提供标准合成接口。

统一标准：
  1. is_available        — 检查 TTS 引擎及模型是否就绪
  2. synthesize          — 合成语音到文件
  3. synthesize_to_array — 合成语音到内存数组
  4. synthesize_streaming — 流式合成并播放
"""

from abc import ABC, abstractmethod
from threading import Event

import numpy as np


class AssistantTTS(ABC):
    """Assistant 语音合成的统一抽象接口"""

    # ── 可用性检查 ────────────────────────────────────────
    @abstractmethod
    def is_available(self) -> bool:
        """TTS 引擎及模型是否就绪"""

    # ── 合成到文件 ────────────────────────────────────────
    @abstractmethod
    def synthesize(self, text: str, output_path: str = None, **kwargs) -> str | None:
        """合成语音并保存到文件

        Args:
            text: 待合成文本
            output_path: 输出文件路径（None 则自动生成临时文件）
        Returns:
            成功返回文件路径，失败返回 None
        """

    # ── 合成到内存 ────────────────────────────────────────
    @abstractmethod
    def synthesize_to_array(self, text: str, **kwargs) -> tuple[np.ndarray, int] | None:
        """合成语音到内存数组

        Returns:
            成功返回 (audio_array, sample_rate)，失败返回 None
        """

    # ── 流式合成播放 ──────────────────────────────────────
    @abstractmethod
    def synthesize_streaming(self, text: str, stop_event: Event = None,
                             volume: float = 1.5) -> bool:
        """合成并即时播放

        Args:
            text: 待合成文本
            stop_event: 外部中断信号
            volume: 音量倍率
        Returns:
            是否成功播放
        """


class NullAssistantTTS(AssistantTTS):
    """空实现 — TTS 禁用时使用，避免到处判 None"""

    def is_available(self) -> bool:
        return False

    def synthesize(self, text: str, output_path: str = None, **kwargs) -> str | None:
        return None

    def synthesize_to_array(self, text: str, **kwargs) -> tuple[np.ndarray, int] | None:
        return None

    def synthesize_streaming(self, text: str, stop_event: Event = None,
                             volume: float = 1.5) -> bool:
        return False
