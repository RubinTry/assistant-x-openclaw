#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
ZipVoice TTS 后端 - 零样本声音克隆，基于 Jarvis 参考音频
"""

import logging
import os
import tempfile
import threading

import librosa
import numpy as np
import sherpa_onnx
import soundfile as sf

logger = logging.getLogger(__name__)

_PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
ZIPVOICE_DIR = os.path.join(
    _PROJECT_DIR, "models", "sherpa-onnx-zipvoice-distill-int8-zh-en-emilia"
)
VOCODER = os.path.join(_PROJECT_DIR, "models", "vocos_24khz.onnx")
REF_AUDIO = os.path.join(_PROJECT_DIR, "data", "voices", "jarvis_start_up.mp3")
REF_TEXT = "Allow me to introduce myself I am jarvis, a virtual artificial intelligence importing all preferences from home interface systems are now fully operational."

_tts = None


def _create_tts():
    global _tts
    if _tts is not None:
        return _tts

    tts_config = sherpa_onnx.OfflineTtsConfig(
        model=sherpa_onnx.OfflineTtsModelConfig(
            zipvoice=sherpa_onnx.OfflineTtsZipvoiceModelConfig(
                tokens=f"{ZIPVOICE_DIR}/tokens.txt",
                encoder=f"{ZIPVOICE_DIR}/encoder.int8.onnx",
                decoder=f"{ZIPVOICE_DIR}/decoder.int8.onnx",
                data_dir=f"{ZIPVOICE_DIR}/espeak-ng-data",
                lexicon=f"{ZIPVOICE_DIR}/lexicon.txt",
                vocoder=VOCODER,
            ),
            debug=False,
            num_threads=6,
            provider="cpu",
        )
    )

    if not tts_config.validate():
        raise ValueError("ZipVoice 配置验证失败")

    _tts = sherpa_onnx.OfflineTts(tts_config)
    return _tts


_ref_audio_cache = None


def _get_ref_audio():
    global _ref_audio_cache
    if _ref_audio_cache is not None:
        return _ref_audio_cache
    ref_audio, ref_sr = librosa.load(REF_AUDIO, sr=32000)
    _ref_audio_cache = (ref_audio, ref_sr)
    return _ref_audio_cache


def is_available():
    return (
        os.path.isfile(REF_AUDIO)
        and os.path.isfile(f"{ZIPVOICE_DIR}/encoder.int8.onnx")
        and os.path.isfile(f"{ZIPVOICE_DIR}/decoder.int8.onnx")
        and os.path.isfile(VOCODER)
    )


def _trim_silence(audio_samples, sample_rate, threshold=0.003, keep_ms=200):
    if len(audio_samples) == 0:
        return audio_samples

    keep_samples = int(sample_rate * keep_ms / 1000)

    abs_audio = np.abs(audio_samples)
    last_idx = len(audio_samples)
    for i in range(len(audio_samples) - 1, -1, -1):
        if abs_audio[i] > threshold:
            last_idx = min(len(audio_samples), i + keep_samples)
            break

    trimmed = audio_samples[:last_idx]

    trimmed_ms = (len(audio_samples) - len(trimmed)) * 1000 / sample_rate
    if trimmed_ms > 10:
        print(f"[DEBUG] 修剪尾部静音: {trimmed_ms:.1f}ms, 原{len(audio_samples)}->现{len(trimmed)} samples")

    return trimmed


def _estimate_duration(text: str) -> float:
    import re
    chinese_chars = len(re.findall(r'[\u4e00-\u9fff]', text))
    english_words = len(re.findall(r'[a-zA-Z]+', text))
    min_duration = chinese_chars * 0.2 + english_words * 0.25 + 0.3
    return min_duration


def synthesize(text: str, output_path: str = None, retry: bool = True, num_steps: int = 10) -> str | None:
    if not is_available():
        logger.error("ZipVoice TTS 不可用")
        return None

    if not text or not text.strip():
        return None

    if output_path is None:
        fd, output_path = tempfile.mkstemp(suffix=".wav")
        os.close(fd)

    try:
        tts = _create_tts()
        ref_audio, ref_sr = _get_ref_audio()

        gen_config = sherpa_onnx.GenerationConfig()
        gen_config.reference_audio = ref_audio
        gen_config.reference_sample_rate = ref_sr
        gen_config.reference_text = REF_TEXT
        gen_config.num_steps = num_steps

        audio = tts.generate(text, gen_config)

        if len(audio.samples) == 0:
            logger.error("合成失败，返回音频为空")
            return None

        audio_array = np.array(audio.samples, dtype=np.float32)
        trimmed_audio = _trim_silence(audio_array, audio.sample_rate)

        actual_duration = len(trimmed_audio) / audio.sample_rate
        expected_min_duration = _estimate_duration(text)

        if retry and actual_duration < expected_min_duration * 0.5:
            print(f"[TTS] 警告: 合成时长过短，增加推理步数重试...")
            return synthesize(text, output_path, retry=False, num_steps=min(num_steps * 2, 30))

        sf.write(
            output_path, trimmed_audio, samplerate=audio.sample_rate, subtype="PCM_16"
        )
        logger.info(f"合成成功: {output_path} ({actual_duration:.2f}s)")
        return output_path

    except Exception as e:
        logger.error(f"合成异常: {e}")
        return None


def synthesize_to_array(text: str, num_steps: int = 10, retry: bool = True) -> tuple[np.ndarray, int] | None:
    if not is_available():
        logger.error("ZipVoice TTS 不可用")
        return None

    if not text or not text.strip():
        return None

    try:
        tts = _create_tts()
        ref_audio, ref_sr = _get_ref_audio()

        gen_config = sherpa_onnx.GenerationConfig()
        gen_config.reference_audio = ref_audio
        gen_config.reference_sample_rate = ref_sr
        gen_config.reference_text = REF_TEXT
        gen_config.num_steps = num_steps

        result = tts.generate(text, gen_config)

        if len(result.samples) == 0:
            logger.error("合成失败，返回音频为空")
            return None

        audio_array = np.array(result.samples, dtype=np.float32)
        trimmed_audio = _trim_silence(audio_array, result.sample_rate)

        actual_duration = len(trimmed_audio) / result.sample_rate
        expected_min_duration = _estimate_duration(text)

        if retry and actual_duration < expected_min_duration * 0.5:
            print(f"[TTS] 预合成时长过短，增加推理步数重试...")
            return synthesize_to_array(text, num_steps=min(num_steps * 2, 30), retry=False)

        # 在开头补200ms静音，防止播放设备初始化吃掉开头
        pad = np.zeros(int(result.sample_rate * 0.2), dtype=np.float32)
        padded_audio = np.concatenate([pad, trimmed_audio])

        return (padded_audio, result.sample_rate)

    except Exception as e:
        logger.error(f"预合成异常: {e}")
        return None


def synthesize_streaming(text: str, stop_event: threading.Event = None, volume: float = 1.5) -> bool:
    if not is_available():
        logger.error("ZipVoice TTS 不可用")
        return False

    if not text or not text.strip():
        return False

    try:
        import sounddevice as sd

        tts = _create_tts()
        ref_audio, ref_sr = _get_ref_audio()

        gen_config = sherpa_onnx.GenerationConfig()
        gen_config.reference_audio = ref_audio
        gen_config.reference_sample_rate = ref_sr
        gen_config.reference_text = REF_TEXT
        gen_config.num_steps = 10

        def on_stop_check(samples, progress):
            if stop_event and stop_event.is_set():
                return 1
            return 0

        result = tts.generate(text, gen_config, callback=on_stop_check)

        if stop_event and stop_event.is_set():
            return False

        if len(result.samples) == 0:
            return False

        audio_data = np.array(result.samples, dtype=np.float32)
        audio_data = _trim_silence(audio_data, result.sample_rate)

        if len(audio_data) == 0:
            return False

        pad = np.zeros(int(result.sample_rate * 0.2), dtype=np.float32)
        audio_data = np.concatenate([pad, audio_data])

        sd.play(audio_data * volume, samplerate=result.sample_rate)
        sd.wait()
        return True

    except Exception as e:
        logger.warning(f"合成播放失败: {e}")
        return False
