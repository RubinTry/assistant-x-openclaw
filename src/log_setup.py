#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""运行日志落盘：把 stdout/stderr 与 logging 同时写到 <项目根>/logs/。

项目主体用 print 输出、部分模块用 logging。这里用 Tee 接管 stdout/stderr，
并让 root logger 也走（已被 Tee 的）stdout，从而把两类输出汇入同一份日志文件，
顺序与控制台完全一致；控制台输出保持不变。
"""

import atexit
import logging
import os
import sys
from datetime import datetime


class _Tee:
    """同时写入原始流和日志文件，使所有 print 进入运行日志。"""

    def __init__(self, stream, log_file):
        self._stream = stream
        self._log = log_file

    def write(self, data):
        self._stream.write(data)
        try:
            self._log.write(data)
        except Exception:
            pass

    def flush(self):
        self._stream.flush()
        try:
            self._log.flush()
        except Exception:
            pass

    def __getattr__(self, name):
        # 透传 isatty/encoding/fileno 等属性，保持终端行为
        return getattr(self._stream, name)


def _cleanup_old_logs(logs_dir, keep):
    try:
        files = [
            os.path.join(logs_dir, f)
            for f in os.listdir(logs_dir)
            if f.startswith("jarvis_") and f.endswith(".log")
        ]
        files.sort(key=os.path.getmtime, reverse=True)
        for old in files[keep:]:
            try:
                os.remove(old)
            except OSError:
                pass
    except OSError:
        pass


def setup_logging(project_dir, keep=15):
    """将运行日志输出到 <project_dir>/logs/，同时保留控制台输出。

    Args:
        project_dir: 项目根目录
        keep: 仅保留最近 keep 个日志文件

    Returns:
        本次运行的日志文件路径
    """
    logs_dir = os.path.join(project_dir, "logs")
    os.makedirs(logs_dir, exist_ok=True)

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_path = os.path.join(logs_dir, f"jarvis_{ts}_{os.getpid()}.log")

    # 行缓冲，确保崩溃时已写内容不丢失
    log_file = open(log_path, "a", encoding="utf-8", buffering=1)
    atexit.register(log_file.close)

    sys.stdout = _Tee(sys.stdout, log_file)
    sys.stderr = _Tee(sys.stderr, log_file)

    # 让 logging 走（已被 Tee 的）stdout，与 print 汇入同一文件且顺序一致
    root = logging.getLogger()
    root.setLevel(logging.INFO)
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(
        logging.Formatter(
            "%(asctime)s [%(levelname)s] %(name)s: %(message)s",
            datefmt="%H:%M:%S",
        )
    )
    root.handlers.clear()
    root.addHandler(handler)

    _cleanup_old_logs(logs_dir, keep)
    print(f"[日志] 运行日志: {log_path}")
    return log_path
