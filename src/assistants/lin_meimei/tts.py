#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
林妹妹 TTS — 基于 VITS MeloTTS 中英文合成

引擎: sherpa-onnx VITS
模型: vits-melo-tts-zh_en (MeloTTS-Chinese, 44100Hz)
"""

from threading import Event

import numpy as np

from assistants.tts import AssistantTTS


class LinMeimeiTTS(AssistantTTS):

    def is_available(self) -> bool:
        import tts_vits
        return tts_vits.is_available()

    def synthesize(self, text: str, output_path: str = None, **kwargs) -> str | None:
        import tts_vits
        return tts_vits.synthesize(text, output_path=output_path, **kwargs)

    def synthesize_to_array(self, text: str, **kwargs) -> tuple[np.ndarray, int] | None:
        import tts_vits
        return tts_vits.synthesize_to_array(text, **kwargs)

    def synthesize_streaming(self, text: str, stop_event: Event = None,
                             volume: float = 1.5) -> bool:
        import tts_vits
        return tts_vits.synthesize_streaming(
            text, stop_event=stop_event, volume=volume,
        )
