import socket
import threading
import time
import logging

from assistants.visual import AssistantVisual

logger = logging.getLogger(__name__)


class JarvisVisual(AssistantVisual):
    """贾维斯特效 — 通过 TCP 控制 Flutter overlay（JARVIS 风格环形动画 + 终端）"""

    def __init__(self, host="127.0.0.1", port=17889):
        self.host = host
        self.port = port
        self.socket = None
        self.lock = threading.Lock()
        self.connected = False
        self._connect_thread = None
        self._running = True
        # 特效调试模式：true 时召唤出来的特效不再被隐藏/清空（便于调样式）
        self.debug_mode = False

    def set_debug_mode(self, enabled: bool):
        self.debug_mode = bool(enabled)
        if self.debug_mode:
            logger.info("Overlay 调试模式开启：特效召唤后不再隐藏/清空")

    def _connect(self):
        while self._running:
            try:
                self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                self.socket.settimeout(1.0)
                self.socket.connect((self.host, self.port))
                self.connected = True
                logger.info(f"Connected to JARVIS overlay at {self.host}:{self.port}")

                while self._running and self.connected:
                    try:
                        data = self.socket.recv(1024)
                        if not data:
                            break
                    except socket.timeout:
                        continue
                    except Exception:
                        break

            except Exception as e:
                if self._running:
                    logger.debug(f"Overlay connection attempt: {e}")

            self.connected = False
            if self._running:
                time.sleep(1.0)

    def start(self):
        if self._connect_thread is None or not self._connect_thread.is_alive():
            self._running = True
            self._connect_thread = threading.Thread(target=self._connect, daemon=True)
            self._connect_thread.start()

    def stop(self):
        self._running = False
        if self.socket:
            try:
                self.socket.close()
            except:
                pass
        self.connected = False

    def send(self, message: str):
        if not self.connected or not self.socket:
            print(f"[JARVIS_VISUAL] Not connected, cannot send: {message}")
            return False
        try:
            clean_msg = message.strip()
            data = (clean_msg + "\n").encode("utf-8")
            print(f"[JARVIS_VISUAL] Sending: {data!r} (message='{clean_msg}')")
            with self.lock:
                self.socket.sendall(data)
            return True
        except Exception as e:
            print(f"[JARVIS_VISUAL] Send error: {e}")
            self.connected = False
            return False

    def show_wake_effect(self):
        """唤醒特效 — 先切换 agent，再唤醒"""
        # 先发送 agent 切换命令
        self.send("agent:jarvis")
        # 然后发送唤醒
        self.send("wake")

    def hide_effects(self):
        if self.debug_mode:
            return  # 调试模式：召唤后保持显示，不隐藏
        self.send("hide")

    def clear_texts(self):
        if self.debug_mode:
            return  # 调试模式：保留文本，便于调终端框样式
        self.send("user:")
        self.send("ai:")

    def show_user_text(self, text: str):
        clean_text = text.strip().replace("\n", " ")
        self.send(f"user:{clean_text}")

    def show_ai_text(self, text: str):
        clean_text = text.strip().replace("\n", " ")
        self.send(f"ai:{clean_text}")

    def reset_speaking_scale(self):
        """用户讲完话，恢复特效大小"""
        self.send("reset_scale")

    def send_audio_level(self, level: float):
        """推送音频电平 (0.0~1.0) 给 Flutter overlay"""
        level = max(0.0, min(1.0, level))
        self.send(f"audio_level:{level:.3f}")
