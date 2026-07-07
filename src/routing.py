#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
快路径白名单路由。

策略：
  - 命中 light_patterns.json 的 agent_intents 时，强制走 agent。
  - 只有 light_patterns.json 明确命中的轻消息，才允许进入快路径。
  - 其余消息默认走 agent。

这样 heavy_patterns.json 不再承担“补漏所有重意图”的职责；系统默认安全地进 agent。
"""

_FRESHNESS_MARKERS = (
    "最新", "最近", "今日", "今天", "现在", "目前", "实时", "现状", "近况",
    "情况", "进展", "动态", "刚刚", "latest", "recent", "current", "today",
    "right now", "status",
)

_EXTERNAL_DOMAINS = (
    # 体育 / 赛事
    "世界杯", "足球", "比赛", "赛事", "赛程", "比分", "战况", "战绩", "球队",
    "联赛", "欧冠", "英超", "西甲", "中超", "世俱杯", "nba", "cba",
    "world cup", "football", "soccer", "match", "game", "score", "schedule",
    "league", "team", "champions league", "premier league", "la liga",
    # 新闻 / 现实动态
    "新闻", "消息", "热搜", "舆情", "进展", "动态", "发布会", "事故", "政策",
    # 天气 / 金融 / 交通等外部状态
    "天气", "气温", "下雨", "降雨", "台风", "股价", "汇率", "航班", "高铁",
    "快递", "订单",
    # 市场状态。避免枚举每一种商品，按“行情类问题”归并。
    "价格", "行情", "报价", "走势", "涨跌", "金价", "油价", "期货", "贵金属",
    "price", "market", "quote", "trend", "gold", "oil", "futures", "precious metal",
)

_FRESHNESS_PATTERNS = (
    "最新消息", "最新新闻", "最新情况", "最新状况", "最新进展", "最新动态",
    "what's the latest", "what is the latest", "latest status",
)


def _contains_any(text: str, markers: tuple[str, ...]) -> bool:
    return any(marker in text for marker in markers)


def needs_live_data(text: str) -> bool:
    """需要实时/外部状态数据的请求返回 True。"""
    low = (text or "").strip().lower()
    if not low:
        return False
    if _contains_any(low, _FRESHNESS_PATTERNS):
        return True
    return _contains_any(low, _FRESHNESS_MARKERS) and _contains_any(low, _EXTERNAL_DOMAINS)


def is_obviously_light(text: str) -> bool:
    """明确允许快路径处理返回 True；否则 False（默认走 agent）。"""
    if not text:
        return False
    import light_store
    if light_store.should_handoff(text):
        return False
    return light_store.contains(text)


def handoff_intent(text: str) -> str:
    """返回强制升级 agent 的意图名；未命中返回空字符串。"""
    if not text:
        return ""
    import light_store
    return light_store.matched_agent_intent(text)
