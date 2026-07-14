"""Platform-neutral system-output echo cancellation."""

from __future__ import annotations

import importlib
import sys
import threading
import time
from collections import deque
from pathlib import Path

import numpy as np

from system_audio_reference import SystemAudioReferenceProvider


def _load_audio_processor():
    """Load the SWIG module while tolerating the dev wheel's version parser bug."""
    try:
        from aec_audio_processing import AudioProcessor

        return AudioProcessor
    except (ImportError, ValueError):
        package_dir = None
        for entry in sys.path:
            candidate = Path(entry) / "aec_audio_processing"
            if (candidate / "audio_processing.py").exists():
                package_dir = candidate
                break
        if package_dir is None:
            raise ImportError("aec_audio_processing is not installed")

        import types

        package = types.ModuleType("aec_audio_processing")
        package.__path__ = [str(package_dir)]
        sys.modules["aec_audio_processing"] = package
        module = importlib.import_module("aec_audio_processing.audio_processing")
        return module.AudioProcessor


class SystemAudioAEC:
    sample_rate = 48_000
    frame_samples = 480

    def __init__(
        self,
        reference_provider: SystemAudioReferenceProvider,
        delay_ms: int = 100,
        reference_delivery_ms: int = 80,
        diagnostics_seconds: float = 0.0,
    ):
        provider_format = (
            reference_provider.sample_rate,
            reference_provider.channels,
            reference_provider.frame_samples,
            np.dtype(reference_provider.sample_dtype),
        )
        required_format = (
            self.sample_rate,
            1,
            self.frame_samples,
            np.dtype("<f4"),
        )
        if provider_format != required_format:
            raise ValueError(
                f"system audio reference format {provider_format} does not match "
                f"required {required_format}"
            )
        AudioProcessor = _load_audio_processor()
        self._reference_provider = reference_provider
        self._processor = AudioProcessor(
            enable_aec=True,
            enable_ns=False,
            enable_agc=False,
            enable_vad=False,
        )
        self._processor.set_stream_format(self.sample_rate, 1)
        self._processor.set_reverse_stream_format(self.sample_rate, 1)
        self._processor.set_stream_delay(int(delay_ms))
        self._delay_ms = int(delay_ms)
        self._mic_delay_frames = max(
            0, int(round(reference_delivery_ms / 10.0))
        )
        self._mic_delay = deque()
        self.last_delayed_raw = np.empty(0, dtype=np.float32)
        self._render = deque()
        self._render_lock = threading.Lock()
        self._render_synced = False
        self._render_frame_count = 0
        self._render_consumed = 0
        self._render_underruns = 0
        self._render_dropped = 0
        self._stats_started = time.monotonic()
        self._diagnostics_seconds = max(0.0, float(diagnostics_seconds))
        self._stats_raw_energy = 0.0
        self._stats_clean_energy = 0.0
        self._stats_render_energy = 0.0
        self._stats_samples = 0
        self._closed = False
        self._processing_failed = False
        self._reference_provider.start(self._on_render_frame, self._on_provider_status)

    @property
    def healthy(self) -> bool:
        return (
            self._reference_provider.healthy
            and not self._processing_failed
            and not self._closed
        )

    @property
    def reference_provider_name(self) -> str:
        return self._reference_provider.name

    def _on_provider_status(self, message: str) -> None:
        if message == "ready":
            print(
                f"[系统 AEC] {self.reference_provider_name} ready，"
                "等待系统音频参考帧"
            )
        else:
            print(f"[系统 AEC/{self.reference_provider_name}] {message}")

    def _on_render_frame(self, frame: np.ndarray) -> None:
        render = np.asarray(frame, dtype=np.float32).reshape(-1)
        if len(render) != self.frame_samples:
            return
        with self._render_lock:
            self._render.append(render.copy())
            self._render_frame_count += 1
            if self._render_frame_count == 1:
                print("[系统 AEC] 已收到首帧系统音频参考")
            while len(self._render) > 50:
                self._render.popleft()

    @staticmethod
    def _to_pcm16(frame: np.ndarray) -> bytes:
        return np.clip(frame * 32767.0, -32768, 32767).astype("<i2").tobytes()

    def process(self, samples: np.ndarray) -> np.ndarray:
        """Return same-length float32 audio; fail open on every error."""
        original = np.asarray(samples, dtype=np.float32).reshape(-1)
        if not self.healthy:
            return original
        if len(original) == 0 or len(original) % self.frame_samples:
            return original
        try:
            generated = []
            delayed_raw = []
            for start in range(0, len(original), self.frame_samples):
                current_mic = original[start : start + self.frame_samples].copy()
                self._mic_delay.append(current_mic)
                if len(self._mic_delay) <= self._mic_delay_frames:
                    generated.append(np.zeros(self.frame_samples, dtype=np.float32))
                    delayed_raw.append(np.zeros(self.frame_samples, dtype=np.float32))
                    continue
                mic = self._mic_delay.popleft()
                delayed_raw.append(mic)
                with self._render_lock:
                    if not self._render_synced and self._render:
                        # helper 比 PortAudio 更早启动时会积压陈旧参考；首个麦克风帧
                        # 只与最新参考对齐，随后严格保持 10ms 对 10ms 的节奏。
                        render = self._render[-1]
                        self._render.clear()
                        self._render_synced = True
                    else:
                        # 系统参考采集器与 PortAudio 使用独立音频时钟，长时间运行
                        # 后参考队列会缓慢漂移。超过 8 帧时丢弃最旧参考并回落到
                        # 4 帧左右，避免 AEC 拿数百毫秒前的系统声处理当前麦克风。
                        if len(self._render) > 8:
                            drop_count = len(self._render) - 4
                            for _ in range(drop_count):
                                self._render.popleft()
                            self._render_dropped += drop_count
                        render = self._render.popleft() if self._render else None
                if render is None:
                    self._render_underruns += 1
                    render_f32 = np.zeros(self.frame_samples, dtype=np.float32)
                else:
                    self._render_consumed += 1
                    render_f32 = render
                self._processor.process_reverse_stream(self._to_pcm16(render_f32))
                self._processor.set_stream_delay(self._delay_ms)
                cleaned = self._processor.process_stream(self._to_pcm16(mic))
                generated.append(
                    np.frombuffer(cleaned, dtype="<i2").astype(np.float32) / 32768.0
                )
                cleaned_f32 = generated[-1]
                self._stats_raw_energy += float(np.dot(mic, mic))
                self._stats_clean_energy += float(np.dot(cleaned_f32, cleaned_f32))
                self._stats_render_energy += float(np.dot(render_f32, render_f32))
                self._stats_samples += len(mic)
            output = np.concatenate(generated)
            self.last_delayed_raw = np.concatenate(delayed_raw)
            now = time.monotonic()
            if (
                self._diagnostics_seconds > 0
                and now - self._stats_started >= self._diagnostics_seconds
                and self._stats_samples
            ):
                raw_rms = (self._stats_raw_energy / self._stats_samples) ** 0.5
                clean_rms = (self._stats_clean_energy / self._stats_samples) ** 0.5
                render_rms = (self._stats_render_energy / self._stats_samples) ** 0.5
                reduction_db = 20.0 * np.log10(
                    (raw_rms + 1e-12) / (clean_rms + 1e-12)
                )
                with self._render_lock:
                    queued = len(self._render)
                print(
                    "[系统 AEC 诊断] "
                    f"render_rms={render_rms:.5f} raw_rms={raw_rms:.5f} "
                    f"clean_rms={clean_rms:.5f} reduction={reduction_db:.2f}dB "
                    f"consumed={self._render_consumed} underrun={self._render_underruns} "
                    f"dropped={self._render_dropped} queued={queued}"
                )
                self._stats_started = now
                self._stats_raw_energy = 0.0
                self._stats_clean_energy = 0.0
                self._stats_render_energy = 0.0
                self._stats_samples = 0
                self._render_consumed = 0
                self._render_underruns = 0
                self._render_dropped = 0
            return output
        except Exception as exc:
            self._processing_failed = True
            print(f"[系统 AEC] 处理失败，已旁路原始麦克风: {exc}")
            return original

    def close(self):
        self._closed = True
        self._reference_provider.close()
