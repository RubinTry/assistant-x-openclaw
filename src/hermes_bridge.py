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
  - 多轮连续：稳定的 X-Hermes-Session-Id（profile 内单一会话即可，已天然隔离）。
  - 清空上下文(/clear)：DELETE /api/sessions/<session_id>。
  - 打断(/stop)：客户端断流。
"""

import json
import logging
import os
import threading
import uuid

import requests

logger = logging.getLogger(__name__)

DEFAULT_TIMEOUT = None
_HERMES_HOME = os.path.expanduser(os.environ.get("HERMES_HOME", "~/.hermes"))


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
        # profile 已物理隔离，单一稳定会话即可保证多轮连续
        self.session_id = f"voice-{agent_id}"
        self.session_key = f"voice:{agent_id}"
        self.available_tools = []
        self._current_request_id = None
        self._lock = threading.Lock()

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
                self._current_request_id = None
                return True
        return False

    def close(self) -> None:
        return None

    def send_stop_command(self) -> bool:
        """打断：Hermes 无控制面，靠客户端断流即可。"""
        return self.cancel_current_request()

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
        # 提示词由用户亲自下达给 session；桥只发用户消息，按 session-id 续历史
        return [{"role": "user", "content": text}]

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
            print(f"[Hermes] ✓ 角色={self.agent_id} 端点={self.gateway_url} 连通")
            logger.info("✓ Hermes API Server 连通正常 (%s)", self.gateway_url)
        except Exception as e:
            print(f"[Hermes] ✗ API Server 不可达: {e}")
            logger.error("✗ Hermes API Server 不可达: %s", e)

    def send_and_wait(self, text: str):
        if not self._ready():
            return None
        if not text or not text.strip():
            return None
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
                with self._lock:
                    if self._current_request_id == request_id:
                        self._current_request_id = None
                return None

            full_reply = ""
            started = False

            for line in resp.iter_lines(decode_unicode=True):
                # 被取消则立即跳出并关闭连接（等价 /stop 打断）
                with self._lock:
                    if self._current_request_id != request_id:
                        logger.info("请求 %s 已被取消", request_id)
                        break

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
                        if not started:
                            started = True
                            if on_start:
                                on_start()
                        full_reply += content
                        if on_chunk:
                            on_chunk(content)
                except json.JSONDecodeError:
                    continue

            try:
                resp.close()
            except Exception:
                pass

            with self._lock:
                if self._current_request_id == request_id:
                    self._current_request_id = None

            if on_end:
                on_end()
            if full_reply:
                logger.info("回复: %s...", full_reply[:100])
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


def get_bridge(**kwargs) -> HermesBridge:
    return HermesBridge(**kwargs)
