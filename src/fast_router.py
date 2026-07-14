#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
快速路由：直连 Control Center 配置的快模型，作为分流的第一线。

思路（与主 agent 桥 drop-in 同接口）：
  - 轻消息：快模型直接流式出文本 → 复用现成的句级 TTS 流水线，首字最快。
  - 重消息：快模型用原生 tool call（handoff_to_agent）把任务交回 agent。
    我们捕获这个 tool call → 抛 AgentHandoff，调用方 fall through 到 agent 桥。
  - tripwire 天然免费：OpenAI 流式里 content 与 tool_calls 是分开的 delta 字段，
    handoff 时不会流出任何 content，所以 TTS 一个字都不会念错。

失败即回退（fail-open）：快模型不可用/网络错/非 200/空回复，一律抛 AgentHandoff
让 agent 兜底，绝不让本轮失败。只有已经流出正文后才发生的错误，返回已得部分。

用 OpenAI Python SDK 直连 OpenAI-compatible Chat Completions。
"""

import json
import os
import re
import shutil
import subprocess
import tempfile
from collections import deque

import model_store
import voice_context_store
from model_probe import HANDOFF_TOOL

try:
    from openai import OpenAI as _OpenAI
except Exception:  # pragma: no cover
    _OpenAI = None

try:
    import httpx as _httpx
except Exception:  # pragma: no cover - openai 通常自带 httpx，缺失时用 float timeout
    _httpx = None

# 连接/读取超时。连接要短（快失败即回退 agent）；读取给足以防长答案被误截。
_CONNECT_TIMEOUT = 6.0
_READ_TIMEOUT = 60.0
_HISTORY_TURNS = 3  # 快速路由注入的近期对话轮数（含 FastRouter + agent 轮，供短追问续接）
_HISTORY_MSG_CHARS = 240
_MEMORY_DIRECT_CHARS = 260

_MEMORY_TRIGGERS = (
    "记得", "还记得", "上次", "之前", "以前", "刚才", "我的", "我喜欢", "我不喜欢",
    "我常", "我一般", "我的偏好", "我的习惯", "remember", "last time",
    "previously", "before", "my preference", "my preferences", "i like",
    "i don't like", "i usually", "do you remember",
)

_CODEX_OUTPUT_SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "properties": {
        "mode": {"type": "string", "enum": ["answer", "handoff"]},
        "text": {"type": "string"},
        "task": {"type": "string"},
    },
    "required": ["mode"],
}


class AgentHandoff(Exception):
    """快速路由决定/被迫把本轮交回 agent。

    reason: 'model'(模型主动 handoff) | 'unavailable' | 'empty' | 'error:...'
    task:   交给 agent 的任务文本（模型清洗过的，或原始用户文本兜底）。
    """

    def __init__(self, task, original_text, reason="model"):
        super().__init__(f"handoff({reason}): {task[:60]}")
        self.task = task or original_text
        self.original_text = original_text
        self.reason = reason


def _needs_memory_context(text: str) -> bool:
    low = (text or "").strip().lower()
    if any(t in low for t in _MEMORY_TRIGGERS):
        return True
    # 短句默认带上长期记忆：短消息最可能是依赖上下文/画像的追问，
    # 却常不含"记得/上次"等触发词（如"我叫什么""讲英文"）。本地检索便宜，值得。
    return len(low) <= 15


def _is_codex_provider(provider: str) -> bool:
    return (provider or "").strip().lower() == "openai-codex"


def _router_persona_rules(agent_name: str, persona: str, agent_id: str = "") -> str:
    """Return a short English persona control block.

    Keep system prompts English for stronger tool-calling compatibility and lower
    token cost. The full SOUL may be long or Chinese; FastRouter only needs stable
    voice constraints, not the whole role bible.
    """
    name = (agent_name or "").strip()
    aid = (agent_id or "").strip().lower().replace("-", "_")
    hay = f"{name}\n{persona or ''}".lower()
    # assistant_id is the authoritative isolation key. Display names and SOUL
    # text are mutable inputs and must never override it during a switch race.
    if aid == "lin_meimei" or (not aid and ("lin" in hay or "林" in hay)):
        return (
            "你是林妹妹，古风撒娇风格的 AI 助手。\n"
            "称呼用户为「哥哥」，自称「妹妹」，绝不自称「梅梅」或其他名字。\n"
            "语气温柔体贴、撒娇可爱，带一点古风韵味（「呢」「呀」「这会儿」「罢了」等），"
            "适度小抱怨增加可爱感。不使用 emoji。\n"
            "默认调用 handoff_to_agent。只有当消息纯粹是闲聊、知识问答、感情类，"
            "且完成它只需妹妹开口说话、不需要任何 app/设备/搜索/文件/现实动作，才直接回答。\n"
            "判断标准：「完成这件事，除了说话还需要做什么别的吗？」——需要或不确定，就 handoff。"
            "不要猜答、不要编造、不要只说「好的妹妹去办」却不 handoff。"
        )
    if aid == "jarvis" or (not aid and ("jarvis" in hay or "贾维斯" in hay)):
        return (
            "You are Jarvis. Always reply in English, even when the user speaks "
            "or writes in another language. Address the user as \"sir\" when "
            "natural. Keep a calm, precise, composed assistant tone. Be concise "
            "and natural for voice. Do not use markdown unless asked."
        )
    if name:
        return (
            f"You are {name}. Reply in the user's language. Keep replies concise, "
            "natural, and suitable for voice. Do not use markdown unless asked."
        )
    return (
        "You are a helpful voice assistant. Reply in the user's language. Keep "
        "replies concise, natural, and suitable for voice."
    )


def _routing_system_prompt(agent_name: str, persona: str, agent_id: str = "") -> str:
    who = f"# Character\n{_router_persona_rules(agent_name, persona, agent_id)}\n\n"
    return (
        f"{who}"
        "You are the FastRouter first-line responder for a voice assistant.\n"
        "Your default action is to call handoff_to_agent. Only answer directly if the "
        "message is PURELY one of these: greetings, chit-chat, opinions, general "
        "knowledge from training, language help, or simple math — and fulfilling it "
        "requires nothing beyond your words.\n"
        "Hand off everything else. Ask yourself: 'Does completing this request require "
        "any app, device, service, search, file, or real-world action?' If yes or maybe "
        "— hand off. Do not answer, do not guess, do not summarize what you would do.\n"
        "SPECIAL CASE — wake-up: if 'voice-assistant-wake-up-<timestamp>' is the ENTIRE "
        "message, the user just woke you and is about to speak. Answer directly (never "
        "hand off) with ONE short, warm greeting in character. If another line follows "
        "the marker, that line is the user's same-breath instruction: use the marker only "
        "as wake/time context and handle or hand off the instruction normally. Never "
        "discard the instruction in favor of a greeting. Do NOT mention the marker or "
        "the voice-assistant system.\n"
        "When answering directly as Jarvis, reply in English only. Otherwise reply "
        "in the configured character's required language. Keep it short and spoken, "
        "no markdown, no lists."
    )


class FastRouterClient:
    def __init__(self, should_stop=None, agent_name: str = "", persona: str = "",
                 history_reader=None, agent_id: str = "", engine: str = ""):
        self._should_stop = should_stop or (lambda: False)
        self.agent_id = (agent_id or agent_name or "main").strip().replace("-", "_")
        self.agent_name = agent_name
        self.engine = (engine or "").strip().lower()
        self.persona = persona
        # 引擎 session/memory 读取器（IHistoryReader）：让轻消息也拿到 agent lane 的
        # 近期对话、长期记忆与用户画像。为空则退化为无引擎上下文。
        self.history_reader = history_reader
        # 快 lane 自身滚动历史：引擎里没有（快答不写回），用于连续快轮的即时连续性。
        self._history = deque(maxlen=_HISTORY_TURNS * 2)  # 交替 user/assistant

    # ── 生命周期辅助 ────────────────────────────────────────────────
    def is_available(self) -> bool:
        """有配置好的 current 快模型才启用快速路由。"""
        cfg = model_store.get_current_decrypted()
        if cfg is None:
            return False
        if _is_codex_provider(cfg.get("provider", "")):
            codex = shutil.which("codex") or "/Applications/Codex.app/Contents/Resources/codex"
            return os.path.exists(codex)
        return _OpenAI is not None

    def set_persona(self, persona: str) -> None:
        self.persona = persona or ""

    def set_history_reader(self, reader) -> None:
        self.history_reader = reader

    def reset(self) -> None:
        """清空快速路由滚动上下文（角色切换 / 退下时调用）。"""
        self._history.clear()

    def _build_system_prompt(self, text: str) -> str:
        """English routing prompt + optional memory context."""
        parts = [_routing_system_prompt(self.agent_name, self.persona, self.agent_id)]

        hr = self.history_reader
        if hr is not None and _needs_memory_context(text):
            try:
                if hr.is_available():
                    profile = hr.user_profile(limit_chars=320)
                    if profile:
                        parts.append(
                            "# User profile from long-term memory\n"
                            "Use this only if it helps the current user message.\n"
                            f"{profile}"
                        )
                    mem = hr.search_memory(text, limit=3)
                    if mem:
                        parts.append(
                            "# Possibly relevant memory\n"
                            "These notes may be stale. Use judgment.\n"
                            + "\n".join(f"- {m[:220]}" for m in mem)
                        )
            except Exception:  # noqa: BLE001 — 记忆注入永不影响主流程
                pass
        return "\n\n".join(parts)

    def _prior_messages(self, text: str) -> list[dict]:
        """Immediate continuity from the shared clean voice log.

        We avoid raw engine DB replay here. The shared store contains only
        user/assistant voice turns from FastRouter and agent lanes, so it is safe to
        inject on every FastRouter turn.

        近期对话**一律注入**（不再靠触发词门控）：像"讲英文""说中文""换个说法"
        这类天然追问却不含"继续/然后呢"等词的短句，此前拿不到任何上下文 → 裸模型
        当场失忆。近期 N 轮 token 成本极小（每条截 _HISTORY_MSG_CHARS 字），
        换来连续性，值得。长期记忆检索仍走 _needs_memory_context 门控（更贵）。
        """
        msgs = []
        lanes = {"fast_router", "fast"}
        if self.engine:
            lanes.add(self.engine)
        shared = voice_context_store.recent_turns(
            self.agent_id, limit=_HISTORY_TURNS * 2, lanes=lanes,
        )
        source = shared or list(self._history)
        for m in source:
            content = (m.get("content") or "")[:_HISTORY_MSG_CHARS]
            if content and m.get("role") in ("user", "assistant"):
                msgs.append({"role": m["role"], "content": content})
        return msgs

    # ── 主入口（与桥 drop-in 同签名）─────────────────────────────────
    def send_and_wait_stream(self, text, on_chunk=None, on_start=None,
                             on_end=None, on_tool_call=None):
        intent = self._light_intent(text)
        if intent.startswith("memory_recent_") or intent == "memory_last_turn":
            answer = self._answer_recent_memory(text, intent)
            if not answer:
                raise AgentHandoff(text, text, reason="memory-miss")
            if on_start:
                on_start()
            if on_chunk:
                on_chunk(answer)
            self._remember(text, answer)
            if on_end:
                on_end()
            return answer

        cfg = model_store.get_current_decrypted()
        if cfg is None:
            raise AgentHandoff(text, text, reason="unavailable")

        if _is_codex_provider(cfg.get("provider", "")):
            return self._send_codex_cli(text, cfg, on_chunk, on_start, on_end)

        if _OpenAI is None:
            raise AgentHandoff(text, text, reason="unavailable")

        messages = [{"role": "system", "content": self._build_system_prompt(text)}]
        messages.extend(self._prior_messages(text))
        messages.append({"role": "user", "content": text})

        timeout = (
            _httpx.Timeout(_READ_TIMEOUT, connect=_CONNECT_TIMEOUT)
            if _httpx is not None else _READ_TIMEOUT
        )
        client = _OpenAI(
            api_key=cfg["api_key"],
            base_url=cfg["base_url"].rstrip("/"),
            timeout=timeout,
        )

        try:
            stream = client.chat.completions.create(
                model=cfg["model"],
                messages=messages,
                tools=[HANDOFF_TOOL],
                tool_choice="auto",
                stream=True,
                temperature=0.3,
            )
        except Exception as e:  # 连接层失败 → 回退 agent
            raise AgentHandoff(text, text, reason=f"error:{e}") from None

        return self._consume_stream(
            stream, on_chunk, on_start, on_end, on_tool_call, text,
        )

    def _send_codex_cli(self, text, cfg, on_chunk=None, on_start=None, on_end=None):
        codex = shutil.which("codex") or "/Applications/Codex.app/Contents/Resources/codex"
        if not os.path.exists(codex):
            raise AgentHandoff(text, text, reason="unavailable")

        prompt = self._build_codex_prompt(text)
        schema_fd, schema_path = tempfile.mkstemp(prefix="codex_router_schema_", suffix=".json")
        out_fd, out_path = tempfile.mkstemp(prefix="codex_router_out_", suffix=".txt")
        os.close(schema_fd)
        os.close(out_fd)
        try:
            with open(schema_path, "w", encoding="utf-8") as f:
                json.dump(_CODEX_OUTPUT_SCHEMA, f)
            cmd = [
                codex, "exec",
                "--model", cfg.get("model") or "gpt-5.4-mini",
                "--sandbox", "read-only",
                "--ask-for-approval", "never",
                "--skip-git-repo-check",
                "--ephemeral",
                "--ignore-rules",
                "--output-schema", schema_path,
                "--output-last-message", out_path,
                prompt,
            ]
            proc = subprocess.run(
                cmd,
                cwd=os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                capture_output=True,
                text=True,
                timeout=_READ_TIMEOUT,
            )
            if self._should_stop():
                return ""
            if proc.returncode != 0:
                msg = (proc.stderr or proc.stdout or "").strip()[:300]
                raise AgentHandoff(text, text, reason=f"error:codex {msg}")
            try:
                with open(out_path, "r", encoding="utf-8") as f:
                    raw = f.read().strip()
            except OSError:
                raw = (proc.stdout or "").strip()
            data = json.loads(raw)
            if data.get("mode") == "handoff":
                raise AgentHandoff(data.get("task") or text, text, reason="model")
            answer = (data.get("text") or "").strip()
            if not answer:
                raise AgentHandoff(text, text, reason="empty")
            if on_start:
                on_start()
            if on_chunk:
                on_chunk(answer)
            self._remember(text, answer)
            if on_end:
                on_end()
            return answer
        except AgentHandoff:
            raise
        except Exception as e:
            raise AgentHandoff(text, text, reason=f"error:{e}") from None
        finally:
            for p in (schema_path, out_path):
                try:
                    os.remove(p)
                except OSError:
                    pass

    def _build_codex_prompt(self, text: str) -> str:
        system = self._build_system_prompt(text)
        history = self._prior_messages(text)
        history_text = ""
        if history:
            history_text = "\n".join(
                f"{m['role']}: {m['content']}" for m in history
            )
        history_block = (
            f"# Recent FastRouter conversation\n{history_text}\n\n"
            if history_text else ""
        )
        return (
            f"{system}\n\n"
            "Return JSON only, matching this contract:\n"
            "- If you can answer directly, return {\"mode\":\"answer\",\"text\":\"...\"}.\n"
            "- If this needs tools, live data, files, devices, scheduling, or real-world actions, "
            "return {\"mode\":\"handoff\",\"task\":\"cleaned-up request\"}.\n"
            "Do not inspect files, run commands, browse, or perform actions. Decide routing only.\n\n"
            f"{history_block}"
            f"User message:\n{text}"
        )

    # ── 流解析（离线可单测：喂 SDK chunk-like 对象的可迭代对象）───────────
    def _consume_stream(self, stream, on_chunk, on_start, on_end,
                        on_tool_call, original_text):
        content_parts = []
        tool_acc = {}          # index -> {"name": str, "args": str}
        saw_content = False
        stopped = False

        try:
            for chunk in stream:
                if self._should_stop():
                    stopped = True
                    break
                choices = getattr(chunk, "choices", None) or []
                if not choices:
                    continue
                delta = getattr(choices[0], "delta", None)
                if delta is None:
                    continue

                c = getattr(delta, "content", None)
                if c:
                    if not saw_content:
                        saw_content = True
                        if on_start:
                            on_start()
                    content_parts.append(c)
                    if on_chunk:
                        on_chunk(c)

                for tc in (getattr(delta, "tool_calls", None) or []):
                    idx = getattr(tc, "index", 0)
                    slot = tool_acc.setdefault(idx, {"name": "", "args": ""})
                    fn = getattr(tc, "function", None)
                    if fn is None:
                        continue
                    name = getattr(fn, "name", None)
                    args = getattr(fn, "arguments", None)
                    if name:
                        slot["name"] = name
                    if args:
                        slot["args"] += args
                    if on_tool_call and slot["name"]:
                        on_tool_call(slot["name"], slot["args"])
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
    def _light_intent(text: str) -> str:
        try:
            import light_store
            return light_store.matched_intent(text)
        except Exception:
            return ""

    def _answer_recent_memory(self, text: str, intent: str) -> str:
        turns = self._recent_voice_turns(limit=14)
        if not turns:
            return ""

        low = (text or "").strip().lower()
        if intent == "memory_recent_user_message":
            turn = self._latest_role_turn(turns, "user")
            return self._format_memory_answer("user", turn)
        if intent == "memory_recent_assistant_message":
            turn = self._latest_role_turn(turns, "assistant")
            return self._format_memory_answer("assistant", turn)
        if intent == "memory_last_turn":
            if re.search(r"(我|用户|user).*(刚|上一|最后)|刚才我|我刚刚|my\\s+(last|previous)", low):
                return self._format_memory_answer("user", self._latest_role_turn(turns, "user"))
            if re.search(r"(你|助手|assistant|jarvis).*(刚|上一|最后)|你刚刚|you\\s+(just|last|previous)", low):
                return self._format_memory_answer("assistant", self._latest_role_turn(turns, "assistant"))
            return self._format_memory_answer("last", turns[-1])
        return ""

    def _recent_voice_turns(self, limit: int = 12) -> list[dict]:
        try:
            lanes = {"fast_router", "fast"}
            if self.engine:
                lanes.add(self.engine)
            shared = voice_context_store.recent_turns(
                self.agent_id, limit=limit, lanes=lanes,
            )
            if shared:
                return self._clean_turns(shared, limit)
        except Exception:
            pass

        hr = self.history_reader
        if hr is not None:
            try:
                if hr.is_available():
                    return self._clean_turns(hr.recent_turns(limit=limit), limit)
            except Exception:
                pass
        return []

    @staticmethod
    def _clean_turns(turns: list[dict], limit: int) -> list[dict]:
        seen = set()
        out = []
        for turn in turns:
            role = turn.get("role")
            content = (turn.get("content") or "").strip()
            if role not in ("user", "assistant") or not content:
                continue
            key = (role, content)
            if key in seen:
                continue
            seen.add(key)
            out.append({"role": role, "content": content})
        return out[-limit:]

    @staticmethod
    def _latest_role_turn(turns: list[dict], role: str) -> dict | None:
        for turn in reversed(turns):
            if turn.get("role") == role:
                return turn
        return None

    def _format_memory_answer(self, kind: str, turn: dict | None) -> str:
        if not turn:
            return ""
        content = (turn.get("content") or "").strip()
        if not content:
            return ""
        content = content[:_MEMORY_DIRECT_CHARS]
        role = turn.get("role") or kind
        is_jarvis = "jarvis" in f"{self.agent_id} {self.agent_name}".lower()
        if is_jarvis:
            if kind == "user":
                return f'Your previous message was: "{content}"'
            if kind == "assistant":
                return f'My previous reply was: "{content}"'
            label = "your message" if role == "user" else "my reply"
            return f'The previous voice turn was {label}: "{content}"'
        if kind == "user":
            return f"你上一条说的是：{content}"
        if kind == "assistant":
            return f"我上一条回复的是：{content}"
        label = "你说的" if role == "user" else "我回复的"
        return f"上一条是{label}：{content}"

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
        voice_context_store.append_turn(self.agent_id, "fast_router", "user", user_text)
        voice_context_store.append_turn(self.agent_id, "fast_router", "assistant", assistant_text)
