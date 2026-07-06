#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Jarvis TTS — 基于 Piper 英音语音合成

引擎: Piper (VITS)
模型: jgkawell/jarvis (en-GB-x-rp, 22050Hz)
"""

from threading import Event

import numpy as np

from assistants.tts import AssistantTTS


class JarvisTTS(AssistantTTS):

    def __init__(self, config: dict = None):
        # 注入 assistants.json 的 tts_config（金属感后处理等）到引擎模块
        from assistants.jarvis import tts_piper
        tts_piper.configure(config or {})

    def is_available(self) -> bool:
        from assistants.jarvis import tts_piper
        return tts_piper.is_available()

    def synthesize(self, text: str, output_path: str = None, **kwargs) -> str | None:
        from assistants.jarvis import tts_piper
        return tts_piper.synthesize(text, output_path=output_path, **kwargs)

    def synthesize_to_array(self, text: str, **kwargs) -> tuple[np.ndarray, int] | None:
        from assistants.jarvis import tts_piper
        return tts_piper.synthesize_to_array(text, **kwargs)

    def synthesize_streaming(self, text: str, stop_event: Event = None,
                             volume: float = 1.5) -> bool:
        from assistants.jarvis import tts_piper
        return tts_piper.synthesize_streaming(
            text, stop_event=stop_event, volume=volume,
        )


class ZipVoiceTTS(AssistantTTS):
    """ZipVoice 零样本克隆后端，参考说话人由 tts_configs.<spec> 指定。"""

    def __init__(self, config: dict = None):
        from assistants.jarvis import tts_zipvoice
        tts_zipvoice.configure(config or {})

    def is_available(self) -> bool:
        from assistants.jarvis import tts_zipvoice
        return tts_zipvoice.is_available()

    def synthesize(self, text: str, output_path: str = None, **kwargs) -> str | None:
        from assistants.jarvis import tts_zipvoice
        return tts_zipvoice.synthesize(text, output_path=output_path, **kwargs)

    def synthesize_to_array(self, text: str, **kwargs) -> tuple[np.ndarray, int] | None:
        from assistants.jarvis import tts_zipvoice
        return tts_zipvoice.synthesize_to_array(text, **kwargs)

    def synthesize_streaming(self, text: str, stop_event: Event = None,
                             volume: float = 1.5) -> bool:
        from assistants.jarvis import tts_zipvoice
        return tts_zipvoice.synthesize_streaming(
            text, stop_event=stop_event, volume=volume,
        )
