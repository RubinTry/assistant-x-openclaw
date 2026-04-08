import socket
import threading
import time
import logging

logger = logging.getLogger(__name__)


class JARVISVisualClient:
    def __init__(self, host="127.0.0.1", port=17889):
        self.host = host
        self.port = port
        self.socket = None
        self.lock = threading.Lock()
        self.connected = False
        self._connect_thread = None
        self._running = True

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
        self.send("wake")

    def hide_effects(self):
        self.send("hide")

    def clear_texts(self):
        self.send("user:")
        self.send("ai:")

    def show_user_text(self, text: str):
        clean_text = text.strip().replace("\n", " ")
        self.send(f"user:{clean_text}")

    def show_ai_text(self, text: str):
        clean_text = text.strip().replace("\n", " ")
        self.send(f"ai:{clean_text}")


_client = None
_lock = threading.Lock()


class NullVisualClient:
    """空对象模式 - 当特效禁用时使用，避免到处检查 None"""

    def show_wake_effect(self):
        pass

    def show_creating_session(self):
        pass

    def show_session_created(self):
        pass

    def show_processing(self):
        pass

    def show_success(self):
        pass

    def show_error(self):
        pass

    def hide_effects(self):
        pass

    def clear_texts(self):
        pass

    def show_user_text(self, text: str):
        pass

    def show_ai_text(self, text: str):
        pass


def get_visual_effects(enabled=True):
    global _client
    with _lock:
        if enabled:
            if _client is None:
                _client = JARVISVisualClient()
                _client.start()
            return _client
        else:
            if _client:
                _client.stop()
                _client = None
            return NullVisualClient()
