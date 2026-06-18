#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
OpenClaw 桥接模块 (WebSocket 版本)
通过 Gateway WebSocket API 与 OpenClaw 对话，支持实时工具调用事件
"""

import json
import logging
import os
import threading
import time
import uuid
import hashlib
import base64
import websocket
from cryptography.hazmat.primitives.asymmetric import ed25519
from cryptography.hazmat.primitives import serialization

logger = logging.getLogger(__name__)

DEFAULT_GATEWAY_URL = "ws://127.0.0.1:18789"
DEFAULT_TIMEOUT = None

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
        with open(config_path, "r", encoding="utf-8") as f:
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


def _load_bootstrap_token():
    """从 bootstrap.json 加载可用的 bootstrap token"""
    bootstrap_path = os.path.expanduser("~/.openclaw/devices/bootstrap.json")
    try:
        with open(bootstrap_path, "r", encoding="utf-8") as f:
            data = json.load(f)
            for token, record in data.items():
                if record.get("deviceId") is None:
                    return token
    except Exception as e:
        logger.error(f"读取 bootstrap.json 失败: {e}")
    return None


class OpenClawBridgeWebSocket:
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
        self._ws = None
        self._connected = False
        self._session_key = None
        self._receive_thread = None
        self._stop_receive = threading.Event()
        self._challenge = None
        self._device_id = None
        self._public_key_b64 = None
        self._private_key = None
        self._bootstrap_token = _load_bootstrap_token()

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
                logger.info(f"取消请求: {self._current_request_id}")
                self._current_request_id = None
                return True
        return False

    def send_stop_command(self) -> bool:
        if not self.token:
            logger.error("Gateway token 不可用")
            return False
        if hasattr(self, "_stop_sending") and self._stop_sending:
            logger.info("/stop 已在发送中，跳过")
            return True
        self._stop_sending = True
        threading.Thread(target=self._send_stop_sync, daemon=True).start()
        return True

    def _send_stop_sync(self):
        try:
            import requests as req
            resp = req.post(
                f"{self.gateway_url.replace('ws://', 'http://').rstrip(':18789')}:18789/v1/chat/completions",
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
                timeout=8,
            )
            if resp.status_code == 200:
                logger.info("已发送 /stop 命令")
            else:
                logger.warning(f"发送 /stop 失败: HTTP {resp.status_code}")
        except Exception as e:
            logger.error(f"发送 /stop 异常: {e}")
        finally:
            self._stop_sending = False

    def _run_precheck(self):
        try:
            import requests as req
            resp = req.get(
                f"{self.gateway_url.replace('ws://', 'http://')}/v1/models",
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
        try:
            import requests as req
            for tool in _CHECK_TOOLS:
                try:
                    r = req.post(
                        f"{self.gateway_url.replace('ws://', 'http://')}/tools/invoke",
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
        except Exception:
            pass

        self.available_tools = tools_ok
        if tools_ok:
            print(f"[OpenClaw] ✓ Gateway 连通 | 可用工具: {', '.join(tools_ok)}")
        else:
            print("[OpenClaw] ✓ Gateway 连通 | 未探测到可用工具（HTTP 端点受限）")

    def _generate_device_identity(self):
        """生成或加载设备身份（Ed25519 密钥对）"""
        keypair_path = os.path.expanduser("~/.openclaw/devices/voice_assistant_keypair.json")
        if os.path.exists(keypair_path):
            try:
                with open(keypair_path, "r") as f:
                    data = json.load(f)
                self._private_key = serialization.load_pem_private_key(
                    data["private_key_pem"].encode("utf-8"), password=None
                )
                public_key = self._private_key.public_key()
                pub_bytes = public_key.public_bytes(
                    encoding=serialization.Encoding.Raw,
                    format=serialization.PublicFormat.Raw
                )
                self._device_id = hashlib.sha256(pub_bytes).digest().hex()
                self._public_key_b64 = base64.urlsafe_b64encode(pub_bytes).decode().rstrip("=")
                logger.info(f"加载已有设备身份: {self._device_id[:16]}...")
                return
            except Exception as e:
                logger.warning(f"加载设备身份失败，将生成新的: {e}")

        self._private_key = ed25519.Ed25519PrivateKey.generate()
        public_key = self._private_key.public_key()
        pub_bytes = public_key.public_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PublicFormat.Raw
        )
        self._device_id = hashlib.sha256(pub_bytes).digest().hex()
        self._public_key_b64 = base64.urlsafe_b64encode(pub_bytes).decode().rstrip("=")
        private_key_pem = self._private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption()
        ).decode("utf-8")
        os.makedirs(os.path.dirname(keypair_path), exist_ok=True)
        with open(keypair_path, "w") as f:
            json.dump({
                "private_key_pem": private_key_pem,
                "device_id": self._device_id
            }, f)
        logger.info(f"生成新设备身份: {self._device_id[:16]}...")

    def _sign_payload(self, role, scopes, signed_at_ms):
        """构建并签名 v3 格式的 payload"""
        scopes_str = ",".join(scopes)
        token = self.token or ""
        payload = f"v3|{self._device_id}|gateway-client|backend|{role}|{scopes_str}|{signed_at_ms}|{token}|{self._challenge}|darwin|"
        signature = self._private_key.sign(payload.encode("utf-8"))
        return base64.urlsafe_b64encode(signature).decode().rstrip("=")

    def _connect_ws(self):
        """建立 WebSocket 连接并完成握手"""
        if self._connected:
            return True

        self._generate_device_identity()

        try:
            self._ws = websocket.WebSocketApp(
                self.gateway_url,
                on_message=self._on_ws_message,
                on_error=self._on_ws_error,
                on_close=self._on_ws_close,
                on_open=self._on_ws_open,
            )
            self._stop_receive.clear()
            self._receive_thread = threading.Thread(target=self._ws.run_forever, daemon=True)
            self._receive_thread.start()

            timeout = 15
            start = time.time()
            while not self._connected and time.time() - start < timeout:
                time.sleep(0.1)

            if not self._connected:
                logger.error("WebSocket 连接超时或握手失败")
                return False

            logger.info("WebSocket 连接成功")
            return True
        except Exception as e:
            logger.error(f"WebSocket 连接失败: {e}")
            return False

    def _on_ws_open(self, ws):
        logger.info("WebSocket 连接已打开")

    def _on_ws_message(self, ws, message):
        try:
            data = json.loads(message)
            msg_type = data.get("type")

            if msg_type == "event":
                event_name = data.get("event")
                if event_name == "connect.challenge":
                    self._handle_connect_challenge(data)
                elif event_name == "session.message":
                    self._handle_session_message(data)
                elif event_name == "session.tool":
                    self._handle_session_tool(data)
                elif event_name == "lifecycle":
                    self._handle_lifecycle(data)
            elif msg_type == "res":
                self._handle_response(data)
            elif msg_type == "ping":
                ws.send(json.dumps({"type": "pong"}))

        except json.JSONDecodeError:
            logger.warning(f"无法解析消息: {message[:100]}")
        except Exception as e:
            logger.error(f"处理消息异常: {e}")

    def _on_ws_error(self, ws, error):
        logger.error(f"WebSocket 错误: {error}")

    def _on_ws_close(self, ws, close_status_code, close_msg):
        logger.info(f"WebSocket 关闭: {close_status_code} {close_msg}")
        self._connected = False

    def _handle_connect_challenge(self, data):
        """处理服务器发来的挑战，准备连接响应"""
        payload = data.get("payload", {})
        self._challenge = payload.get("nonce")
        logger.info(f"收到连接挑战: {self._challenge[:20]}...")

        if not self._bootstrap_token:
            logger.error("没有可用的 bootstrap token")
            return

        signed_at = int(time.time() * 1000)
        role = "operator"
        scopes = []
        signature = self._sign_payload(role, scopes, signed_at)

        connect_req = {
            "type": "req",
            "id": str(uuid.uuid4()),
            "method": "connect",
            "params": {
                "minProtocol": 4,
                "maxProtocol": 4,
                "client": {
                    "id": "gateway-client",
                    "version": "1.0.0",
                    "platform": "darwin",
                    "mode": "backend"
                },
                "device": {
                    "id": self._device_id,
                    "publicKey": self._public_key_b64,
                    "signature": signature,
                    "signedAt": signed_at,
                    "nonce": self._challenge
                },
"auth": {
                    "token": self.token
                }
            }
        }
        logger.info("发送连接请求...")
        self._ws.send(json.dumps(connect_req))

    def _handle_response(self, data):
        msg_method = data.get("method")
        if msg_method == "connect":
            if data.get("ok"):
                logger.info("WebSocket 握手成功")
                self._connected = True
            else:
                error = data.get("error", {})
                logger.error(f"连接失败: {error.get('message', 'unknown error')}")
        elif msg_method == "sessions.create" and data.get("ok"):
            self._session_key = data.get("sessionKey")
        elif data.get("type") == "res" and data.get("ok") and msg_method is None:
            logger.info("WebSocket 握手成功")
            self._connected = True

    def _handle_session_message(self, data):
        if hasattr(self, '_on_chunk'):
            delta_text = data.get("deltaText", "")
            if delta_text:
                self._on_chunk(delta_text)

    def _handle_session_tool(self, data):
        if hasattr(self, '_on_tool_call'):
            name = data.get("name", "")
            arguments = data.get("arguments", "")
            self._on_tool_call(name, arguments)

    def _handle_lifecycle(self, data):
        phase = data.get("phase", "")
        if phase == "end" and hasattr(self, '_on_end'):
            self._on_end()

    def _send_request(self, method, params=None):
        if not self._ws or not self._connected:
            logger.error("WebSocket 未连接")
            return False
        request = {
            "type": "req",
            "method": method,
            "params": params or {},
        }
        self._ws.send(json.dumps(request))
        return True

    def _disconnect(self):
        if self._ws:
            self._stop_receive.set()
            try:
                self._ws.close()
            except Exception:
                pass
            self._ws = None
            self._connected = False

    def send_and_wait_stream(
        self, text: str, on_chunk=None, on_start=None, on_end=None, on_tool_call=None
    ) -> str | None:
        if not self.token and not self._bootstrap_token:
            logger.error("Gateway token 和 bootstrap token 都不可用")
            return None
        if not text or not text.strip():
            return None

        request_id = self.start_request()
        logger.info(f"发送(流式 WS): {text} [request_id={request_id}]")

        self._on_chunk = on_chunk
        self._on_tool_call = on_tool_call
        self._on_end = on_end
        self._full_reply = ""
        self._started = False
        self._request_id = request_id
        self._session_key = None

        if not self._connect_ws():
            return None

        if not self._session_key:
            create_resp = self._send_and_wait_response(
                "sessions.create",
                {"agentId": self.agent_id}
            )
            if not create_resp or not create_resp.get("ok"):
                logger.error("创建会话失败")
                return None
            self._session_key = create_resp.get("sessionKey")

        self._send_request("sessions.subscribe", {
            "sessionKey": self._session_key,
            "events": ["session.message", "session.tool", "lifecycle"],
        })

        self._send_request("sessions.send", {
            "sessionKey": self._session_key,
            "message": {"role": "user", "content": text},
        })

        timeout = self.timeout or 120
        start = time.time()
        while time.time() - start < timeout:
            with self._lock:
                if self._current_request_id != request_id:
                    break
            time.sleep(0.1)

        self._send_request("sessions.unsubscribe", {
            "sessionKey": self._session_key,
            "events": ["session.message", "session.tool", "lifecycle"],
        })

        with self._lock:
            if self._current_request_id == request_id:
                self._current_request_id = None

        return self._full_reply if self._full_reply else None

    def _send_and_wait_response(self, method, params=None):
        if not self._ws or not self._connected:
            if not self._connect_ws():
                return None

        request_id = str(uuid.uuid4())
        request = {
            "type": "req",
            "method": method,
            "params": params or {},
            "requestId": request_id,
        }
        self._ws.send(json.dumps(request))

        timeout = 10
        start = time.time()
        while time.time() - start < timeout:
            time.sleep(0.05)
        return None


def get_bridge(**kwargs):
    return OpenClawBridgeWebSocket(**kwargs)