#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
通用配置驱动 Visual — TCP → Flutter Overlay
通过 config 中的 agent_id 决定发送的 agent 切换命令
"""

import socket
import threading
import time
import logging

from assistants.visual import AssistantVisual

logger = logging.getLogger(__name__)


class ConfigurableVisual(AssistantVisual):
    def __init__(self, config: dict):
        self.agent_id = config.get("agent_id", "default")
        host = config.get("host", "127.0.0.1")
        port = config.get("port", 17889)
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
                logger.info(
                    f"Connected to overlay at {self.host}:{self.port} (agent={self.agent_id})"
                )

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
            except Exception:
                pass
        self.connected = False

    def send(self, message: str):
        if not self.connected or not self.socket:
            print(f"[VISUAL] Not connected, cannot send: {message}")
            return False
        try:
            clean_msg = message.strip()
            data = (clean_msg + "\n").encode("utf-8")
            print(f"[VISUAL] Sending: {data!r} (message='{clean_msg}')")
            with self.lock:
                self.socket.sendall(data)
            return True
        except Exception as e:
            print(f"[VISUAL] Send error: {e}")
            self.connected = False
            return False

    def show_wake_effect(self):
        self.send(f"agent:{self.agent_id}")
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

    def reset_speaking_scale(self):
        self.send("reset_scale")

    def send_audio_level(self, level: float):
        level = max(0.0, min(1.0, level))
        self.send(f"audio_level:{level:.3f}")
