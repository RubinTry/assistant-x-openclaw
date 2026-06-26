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
        # log_file 为 None 时只做控制台行首时间戳，不落盘
        # （日志文件只保留 error 级，见 setup_logging 的 FileHandler）。
        if self._log is not None:
            try:
                self._log.write(stamped)
            except Exception:
                pass

    def flush(self):
        self._stream.flush()
        if self._log is not None:
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

    # stdout/stderr 仅做控制台行首时间戳，不再把全部输出落盘——日志文件只保留
    # error 级（见下方 FileHandler）。终端/控制中心读的是进程 stdout，不受影响。
    _tee_state = {"line_start": True}
    sys.stdout = _Tee(sys.stdout, None, _tee_state)
    sys.stderr = _Tee(sys.stderr, None, _tee_state)

    # 控制台 logging（INFO+，与 print 一起进终端/控制中心，不落盘）
    root = logging.getLogger()
    root.setLevel(logging.INFO)
    console = logging.StreamHandler(sys.stdout)
    # 时间戳由 _Tee 统一在行首添加，这里不再带 asctime，避免双重时间戳
    console.setFormatter(
        logging.Formatter("[%(levelname)s] %(name)s: %(message)s")
    )
    root.handlers.clear()
    root.addHandler(console)

    # ── 日志文件：只记录 ERROR 及以上，其余一律不落盘 ──────────────
    file_handler = logging.FileHandler(log_path, encoding="utf-8")
    file_handler.setLevel(logging.ERROR)
    file_handler.setFormatter(
        logging.Formatter(
            "[%(asctime)s] [%(levelname)s] %(name)s: %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S",
        )
    )
    root.addHandler(file_handler)
    atexit.register(file_handler.close)

    # diag logger 沿用同一份 error 文件（propagate=False，仍只落盘不进控制中心）。
    # 仅 .error()/.exception() 会写入，.info()/.warning() 一律忽略。
    diag = logging.getLogger(DIAG_LOGGER_NAME)
    diag.setLevel(logging.ERROR)
    diag.handlers.clear()
    diag.addHandler(file_handler)
    diag.propagate = False

    # 未捕获异常也写进 error 文件，避免崩溃信息只出现在终端
    def _log_uncaught(exc_type, exc, tb):
        if not issubclass(exc_type, KeyboardInterrupt):
            logging.getLogger("jarvis.uncaught").error(
                "未捕获异常", exc_info=(exc_type, exc, tb)
            )
        sys.__excepthook__(exc_type, exc, tb)

    sys.excepthook = _log_uncaught

    _cleanup_old_logs(logs_dir, keep)
    print(f"[日志] 错误日志(仅 error 落盘): {log_path}")
    return log_path
