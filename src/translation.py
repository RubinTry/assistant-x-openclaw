#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""Local lightweight translation for Jarvis full-English mode."""

from __future__ import annotations

import os
import re
import threading
import time
from dataclasses import dataclass

_PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_DEFAULT_MODEL_PATH = os.path.join(
    _PROJECT_DIR,
    "models",
    "translation",
    "opus-mt-zh-en-ct2-int8",
)
_CJK_RE = re.compile(r"[\u3400-\u9fff]")

_lock = threading.RLock()
_translator = None
_source_spm = None
_target_spm = None
_loaded_path = ""


@dataclass
class TranslationResult:
    original_text: str
    translated_text: str
    success: bool
    error: str = ""
    latency_ms: int = 0
    provider: str = "ctranslate2"


def contains_cjk(text: str) -> bool:
    return bool(_CJK_RE.search(text or ""))


def default_model_path() -> str:
    return os.environ.get(
        "VOICE_ASSISTANT_TRANSLATION_MODEL_PATH",
        _DEFAULT_MODEL_PATH,
    )


def translate_to_english(text: str, model_path: str | None = None) -> TranslationResult:
    """Translate text to English with the local CT2 OPUS-MT model."""
    original = (text or "").strip()
    started = time.perf_counter()
    if not original:
        return TranslationResult(original, "", False, error="empty")
    if not contains_cjk(original):
        return TranslationResult(original, original, True, latency_ms=0)

    path = model_path or default_model_path()
    try:
        translator, source_spm, target_spm = _load(path)
        tokens = source_spm.encode(original, out_type=str)
        if not tokens:
            return TranslationResult(original, "", False, error="tokenize_empty")
        tokens.append("</s>")
        result = translator.translate_batch(
            [tokens],
            beam_size=1,
            max_decoding_length=max(32, min(256, len(tokens) * 4)),
            end_token="</s>",
        )
        hypothesis = [t for t in result[0].hypotheses[0] if t != "</s>"]
        translated = target_spm.decode(hypothesis).strip()
        latency = int((time.perf_counter() - started) * 1000)
        return TranslationResult(
            original,
            translated,
            bool(translated),
            error="" if translated else "empty_translation",
            latency_ms=latency,
        )
    except Exception as e:  # noqa: BLE001 - caller decides fail policy
        latency = int((time.perf_counter() - started) * 1000)
        return TranslationResult(
            original,
            "",
            False,
            error=f"{type(e).__name__}: {e}",
            latency_ms=latency,
        )


def _load(model_path: str):
    global _translator, _source_spm, _target_spm, _loaded_path
    with _lock:
        if _translator is not None and _loaded_path == model_path:
            return _translator, _source_spm, _target_spm

        import ctranslate2
        import sentencepiece as spm

        if not os.path.isdir(model_path):
            raise FileNotFoundError(model_path)
        source_path = os.path.join(model_path, "source.spm")
        target_path = os.path.join(model_path, "target.spm")
        if not os.path.exists(source_path):
            raise FileNotFoundError(source_path)
        if not os.path.exists(target_path):
            raise FileNotFoundError(target_path)

        source = spm.SentencePieceProcessor()
        target = spm.SentencePieceProcessor()
        source.load(source_path)
        target.load(target_path)

        _translator = ctranslate2.Translator(model_path, device="cpu", compute_type="int8")
        _source_spm = source
        _target_spm = target
        _loaded_path = model_path
        return _translator, _source_spm, _target_spm
