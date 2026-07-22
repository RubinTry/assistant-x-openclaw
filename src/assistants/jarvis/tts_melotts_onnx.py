#!/usr/bin/env python3
"""JARVIS-V2 bilingual MeloTTS backend using ONNX Runtime."""

import json
import logging
import os
import tempfile
import threading
import time
from types import SimpleNamespace

import numpy as np

logger = logging.getLogger(__name__)

_PROJECT_DIR = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
)
_DEFAULT_MODEL_DIR = os.path.join(_PROJECT_DIR, "models", "jarvis-v2-melotts-onnx")
_config = {}
_runtime = None
_runtime_lock = threading.Lock()
_generation_lock = threading.Lock()
_preload_done = threading.Event()
_preload_started = False
_config_revision = 0


def _resolve(path: str) -> str:
    return path if os.path.isabs(path) else os.path.join(_PROJECT_DIR, path)


def configure(config: dict) -> None:
    global _config, _runtime, _preload_started, _config_revision
    new_config = dict(config or {})
    if new_config != _config:
        with _runtime_lock:
            _config = new_config
            _runtime = None
            _config_revision += 1
            _preload_started = False
            _preload_done.clear()


def _namespace(value):
    if isinstance(value, dict):
        return SimpleNamespace(**{k: _namespace(v) for k, v in value.items()})
    if isinstance(value, list):
        return [_namespace(v) for v in value]
    return value


class _Runtime:
    def __init__(self, config: dict):
        import onnxruntime as ort

        self.model_dir = _resolve(config.get("model_dir", _DEFAULT_MODEL_DIR))
        model_path = os.path.join(self.model_dir, "model.onnx")
        config_path = os.path.join(self.model_dir, "config.json")
        self.bert_path = os.path.join(self.model_dir, "bert-base-multilingual-uncased")
        with open(config_path, "r", encoding="utf-8") as f:
            self.hps = _namespace(json.load(f))
        threads = max(1, int(config.get("num_threads", 4)))
        options = ort.SessionOptions()
        options.intra_op_num_threads = threads
        options.inter_op_num_threads = 1
        self.session = ort.InferenceSession(
            model_path, sess_options=options, providers=["CPUExecutionProvider"]
        )
        self.input_names = {item.name for item in self.session.get_inputs()}
        self.sample_rate = int(self.hps.data.sampling_rate)
        expected_sample_rate = int(config.get("sample_rate", self.sample_rate))
        if self.sample_rate != expected_sample_rate:
            raise ValueError(
                f"JARVIS-V2 sample-rate mismatch: model={self.sample_rate}, "
                f"configured={expected_sample_rate}"
            )
        hop_length = int(self.hps.data.hop_length)
        upsample_factor = int(np.prod(self.hps.model.upsample_rates))
        if hop_length != upsample_factor:
            raise ValueError(
                f"JARVIS-V2 hop mismatch: hop_length={hop_length}, "
                f"upsample_factor={upsample_factor}"
            )
        self.speed = float(config.get("speed", 1.0))
        self.sdp_ratio = float(config.get("sdp_ratio", 0.2))
        self.noise_scale = float(config.get("noise_scale", 0.667))
        self.noise_scale_w = float(config.get("noise_scale_w", 0.8))
        from .melotts_onnx_runtime.text import chinese_mix
        chinese_mix.configure_model_path(self.bert_path)

    def preprocess(self, text: str):
        from .melotts_onnx_runtime import commons
        from .melotts_onnx_runtime.text import cleaned_text_to_sequence
        from .melotts_onnx_runtime.text.cleaner import clean_text
        from .melotts_onnx_runtime.text import chinese_mix

        norm_text, phone, tone, word2ph = clean_text(text, "ZH_MIX_EN")
        symbol_to_id = {s: i for i, s in enumerate(self.hps.symbols)}
        phone, tone, language = cleaned_text_to_sequence(
            phone, tone, "ZH_MIX_EN", symbol_to_id
        )
        if self.hps.data.add_blank:
            phone = commons.intersperse(phone, 0)
            tone = commons.intersperse(tone, 0)
            language = commons.intersperse(language, 0)
            word2ph = [n * 2 for n in word2ph]
            word2ph[0] += 1
        feature = chinese_mix.get_bert_feature(
            norm_text, word2ph, "cpu", self.bert_path
        ).numpy().astype(np.float32)
        length = len(phone)
        if feature.shape[-1] != length:
            raise ValueError(f"BERT length {feature.shape[-1]} != phone length {length}")
        return {
            "x_tst": np.asarray([phone], dtype=np.int32),
            "x_tst_lengths": np.asarray([length], dtype=np.int32),
            "speakers": np.asarray([0], dtype=np.int32),
            "tones": np.asarray([tone], dtype=np.int32),
            "lang_ids": np.asarray([language], dtype=np.int32),
            "bert": np.zeros((1, 1024, length), dtype=np.float32),
            "ja_bert": feature[None, :, :],
            "sdp_ratio": np.asarray([self.sdp_ratio], dtype=np.float32),
            "noise_scale": np.asarray([self.noise_scale], dtype=np.float32),
            "noise_scale_w": np.asarray([self.noise_scale_w], dtype=np.float32),
            "speed": np.asarray([self.speed], dtype=np.float32),
        }

    def generate(self, text: str) -> np.ndarray:
        inputs = self.preprocess(text)
        audio = self.session.run(None, {k: v for k, v in inputs.items() if k in self.input_names})[0]
        return np.asarray(audio, dtype=np.float32).reshape(-1)


def _get_runtime() -> _Runtime:
    global _runtime
    if _runtime is None:
        with _runtime_lock:
            if _runtime is None:
                _runtime = _Runtime(_config)
    return _runtime


def _preload_worker(revision: int) -> None:
    """Load every heavyweight component and run one inference off the hot path."""
    started = time.perf_counter()
    try:
        runtime = _get_runtime()
        with _generation_lock:
            # Preprocessing loads/tokenizes the multilingual BERT model; inference
            # initializes ONNX Runtime kernels and memory arenas.
            runtime.generate("Systems online.")
        logger.info(
            "JARVIS-V2 MeloTTS ONNX preloaded in %.2fs", time.perf_counter() - started
        )
    except Exception as exc:
        # Preloading is an optimization only. A later real request still retries and
        # reports the normal synthesis error if the underlying problem persists.
        logger.warning("JARVIS-V2 MeloTTS ONNX preload failed: %s", exc)
    finally:
        if revision == _config_revision:
            _preload_done.set()


def preload() -> None:
    """Start non-blocking model/BERT/session warm-up once per configuration."""
    global _preload_started
    if not is_available():
        return
    with _runtime_lock:
        if _preload_started:
            return
        _preload_started = True
        revision = _config_revision
    threading.Thread(
        target=_preload_worker,
        args=(revision,),
        name="jarvis-v2-tts-preload",
        daemon=True,
    ).start()


def is_available() -> bool:
    model_dir = _resolve(_config.get("model_dir", _DEFAULT_MODEL_DIR))
    required = (
        os.path.join(model_dir, "model.onnx"),
        os.path.join(model_dir, "config.json"),
        os.path.join(model_dir, "bert-base-multilingual-uncased", "config.json"),
        os.path.join(model_dir, "bert-base-multilingual-uncased", "pytorch_model.bin"),
        os.path.join(model_dir, "bert-base-multilingual-uncased", "tokenizer.json"),
    )
    return all(os.path.isfile(path) for path in required)


def synthesize_to_array(text: str, **kwargs):
    if not text or not text.strip() or not is_available():
        return None
    try:
        runtime = _get_runtime()
        # This backend uses one outer worker. The lock also prevents a real request
        # from racing the background warm-up during application startup.
        with _generation_lock:
            return runtime.generate(text), runtime.sample_rate
    except Exception as exc:
        logger.error("JARVIS-V2 MeloTTS ONNX synthesis failed: %s", exc)
        return None


def synthesize(text: str, output_path: str = None, **kwargs):
    result = synthesize_to_array(text, **kwargs)
    if result is None:
        return None
    import soundfile as sf
    audio, sample_rate = result
    if output_path is None:
        fd, output_path = tempfile.mkstemp(suffix=".wav")
        os.close(fd)
    sf.write(output_path, audio, sample_rate, subtype="PCM_16")
    return output_path


def synthesize_streaming(text: str, stop_event=None, volume: float = 1.5) -> bool:
    result = synthesize_to_array(text)
    if result is None or (stop_event and stop_event.is_set()):
        return False
    try:
        from audio import play_array
        audio, sample_rate = result
        return bool(play_array(
            audio,
            sample_rate,
            volume=volume,
            blocking=True,
            stop_check=stop_event.is_set if stop_event else None,
        ))
    except Exception as exc:
        logger.warning("JARVIS-V2 MeloTTS ONNX playback failed: %s", exc)
        return False
