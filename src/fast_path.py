#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
快路径：直连 Control Center 配置的快模型，作为分流的第一线。

思路（与 openclaw/hermes 桥 drop-in 同接口）：
  - 轻消息：快模型直接流式出文本 → 复用现成的句级 TTS 流水线，首字最快。
  - 重消息：快模型用原生 tool call（handoff_to_agent）把任务交回 agent。
    我们捕获这个 tool call → 抛 AgentHandoff，调用方 fall through 到 agent 桥。
  - tripwire 天然免费：OpenAI 流式里 content 与 tool_calls 是分开的 delta 字段，
    handoff 时不会流出任何 content，所以 TTS 一个字都不会念错。

失败即回退（fail-open）：快模型不可用/网络错/非 200/空回复，一律抛 AgentHandoff
让 agent 兜底，绝不让本轮失败。只有已经流出正文后才发生的错误，返回已得部分。

用 requests 直连 {base_url}/chat/completions（OpenAI 标准），不引入 openai SDK。
"""

import json
from collections import deque

import model_store
from model_probe import HANDOFF_TOOL

try:
    import requests as _requests
except Exception:  # pragma: no cover
    _requests = None

# 连接/读取超时。连接要短（快失败即回退 agent）；读取给足以防长答案被误截。
_CONNECT_TIMEOUT = 6.0
_READ_TIMEOUT = 60.0
_HISTORY_TURNS = 3  # 快路径自留的滚动上下文轮数（仅快轮，供“再说一遍”类追问）


class AgentHandoff(Exception):
    """快路径决定/被迫把本轮交回 agent。

    reason: 'model'(模型主动 handoff) | 'unavailable' | 'empty' | 'error:...'
    task:   交给 agent 的任务文本（模型清洗过的，或原始用户文本兜底）。
    """

    def __init__(self, task, original_text, reason="model"):
        super().__init__(f"handoff({reason}): {task[:60]}")
        self.task = task or original_text
        self.original_text = original_text
        self.reason = reason


def _routing_system_prompt(agent_name: str, persona: str) -> str:
    if persona and persona.strip():
        # 有 SOUL 精简人设：以角色圣经开场，快路径回答须完全保持这个角色。
        who = (
            f"# Your character\n{persona.strip()}\n\n"
            "Stay fully in this character in every spoken reply below.\n\n"
        )
    else:
        who = (
            f"You are {agent_name}.\n\n" if agent_name
            else "You are a helpful voice assistant.\n\n"
        )
    return (
        f"{who}"
        "You are the fast first-line responder for a voice assistant. For the user's "
        "message, decide:\n"
        "- If you can FULLY answer it yourself right now — greetings, chit-chat, "
        "opinions, general knowledge, language help, simple math, or anything that does "
        "NOT need tools, memory of past sessions, real-time/live data, files, devices, "
        "scheduling, or real-world actions — then just answer directly. This is voice: "
        "reply in the user's language, short and spoken, no markdown, no lists.\n"
        "- Otherwise (it needs tools, web/live info, memory of previous conversations, "
        "files, devices, scheduling, or any action you cannot perform as a plain model) "
        "do NOT answer or guess. Call handoff_to_agent with a cleaned-up version of the "
        "request.\n"
        "Never fabricate tool results. When unsure whether you can truly fulfill it, hand off."
    )


class FastPathClient:
    def __init__(self, should_stop=None, agent_name: str = "", persona: str = "",
                 history_reader=None):
        self._should_stop = should_stop or (lambda: False)
        self.agent_name = agent_name
        self.persona = persona
        # 引擎 session/memory 读取器（IHistoryReader）：让轻消息也拿到 agent lane 的
        # 近期对话、长期记忆与用户画像。为空则退化为无引擎上下文。
        self.history_reader = history_reader
        # 快 lane 自身滚动历史：引擎里没有（快答不写回），用于连续快轮的即时连续性。
        self._history = deque(maxlen=_HISTORY_TURNS * 2)  # 交替 user/assistant

    # ── 生命周期辅助 ────────────────────────────────────────────────
    def is_available(self) -> bool:
        """有配置好的 current 快模型才启用快路径。"""
        return _requests is not None and model_store.get_current_decrypted() is not None

    def set_persona(self, persona: str) -> None:
        self.persona = persona or ""

    def set_history_reader(self, reader) -> None:
        self.history_reader = reader

    def reset(self) -> None:
        """清空快路径滚动上下文（角色切换 / 退下时调用）。"""
        self._history.clear()

    def _build_system_prompt(self, text: str) -> str:
        """路由人设 + 引擎注入的用户画像 + 相关记忆。"""
        parts = [_routing_system_prompt(self.agent_name, self.persona)]
        hr = self.history_reader
        if hr is not None:
            try:
                if hr.is_available():
                    profile = hr.user_profile()
                    if profile:
                        parts.append(f"# About the user (from long-term memory)\n{profile}")
                    mem = hr.search_memory(text)
                    if mem:
                        parts.append(
                            "# Possibly relevant memory (may be stale; use judgment)\n"
                            + "\n".join(f"- {m}" for m in mem)
                        )
            except Exception:  # noqa: BLE001 — 记忆注入永不影响主流程
                pass
        return "\n\n".join(parts)

    def _prior_messages(self) -> list[dict]:
        """近期对话：引擎 session（agent lane）+ 快 lane 内部历史，供上下文连续性。"""
        msgs: list[dict] = []
        hr = self.history_reader
        if hr is not None:
            try:
                if hr.is_available():
                    for t in hr.recent_turns(limit=_HISTORY_TURNS * 2):
                        content = (t.get("content") or "")[:400]
                        if content and t.get("role") in ("user", "assistant"):
                            msgs.append({"role": t["role"], "content": content})
            except Exception:  # noqa: BLE001
                pass
        msgs.extend(self._history)
        return msgs

    # ── 主入口（与桥 drop-in 同签名）─────────────────────────────────
    def send_and_wait_stream(self, text, on_chunk=None, on_start=None,
                             on_end=None, on_tool_call=None):
        cfg = model_store.get_current_decrypted()
        if cfg is None:
            raise AgentHandoff(text, text, reason="unavailable")

        url = cfg["base_url"].rstrip("/") + "/chat/completions"
        headers = {"Authorization": f"Bearer {cfg['api_key']}",
                   "Content-Type": "application/json"}
        messages = [{"role": "system", "content": self._build_system_prompt(text)}]
        messages.extend(self._prior_messages())
        messages.append({"role": "user", "content": text})
        payload = {
            "model": cfg["model"],
            "messages": messages,
            "tools": [HANDOFF_TOOL],
            "tool_choice": "auto",
            "stream": True,
            "temperature": 0.3,
        }

        try:
            r = _requests.post(url, headers=headers, json=payload, stream=True,
                               timeout=(_CONNECT_TIMEOUT, _READ_TIMEOUT))
        except Exception as e:  # 连接层失败 → 回退 agent
            raise AgentHandoff(text, text, reason=f"error:{e}") from None

        if r.status_code != 200:
            body = ""
            try:
                body = (r.text or "")[:200]
            except Exception:
                pass
            raise AgentHandoff(text, text, reason=f"error:HTTP {r.status_code} {body}")

        return self._consume_stream(r.iter_lines(), on_chunk, on_start, on_end, text)

    # ── 流解析（离线可单测：喂 raw bytes 行的可迭代对象）───────────────
    def _consume_stream(self, line_iter, on_chunk, on_start, on_end, original_text):
        content_parts = []
        tool_acc = {}          # index -> {"name": str, "args": str}
        saw_content = False
        stopped = False

        try:
            for raw in line_iter:
                if self._should_stop():
                    stopped = True
                    break
                if not raw:
                    continue
                line = raw.decode("utf-8", "ignore").strip() if isinstance(raw, (bytes, bytearray)) else raw.strip()
                if not line.startswith("data:"):
                    continue
                data = line[5:].strip()
                if data == "[DONE]":
                    break
                try:
                    obj = json.loads(data)
                except (ValueError, json.JSONDecodeError):
                    continue
                choices = obj.get("choices") or []
                if not choices:
                    continue
                delta = (choices[0] or {}).get("delta") or {}

                c = delta.get("content")
                if c:
                    if not saw_content:
                        saw_content = True
                        if on_start:
                            on_start()
                    content_parts.append(c)
                    if on_chunk:
                        on_chunk(c)

                for tc in (delta.get("tool_calls") or []):
                    idx = tc.get("index", 0)
                    slot = tool_acc.setdefault(idx, {"name": "", "args": ""})
                    fn = tc.get("function") or {}
                    if fn.get("name"):
                        slot["name"] = fn["name"]
                    if fn.get("arguments"):
                        slot["args"] += fn["arguments"]
        except Exception as e:  # 流中途异常
            if saw_content:
                # 已经念出部分正文，无法再干净地 handoff：返回已得，记入历史
                content = "".join(content_parts)
                self._remember(original_text, content)
                if on_end:
                    on_end()
                return content
            raise AgentHandoff(original_text, original_text, reason=f"error:{e}") from None

        content = "".join(content_parts)

        # 用户打断（barge-in）：不升级 agent，直接返回已得（可能为空），交上层按中止处理。
        if stopped:
            if saw_content and on_end:
                on_end()
            return content

        # 正文优先：只要流出过正文，就是“直接回答”，忽略尾随 tool_call
        if saw_content:
            self._remember(original_text, content)
            if on_end:
                on_end()
            return content

        # 无正文但有 tool_call → 升级
        if tool_acc:
            task = self._extract_task(tool_acc) or original_text
            raise AgentHandoff(task, original_text, reason="model")

        # 既无正文也无 tool_call（空回复）→ 保守回退 agent
        raise AgentHandoff(original_text, original_text, reason="empty")

    # ── 内部工具 ────────────────────────────────────────────────────
    @staticmethod
    def _extract_task(tool_acc: dict) -> str:
        """从累积的 tool_call 参数里取 handoff 的 task 字段。"""
        for slot in tool_acc.values():
            args = slot.get("args") or ""
            try:
                parsed = json.loads(args)
                if isinstance(parsed, dict) and parsed.get("task"):
                    return str(parsed["task"])
            except (ValueError, json.JSONDecodeError):
                continue
        return ""

    def _remember(self, user_text: str, assistant_text: str) -> None:
        if not assistant_text:
            return
        self._history.append({"role": "user", "content": user_text})
        self._history.append({"role": "assistant", "content": assistant_text})
