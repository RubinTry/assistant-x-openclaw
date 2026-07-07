#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
轻消息意图路由。

只有命中 light_patterns.json 的消息才允许进入快路径；其余默认走 agent。
配置文件支持按 intents 记录轻意图分组、按 agent_intents 记录强制升级分组，
每个意图下支持 exact / contains / prefix / regex。
同时兼容旧版顶层 exact / contains / prefix / regex，不在代码里固化具体话术。
"""

import json
import logging
import os
import re
import threading

logger = logging.getLogger(__name__)

_PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_STORE_PATH = os.path.join(_PROJECT_DIR, "light_patterns.json")

_lock = threading.RLock()
_loaded = False
_rules = {
    "exact": [],
    "contains": [],
    "prefix": [],
    "regex": [],
}
_compiled_regex: list[re.Pattern] = []
_intent_rules: dict[str, dict[str, list[str]]] = {}
_compiled_intent_regex: dict[str, list[re.Pattern]] = {}
_agent_intent_rules: dict[str, dict[str, list[str]]] = {}
_compiled_agent_intent_regex: dict[str, list[re.Pattern]] = {}


def _norm_list(value) -> list[str]:
    if not isinstance(value, list):
        return []
    return [item.strip().lower() for item in value if isinstance(item, str) and item.strip()]


def _empty_rules() -> dict[str, list[str]]:
    return {"exact": [], "contains": [], "prefix": [], "regex": []}


def _read_rule_block(data: dict) -> dict[str, list[str]]:
    return {
        "exact": _norm_list(data.get("exact")),
        "contains": _norm_list(data.get("contains")),
        "prefix": _norm_list(data.get("prefix")),
        "regex": _norm_list(data.get("regex")),
    }


def _merge_rules(target: dict[str, list[str]], source: dict[str, list[str]]) -> None:
    for key in ("exact", "contains", "prefix", "regex"):
        target[key].extend(source.get(key, []))


def _compile_regex_by_intent(
    intent_rules: dict[str, dict[str, list[str]]]
) -> dict[str, list[re.Pattern]]:
    compiled: dict[str, list[re.Pattern]] = {}
    for intent, rules in intent_rules.items():
        compiled[intent] = []
        for pattern in rules["regex"]:
            try:
                compiled[intent].append(re.compile(pattern, re.IGNORECASE))
            except re.error as e:
                logger.warning("light_store 忽略非法 regex %r (%s): %s", pattern, intent, e)
    return compiled


def _load() -> None:
    global _loaded, _rules, _compiled_regex, _intent_rules, _compiled_intent_regex
    global _agent_intent_rules, _compiled_agent_intent_regex
    if _loaded:
        return
    try:
        rules = _empty_rules()
        intent_rules: dict[str, dict[str, list[str]]] = {}
        agent_intent_rules: dict[str, dict[str, list[str]]] = {}
        if os.path.exists(_STORE_PATH):
            with open(_STORE_PATH, encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict):
                _merge_rules(rules, _read_rule_block(data))
                for group_key, target, merge_to_light in (
                    ("intents", intent_rules, True),
                    ("agent_intents", agent_intent_rules, False),
                ):
                    intents = data.get(group_key)
                    if not isinstance(intents, dict):
                        continue
                    for intent, block in intents.items():
                        if not isinstance(intent, str) or not isinstance(block, dict):
                            continue
                        intent_key = intent.strip().lower()
                        if not intent_key:
                            continue
                        intent_rule = _read_rule_block(block)
                        target[intent_key] = intent_rule
                        if merge_to_light:
                            _merge_rules(rules, intent_rule)
        _rules = rules
        _intent_rules = intent_rules
        _agent_intent_rules = agent_intent_rules
        _compiled_regex = []
        for pattern in _rules["regex"]:
            try:
                _compiled_regex.append(re.compile(pattern, re.IGNORECASE))
            except re.error as e:
                logger.warning("light_store 忽略非法 regex %r: %s", pattern, e)
        _compiled_intent_regex = _compile_regex_by_intent(_intent_rules)
        _compiled_agent_intent_regex = _compile_regex_by_intent(_agent_intent_rules)
    except Exception as e:
        logger.warning("light_store 加载失败，从空白名单启动: %s", e)
        _rules = _empty_rules()
        _compiled_regex = []
        _intent_rules = {}
        _compiled_intent_regex = {}
        _agent_intent_rules = {}
        _compiled_agent_intent_regex = {}
    _loaded = True


def _matches_rules(
    low: str,
    rules: dict[str, list[str]],
    compiled_regex: list[re.Pattern],
) -> bool:
    if low in rules["exact"]:
        return True
    if any(marker in low for marker in rules["contains"]):
        return True
    if any(low.startswith(marker) for marker in rules["prefix"]):
        return True
    return any(pattern.search(low) for pattern in compiled_regex)


def contains(text: str) -> bool:
    """文本是否命中轻消息白名单。"""
    if not text:
        return False
    low = text.strip().lower()
    if not low:
        return False
    with _lock:
        _load()
        if matched_agent_intent(text):
            return False
        return _matches_rules(low, _rules, _compiled_regex)


def matched_intent(text: str) -> str:
    """返回命中的轻消息意图名；未命中返回空字符串。"""
    if not text:
        return ""
    low = text.strip().lower()
    if not low:
        return ""
    with _lock:
        _load()
        for intent, rules in _intent_rules.items():
            if _matches_rules(low, rules, _compiled_intent_regex.get(intent, [])):
                return intent
    return ""


def matched_agent_intent(text: str) -> str:
    """返回强制升级 agent 的意图名；未命中返回空字符串。"""
    if not text:
        return ""
    low = text.strip().lower()
    if not low:
        return ""
    with _lock:
        _load()
        for intent, rules in _agent_intent_rules.items():
            if _matches_rules(low, rules, _compiled_agent_intent_regex.get(intent, [])):
                return intent
    return ""


def should_handoff(text: str) -> bool:
    """文本是否命中强制升级规则。"""
    return bool(matched_agent_intent(text))
