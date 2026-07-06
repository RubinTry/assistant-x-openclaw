#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
重消息库 — 运行时可由 agent 通过 HTTP API 动态添加的重任务模式。

存储：项目根目录 heavy_patterns.json，启动时自动加载，进程内缓存。
匹配：与 routing._HEAVY_MARKERS 相同的子串匹配（大小写不敏感）。
线程安全：读写均持锁，HTTP 回调与主循环可并发调用。
"""

import json
import logging
import os
import threading

logger = logging.getLogger(__name__)

_PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_STORE_PATH = os.path.join(_PROJECT_DIR, "heavy_patterns.json")

_lock = threading.Lock()
_patterns: list[str] = []   # 规范化（lower + strip）后存储
_loaded = False


def _load() -> None:
    global _patterns, _loaded
    if _loaded:
        return
    try:
        if os.path.exists(_STORE_PATH):
            with open(_STORE_PATH, encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, list):
                _patterns = [p for p in data if isinstance(p, str) and p.strip()]
    except Exception as e:
        logger.warning("heavy_store 加载失败，从空库启动: %s", e)
        _patterns = []
    _loaded = True


def _save() -> None:
    try:
        with open(_STORE_PATH, "w", encoding="utf-8") as f:
            json.dump(_patterns, f, ensure_ascii=False, indent=2)
    except Exception as e:
        logger.warning("heavy_store 保存失败: %s", e)


def add(pattern: str) -> bool:
    """添加一条模式，返回 True=新增 / False=已存在。"""
    p = pattern.strip().lower()
    if not p:
        return False
    with _lock:
        _load()
        if p in _patterns:
            return False
        _patterns.append(p)
        _save()
    return True


def remove(pattern: str) -> bool:
    """删除一条模式，返回 True=删除成功 / False=不存在。"""
    p = pattern.strip().lower()
    with _lock:
        _load()
        if p not in _patterns:
            return False
        _patterns.remove(p)
        _save()
    return True


def list_all() -> list[str]:
    """返回当前所有模式的副本。"""
    with _lock:
        _load()
        return list(_patterns)


def contains(text: str) -> bool:
    """文本是否命中库中任意模式（子串匹配，大小写不敏感）。"""
    if not text:
        return False
    low = text.strip().lower()
    with _lock:
        _load()
        return any(p in low for p in _patterns)
