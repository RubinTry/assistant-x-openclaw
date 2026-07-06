#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
打断词生成（分流方案 B）：assistants.json 的 interrupt_words → KWS 关键词文件。

真源是 assistants.json 里每个助手的 `interrupt_words`（中文/英文短语）。语音助手
**启动时自动调用 generate_all()** 生成 keywords/interrupt/<id>.txt，唤醒对应助手时
再加载该文件（见 main.py 的 _load_interrupt_spotter_async）。

KWS 模型（sherpa-onnx-kws-zipformer-zh-en）是**音素模型**，中英双语：
  - 中文：pypinyin 转「声母 韵母带调」（如 停一下 → t íng y ī x ià）
  - 英文：查模型自带 en.phone 词典转 ARPABET（如 stop → S T AA1 P）
输出格式与唤醒词一致：`<音素 ...> :<score> #<threshold> @<原词>`

一切 fail-open：某词转换失败就跳过并告警，绝不因打断词生成拖垮启动。
"""

import json
import os
import re

from pypinyin import lazy_pinyin, Style

DEFAULT_SCORE = 2.0
DEFAULT_THRESHOLD = 0.05  # 比唤醒词(0.02)略严；打断词是刻意喊出的，无需超敏感

_CJK = re.compile(r"[一-鿿]")


def _has_cjk(s: str) -> bool:
    return bool(_CJK.search(s or ""))


def _chinese_tokens(phrase: str) -> list:
    initials = lazy_pinyin(phrase, style=Style.INITIALS, strict=False)
    finals = lazy_pinyin(phrase, style=Style.FINALS_TONE, strict=False)
    toks = []
    for ini, fin in zip(initials, finals):
        if ini:
            toks.append(ini)
        if fin:
            toks.append(fin)
    return toks


def _english_tokens(phrase: str, en_phone: dict) -> list | None:
    """英文短语 → ARPABET 音素序列；有词查不到则返回 None（整条放弃）。"""
    toks = []
    for word in re.findall(r"[A-Za-z']+", phrase):
        phones = en_phone.get(word.upper())
        if not phones:
            return None
        toks.extend(phones.split())
    return toks or None


def _phrase_to_line(phrase: str, en_phone: dict, score, threshold) -> str | None:
    phrase = (phrase or "").strip()
    if not phrase:
        return None
    toks = _chinese_tokens(phrase) if _has_cjk(phrase) else _english_tokens(phrase, en_phone)
    if not toks:
        return None
    # @标签不能含空格（sherpa 会把空格后的部分当成 token 报错）；多词短语用 _ 连接。
    tag = re.sub(r"\s+", "_", phrase)
    return f"{' '.join(toks)} :{score} #{threshold} @{tag}"


def _load_en_phone(kws_model_dir: str) -> dict:
    """加载模型自带 en.phone 英文词典 {WORD: 'PH PH ...'}；缺失返回空 dict。"""
    d = {}
    if not kws_model_dir:
        return d
    path = os.path.join(kws_model_dir, "en.phone")
    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                parts = line.strip().split(None, 1)
                if len(parts) == 2:
                    d[parts[0].upper()] = parts[1]
    except OSError:
        pass
    return d


def _load_interrupt_words(project_dir: str) -> dict:
    """从 assistants.json 读 {assistant_id: [打断词, ...]}。"""
    path = os.path.join(project_dir, "assistants.json")
    try:
        with open(path, "r", encoding="utf-8") as f:
            cfg = json.load(f)
    except (OSError, ValueError):
        return {}
    result = {}
    for a in cfg.get("assistants", []):
        if not isinstance(a, dict):
            continue
        aid = a.get("id")
        words = a.get("interrupt_words") or []
        if aid and isinstance(words, list):
            cleaned = [w for w in words if isinstance(w, str) and w.strip()]
            if cleaned:
                result[aid] = cleaned
    return result


def generate_all(project_dir: str, kws_model_dir: str = "",
                 score=DEFAULT_SCORE, threshold=DEFAULT_THRESHOLD,
                 verbose: bool = False) -> dict:
    """读取 assistants.json，为每个助手生成 keywords/interrupt/<id>.txt。

    返回 {assistant_id: 写入的打断词条数}。中英双语；英文需 kws_model_dir 指向
    含 en.phone 的模型目录。fail-open：任何异常不抛出，仅告警。
    """
    out = {}
    try:
        assistants = _load_interrupt_words(project_dir)
        if not assistants:
            return out
        out_dir = os.path.join(project_dir, "keywords", "interrupt")
        os.makedirs(out_dir, exist_ok=True)

        en_phone = None  # 惰性加载（只有出现英文词才读 126k 行词典）
        for aid, words in assistants.items():
            if en_phone is None and any(not _has_cjk(w) for w in words):
                en_phone = _load_en_phone(kws_model_dir)
            lines = []
            for w in words:
                line = _phrase_to_line(w, en_phone or {}, score, threshold)
                if line:
                    lines.append(line)
                elif verbose:
                    print(f"[打断词] 跳过无法转换的词「{w}」(assistant={aid})"
                          + ("；英文需 en.phone 命中" if not _has_cjk(w) else ""))
            path = os.path.join(out_dir, f"{aid}.txt")
            with open(path, "w", encoding="utf-8") as f:
                f.write("\n".join(lines) + ("\n" if lines else ""))
            out[aid] = len(lines)
            if verbose:
                print(f"[打断词] 生成 {path}（{len(lines)} 词）")
    except Exception as e:  # noqa: BLE001 — 生成绝不拖垮启动
        print(f"[打断词] 生成失败（忽略）: {e}")
    return out
