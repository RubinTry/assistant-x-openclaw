#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""运行日志落盘：把 stdout/stderr 与 logging 同时写到 <项目根>/logs/。

项目主体用 print 输出、部分模块用 logging。这里用 Tee 接管 stdout/stderr，
并让 root logger 也走（已被 Tee 的）stdout，从而把两类输出汇入同一份日志文件，
顺序与控制台一致。每行行首统一盖 [年-月-日 时:分:秒] 时间戳（控制中心与
日志文件都带）。另设一条文件级诊断/错误日志（get_diag_logger），只落盘、
不进控制中心。
"""

import atexit
import logging
import os
import sys
from datetime import datetime

# 文件级诊断/错误日志的 logger 名。用 get_diag_logger() 取用。
# 该 logger propagate=False、只挂 FileHandler，写进 logs/ 但**不进控制中心**
# （控制中心读的是进程 stdout，而此 logger 不经过 stdout）。
DIAG_LOGGER_NAME = "jarvis.diag"


def get_diag_logger() -> logging.Logger:
    """取文件级诊断/错误 logger（只落盘、不进控制中心）。

    用于排查类、错误类日志：希望留底但不想刷控制中心的内容都走这里。
    setup_logging() 未调用前也可安全取用（无 handler 时按 root 处理，不报错）。
    """
    return logging.getLogger(DIAG_LOGGER_NAME)


class _Tee:
    """同时写入原始流和日志文件，并在每行行首盖上 [年-月-日 时:分:秒] 时间戳。

    所有 print / logging 都经此流，故每行输出统一带时间戳（控制中心与日志文件
    一致）。空行不盖戳。多个 _Tee（stdout/stderr）共享行首状态，避免交错时重复盖。
    """

    def __init__(self, stream, log_file, state):
        self._stream = stream
        self._log = log_file
        self._state = state  # {"line_start": bool}，stdout/stderr 共享

    def _stamp(self, data):
        if not data:
            return data
        ts = datetime.now().strftime("[%Y-%m-%d %H:%M:%S] ")
        out = []
        for ch in data:
            if self._state["line_start"] and ch not in ("\n", "\r"):
                out.append(ts)
                self._state["line_start"] = False
            out.append(ch)
            if ch == "\n":
                self._state["line_start"] = True
        return "".join(out)

    def write(self, data):
        stamped = self._stamp(data)
        self._stream.write(stamped)
        try:
            self._log.write(stamped)
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
    # 运行日志(jarvis_*) 与诊断日志(jarvis_diag_*) 各自保留最近 keep 份，互不挤占
    try:
        names = [
            f for f in os.listdir(logs_dir)
            if f.startswith("jarvis_") and f.endswith(".log")
        ]
        diag = [n for n in names if n.startswith("jarvis_diag_")]
        run = [n for n in names if not n.startswith("jarvis_diag_")]
        for group in (run, diag):
            paths = [os.path.join(logs_dir, n) for n in group]
            paths.sort(key=os.path.getmtime, reverse=True)
            for old in paths[keep:]:
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

    # stdout/stderr 共享同一行首状态，交错写时不会重复盖戳
    _tee_state = {"line_start": True}
    sys.stdout = _Tee(sys.stdout, log_file, _tee_state)
    sys.stderr = _Tee(sys.stderr, log_file, _tee_state)

    # 让 logging 走（已被 Tee 的）stdout，与 print 汇入同一文件且顺序一致
    root = logging.getLogger()
    root.setLevel(logging.INFO)
    handler = logging.StreamHandler(sys.stdout)
    # 时间戳由 _Tee 统一在行首添加，这里不再带 asctime，避免双重时间戳
    handler.setFormatter(
        logging.Formatter("[%(levelname)s] %(name)s: %(message)s")
    )
    root.handlers.clear()
    root.addHandler(handler)

    # ── 文件级诊断/错误日志（独立文件，不进控制中心）──────────────
    # 关键：FileHandler 直接写文件、不经过被 Tee 的 stdout；diag logger
    # propagate=False 不冒泡到 root，故这些内容只落盘、控制中心看不到。
    diag_path = os.path.join(logs_dir, f"jarvis_diag_{ts}_{os.getpid()}.log")
    diag_handler = logging.FileHandler(diag_path, encoding="utf-8")
    diag_handler.setLevel(logging.DEBUG)
    diag_handler.setFormatter(
        logging.Formatter(
            "[%(asctime)s] [%(levelname)s] %(name)s: %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S",
        )
    )
    diag = logging.getLogger(DIAG_LOGGER_NAME)
    diag.setLevel(logging.DEBUG)
    diag.handlers.clear()
    diag.addHandler(diag_handler)
    diag.propagate = False  # 不冒泡到 root → 不进 stdout → 不进控制中心
    atexit.register(diag_handler.close)

    _cleanup_old_logs(logs_dir, keep)
    print(f"[日志] 运行日志: {log_path}")
    print(f"[日志] 诊断/错误日志(仅落盘): {diag_path}")
    diag.info("诊断日志初始化完成 pid=%s", os.getpid())
    return log_path
