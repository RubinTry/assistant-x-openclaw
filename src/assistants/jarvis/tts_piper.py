#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Piper TTS 后端 — Jarvis 英音语音合成
模型: jgkawell/jarvis (Piper VITS, en-GB-x-rp, 22050Hz)
"""

import io
import logging
import os
import shutil
import subprocess
import tempfile
import threading

import numpy as np
import soundfile as sf

logger = logging.getLogger(__name__)

_PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)
))))

MODEL_DIR = os.path.join(
    _PROJECT_DIR, "models", "jarvis", "en", "en_GB", "jarvis", "high"
)
MODEL_PATH = os.path.join(MODEL_DIR, "jarvis-high.onnx")
CONFIG_PATH = os.path.join(MODEL_DIR, "jarvis-high.onnx.json")

# 语速控制：length_scale 越小语速越快。模型默认 1.15，这里略微调快一点点。
LENGTH_SCALE = 1.05

# 下游各播放出口（main.py 回复播报、synthesize_streaming、文件播放）统一以
# 约 1.5 倍增益播放。Piper(jarvis) 模型输出本身接近满幅（峰值≈1.0），直接 ×1.5
# 会硬削波产生明显杂音。下面在合成阶段先按峰值缩小、为下游增益预留 headroom，
# 使 ×PLAYBACK_GAIN 后峰值≈TARGET_PEAK 而不削波，再对个别尖峰做软限幅兜底。
PLAYBACK_GAIN = 1.5  # 与下游播放端的增益保持一致
TARGET_PEAK = 0.97   # 期望下游放大后的峰值上限（<1.0，留削波余量）
SOFT_KNEE = 0.95     # 下游放大后超过此值的样本做 tanh 软压缩

_voice = None
_voice_lock = threading.Lock()


def _create_voice():
    global _voice
    if _voice is not None:
        return _voice

    # 多个合成线程会并发首次调用，加锁保证模型只加载一次
    with _voice_lock:
        if _voice is not None:
            return _voice
        from piper import PiperVoice
        voice = PiperVoice.load(MODEL_PATH, config_path=CONFIG_PATH)
        logger.info(f"Piper voice loaded, sample_rate={voice.config.sample_rate}")
        _voice = voice
    return _voice


def is_available() -> bool:
    return os.path.isfile(MODEL_PATH) and os.path.isfile(CONFIG_PATH)


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

    return audio_samples[:last_idx]


def _normalize_for_playback(audio: np.ndarray) -> np.ndarray:
    """为下游固定增益播放预留 headroom，避免 ×PLAYBACK_GAIN 后削波。

    1. 按峰值缩小，使下游放大后峰值≈TARGET_PEAK；
    2. 对个别仍可能越界的尖峰，在「最终播放域」以 SOFT_KNEE 为膝点做 tanh 软压缩
       （阈值以下保持线性、不失真），膝点折算回当前域处理。
    """
    if len(audio) == 0:
        return audio

    peak = float(np.max(np.abs(audio)))
    if peak < 1e-6:
        return audio

    audio = audio * (TARGET_PEAK / PLAYBACK_GAIN / peak)

    # 软限幅：当前域上限 = 播放域 1.0 / PLAYBACK_GAIN，膝点 = SOFT_KNEE / PLAYBACK_GAIN
    limit = SOFT_KNEE / PLAYBACK_GAIN
    ceil = 1.0 / PLAYBACK_GAIN
    span = ceil - limit
    abs_audio = np.abs(audio)
    over = abs_audio > limit
    if span > 1e-6 and np.any(over):
        sign = np.sign(audio[over])
        excess = abs_audio[over] - limit
        audio[over] = sign * (limit + span * np.tanh(excess / span))

    return audio.astype(np.float32)


# ── 金属感后处理（ffmpeg）─────────────────────────────────────
# 由 configure() 从 assistants.json 的 tts_config.metallic 装配为一条 ffmpeg
# -af 滤镜链字符串（None=不处理）。
_METALLIC_AF = None
_FFMPEG_BIN = None  # 缓存解析到的 ffmpeg 绝对路径（False=确认找不到）


def configure(config: dict) -> None:
    """读取 tts_config，装配金属感 ffmpeg 滤镜链。

    config.metallic = {
        "enabled": true/false,
        "af": { "aecho": "...", "chorus": "...", "bass": "g=4:f=110",
                "treble": "g=2.5", "highpass": "f=80", "lowpass": "f=8500" }
    }
    af 是对象：键=ffmpeg 滤镜名，值=该滤镜参数。按书写顺序拼成
    "名=值,名=值,..."。值留空的项会被跳过（便于临时禁用单个滤镜）。
    """
    global _METALLIC_AF
    m = (config or {}).get("metallic") or {}
    if not m.get("enabled"):
        _METALLIC_AF = None
        return
    af = m.get("af") or {}
    parts = [f"{name}={val}" for name, val in af.items() if str(val).strip()]
    _METALLIC_AF = ",".join(parts) if parts else None
    if _METALLIC_AF:
        # 启动时检测一次 ffmpeg：没装就给一条可操作提示，并自动回退原声
        # （不报错、不影响语音助手运行），避免每次合成都刷 warning。
        if _ffmpeg_bin():
            logger.info("Jarvis 金属感后处理已启用: %s", _METALLIC_AF)
        else:
            logger.warning(
                "已配置金属感语音(tts_config.metallic)，但 ffmpeg 不可用，"
                "将使用原始 Piper 原声。正常情况下 pip 包 imageio-ffmpeg 会自带 ffmpeg，"
                "请确认已 `pip install -r requirements.txt`（或单独 `pip install imageio-ffmpeg`）；"
                "也可设环境变量 FFMPEG_BIN 指向自有 ffmpeg。"
            )


def _ffmpeg_bin() -> str | None:
    """解析 ffmpeg 绝对路径。

    优先级（本项目策略：不依赖系统安装/PATH，跨平台一致）：
      1. FFMPEG_BIN 环境变量（显式覆盖）
      2. pip 包 imageio-ffmpeg 自带的静态二进制（主路径，macOS/Linux/Windows 通用，
         随 requirements 一起装；首次调用如未内置会自动下载并缓存）
      3. 系统 ffmpeg（shutil.which + 常见安装位置，最后兜底）
    """
    global _FFMPEG_BIN
    if _FFMPEG_BIN is not None:
        return _FFMPEG_BIN or None

    cand = os.environ.get("FFMPEG_BIN")

    # 主路径：pip 自带的静态 ffmpeg
    if not cand:
        try:
            import imageio_ffmpeg
            exe = imageio_ffmpeg.get_ffmpeg_exe()
            if exe and os.path.isfile(exe):
                cand = exe
        except Exception as e:
            logger.debug("imageio-ffmpeg 不可用，回退系统 ffmpeg: %s", e)

    # 兜底：系统 ffmpeg
    if not cand:
        cand = shutil.which("ffmpeg")
    if not cand:
        for p in ("/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg",
                  "/usr/bin/ffmpeg"):
            if os.path.isfile(p):
                cand = p
                break

    _FFMPEG_BIN = cand or False
    if cand:
        logger.info("金属处理使用 ffmpeg: %s", cand)
    return cand


def _apply_metallic(audio: np.ndarray, sr: int) -> tuple[np.ndarray, int]:
    """把音频过一遍 ffmpeg 金属链。失败/无 ffmpeg 时原样返回，不阻断合成。"""
    if not _METALLIC_AF:
        return audio, sr
    ff = _ffmpeg_bin()
    if not ff:
        # 未装 ffmpeg：configure() 已在启动时给过一次可操作提示，这里静默回退原声
        return audio, sr
    try:
        buf = io.BytesIO()
        sf.write(buf, audio, sr, format="WAV", subtype="FLOAT")
        proc = subprocess.run(
            [ff, "-hide_banner", "-loglevel", "error",
             "-f", "wav", "-i", "pipe:0", "-af", _METALLIC_AF,
             "-f", "wav", "pipe:1"],
            input=buf.getvalue(), capture_output=True,
        )
        if proc.returncode != 0 or not proc.stdout:
            logger.warning("金属处理失败，用原声: %s",
                           proc.stderr.decode("utf-8", "ignore")[:200])
            return audio, sr
        out, osr = sf.read(io.BytesIO(proc.stdout), dtype="float32")
        if out.ndim > 1:
            out = out.mean(axis=1)
        return out.astype(np.float32), osr
    except Exception as e:
        logger.warning("金属处理异常，用原声: %s", e)
        return audio, sr


def _synthesize_raw(text: str) -> tuple[np.ndarray, int] | None:
    """合成文本为 float32 音频数组"""
    from piper import SynthesisConfig

    voice = _create_voice()
    syn_config = SynthesisConfig(length_scale=LENGTH_SCALE)
    all_audio = []
    for chunk in voice.synthesize(text, syn_config=syn_config):
        all_audio.append(chunk.audio_float_array)

    if not all_audio:
        return None

    audio = np.concatenate(all_audio)
    sr = voice.config.sample_rate
    audio = _trim_silence(audio, sr)
    audio, sr = _apply_metallic(audio, sr)  # 金属感后处理（启用时）
    audio = _normalize_for_playback(audio)
    return (audio, sr)


def synthesize(text: str, output_path: str = None, **kwargs) -> str | None:
    if not is_available():
        logger.error("Piper TTS 不可用")
        return None
    if not text or not text.strip():
        return None

    if output_path is None:
        fd, output_path = tempfile.mkstemp(suffix=".wav")
        os.close(fd)

    try:
        result = _synthesize_raw(text)
        if result is None:
            logger.error("合成失败，音频为空")
            return None

        audio, sr = result
        sf.write(output_path, audio, samplerate=sr, subtype="PCM_16")
        logger.info(f"合成成功: {output_path} ({len(audio)/sr:.2f}s)")
        return output_path
    except Exception as e:
        logger.error(f"合成异常: {e}")
        return None


def synthesize_to_array(text: str, **kwargs) -> tuple[np.ndarray, int] | None:
    if not is_available():
        logger.error("Piper TTS 不可用")
        return None
    if not text or not text.strip():
        return None

    try:
        return _synthesize_raw(text)
    except Exception as e:
        logger.error(f"预合成异常: {e}")
        return None


def synthesize_streaming(text: str, stop_event: threading.Event = None,
                         volume: float = 1.5) -> bool:
    if not is_available():
        logger.error("Piper TTS 不可用")
        return False
    if not text or not text.strip():
        return False

    try:
        from audio import play_array

        result = _synthesize_raw(text)
        if stop_event and stop_event.is_set():
            return False
        if result is None:
            return False

        audio, sr = result
        if len(audio) == 0:
            return False

        # 重采样到设备原生采样率后再播放，避免实时变采样产生电流杂音
        play_array(
            audio, sr, volume=volume, blocking=True,
            stop_check=(stop_event.is_set if stop_event else None),
        )
        return True
    except Exception as e:
        logger.warning(f"合成播放失败: {e}")
        return False
