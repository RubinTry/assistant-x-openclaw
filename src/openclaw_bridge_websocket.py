#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
OpenClaw 桥接模块 (WebSocket 版本)
=================================

通过 Gateway WebSocket API 与 OpenClaw 对话，支持：
- 实时 chat 流式事件 (delta / final)
- 工具调用事件
- chat.abort / sessions.reset 通过 WebSocket RPC（避免 /v1/chat/completions 不拦截 slash 命令的 bug）

协议要点（已通过 live probe 验证）:
- 协议: protocol 4 (connect 时通过 connect.challenge 收到 nonce)
- 设备签名: v3 payload，sha256(raw pubkey) -> device_id, Ed25519 签名
- 签名必须覆盖请求方声明的 scopes 才能通过校验
- connect 成功后 claim 的 scopes 必须 <= paired.approvedScopes；否则需 pairing-approval
- HTTP /tools/invoke 端点对 shared-secret token 自动恢复完整 operator scope（无需 WS）
- WebSocket slash 命令路径: chat.send (不是 sessions.send) — sessions.send 不拦截 slash

设备配对前置条件 (一次性):
- 设备必须在 ~/.openclaw/devices/paired.json 中已 pair，且 approvedScopes 包含
  operator.read, operator.write, operator.admin
- 通过 CLI: openclaw devices approve <requestId> --token <shared_token>

调用示例:
    bridge = OpenClawBridgeWebSocket(agent_id="main")
    bridge.precheck_async()  # 异步连通性检测
    reply = bridge.send_and_wait_stream("hello")  # 阻塞流式
    bridge.send_stop_command()  # 异步中断当前请求
    bridge.send_clear_command()  # 异步重置会话上下文
"""

import base64
import hashlib
import json
import logging
import os
import threading
import time
import uuid
from typing import Any, Callable, Optional

import websocket  # websocket-client
from cryptography.hazmat.primitives import serialization

try:
    import requests as _requests  # 预检用
except ImportError:  # pragma: no cover
    _requests = None  # type: ignore

logger = logging.getLogger(__name__)

DEFAULT_GATEWAY_URL = "ws://127.0.0.1:18789"
DEFAULT_HTTP_URL = "http://127.0.0.1:18789"
DEFAULT_TIMEOUT = 120

# /tools/invoke HTTP 预检要探测的工具。HTTP 端点对 shared-secret token 自动恢复完整 operator scope。
_CHECK_TOOLS = [
    "session_status",
    "memory_search",
    "web_search",
    "feishu_doc",
    "cron",
    "nodes",
]

# v3 device-signature payload 使用的客户端身份（与 MBP / 控制台 UI 不同的命名空间，避免被识别为 UI 实例）
_CLIENT_ID = "gateway-client"
_CLIENT_MODE = "backend"
_CLIENT_PLATFORM = "darwin"
_CLIENT_DEVICE_FAMILY = ""  # backend 客户端无 deviceFamily

# 设备配对申请 scopes。**必须**与 paired.json 中的 approvedScopes 一致，否则签名校验失败。
# 如 pairing 未带这些 scopes，connect 时会自动走 pairing-required 分支，需手动 openclaw devices approve。
_CONNECT_SCOPES = [
    "operator.read",
    "operator.write",
    "operator.admin",
]


def _load_token() -> Optional[str]:
    """从 env 或 ~/.openclaw/openclaw.json 读取 shared gateway token。"""
    token = os.environ.get("OPENCLAW_GATEWAY_TOKEN")
    if token:
        return token

    config_path = os.path.expanduser("~/.openclaw/openclaw.json")
    try:
        with open(config_path, "r", encoding="utf-8") as f:
            cfg = json.load(f)
            tok = cfg.get("gateway", {}).get("auth", {}).get("token")
            if tok:
                logger.warning(
                    "从配置文件读取 token 已弃用，请设置 OPENCLAW_GATEWAY_TOKEN"
                )
                return tok
    except FileNotFoundError:
        pass
    except Exception as e:
        logger.error("读取 openclaw.json 失败: %s", e)
    logger.error("未找到 OPENCLAW_GATEWAY_TOKEN env var")
    return None


class _PendingRequest:
    """RPC 期望：发出去的 req 等回来的 res（按 id 关联）。"""
    __slots__ = ("id", "method", "future", "sent_at", "_response")

    def __init__(self, req_id: str, method: str):
        self.id = req_id
        self.method = method
        self.future: "threading.Event" = threading.Event()
        self.sent_at = time.time()
        self._response: Optional[dict] = None

    def set_response(self, response: dict) -> None:
        self._response = response
        self.future.set()

    def get_response(self, timeout: float) -> Optional[dict]:
        if not self.future.wait(timeout):
            return None
        return self._response


class OpenClawBridgeWebSocket:
    """单个 bridge 实例 = 一个持久 WebSocket 连接 + 一个接收线程。"""

    def __init__(
        self,
        gateway_url: str = DEFAULT_GATEWAY_URL,
        timeout: float = DEFAULT_TIMEOUT,
        agent_id: str = "main",
        namespace: str = "main",
    ):
        self.gateway_url = gateway_url.rstrip("/")
        self.timeout = timeout
        self.token = _load_token()
        self.agent_id = agent_id
        self.namespace = namespace

        # 状态
        self._ws: Optional[websocket.WebSocketApp] = None
        self._ws_thread: Optional[threading.Thread] = None
        self._stop = threading.Event()
        self._connected = threading.Event()
        self._connect_lock = threading.Lock()
        self._challenge: Optional[str] = None
        self._hello_ok: Optional[dict] = None

        # 设备身份
        self._device_id: Optional[str] = None
        self._public_key_b64: Optional[str] = None
        self._private_key = None

        # RPC futures (id -> _PendingRequest)
        self._pending: dict[str, _PendingRequest] = {}
        self._pending_lock = threading.Lock()

        # 流式回复回调（按 runId 关联）
        self._on_chunk: Optional[Callable[[str], None]] = None
        self._on_tool_call: Optional[Callable[[str, str], None]] = None
        self._on_start: Optional[Callable[[], None]] = None
        self._on_end: Optional[Callable[[], None]] = None
        self._stream_run_id: Optional[str] = None
        self._stream_full_text: str = ""
        # 已通过 on_chunk 发出的累计长度。chat 事件携带的是累计文本，
        # 这里据此切出"增量" chunk，与 HTTP 桥/上层 _on_stream_chunk(append) 的约定一致。
        self._stream_emitted_len: int = 0
        self._stream_done = threading.Event()

        # 预检结果
        self.available_tools: list[str] = []

        # 当前 request（用于中断）
        self._current_request_id: Optional[str] = None
        self._current_request_lock = threading.Lock()

    # ─────────────────────────────────────────────────────────────────
    # 公共 API：start_request / cancel_current_request（保持旧接口兼容）
    # ─────────────────────────────────────────────────────────────────

    def precheck_async(self) -> None:
        """异步预检：HTTP /v1/models + /tools/invoke（HTTP 对 shared-secret 恢复完整 scope）。"""
        threading.Thread(target=self._run_precheck, daemon=True, name="bridge-precheck").start()

    def start_request(self) -> str:
        with self._current_request_lock:
            self._current_request_id = str(uuid.uuid4())
            return self._current_request_id

    def cancel_current_request(self) -> bool:
        with self._current_request_lock:
            if self._current_request_id is not None:
                logger.info("取消请求: %s", self._current_request_id)
                self._current_request_id = None
                return True
        return False

    def close(self) -> None:
        """关闭 WebSocket 长连接与接收线程（切换 bridge 时调用，防连接泄漏）。"""
        self._stop.set()
        self._connected.clear()
        ws = self._ws
        if ws is not None:
            try:
                ws.close()
            except Exception as e:
                logger.warning("关闭 WebSocket 失败: %s", e)
        self._ws = None

    def send_stop_command(self) -> bool:
        """异步中断：WebSocket chat.abort。

        chat.abort 在 runtime 是 O(1) 的 cancel，不需要等任何回复。"""
        if not self.token:
            logger.error("Gateway token 不可用")
            return False
        if getattr(self, "_stop_sending", False):
            logger.info("chat.abort 已在发送中，跳过")
            return True
        self._stop_sending = True
        threading.Thread(target=self._send_stop_sync, daemon=True, name="bridge-stop").start()
        return True

    def send_clear_command(self) -> bool:
        """异步清空会话上下文：WebSocket sessions.reset。

        与 /clear 等价——清空消息历史但保留 session 元数据。
        如需 /compact（保留最近 N 轮 + summary）改用 send_compact_command。
        """
        if not self.token:
            logger.error("Gateway token 不可用")
            return False
        if getattr(self, "_clear_sending", False):
            logger.info("sessions.reset 已在发送中，跳过")
            return True
        self._clear_sending = True
        threading.Thread(target=self._send_clear_sync, daemon=True, name="bridge-clear").start()
        return True

    def send_compact_command(self, keep_recent: int = 5) -> bool:
        """异步压缩会话上下文：WebSocket sessions.compact。

        keep_recent: 保留最近 N 轮对话不被压缩。
        """
        if not self.token:
            logger.error("Gateway token 不可用")
            return False
        threading.Thread(
            target=self._send_compact_sync,
            args=(keep_recent,),
            daemon=True,
            name="bridge-compact",
        ).start()
        return True

    # ─────────────────────────────────────────────────────────────────
    # HTTP 预检（HTTP 端点对 shared-secret token 自动恢复完整 operator scope）
    # ─────────────────────────────────────────────────────────────────

    def _run_precheck(self) -> None:
        if _requests is None:
            logger.warning("requests 模块不可用，跳过预检")
            return
        http_url = self.gateway_url.replace("ws://", "http://").replace("wss://", "https://")
        # /v1/models
        try:
            r = _requests.get(
                f"{http_url}/v1/models",
                headers={"Authorization": f"Bearer {self.token}"},
                timeout=5,
            )
            if r.status_code != 200:
                logger.warning("Gateway 响应异常: HTTP %s", r.status_code)
                return
            logger.info("✓ Gateway 连通正常")
        except Exception as e:
            print(f"[OpenClaw] ✗ Gateway 不可达: {e}")
            logger.error("✗ Gateway 不可达: %s", e)
            return

        # /tools/invoke 预检（注意：字段名是 name，不是 tool——旧代码 bug 已修复）
        tools_ok: list[str] = []
        for tool in _CHECK_TOOLS:
            try:
                r = _requests.post(
                    f"{http_url}/tools/invoke",
                    headers={
                        "Authorization": f"Bearer {self.token}",
                        "Content-Type": "application/json",
                    },
                    json={"name": tool, "args": {}, "dryRun": True},
                    timeout=3,
                )
                if r.status_code == 200:
                    try:
                        body = r.json()
                        if body.get("ok") is True or body.get("ok") is False:
                            tools_ok.append(tool)
                        elif "error" not in body:
                            tools_ok.append(tool)
                    except Exception:
                        tools_ok.append(tool)
            except Exception:
                pass
        self.available_tools = tools_ok
        if tools_ok:
            print(f"[OpenClaw] ✓ Gateway 连通 | 可用工具: {', '.join(tools_ok)}")
        else:
            print("[OpenClaw] ✓ Gateway 连通 | /tools/invoke 未暴露目标工具")

    # ─────────────────────────────────────────────────────────────────
    # WebSocket connect：v3 device signature + connectParams.role/scopes
    # ─────────────────────────────────────────────────────────────────

    def _ensure_connected(self) -> bool:
        """确保 WS 已连接。未连接则连接。"""
        if self._connected.is_set():
            return True
        with self._connect_lock:
            if self._connected.is_set():
                return True
            return self._do_connect()

    def _do_connect(self) -> bool:
        self._ensure_device_identity()
        self._stop.clear()
        self._connected.clear()

        ws_url = self.gateway_url
        try:
            self._ws = websocket.WebSocketApp(
                ws_url,
                on_open=self._on_open,
                on_message=self._on_message,
                on_error=self._on_error,
                on_close=self._on_close,
            )
        except Exception as e:
            logger.error("创建 WebSocketApp 失败: %s", e)
            return False

        # 开启 WebSocket 心跳保活：每 ping_interval 秒发 ping，ping_timeout 秒内无
        # pong 即判定连接已死并关闭（触发 on_close 清 _connected），下次发送时
        # _ensure_connected 会自动重连。否则长空闲/网关重启后连接半死、_connected
        # 仍为 set，ws.send() 会卡在死 socket 上无限阻塞，表现为"喊着喊着没反应"。
        ws_obj = self._ws
        self._ws_thread = threading.Thread(
            target=lambda: ws_obj.run_forever(ping_interval=20, ping_timeout=10),
            daemon=True,
            name="bridge-ws",
        )
        self._ws_thread.start()

        # 等待 hello-ok
        ok = self._connected.wait(timeout=15)
        if not ok:
            logger.error("WebSocket 握手超时")
            return False
        logger.info(
            "WebSocket 已连接 (role=%s scopes=%s)",
            self._hello_ok.get("auth", {}).get("role"),
            self._hello_ok.get("auth", {}).get("scopes"),
        )
        return True

    def _on_open(self, ws) -> None:
        logger.info("WebSocket 已打开，等待 connect.challenge...")

    def _on_close(self, ws, code, msg) -> None:
        logger.info("WebSocket 关闭: %s %s", code, msg)
        self._connected.clear()
        self._hello_ok = None

    def _on_error(self, ws, error) -> None:
        logger.error("WebSocket 错误: %s", error)
        # ping 超时等错误也标记为未连接，确保下次发送触发重连（双保险，on_close 亦会清）
        self._connected.clear()

    def _on_message(self, ws, message) -> None:
        try:
            data = json.loads(message)
        except json.JSONDecodeError:
            logger.warning("无法解析消息: %s", message[:100])
            return

        msg_type = data.get("type")

        if msg_type == "event":
            self._handle_event(data)
        elif msg_type == "res":
            self._handle_response(data)
        # "req" from server is not expected here; ignore.

    # ─────────────────────────────────────────────────────────────────
    # Event handling
    # ─────────────────────────────────────────────────────────────────

    def _handle_event(self, data: dict) -> None:
        event = data.get("event")
        payload = data.get("payload") or {}

        if event == "connect.challenge":
            self._challenge = payload.get("nonce")
            logger.debug("收到 challenge: %s", (self._challenge or "")[:20])
            self._send_connect()

        elif event == "chat":
            self._handle_chat_event(payload)

        elif event == "session.tool":
            # 工具调用（备用 schema，与 chat 事件可能并存）
            name = payload.get("name", "")
            args = payload.get("arguments", "")
            if self._on_tool_call:
                try:
                    self._on_tool_call(name, args)
                except Exception as e:
                    logger.error("on_tool_call 回调异常: %s", e)

        # 其他事件（health/tick/presence/...）忽略

    def _handle_chat_event(self, payload: dict) -> None:
        """处理 chat 事件：state=delta 表示增量，state=final 表示结束。

        payload schema:
          { runId, sessionKey, seq, state, message: {role, content: [{type, text}], ...} }
        """
        run_id = payload.get("runId")
        state = payload.get("state")
        msg = payload.get("message") or {}
        content_blocks = msg.get("content") or []

        # 提取 text blocks 的纯文本
        text_parts: list[str] = []
        for blk in content_blocks:
            if isinstance(blk, dict):
                btype = blk.get("type")
                if btype in ("text", None):  # 兼容无 type
                    if "text" in blk and isinstance(blk["text"], str):
                        text_parts.append(blk["text"])
                # tool_use / tool_result 等不直接展示到 on_chunk
            elif isinstance(blk, str):
                text_parts.append(blk)

        if state == "delta":
            # delta 事件携带的是累计文本；切出增量后再回调 on_chunk
            text = "".join(text_parts)
            if run_id == self._stream_run_id and text:
                self._emit_increment(text)

        elif state == "final":
            text = "".join(text_parts)
            if run_id == self._stream_run_id:
                final_full = text or self._stream_full_text
                # 补发 delta 阶段还没发出的尾巴，避免最后一句丢失
                if final_full:
                    self._emit_increment(final_full)
                self._stream_done.set()
                if self._on_end:
                    try:
                        self._on_end()
                    except Exception as e:
                        logger.error("on_end 回调异常: %s", e)

        elif state == "error":
            err = payload.get("error") or (msg.get("error") if isinstance(msg, dict) else None) or "chat error"
            logger.error("chat 事件 error: %s", err)
            if run_id == self._stream_run_id:
                self._stream_done.set()
                if self._on_end:
                    try:
                        self._on_end()
                    except Exception:
                        pass

    def _emit_increment(self, full_text: str) -> None:
        """把累计文本 full_text 与已发出部分做差，仅回调 on_chunk 发出新增片段。

        chat 事件每次给的是累计视图；上层 on_chunk 约定收到的是增量，故在此切片。
        若新文本不是已发前缀的延续（极少见：内容被重写/回退），则整体重发。
        """
        if not full_text:
            return
        if full_text.startswith(self._stream_full_text):
            delta_text = full_text[self._stream_emitted_len:]
        else:
            delta_text = full_text
            self._stream_emitted_len = 0
        if not delta_text:
            self._stream_full_text = full_text
            return
        if self._on_start and self._stream_emitted_len == 0:
            try:
                self._on_start()
            except Exception as e:
                logger.error("on_start 回调异常: %s", e)
        self._stream_full_text = full_text
        self._stream_emitted_len = len(full_text)
        if self._on_chunk:
            try:
                self._on_chunk(delta_text)
            except Exception as e:
                logger.error("on_chunk 回调异常: %s", e)

    # ─────────────────────────────────────────────────────────────────
    # Response handling (RPC req/res correlation by id)
    # ─────────────────────────────────────────────────────────────────

    def _handle_response(self, data: dict) -> None:
        req_id = data.get("id")
        if not req_id:
            logger.warning("收到无 id 的 res: %s", json.dumps(data, ensure_ascii=False)[:200])
            return
        # Special-case: connect response carries hello-ok in payload.type, not in pending RPCs.
        if req_id.startswith("connect-"):
            self._handle_connect_response(data)
            return
        with self._pending_lock:
            pending = self._pending.pop(req_id, None)
        if pending is None:
            if data.get("ok"):
                logger.info("未追踪的 RPC 成功响应 id=%s", req_id)
            else:
                logger.warning("未追踪的 RPC 失败响应 id=%s err=%s", req_id, data.get("error"))
            return
        pending.set_response(data)

    def _handle_connect_response(self, data: dict) -> None:
        """处理 connect RPC 的 res——其 payload 含 hello-ok。"""
        if not data.get("ok"):
            err = data.get("error") or {}
            logger.error("WebSocket connect 失败: %s", err.get("message", "unknown"))
            # 把 ws 关掉，让重连逻辑接手
            try:
                if self._ws is not None:
                    self._ws.close()
            except Exception:
                pass
            return
        payload = data.get("payload") or {}
        if payload.get("type") != "hello-ok":
            logger.warning("connect 响应缺 hello-ok: %s", json.dumps(data, ensure_ascii=False)[:200])
            return
        self._hello_ok = payload
        logger.info(
            "WebSocket 握手成功 (role=%s scopes=%s)",
            (payload.get("auth") or {}).get("role"),
            (payload.get("auth") or {}).get("scopes"),
        )
        self._connected.set()

    # ─────────────────────────────────────────────────────────────────
    # 设备身份 + v3 签名
    # ─────────────────────────────────────────────────────────────────

    def _ensure_device_identity(self) -> None:
        if self._private_key is not None:
            return
        keypair_path = os.path.expanduser("~/.openclaw/devices/voice_assistant_keypair.json")
        loaded = False
        if os.path.exists(keypair_path):
            try:
                with open(keypair_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                self._private_key = serialization.load_pem_private_key(
                    data["private_key_pem"].encode("utf-8"), password=None
                )
                pub = self._private_key.public_key().public_bytes(
                    encoding=serialization.Encoding.Raw,
                    format=serialization.PublicFormat.Raw,
                )
                self._public_key_b64 = base64.urlsafe_b64encode(pub).decode().rstrip("=")
                self._device_id = hashlib.sha256(pub).hexdigest()
                logger.info("加载已有设备身份: %s...", self._device_id[:16])
                loaded = True
            except Exception as e:
                logger.warning("加载设备身份失败，将重新生成: %s", e)

        if not loaded:
            from cryptography.hazmat.primitives.asymmetric import ed25519
            self._private_key = ed25519.Ed25519PrivateKey.generate()
            pub = self._private_key.public_key().public_bytes(
                encoding=serialization.Encoding.Raw,
                format=serialization.PublicFormat.Raw,
            )
            self._public_key_b64 = base64.urlsafe_b64encode(pub).decode().rstrip("=")
            self._device_id = hashlib.sha256(pub).hexdigest()
            pem = self._private_key.private_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.PKCS8,
                encryption_algorithm=serialization.NoEncryption(),
            ).decode("utf-8")
            os.makedirs(os.path.dirname(keypair_path), exist_ok=True)
            with open(keypair_path, "w", encoding="utf-8") as f:
                json.dump({"private_key_pem": pem, "device_id": self._device_id}, f)
            logger.info("生成新设备身份: %s...", self._device_id[:16])

    def _sign_v3_payload(
        self,
        role: str,
        scopes: list[str],
        signed_at_ms: int,
        token: str,
        nonce: str,
    ) -> str:
        """构造并签 v3 payload。scopes 必须与 connectParams.scopes 完全一致。"""
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

        scopes_str = ",".join(scopes)
        payload = "|".join([
            "v3",
            self._device_id or "",
            _CLIENT_ID,
            _CLIENT_MODE,
            role,
            scopes_str,
            str(signed_at_ms),
            token or "",
            nonce,
            _CLIENT_PLATFORM,
            _CLIENT_DEVICE_FAMILY,
        ])
        assert isinstance(self._private_key, Ed25519PrivateKey)
        sig = self._private_key.sign(payload.encode("utf-8"))
        return base64.urlsafe_b64encode(sig).decode().rstrip("=")

    def _send_connect(self) -> None:
        if self._challenge is None:
            logger.error("connect.challenge 未到达，无法签名")
            return
        signed_at = int(time.time() * 1000)
        scopes = _CONNECT_SCOPES
        role = "operator"
        sig = self._sign_v3_payload(role, scopes, signed_at, self.token or "", self._challenge)

        connect_req = {
            "type": "req",
            "id": "connect-" + str(uuid.uuid4()),
            "method": "connect",
            "params": {
                "minProtocol": 4,
                "maxProtocol": 4,
                "client": {
                    "id": _CLIENT_ID,
                    "version": "1.0.0",
                    "platform": _CLIENT_PLATFORM,
                    "mode": _CLIENT_MODE,
                },
                "device": {
                    "id": self._device_id,
                    "publicKey": self._public_key_b64,
                    "signature": sig,
                    "signedAt": signed_at,
                    "nonce": self._challenge,
                },
                "auth": {"token": self.token},
                "role": role,
                "scopes": scopes,
            },
        }
        assert self._ws is not None
        try:
            self._ws.send(json.dumps(connect_req))
        except Exception as e:
            logger.error("发送 connect 请求失败: %s", e)

    # ─────────────────────────────────────────────────────────────────
    # RPC 发送/接收
    # ─────────────────────────────────────────────────────────────────

    def _rpc(self, method: str, params: Optional[dict] = None, timeout: float = 15) -> Optional[dict]:
        """同步 RPC：发出去 -> 等回来。返回 {"ok": ..., "payload"|"error": ...} 或 None（超时）。"""
        if not self._ensure_connected():
            return None
        req_id = f"{method}-{uuid.uuid4()}"
        pending = _PendingRequest(req_id, method)
        with self._pending_lock:
            self._pending[req_id] = pending
        frame = {
            "type": "req",
            "id": req_id,
            "method": method,
            "params": params or {},
        }
        assert self._ws is not None
        try:
            self._ws.send(json.dumps(frame))
        except Exception as e:
            logger.error("WS send 失败: %s", e)
            with self._pending_lock:
                self._pending.pop(req_id, None)
            return None

        resp = pending.get_response(timeout=timeout)
        if resp is None:
            with self._pending_lock:
                self._pending.pop(req_id, None)
            logger.warning("RPC 超时 method=%s", method)
        return resp

    # ─────────────────────────────────────────────────────────────────
    # 异步 control 命令（chat.abort / sessions.reset / sessions.compact）
    # ─────────────────────────────────────────────────────────────────

    def _send_stop_sync(self) -> None:
        try:
            if not self._ensure_connected():
                return
            session_key = f"agent:{self.agent_id}:{self.namespace}"
            resp = self._rpc("chat.abort", {"sessionKey": session_key}, timeout=8)
            if resp is None:
                logger.warning("chat.abort 超时")
            elif resp.get("ok"):
                logger.info("已发送 chat.abort（/stop）")
            else:
                logger.warning("chat.abort 失败: %s", resp.get("error"))
        except Exception as e:
            logger.error("chat.abort 异常: %s", e)
        finally:
            self._stop_sending = False

    def _send_clear_sync(self) -> None:
        try:
            if not self._ensure_connected():
                return
            session_key = f"agent:{self.agent_id}:{self.namespace}"
            # sessions.reset 清空消息历史但保留 session 元数据；与 /clear 语义一致
            resp = self._rpc("sessions.reset", {"key": session_key}, timeout=10)
            if resp is None:
                logger.warning("sessions.reset 超时")
            elif resp.get("ok"):
                logger.info("已发送 sessions.reset（/clear）")
            else:
                logger.warning("sessions.reset 失败: %s", resp.get("error"))
        except Exception as e:
            logger.error("sessions.reset 异常: %s", e)
        finally:
            self._clear_sending = False

    def _send_compact_sync(self, keep_recent: int) -> None:
        try:
            if not self._ensure_connected():
                return
            session_key = f"agent:{self.agent_id}:{self.namespace}"
            resp = self._rpc(
                "sessions.compact",
                {"key": session_key, "keepRecent": keep_recent},
                timeout=15,
            )
            if resp is None:
                logger.warning("sessions.compact 超时")
            elif resp.get("ok"):
                payload = resp.get("payload") or {}
                logger.info(
                    "sessions.compact 完成: compacted=%s reason=%s",
                    payload.get("compacted"),
                    payload.get("reason"),
                )
            else:
                logger.warning("sessions.compact 失败: %s", resp.get("error"))
        except Exception as e:
            logger.error("sessions.compact 异常: %s", e)

    # ─────────────────────────────────────────────────────────────────
    # 流式发送主流程（chat.send + 监听 chat 事件）
    # ─────────────────────────────────────────────────────────────────

    def send_and_wait_stream(
        self,
        text: str,
        on_chunk: Optional[Callable[[str], None]] = None,
        on_start: Optional[Callable[[], None]] = None,
        on_end: Optional[Callable[[], None]] = None,
        on_tool_call: Optional[Callable[[str, str], None]] = None,
    ) -> Optional[str]:
        if not self.token:
            logger.error("Gateway token 不可用")
            return None
        if not text or not text.strip():
            return None

        request_id = self.start_request()
        logger.info("发送(流式 WS): %s [request_id=%s]", text, request_id)

        self._on_chunk = on_chunk
        self._on_tool_call = on_tool_call
        self._on_start = on_start
        self._on_end = on_end
        self._stream_full_text = ""
        self._stream_emitted_len = 0
        self._stream_run_id = None
        self._stream_done.clear()

        try:
            if not self._ensure_connected():
                return None

            session_key = f"agent:{self.agent_id}:{self.namespace}"
            idempotency_key = str(uuid.uuid4())

            resp = self._rpc(
                "chat.send",
                {
                    "sessionKey": session_key,
                    "idempotencyKey": idempotency_key,
                    "message": text,
                },
                timeout=15,
            )
            if resp is None:
                logger.error("chat.send 超时")
                return None
            if not resp.get("ok"):
                logger.error("chat.send 失败: %s", resp.get("error"))
                return None

            run_id = (resp.get("payload") or {}).get("runId")
            if not run_id:
                logger.error("chat.send 响应缺 runId: %s", resp)
                return None
            self._stream_run_id = run_id
            logger.info("chat.send 接受 runId=%s", run_id)

            # 等待 final 事件
            timeout_at = time.time() + (self.timeout or 120)
            interrupted = False
            while not self._stream_done.is_set():
                if time.time() > timeout_at:
                    logger.warning("等待 chat final 超时")
                    break
                with self._current_request_lock:
                    if self._current_request_id != request_id:
                        interrupted = True
                        break
                # 用短 sleep 让出 CPU
                if not self._stream_done.wait(timeout=0.1):
                    continue

            if interrupted:
                logger.info("请求 %s 已被取消（中断）", request_id)
                # 中断尝试：主动 chat.abort
                try:
                    self._rpc(
                        "chat.abort",
                        {"sessionKey": session_key, "runId": run_id},
                        timeout=3,
                    )
                except Exception:
                    pass

            return self._stream_full_text or None

        except Exception as e:
            logger.error("send_and_wait_stream 异常: %s", e)
            return None
        finally:
            with self._current_request_lock:
                if self._current_request_id == request_id:
                    self._current_request_id = None
            self._on_chunk = None
            self._on_tool_call = None
            self._on_start = None
            self._on_end = None

    # ─────────────────────────────────────────────────────────────────
    # 非流式兼容接口（保留原 HTTP 接口语义，方便上层不改）
    # ─────────────────────────────────────────────────────────────────

    def send_and_wait(self, text: str) -> Optional[str]:
        """非流式：阻塞返回完整文本。"""
        return self.send_and_wait_stream(text)


def get_bridge(**kwargs) -> OpenClawBridgeWebSocket:
    return OpenClawBridgeWebSocket(**kwargs)