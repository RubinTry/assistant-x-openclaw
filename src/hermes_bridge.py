#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Hermes 桥接模块（engine=hermes，方案 B：一角色一 profile 一网关）

与 OpenClaw 桥同接口（drop-in），对接 Hermes Agent 的 OpenAI 兼容 API Server。

方案 B —— 完全隔离：
  - 每个角色 = 一个独立 Hermes profile（独立 HERMES_HOME = 独立记忆/会话/技能/state.db），
    各自跑一个网关、占一个端口。角色之间的长期记忆物理隔离，不会串。
  - 桥按 agent_id 定位 profile（~/.hermes/profiles/<agent_id>/），
    从其 .env 读取 API_SERVER_PORT / API_SERVER_KEY，自解析端点，无需环境变量。
  - 网关的建立/启动由 scripts/hermes_provision.py 在 start.sh 中完成。
  - 人设/提示词与 SOUL：不在此处理，由用户亲自管理与下达。
  - 多轮连续：X-Hermes-Session-Id 按「空闲间隔」滚动（voice-<agent>-<YYYYMMDDHHMMSS>）。
    只有当距上次对话静默超过 HERMES_SESSION_IDLE_GAP_SEC（默认 1800s=30min）时才新建会话；
    连续对话（哪怕跨整点）永远续用同一 session，不会被腰斩——修复了此前按整点滚动导致
    跨整点对话记忆断裂的问题。真正空闲后才切断，老会话留在 state.db（可被 session_search 召回），
    避免单一长存会话无限膨胀；上下文压缩另由 hermes config 的 compression 负责。
  - 清空上下文(/clear)：DELETE /api/sessions/<session_id>。
  - 打断(/stop)：客户端断流。
"""

import json
import logging
import os
import threading
import time
import uuid

import requests

import voice_context_store

logger = logging.getLogger(__name__)

DEFAULT_TIMEOUT = None
_HERMES_HOME = os.path.expanduser(os.environ.get("HERMES_HOME", "~/.hermes"))
# 会话空闲滚动阈值：静默超过该秒数才开新 session（默认 30 分钟）。
_SESSION_IDLE_GAP_SEC = int(os.environ.get("HERMES_SESSION_IDLE_GAP_SEC", "1800"))


def _profile_env_path(profile: str) -> str:
    return os.path.join(_HERMES_HOME, "profiles", profile, ".env")


def _read_env_file(path: str) -> dict:
    d = {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                d[k.strip()] = v.strip().strip('"').strip("'")
    except FileNotFoundError:
        pass
    except Exception as e:
        logger.error("读取 profile .env 失败 %s: %s", path, e)
    return d


def _resolve_endpoint(profile: str):
    """从角色 profile 的 .env 解析 (url, key)。缺失返回 (None, None)。"""
    env = _read_env_file(_profile_env_path(profile))
    port = env.get("API_SERVER_PORT")
    key = env.get("API_SERVER_KEY")
    host = env.get("API_SERVER_HOST", "127.0.0.1")
    if not port or not key:
        logger.error(
            "profile '%s' 未配置 API Server（缺 PORT/KEY）；请确认 start.sh 已自愈该角色网关",
            profile,
        )
        return None, None
    return f"http://{host}:{port}", key


class HermesBridge:
    def __init__(
        self,
        gateway_url=None,
        timeout=DEFAULT_TIMEOUT,
        agent_id="main",
        namespace="main",
    ):
        self.timeout = timeout
        self.agent_id = agent_id
        self.namespace = namespace
        self.profile = agent_id  # profile 名 = agent_id（main.py 已把 '-' 换成 '_'）
        url, key = _resolve_endpoint(self.profile)
        self.gateway_url = (gateway_url or url or "").rstrip("/")
        self.key = key
        # 会话按「空闲间隔」滚动（见 session_id / session_key 属性 + _touch_session）：
        # 每次请求开始调 _touch_session()——静默超过 _SESSION_IDLE_GAP_SEC 才换新 stamp，
        # 否则续用当前 session。连续对话（含跨整点）永不腰斩，真正空闲后才切断防膨胀。
        # stamp 由 _touch_session 定，请求内保持不变，保证 _headers 与 _record_voice_turn 一致。
        self._session_stamp: str | None = None
        self._last_activity = 0.0
        self._session_lock = threading.Lock()
        self.available_tools = []
        self._current_request_id = None
        self._lock = threading.Lock()
        # ── 断点续传：软停止 vs 硬取消 ──────────────────────────
        # 软停止（soft_stop）：打断/退下时只停 TTS 回调，SSE 流继续消费到自然结束。
        #   浏览器等后台资源不会被清理（idle reaper 稍后回收）。
        # 硬取消（cancel_current_request）：断开 SSE 连接，触发 agent.interrupt()，
        #   用于快路径识别到"中断任务"意图的场景。
        # 软停/硬取消必须按 request_id 记录。软停后的 SSE 会继续在后台消费；
        # 如果此时用户说“继续”并启动新请求，不能让旧请求因为 current_id 被覆盖
        # 就误判成硬取消，否则会触发 agent.interrupt() 并清理浏览器等资源。
        self._soft_stopped_requests = set()
        self._cancelled_requests = set()
        # ── 唤醒待决策：退下软停后台任务的续做/搁置 ─────────────
        # _soft_stopped_requests 只在其 SSE 流仍在后台消费期间保留（流结束即 discard），
        # 故「集合非空」= 有一个被软停但仍在后台跑的 turn → has_inflight_task。
        # _last_user_text 供唤醒时向用户复述"刚才在做什么"。
        # _suppress_prev_task：用户选择"不继续"后置位，_build_messages 注入系统提示
        # 让模型别再主动接续搁置的任务；换新 session（_touch_session 滚动）时自动清零。
        self._last_user_text = ""
        self._suppress_prev_task = False

    def _current_stamp(self) -> str:
        # 尚无请求发生时的兜底：用当前时刻，保证 /clear 等旁路调用不崩。
        return self._session_stamp or time.strftime("%Y%m%d%H%M%S")

    @property
    def session_id(self) -> str:
        return f"voice-{self.agent_id}-{self._current_stamp()}"

    @property
    def session_key(self) -> str:
        return f"voice:{self.agent_id}:{self._current_stamp()}"

    def _touch_session(self) -> None:
        """请求开始时调用：静默超过阈值则开新会话，否则续用当前会话。

        更新 _last_activity；stamp 一旦生成，在整个请求生命周期内保持不变，
        保证 _headers（发送）与 _record_voice_turn（回写）落在同一 session。
        """
        now = time.time()
        with self._session_lock:
            if (
                self._session_stamp is None
                or (now - self._last_activity) > _SESSION_IDLE_GAP_SEC
            ):
                self._session_stamp = time.strftime("%Y%m%d%H%M%S", time.localtime(now))
                logger.info("新建 Hermes 会话 stamp=%s（空闲滚动）", self._session_stamp)
                # 新会话里老任务不在上下文，搁置抑制失去意义，清零。
                self._suppress_prev_task = False
            self._last_activity = now

    # ── 唤醒待决策：退下后台任务的续做/搁置 ──────────────────────

    def has_inflight_task(self) -> bool:
        """是否有「被软停但后台仍在跑」的 turn（供唤醒时决定是否询问续做）。"""
        with self._lock:
            return bool(self._soft_stopped_requests)

    def pending_task_hint(self) -> str:
        """最近一次用户指令文本，供唤醒时向用户复述"刚才在做什么"。"""
        return (self._last_user_text or "").strip()

    def mark_previous_task_abandoned(self) -> None:
        """用户选择"不继续"：置抑制位，后续 turn 注入提示阻止模型主动接续。"""
        self._suppress_prev_task = True
        logger.info("用户搁置上一任务：已置 suppress_prev_task")

    # ── 公共 API（与 OpenClaw 桥保持一致） ──────────────────────

    def precheck_async(self):
        threading.Thread(target=self._run_precheck, daemon=True).start()

    def start_request(self) -> str:
        request_id = str(uuid.uuid4())
        with self._lock:
            self._current_request_id = request_id
        return request_id

    def cancel_current_request(self) -> bool:
        with self._lock:
            if self._current_request_id is not None:
                logger.info("取消请求: %s", self._current_request_id)
                self._cancelled_requests.add(self._current_request_id)
                self._current_request_id = None
                return True
        return False

    def close(self) -> None:
        return None

    def soft_stop(self) -> bool:
        """软停止：打断/退下时调用。

        只标记请求为"已软停"，不再将流式回调中的文本传给 TTS。
        SSE 连接保持不断开——agent 继续完成当前 turn（浏览器等后台任务
        不被中断），但语音播报立即静默。浏览器等资源由 idle reaper
        在超时后自动回收（断点续传语义）。
        """
        with self._lock:
            if self._current_request_id is not None:
                logger.info("软停止请求: %s（不断开连接）", self._current_request_id)
                self._soft_stopped_requests.add(self._current_request_id)
                return True
        return False

    def cancel_task(self) -> bool:
        """硬取消：快路径识别到「中断任务」意图时调用。

        断开 SSE 连接，触发 agent.interrupt()，浏览器/终端等后台资源
        会被 agent 的 close() 路径清理。用于用户明确要求取消任务
        （如"别打开今日头条了"、"取消刚才的操作"）。
        """
        logger.info("硬取消任务（中断任务意图）")
        return self.cancel_current_request()

    def send_stop_command(self) -> bool:
        """打断：默认走软停止（断点续传），不断开 SSE 连接。

        快路径识别到「中断任务」意图时，由 main.py 改调 cancel_task()。
        """
        return self.soft_stop()

    def send_clear_command(self) -> bool:
        """清空当前角色的会话上下文（异步，不阻塞）。"""
        threading.Thread(target=self._clear_session_sync, daemon=True).start()
        return True

    # ── 内部实现 ────────────────────────────────────────────────

    def _headers(self):
        return {
            "Authorization": f"Bearer {self.key}",
            "Content-Type": "application/json",
            "X-Hermes-Session-Id": self.session_id,
            "X-Hermes-Session-Key": self.session_key,
        }

    def _build_messages(self, text):
        # 提示词由用户亲自下达给 session；桥只发用户消息，按 session-id 续历史。
        # 额外注入快路径最近对话，补齐 fast lane 没写入 Hermes session 的上下文。
        messages = []
        if self._suppress_prev_task:
            messages.append({
                "role": "system",
                "content": (
                    "The user set aside a previously unfinished task and did not "
                    "ask to resume it. Do not proactively continue, re-raise, or "
                    "mention that task. Focus only on the user's current request. "
                    "Do not quote or mention this system note."
                ),
            })
        fast_context = self._fast_context_message()
        if fast_context:
            messages.append({"role": "system", "content": fast_context})
        messages.append({"role": "user", "content": text})
        return messages

    def _fast_context_message(self) -> str:
        turns = voice_context_store.recent_fast_context(self.agent_id, limit=8)
        if not turns:
            return ""
        lines = []
        for t in turns:
            role = t.get("role")
            content = (t.get("content") or "").strip()
            if role not in ("user", "assistant") or not content:
                continue
            lines.append(f"{role}: {content[:500]}")
        if not lines:
            return ""
        return (
            "Recent voice fast-path context. These turns happened in the same "
            "voice assistant before this request, but may not exist in the "
            "Hermes session database. Use them only for continuity; do not quote "
            "or mention this system note.\n"
            + "\n".join(lines)
        )

    def _clear_session_sync(self):
        if not self._ready():
            return
        try:
            resp = requests.delete(
                f"{self.gateway_url}/api/sessions/{self.session_id}",
                headers=self._headers(),
                timeout=8,
            )
            if resp.status_code in (200, 204, 404):
                logger.info("已清空会话 %s (HTTP %s)", self.session_id, resp.status_code)
            else:
                logger.warning("清空会话失败: HTTP %s", resp.status_code)
        except requests.exceptions.Timeout:
            logger.warning("清空会话超时")
        except requests.exceptions.ConnectionError:
            logger.warning("无法连接 Hermes API Server")
        except Exception as e:
            logger.error("清空会话异常: %s", e)

    def _ready(self) -> bool:
        if not self.gateway_url or not self.key:
            logger.error("角色 '%s' 的 Hermes 端点未就绪（端口/key 缺失）", self.agent_id)
            return False
        return True

    def _run_precheck(self):
        if not self._ready():
            print(f"[Hermes] ✗ 角色 {self.agent_id} 端点未就绪")
            return
        try:
            resp = requests.get(
                f"{self.gateway_url}/v1/models",
                headers={"Authorization": f"Bearer {self.key}"},
                timeout=5,
            )
            if resp.status_code != 200:
                print(f"[Hermes] ✗ API Server 响应异常: HTTP {resp.status_code}")
                logger.warning("API Server 响应异常: HTTP %s", resp.status_code)
                return
            _k = self.key or ""
            print(f"[Hermes] ✓ 角色={self.agent_id} 端点={self.gateway_url} 连通 (key={_k[:6]}…len={len(_k)})")
            logger.info("✓ Hermes API Server 连通正常 (%s)", self.gateway_url)
        except Exception as e:
            print(f"[Hermes] ✗ API Server 不可达: {e}")
            logger.error("✗ Hermes API Server 不可达: %s", e)

    def send_and_wait(self, text: str):
        if not self._ready():
            return None
        if not text or not text.strip():
            return None
        self._touch_session()
        try:
            resp = requests.post(
                f"{self.gateway_url}/v1/chat/completions",
                headers=self._headers(),
                json={
                    "model": self.profile,
                    "messages": self._build_messages(text),
                    "stream": False,
                },
                timeout=self.timeout,
            )
            data = resp.json()
            if resp.status_code != 200:
                logger.error("HTTP %s: %s", resp.status_code,
                             json.dumps(data, ensure_ascii=False)[:300])
                return None
            choices = data.get("choices", [])
            if choices:
                reply = choices[0].get("message", {}).get("content", "")
                if reply:
                    self._record_voice_turn(text, reply)
                    return reply
            return None
        except requests.exceptions.Timeout:
            logger.error("请求超时")
            return None
        except Exception as e:
            logger.error("请求异常: %s", e)
            return None

    def send_and_wait_stream(
        self, text: str, on_chunk=None, on_start=None, on_end=None, on_tool_call=None
    ):
        if not self._ready():
            return None
        if not text or not text.strip():
            return None

        self._touch_session()
        self._last_user_text = text
        request_id = self.start_request()
        logger.info("发送(流式 Hermes): %s [request_id=%s]", text, request_id)

        try:
            resp = requests.post(
                f"{self.gateway_url}/v1/chat/completions",
                headers=self._headers(),
                json={
                    "model": self.profile,
                    "messages": self._build_messages(text),
                    "stream": True,
                },
                stream=True,
                timeout=self.timeout,
            )

            if resp.status_code != 200:
                logger.error("HTTP %s: %s", resp.status_code, resp.text[:300])
                print(f"[Hermes] ✗ chat/completions HTTP {resp.status_code}: {resp.text[:160]}")
                with self._lock:
                    if self._current_request_id == request_id:
                        self._current_request_id = None
                return None

            full_reply = ""
            started = False
            soft_stopped = False  # 本地快照，减少锁竞争

            for line in resp.iter_lines(decode_unicode=True):
                # 硬取消：快路径「中断任务」意图 → 断开连接
                with self._lock:
                    if request_id in self._cancelled_requests:
                        logger.info("请求 %s 已被硬取消（中断任务意图）", request_id)
                        break
                    soft_stopped = request_id in self._soft_stopped_requests

                if not line or not line.strip():
                    continue
                if line.startswith("data: "):
                    line = line[6:]
                if line == "[DONE]":
                    break

                try:
                    chunk_data = json.loads(line)
                    delta = chunk_data.get("choices", [{}])[0].get("delta", {})
                    content = delta.get("content", "")
                    if content:
                        if not started and not soft_stopped:
                            started = True
                            if on_start:
                                on_start()
                        full_reply += content
                        # 软停止后：继续消费 SSE 流（不断开连接），但不再回调 TTS
                        if on_chunk and not soft_stopped:
                            on_chunk(content)
                except json.JSONDecodeError:
                    continue

            try:
                resp.close()
            except Exception:
                pass

            with self._lock:
                final_soft_stopped = request_id in self._soft_stopped_requests
                if self._current_request_id == request_id:
                    self._current_request_id = None
                self._soft_stopped_requests.discard(request_id)
                self._cancelled_requests.discard(request_id)

            if on_end and not final_soft_stopped:
                on_end()
            if full_reply and not final_soft_stopped:
                logger.info("回复: %s...", full_reply[:100])
                self._record_voice_turn(text, full_reply)
            elif final_soft_stopped:
                logger.info("软停止：agent 继续执行，TTS 已静默")
            return full_reply if full_reply else None

        except requests.exceptions.Timeout:
            logger.error("请求超时")
            with self._lock:
                if self._current_request_id == request_id:
                    self._current_request_id = None
            return None
        except Exception as e:
            logger.error("请求异常: %s", e)
            with self._lock:
                if self._current_request_id == request_id:
                    self._current_request_id = None
            return None

    def _record_voice_turn(self, user_text: str, assistant_text: str) -> None:
        # 回写时刷新活动时钟：长耗时 turn（如浏览器任务）结束后，下一轮不因空闲阈值误滚。
        with self._session_lock:
            self._last_activity = time.time()
        voice_context_store.append_turn(
            self.agent_id,
            "hermes",
            "user",
            user_text,
            session_id=self.session_id,
            session_key=self.session_key,
        )
        voice_context_store.append_turn(
            self.agent_id,
            "hermes",
            "assistant",
            assistant_text,
            session_id=self.session_id,
            session_key=self.session_key,
        )


def get_bridge(**kwargs) -> HermesBridge:
    return HermesBridge(**kwargs)
