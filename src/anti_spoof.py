#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
活体检测 / 反欺骗模块（Anti-Spoofing / Replay Detection）

用途：区分"活人当面说话" vs "电脑/音箱播放的录音"，与声纹验证配合使用。
  - 声纹验证（campplus）回答"是不是你" —— 挡掉别人/媒体里的人声
  - 本模块（AASIST）回答"是不是活人当场说" —— 挡掉音箱重放你本人的录音

模型：推荐 AASIST-L（clovaai/aasist），原始波形端到端，16kHz 单声道输入。
导出 ONNX 见 scripts/export_aasist_onnx.py。

设计原则：**软失败**。模型文件缺失、onnxruntime 不可用、或推理异常时，
本模块一律放行（返回"通过"），绝不阻塞现有语音助手功能。
拿到模型权重放入 models/ 后自动启用。
"""

import logging
import os
import threading

import numpy as np

logger = logging.getLogger(__name__)

# AASIST 官方固定输入长度：64600 采样点 ≈ 4.04s @ 16kHz
_DEFAULT_TARGET_LEN = 64600
_DEFAULT_SAMPLE_RATE = 16000


def _pad_or_trim(x: np.ndarray, target_len: int) -> np.ndarray:
    """将波形补齐/截断到固定长度。

    复刻 clovaai/aasist 的 pad()：不足时循环平铺（repeat-pad），超长时截前段。
    """
    x = np.asarray(x, dtype=np.float32).reshape(-1)
    x_len = x.shape[0]
    if x_len == 0:
        return np.zeros(target_len, dtype=np.float32)
    if x_len >= target_len:
        return x[:target_len]
    num_repeats = int(target_len / x_len) + 1
    padded = np.tile(x, num_repeats)[:target_len]
    return padded.astype(np.float32)


def _softmax(v: np.ndarray) -> np.ndarray:
    v = v - np.max(v)
    e = np.exp(v)
    return e / np.sum(e)


def _sigmoid(x: float) -> float:
    return float(1.0 / (1.0 + np.exp(-x)))


class AntiSpoofDetector:
    """AASIST 活体检测器（ONNX 推理）。

    score(samples) 返回 bonafide（真人活体）概率 0~1，越高越像活人。
    is_live(samples) 返回 (是否通过, 分数)，分数 >= threshold 视为活体。
    """

    def __init__(
        self,
        model_path: str,
        threshold: float = 0.5,
        target_len: int = _DEFAULT_TARGET_LEN,
        sample_rate: int = _DEFAULT_SAMPLE_RATE,
        bonafide_index: int = 1,
        num_threads: int = 1,
    ):
        self.model_path = model_path
        self.threshold = threshold
        self.target_len = target_len
        self.sample_rate = sample_rate
        self.bonafide_index = bonafide_index
        self.num_threads = num_threads

        self._session = None
        self._input_name = None
        self._output_name = None
        self._available = False
        self._lock = threading.Lock()

        self._try_load()

    # ── 加载 ──────────────────────────────────────────────
    def _try_load(self):
        if not self.model_path or not os.path.exists(self.model_path):
            logger.info(f"[活体] 模型不存在，软失败放行: {self.model_path}")
            return

        try:
            import onnxruntime as ort
        except Exception as e:
            logger.warning(f"[活体] onnxruntime 不可用，软失败放行: {e}")
            return

        try:
            so = ort.SessionOptions()
            so.intra_op_num_threads = self.num_threads
            so.inter_op_num_threads = self.num_threads
            # 仅用 CPU，避免与其它模型抢占加速器；如需可改为 CoreML/CUDA
            providers = ["CPUExecutionProvider"]
            self._session = ort.InferenceSession(
                self.model_path, sess_options=so, providers=providers
            )
            self._input_name = self._session.get_inputs()[0].name
            self._output_name = self._session.get_outputs()[0].name
            self._available = True
            logger.info(
                f"[活体] AASIST 模型已加载: {self.model_path} "
                f"(input={self._input_name}, output={self._output_name})"
            )
        except Exception as e:
            logger.error(f"[活体] 模型加载失败，软失败放行: {e}")
            self._session = None
            self._available = False

    def is_available(self) -> bool:
        return self._available and self._session is not None

    # ── 推理 ──────────────────────────────────────────────
    def _to_bonafide_prob(self, output: np.ndarray) -> float:
        """把模型原始输出归一化为 bonafide 概率 0~1。

        兼容多种导出形态：
          - (1, 2) / (2,)：两类 logits → softmax 取 bonafide 列
          - (1, 1) / (1,) / 标量：单一分数 → sigmoid
        """
        arr = np.asarray(output, dtype=np.float32).reshape(-1)
        if arr.size >= 2:
            probs = _softmax(arr[:2])
            idx = self.bonafide_index if self.bonafide_index < probs.size else 1
            return float(np.clip(probs[idx], 0.0, 1.0))
        # 单值输出：当作 logit 走 sigmoid
        return _sigmoid(float(arr[0]))

    def score(self, samples, sample_rate: int = None):
        """返回 bonafide（活体）概率 0~1；失败返回 None。"""
        if not self.is_available():
            return None
        if samples is None:
            return None

        sr = sample_rate or self.sample_rate
        try:
            x = np.asarray(samples, dtype=np.float32).reshape(-1)
        except Exception:
            return None
        if x.size == 0:
            return None

        # 注意：模型按 16kHz 训练，调用方需保证已是 16kHz。
        if sr != self.sample_rate:
            logger.warning(
                f"[活体] 采样率 {sr} != {self.sample_rate}，结果可能不准"
            )

        feat = _pad_or_trim(x, self.target_len)
        feat = feat.reshape(1, -1).astype(np.float32)

        try:
            with self._lock:
                out = self._session.run([self._output_name], {self._input_name: feat})
            prob = self._to_bonafide_prob(out[0])
            return prob
        except Exception as e:
            logger.error(f"[活体] 推理失败，软失败放行: {e}")
            return None

    def is_live(self, samples, sample_rate: int = None):
        """返回 (是否通过, 分数)。

        软失败：模型不可用或推理失败时返回 (True, -1.0)，不阻塞。
        """
        prob = self.score(samples, sample_rate)
        if prob is None:
            return True, -1.0
        return (prob >= self.threshold), prob


# ── 单例 ──────────────────────────────────────────────────
_detector = None
_detector_lock = threading.Lock()


def get_anti_spoof_detector(
    model_path: str = None, threshold: float = 0.5, **kwargs
) -> AntiSpoofDetector:
    """获取（懒加载）全局活体检测器单例。"""
    global _detector
    with _detector_lock:
        if _detector is None:
            _detector = AntiSpoofDetector(
                model_path=model_path, threshold=threshold, **kwargs
            )
        return _detector
