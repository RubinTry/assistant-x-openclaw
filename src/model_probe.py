#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
模型能力探针（配置前校验）。

分流设计里，快模型判定"重消息"是靠**原生 tool call** 把任务 handoff 给 agent，
所以快模型**必须支持工具调用**，否则升级路径断掉。快模型由 Control Center 配置，
因此存表前要探一层：不支持工具的模型直接拦下、提示用户改。

探针只用一次最小请求，测的是"能力"而非"意愿"——挂一个 handoff 工具 + 强制
tool_choice，看端点/模型能否吐出合规的 tool_calls。判读逻辑（interpret_probe）
是纯函数，可离线单测；网络部分（probe_model）用 requests，避免引入新依赖。

用 requests 直连 {base_url}/chat/completions（OpenAI 标准），不经过 openai SDK——
venv 未装 openai，且仓库既有桥（openclaw_bridge.py）也是 requests 风格。
"""

import json

try:
    import requests as _requests
except Exception:  # pragma: no cover - requests 是既有依赖，理论上恒在
    _requests = None

# 校验用的 handoff 工具 schema。与后续快路径真正下发给模型的应保持一致
# （单一事实源：真正接快路径时从这里 import）。
HANDOFF_TOOL = {
    "type": "function",
    "function": {
        "name": "handoff_to_agent",
        "description": (
            "When the request needs tools, memory, real-time data, or real-world "
            "actions that you cannot fulfill yourself, hand it off to the main agent."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "task": {
                    "type": "string",
                    "description": "The user's request to hand off, cleaned up.",
                },
            },
            "required": ["task"],
        },
    },
}

_PROBE_MESSAGES = [
    {
        "role": "user",
        "content": "Hand this task off to the agent: search the web for today's news.",
    }
]


def _chat_url(base_url: str) -> str:
    return base_url.rstrip("/") + "/chat/completions"


def interpret_probe(status, body, exc=None, forced=True) -> dict:
    """纯函数：把一次探针的 (status, body, exc) 判读成能力结论。

    返回:
      {ok, reachable, auth_ok, model_ok, tool_support, message}
    ok = 四项全绿（可达 + 鉴权 + 模型有效 + 支持工具）。
    """
    res = {
        "ok": False,
        "reachable": True,
        "auth_ok": True,
        "model_ok": True,
        "tool_support": False,
        "message": "",
    }

    # 1) 连接层异常：不可达
    if exc is not None:
        res.update(reachable=False, message=f"连接失败: {exc}")
        return res

    # 抽取错误文本（尽量兼容 OpenAI/各家结构）
    err_text = ""
    if isinstance(body, dict):
        err = body.get("error")
        if isinstance(err, dict):
            err_text = str(err.get("message") or err.get("code") or "")
        elif isinstance(err, str):
            err_text = err
        if not err_text:
            err_text = str(body.get("message") or "")
    low = err_text.lower()

    # 2) 鉴权失败
    if status in (401, 403):
        res.update(auth_ok=False, message=f"鉴权失败(HTTP {status}): {err_text or 'API key 无效'}")
        return res

    # 3) 模型无效（404，或 400 明确说 model 未知）
    if status == 404 or (
        status == 400 and any(k in low for k in ("model", "模型"))
        and any(k in low for k in ("not found", "unknown", "does not exist", "无效", "不存在"))
    ):
        res.update(model_ok=False, message=f"模型无效(HTTP {status}): {err_text}")
        return res

    # 4) 400 且错误指向 tool/function/tool_choice → 端点/模型不支持工具
    if status == 400 and any(k in low for k in ("tool", "function", "tool_choice")):
        res.update(tool_support=False,
                   message=f"不支持工具调用(HTTP 400): {err_text}")
        return res

    # 5) 其它非 200
    if status != 200:
        res.update(message=f"请求失败(HTTP {status}): {err_text or '未知错误'}")
        return res

    # 6) 200：看有没有吐出 tool_calls
    tool_calls = None
    try:
        choices = body.get("choices") or []
        msg = (choices[0] or {}).get("message") or {}
        tool_calls = msg.get("tool_calls")
    except (AttributeError, IndexError, TypeError):
        tool_calls = None

    if tool_calls:
        res.update(ok=True, tool_support=True, message="支持工具调用 ✓")
    else:
        # 被强制 tool_choice 仍不吐 tool_calls → 判为不支持（能力不足/静默忽略）
        hint = "（强制 tool_choice 下仍未产生 tool_calls，判为不支持）" if forced else \
               "（auto 模式下未调用工具，可能不支持或未触发）"
        res.update(tool_support=False,
                   message=f"未产生 tool_calls，判定不支持工具调用 {hint}")
    return res


def probe_model(base_url: str, model: str, api_key: str, timeout: float = 12.0) -> dict:
    """对单个模型跑一次能力探针。返回 interpret_probe 的结论 dict。

    tool_choice 采用"强制对象形式 → required → auto"的降级阶梯，
    以兼容不同 provider 对 tool_choice 的支持差异，避免误判为不支持。
    """
    if _requests is None:
        return {"ok": False, "reachable": False, "auth_ok": False,
                "model_ok": False, "tool_support": False,
                "message": "requests 模块不可用，无法校验"}

    url = _chat_url(base_url)
    headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
    base_payload = {
        "model": model,
        "messages": _PROBE_MESSAGES,
        "tools": [HANDOFF_TOOL],
        "max_tokens": 64,
        "stream": False,
        "temperature": 0,
    }

    # tool_choice 降级阶梯
    choices_ladder = [
        {"type": "function", "function": {"name": "handoff_to_agent"}},  # 强制对象
        "required",                                                       # 强制任意
        "auto",                                                           # 自动
    ]

    last = None
    for i, tc in enumerate(choices_ladder):
        payload = dict(base_payload, tool_choice=tc)
        forced = tc != "auto"
        try:
            r = _requests.post(url, headers=headers, json=payload, timeout=timeout)
        except Exception as e:  # noqa: BLE001 — 连接层异常统一判不可达
            return interpret_probe(None, None, exc=e)
        try:
            body = r.json()
        except (ValueError, json.JSONDecodeError):
            body = {"error": {"message": (r.text or "")[:300]}}

        result = interpret_probe(r.status_code, body, forced=forced)
        last = result

        # 明确成功 / 明确鉴权或模型问题 → 立即返回，不再降级
        if result["ok"] or not result["auth_ok"] or not result["model_ok"]:
            return result
        # 若失败原因是 tool_choice 本身不被支持，降级再试；否则直接返回
        low = result["message"].lower()
        tool_choice_rejected = ("tool_choice" in low) or ("tool choice" in low)
        if not tool_choice_rejected:
            return result
        # 否则继续 ladder 下一档

    return last
