#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Sherpa-onnx TTS 模块 - 本地离线语音合成
使用 ZipVoice 零样本声音克隆，基于 Jarvis 参考音频
"""

import logging
import os
import subprocess
import tempfile

import librosa
import numpy as np
import sherpa_onnx
import soundfile as sf

logger = logging.getLogger(__name__)

_PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
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
                guidance_scale=1.5,
                feat_scale=0.1,
                t_shift=0.5,
                target_rms=0.1,
            ),
            debug=False,
            num_threads=3,
            provider="cpu",
        )
    )

    if not tts_config.validate():
        raise ValueError("ZipVoice 配置验证失败")

    _tts = sherpa_onnx.OfflineTts(tts_config)
    return _tts


def _get_ref_audio():
    ref_audio, ref_sr = librosa.load(REF_AUDIO, sr=32000)
    return ref_audio, ref_sr


def is_available():
    return (
        os.path.isfile(REF_AUDIO)
        and os.path.isfile(f"{ZIPVOICE_DIR}/encoder.int8.onnx")
        and os.path.isfile(f"{ZIPVOICE_DIR}/decoder.int8.onnx")
        and os.path.isfile(VOCODER)
    )


def synthesize(text: str, output_path: str = None) -> str | None:
    if not is_available():
        logger.error("Sherpa-onnx TTS 不可用")
        return None

    if not text or not text.strip():
        logger.warning("合成文本为空")
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
        gen_config.num_steps = 8

        audio = tts.generate(text, gen_config)

        if len(audio.samples) == 0:
            logger.error("合成失败，返回音频为空")
            return None

        sf.write(
            output_path, audio.samples, samplerate=audio.sample_rate, subtype="PCM_16"
        )
        logger.info(f"合成成功: {output_path}")
        return output_path

    except Exception as e:
        logger.error(f"合成异常: {e}")
        return None


def play_audio(file_path: str):
    try:
        subprocess.run(
            ["afplay", "-v", "1.5", file_path],
            check=True,
            capture_output=True,
        )
    except subprocess.CalledProcessError as e:
        logger.error(f"播放失败: {e}")
    except Exception as e:
        logger.error(f"播放异常: {e}")


def text_to_speech_play(text: str, **kwargs):
    if not text:
        return

    logger.info(f"[Sherpa-onnx TTS] 合成: {text[:50]}...")
    output_path = synthesize(text)
    if output_path:
        logger.info(f"[Sherpa-onnx TTS] 播放: {output_path}")
        play_audio(output_path)
        try:
            os.unlink(output_path)
        except Exception:
            pass
    else:
        logger.error("[Sherpa-onnx TTS] 合成失败")


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)

    if not is_available():
        print("Sherpa-onnx TTS 不可用!")
        print(f"  REF_AUDIO: {REF_AUDIO} - {'✓' if os.path.isfile(REF_AUDIO) else '✗'}")
        print(
            f"  ZIPVOICE encoder: {'✓' if os.path.isfile(f'{ZIPVOICE_DIR}/encoder.int8.onnx') else '✗'}"
        )
        print(f"  VOCODER: {VOCODER} - {'✓' if os.path.isfile(VOCODER) else '✗'}")
        exit(1)

    print("Sherpa-onnx TTS 测试 (Jarvis 克隆音色)")
    print(f"参考音频: {REF_AUDIO}")
    print()

    tests = [
        "你好，我是贾维斯，你的智能助手。",
        "Hello, I am Jarvis. Your personal AI assistant. How may I help you today?",
        "今天天气真不错，我们出去走走吧。",
    ]

    for text in tests:
        print(f"测试: {text}")
        text_to_speech_play(text)
        print()
