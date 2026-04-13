#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
OpenClaw 桥接模块
通过 Gateway /v1/chat/completions API 与 OpenClaw 对话
"""

import json
import logging
import os
import threading
import requests
import uuid

logger = logging.getLogger(__name__)

DEFAULT_GATEWAY_URL = "http://127.0.0.1:18789"
DEFAULT_TIMEOUT = None

# 预检时探测的工具列表
_CHECK_TOOLS = [
    "session_status",
    "memory_search",
    "web_search",
    "feishu_doc",
    "cron",
    "nodes",
]


def _load_token():
    token = os.environ.get("OPENCLAW_GATEWAY_TOKEN")
    if token:
        return token

    config_path = os.path.expanduser("~/.openclaw/openclaw.json")
    try:
        with open(config_path, "r") as f:
            config = json.load(f)
            token = config.get("gateway", {}).get("auth", {}).get("token")
            if token:
                logger.warning(
                    "从配置文件读取 token 已弃用，请设置环境变量 OPENCLAW_GATEWAY_TOKEN"
                )
                return token
    except FileNotFoundError:
        pass
    except Exception as e:
        logger.error(f"读取配置文件失败: {e}")

    logger.error("未找到 OPENCLAW_GATEWAY_TOKEN 环境变量，请设置后再运行程序")
    return None


class OpenClawBridge:
    def __init__(
        self,
        gateway_url=DEFAULT_GATEWAY_URL,
        timeout=DEFAULT_TIMEOUT,
        agent_id="main",
        namespace="main",
    ):
        self.gateway_url = gateway_url.rstrip("/")
        self.timeout = timeout
        self.token = _load_token()
        self.agent_id = agent_id
        self.namespace = namespace
        self.available_tools = []
        self._current_request_id = None
        self._lock = threading.Lock()

    def precheck_async(self):
        """异步预检：连通性 + 可用工具"""
        threading.Thread(target=self._run_precheck, daemon=True).start()

    def start_request(self) -> str:
        """开始一个新请求，返回请求ID用于取消"""
        request_id = str(uuid.uuid4())
        with self._lock:
            self._current_request_id = request_id
        return request_id

    def cancel_current_request(self) -> bool:
        """取消当前正在进行的请求"""
        with self._lock:
            if self._current_request_id is not None:
                logger.info(f"取消请求: {self._current_request_id}")
                self._current_request_id = None
                return True
        return False

    def send_stop_command(self) -> bool:
        """发送 /stop 命令中断 OpenClaw（异步，不阻塞）"""
        if not self.token:
            logger.error("Gateway token 不可用")
            return False
        threading.Thread(target=self._send_stop_sync, daemon=True).start()
        return True

    def _send_stop_sync(self):
        """同步发送 /stop（内部用）"""
        try:
            resp = requests.post(
                f"{self.gateway_url}/v1/chat/completions",
                headers={
                    "Authorization": f"Bearer {self.token}",
                    "Content-Type": "application/json",
                    "x-openclaw-agent-id": self.agent_id,
                    "x-openclaw-session-key": f"agent:{self.agent_id}:{self.agent_id}",
                },
                json={
                    "model": "openclaw",
                    "messages": [{"role": "user", "content": "/stop"}],
                },
                timeout=5,  # 降低超时时间，stop 命令应该快速响应
            )
            if resp.status_code == 200:
                logger.info("已发送 /stop 命令")
            else:
                logger.warning(f"发送 /stop 失败: HTTP {resp.status_code}")
        except requests.exceptions.Timeout:
            logger.warning("发送 /stop 命令超时 (5s)，Gateway 可能正在处理中")
        except requests.exceptions.ConnectionError:
            logger.warning("无法连接到 Gateway，连接被拒绝或网关未启动")
        except Exception as e:
            logger.error(f"发送 /stop 异常: {e}")

    def _run_precheck(self):
        try:
            resp = requests.get(
                f"{self.gateway_url}/v1/models",
                headers={"Authorization": f"Bearer {self.token}"},
                timeout=5,
            )
            if resp.status_code != 200:
                logger.warning(f"Gateway 响应异常: HTTP {resp.status_code}")
                return
            logger.info("✓ Gateway 连通正常")
        except Exception as e:
            print(f"[OpenClaw] ✗ Gateway 不可达: {e}")
            logger.error(f"✗ Gateway 不可达: {e}")
            return

        tools_ok = []
        for tool in _CHECK_TOOLS:
            try:
                r = requests.post(
                    f"{self.gateway_url}/tools/invoke",
                    headers={
                        "Authorization": f"Bearer {self.token}",
                        "Content-Type": "application/json",
                    },
                    json={"tool": tool, "args": {}, "dryRun": True},
                    timeout=3,
                )
                if r.status_code == 200:
                    tools_ok.append(tool)
            except Exception:
                pass

        self.available_tools = tools_ok
        if tools_ok:
            print(f"[OpenClaw] ✓ Gateway 连通 | 可用工具: {', '.join(tools_ok)}")
        else:
            print("[OpenClaw] ✓ Gateway 连通 | 未探测到可用工具（HTTP 端点受限）")

    def send_and_wait(self, text: str) -> str | None:
        if not self.token:
            logger.error("Gateway token 不可用")
            return None
        if not text or not text.strip():
            return None

        logger.info(f"发送: {text}")

        try:
            resp = requests.post(
                f"{self.gateway_url}/v1/chat/completions",
                headers={
                    "Authorization": f"Bearer {self.token}",
                    "Content-Type": "application/json",
                    "x-openclaw-agent-id": self.agent_id,
                    "x-openclaw-session-key": f"agent:{self.agent_id}:{self.agent_id}",
                },
                json={
                    "model": "openclaw",
                    "messages": [{"role": "user", "content": text}],
                },
                timeout=self.timeout,
            )

            data = resp.json()

            if resp.status_code != 200:
                logger.error(
                    f"HTTP {resp.status_code}: {json.dumps(data, ensure_ascii=False)[:300]}"
                )
                return None

            choices = data.get("choices", [])
            if choices:
                reply = choices[0].get("message", {}).get("content", "")
                if reply:
                    logger.info(f"回复: {reply}")
                    return reply

            logger.warning(f"无有效回复: {json.dumps(data, ensure_ascii=False)[:300]}")
            return None

        except requests.exceptions.Timeout:
            logger.error("请求超时")
            return None
        except Exception as e:
            logger.error(f"请求异常: {e}")
            return None

    def send_and_wait_stream(
        self, text: str, on_chunk=None, on_start=None, on_end=None
    ) -> str | None:
        """
        流式发送并等待回复

        Args:
            text: 用户消息
            on_chunk: 每收到一个文本块时的回调 (chunk_text: str)
            on_start: 开始收到回复时的回调
            on_end: 回复完成时的回调

        Returns:
            完整的回复文本
        """
        if not self.token:
            logger.error("Gateway token 不可用")
            return None
        if not text or not text.strip():
            return None

        request_id = self.start_request()
        logger.info(f"发送(流式): {text} [request_id={request_id}]")

        try:
            resp = requests.post(
                f"{self.gateway_url}/v1/chat/completions",
                headers={
                    "Authorization": f"Bearer {self.token}",
                    "Content-Type": "application/json",
                    "x-openclaw-agent-id": self.agent_id,
                    "x-openclaw-session-key": f"agent:{self.agent_id}:{self.agent_id}",
                },
                json={
                    "model": "openclaw",
                    "messages": [{"role": "user", "content": text}],
                    "stream": True,
                },
                stream=True,
                timeout=self.timeout,
            )

            if resp.status_code != 200:
                error_body = resp.text[:300]
                logger.error(f"HTTP {resp.status_code}: {error_body}")
                with self._lock:
                    if self._current_request_id == request_id:
                        self._current_request_id = None
                return None

            full_reply = ""
            started = False

            for line in resp.iter_lines(decode_unicode=True):
                with self._lock:
                    if self._current_request_id != request_id:
                        logger.info(f"请求 {request_id} 已被取消")
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

            with self._lock:
                if self._current_request_id == request_id:
                    self._current_request_id = None

            if on_end:
                on_end()

            if full_reply:
                logger.info(f"回复: {full_reply[:100]}...")

            return full_reply if full_reply else None

        except requests.exceptions.Timeout:
            logger.error("请求超时")
            with self._lock:
                if self._current_request_id == request_id:
                    self._current_request_id = None
            return None
        except Exception as e:
            logger.error(f"请求异常: {e}")
            with self._lock:
                if self._current_request_id == request_id:
                    self._current_request_id = None
            return None


def get_bridge(**kwargs):
    return OpenClawBridge(**kwargs)
