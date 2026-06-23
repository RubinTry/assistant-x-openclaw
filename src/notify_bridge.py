#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
桌面通知桥 —— 把通知请求发给 control_center（Flutter 桌面应用）。

由 control_center 来弹系统通知，通知图标即该应用自身的 bundle 图标，
从而避免 osascript `display notification` 只能显示终端/脚本宿主图标的问题。

协议（复用 control_center 的 18792 TCP 通道，每条一行 JSON）：
    {"type": "notify", "title": "...", "text": "...", "sound": true}
control_center 端对未知/非 JSON 内容仍按旧的 "speaker_rejected" 裸串处理，向后兼容。
"""

import json
import socket

_NOTIFY_HOST = "127.0.0.1"
_NOTIFY_PORT = 18792  # 与 control_center ServerSocket、main._SPEAKER_NOTIFY_PORT 一致


def notify_control_center(title: str, text: str, sound: bool = True) -> bool:
    """把桌面通知请求发给 control_center。

    成功送达返回 True；control_center 未运行或连接失败返回 False（调用方可回退到原生通知）。
    """
    try:
        payload = json.dumps(
            {"type": "notify", "title": title, "text": text, "sound": bool(sound)},
            ensure_ascii=False,
        )
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(1.5)
        sock.connect((_NOTIFY_HOST, _NOTIFY_PORT))
        sock.sendall((payload + "\n").encode("utf-8"))
        sock.close()
        return True
    except Exception:
        return False
