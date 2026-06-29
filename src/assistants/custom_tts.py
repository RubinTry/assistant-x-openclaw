#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
通用配置驱动 TTS — 支持 VITS 引擎
模型路径由 assistants.json 的 tts_config 指定
"""

import logging
import os
import tempfile
import threading

import numpy as np

from assistants.tts import AssistantTTS

logger = logging.getLogger(__name__)

_PROJECT_DIR = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)

# MeloTTS 模型固有输出振幅极低（peak≈0.13, -18 dBFS），合成后做
# peak 归一化，让 WAV 文件本身响度足够；Mac 上 afplay -v 上限
# 是 1.0，无法靠播放端增益补偿，所以必须在写文件前放大。
_TARGET_PEAK = 0.9
# synthesize_to_array 的输出会被 main.py 的 play_array(volume=1.5) 再放大
# 一次，若归一化到 0.9 再乘 1.5 会 clip 削顶，故此路径单独用更低的
# 目标峰值，预留 1.5× 增益空间（0.6×1.5=0.9，不 clip）。
_TARGET_PEAK_ARRAY = 0.6


class CustomTTS(AssistantTTS):
    def __init__(self, config: dict):
        self.config = config
        self._engine = config.get("engine", "vits")
        self._speed = config.get("speed", 1.0)
        model_dir = config.get("model_dir", "models/vits-melo-tts-zh_en")
        self._model_dir = os.path.join(_PROJECT_DIR, model_dir)
        self._tts = None
        self._lock = threading.Lock()

    def _get_tts(self):
        if self._tts is not None:
            return self._tts

        import sherpa_onnx

        model_path = os.path.join(self._model_dir, "model.onnx")
        lexicon_path = os.path.join(self._model_dir, "lexicon.txt")
        tokens_path = os.path.join(self._model_dir, "tokens.txt")

        if not os.path.isfile(model_path):
            raise FileNotFoundError(f"TTS 模型不存在: {model_path}")

        rule_fsts_parts = []
        for fst_name in ("date.fst", "number.fst", "phone.fst"):
            fst_path = os.path.join(self._model_dir, fst_name)
            if os.path.isfile(fst_path):
                rule_fsts_parts.append(fst_path)
        rule_fsts = ",".join(rule_fsts_parts)

        tts_config = sherpa_onnx.OfflineTtsConfig(
            model=sherpa_onnx.OfflineTtsModelConfig(
                vits=sherpa_onnx.OfflineTtsVitsModelConfig(
                    model=model_path,
                    lexicon=lexicon_path,
                    tokens=tokens_path,
                ),
                debug=False,
                num_threads=4,
                provider="cpu",
            ),
            rule_fsts=rule_fsts,
        )

        if not tts_config.validate():
            raise ValueError("CustomTTS 配置验证失败")

        self._tts = sherpa_onnx.OfflineTts(tts_config)
        return self._tts

    def is_available(self) -> bool:
        model_path = os.path.join(self._model_dir, "model.onnx")
        lexicon_path = os.path.join(self._model_dir, "lexicon.txt")
        tokens_path = os.path.join(self._model_dir, "tokens.txt")
        return (
            os.path.isfile(model_path)
            and os.path.isfile(lexicon_path)
            and os.path.isfile(tokens_path)
        )

    def synthesize(self, text: str, output_path: str = None, **kwargs) -> str | None:
        if not self.is_available():
            logger.error("CustomTTS 不可用")
            return None
        if not text or not text.strip():
            return None

        import soundfile as sf
        from tts_vits import _normalize_for_tts, _split_with_pauses, _trim_silence

        if output_path is None:
            fd, output_path = tempfile.mkstemp(suffix=".wav")
            os.close(fd)

        try:
            with self._lock:
                tts = self._get_tts()
            result = _generate_with_pauses_impl(tts, text, self._speed)
            if result is None:
                logger.error("合成失败，返回音频为空")
                return None

            trimmed_audio, sample_rate = result

            # peak 归一化：MeloTTS 默认输出 peak≈0.13 太轻，
            # 放大到 _TARGET_PEAK 让 WAV 响度足够。
            peak = float(np.max(np.abs(trimmed_audio))) if len(trimmed_audio) else 0.0
            if peak > 1e-6:
                gain = _TARGET_PEAK / peak
                trimmed_audio = (trimmed_audio * gain).astype(np.float32)
                logger.debug(
                    f"CustomTTS 归一化: peak={peak:.4f} → gain={gain:.2f} → "
                    f"new_peak={float(np.max(np.abs(trimmed_audio))):.4f}"
                )

            actual_duration = len(trimmed_audio) / sample_rate
            sf.write(
                output_path, trimmed_audio, samplerate=sample_rate, subtype="PCM_16"
            )
            logger.info(f"CustomTTS 合成成功: {output_path} ({actual_duration:.2f}s)")
            return output_path

        except Exception as e:
            logger.error(f"CustomTTS 合成异常: {e}")
            return None

    def synthesize_to_array(self, text: str, **kwargs) -> tuple[np.ndarray, int] | None:
        if not self.is_available():
            logger.error("CustomTTS 不可用")
            return None
        if not text or not text.strip():
            return None

        from tts_vits import _normalize_for_tts, _split_with_pauses, _trim_silence

        try:
            with self._lock:
                tts = self._get_tts()
            result = _generate_with_pauses_impl(tts, text, self._speed)
            if result is None:
                logger.error("CustomTTS 预合成失败")
                return None
            audio_arr, sr = result

            # peak 归一化（同 synthesize 路径，但目标峰值更低，给
            # play_array(volume=1.5) 预留增益空间避免 clip）
            peak = float(np.max(np.abs(audio_arr))) if len(audio_arr) else 0.0
            if peak > 1e-6:
                gain = _TARGET_PEAK_ARRAY / peak
                audio_arr = (audio_arr * gain).astype(np.float32)
                logger.debug(
                    f"CustomTTS 归一化(array): peak={peak:.4f} → gain={gain:.2f} → "
                    f"new_peak={float(np.max(np.abs(audio_arr))):.4f}"
                )

            return (audio_arr, sr)

        except Exception as e:
            logger.error(f"CustomTTS 预合成异常: {e}")
            return None

    def synthesize_streaming(
        self, text: str, stop_event: threading.Event = None, volume: float = 1.5
    ) -> bool:
        if not self.is_available():
            logger.error("CustomTTS 不可用")
            return False
        if not text or not text.strip():
            return False

        try:
            import sounddevice as sd

            with self._lock:
                tts = self._get_tts()

            def on_stop_check(samples, progress):
                if stop_event and stop_event.is_set():
                    return 1
                return 0

            result = _generate_with_pauses_impl(
                tts, text, self._speed, callback=on_stop_check
            )

            if stop_event and stop_event.is_set():
                return False
            if result is None:
                return False

            audio_data, sample_rate = result
            if len(audio_data) == 0:
                return False

            sd.play(audio_data * volume, samplerate=sample_rate)
            sd.wait()
            return True

        except Exception as e:
            logger.warning(f"CustomTTS 合成播放失败: {e}")
            return False


def _generate_with_pauses_impl(tts, text: str, speed: float, callback=None):
    from tts_vits import _normalize_for_tts, _split_with_pauses, _trim_silence

    text = _normalize_for_tts(text)
    segments = _split_with_pauses(text)
    if not segments:
        return None

    all_audio = []
    sample_rate = None

    for seg_text, pause_ms in segments:
        if callback:
            result = tts.generate(seg_text, sid=0, speed=speed, callback=callback)
        else:
            result = tts.generate(seg_text, sid=0, speed=speed)

        if len(result.samples) == 0:
            continue

        sample_rate = result.sample_rate
        audio_arr = np.array(result.samples, dtype=np.float32)
        audio_arr = _trim_silence(audio_arr, sample_rate)
        all_audio.append(audio_arr)

        if pause_ms > 0:
            silence = np.zeros(int(sample_rate * pause_ms / 1000), dtype=np.float32)
            all_audio.append(silence)

    if not all_audio or sample_rate is None:
        return None

    return (np.concatenate(all_audio), sample_rate)
