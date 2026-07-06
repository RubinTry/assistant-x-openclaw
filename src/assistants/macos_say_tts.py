#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
macOS 系统语音 TTS —— 走内置 `say` 命令合成，可选 Lee 等系统音色。

用途：给 jarvis（或任意角色）配一个「原本 Piper 不动」的备选 TTS。
在 assistants.json 里把 components.tts 从 "jarvis" 改成 "macos_say" 即启用，
tts_config 支持：
    {
      "voice": "Lee",          # say -v 的音色名，默认 Lee
      "rate": 180,             # 语速（words/min），可选；不填用系统默认
      "metallic": { ... }      # 可选：复用 jarvis 金属感 ffmpeg 链（默认关）
    }

设计取舍：
  - say 直出 22050Hz 单声道 PCM WAV，正好与 Piper 同采样率，接现成播放管线。
  - 金属感后处理复用 assistants.jarvis.tts_piper 的 configure/_apply_metallic
    （只读引用，不修改原模块；同一时刻只有一个 TTS 生效，其模块级状态不冲突）。
  - 仅 macOS 可用；非 darwin / 无 say / 音色不存在 → is_available 返回 False，
    上层退化处理，绝不崩。
"""

import logging
import os
import shutil
import subprocess
import sys
import tempfile
import threading

import numpy as np

from assistants.tts import AssistantTTS

logger = logging.getLogger(__name__)

# say 输出统一 22050Hz PCM16 WAV（与 Piper 一致）。
_SAMPLE_RATE = 22050
# 归一化目标峰值：留足 1.5× 播放增益空间（0.6×1.5=0.9，不 clip）。
# say 原始输出常接近满幅，直接 1.5× 会削顶，故先压到 _TARGET_PEAK。
_TARGET_PEAK = 0.6


class MacosSayTTS(AssistantTTS):
    def __init__(self, config: dict = None):
        config = config or {}
        self.config = config
        self._voice = config.get("voice", "Lee")
        self._rate = config.get("rate")  # words/min；None=系统默认
        self._lock = threading.Lock()
        self._available = None  # 缓存可用性检查结果（首次深检后固定）
        # 金属感后处理：复用 jarvis 的 ffmpeg 链（默认关）。
        self._metallic = bool((config.get("metallic") or {}).get("enabled"))
        if self._metallic:
            try:
                from assistants.jarvis import tts_piper
                tts_piper.configure(config)  # 装配 _METALLIC_AF
            except Exception as e:  # noqa: BLE001 — 金属处理可选，失败退化为原声
                logger.warning("macos_say 金属链装配失败，改用原声: %s", e)
                self._metallic = False

    # ── 可用性 ────────────────────────────────────────────
    def is_available(self) -> bool:
        # 只查平台 + say 二进制：say 对未知音色会静默回退默认音（写文件仍 exit 0），
        # 且 Lee 等增强音不在 `say -v '?'` 列表里，故音色本身无法可靠校验——
        # 校验要么误拒 Lee，要么放过错名。音色配错时只会听到默认音，改 json 即可。
        if self._available is not None:
            return self._available
        self._available = sys.platform == "darwin" and bool(shutil.which("say"))
        if self._available:
            logger.info("macos_say TTS 就绪：voice=%s rate=%s metallic=%s",
                        self._voice, self._rate, self._metallic)
        else:
            logger.warning("macos_say TTS 不可用：非 macOS 或缺 say 命令")
        return self._available

    # ── 合成 ──────────────────────────────────────────────
    def _say_to_wav(self, text: str, out_path: str) -> bool:
        cmd = ["say", "-v", self._voice]
        if self._rate:
            cmd += ["-r", str(int(self._rate))]
        cmd += ["-o", out_path, "--file-format=WAVE",
                f"--data-format=LEI16@{_SAMPLE_RATE}", text]
        try:
            with self._lock:
                proc = subprocess.run(cmd, capture_output=True, timeout=60)
            if proc.returncode != 0:
                logger.error("say 合成失败: %s",
                             proc.stderr.decode("utf-8", "ignore")[:200])
                return False
            return os.path.getsize(out_path) > 0
        except Exception as e:  # noqa: BLE001
            logger.error("say 合成异常: %s", e)
            return False

    def _load_normalized(self, wav_path: str) -> tuple[np.ndarray, int] | None:
        """读 WAV → (可选金属处理) → peak 归一化到 _TARGET_PEAK。"""
        import soundfile as sf
        audio, sr = sf.read(wav_path, dtype="float32")
        if audio.ndim > 1:
            audio = audio.mean(axis=1)
        if self._metallic:
            try:
                from assistants.jarvis import tts_piper
                audio, sr = tts_piper._apply_metallic(audio, sr)
            except Exception as e:  # noqa: BLE001
                logger.warning("金属处理异常，用原声: %s", e)
        peak = float(np.max(np.abs(audio))) if len(audio) else 0.0
        if peak > 1e-6:
            audio = (audio * (_TARGET_PEAK / peak)).astype(np.float32)
        return audio, sr

    def synthesize(self, text: str, output_path: str = None, **kwargs) -> str | None:
        if not self.is_available() or not text or not text.strip():
            return None
        import soundfile as sf

        fd, raw_path = tempfile.mkstemp(suffix=".wav")
        os.close(fd)
        try:
            if not self._say_to_wav(text, raw_path):
                return None
            loaded = self._load_normalized(raw_path)
            if loaded is None:
                return None
            audio, sr = loaded
            if output_path is None:
                fd2, output_path = tempfile.mkstemp(suffix=".wav")
                os.close(fd2)
            sf.write(output_path, audio, samplerate=sr, subtype="PCM_16")
            return output_path
        except Exception as e:  # noqa: BLE001
            logger.error("macos_say synthesize 异常: %s", e)
            return None
        finally:
            try:
                os.unlink(raw_path)
            except OSError:
                pass

    def synthesize_to_array(self, text: str, **kwargs) -> tuple[np.ndarray, int] | None:
        if not self.is_available() or not text or not text.strip():
            return None
        fd, raw_path = tempfile.mkstemp(suffix=".wav")
        os.close(fd)
        try:
            if not self._say_to_wav(text, raw_path):
                return None
            return self._load_normalized(raw_path)
        except Exception as e:  # noqa: BLE001
            logger.error("macos_say synthesize_to_array 异常: %s", e)
            return None
        finally:
            try:
                os.unlink(raw_path)
            except OSError:
                pass

    def synthesize_streaming(self, text: str, stop_event: threading.Event = None,
                             volume: float = 1.5) -> bool:
        result = self.synthesize_to_array(text)
        if result is None:
            return False
        if stop_event and stop_event.is_set():
            return False
        audio, sr = result
        if len(audio) == 0:
            return False
        try:
            import sounddevice as sd
            sd.play(audio * volume, samplerate=sr)
            sd.wait()
            return True
        except Exception as e:  # noqa: BLE001
            logger.warning("macos_say 流式播放失败: %s", e)
            return False
