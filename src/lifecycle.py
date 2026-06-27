#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
激活生命周期联动（lifecycle linkage）

用途：把"助手进入激活态 / 退回待机态"这两个时刻抽象成统一的钩子点，
让任何需要随激活状态联动的动作（暂停媒体、藏 Dock、调灯光……）都能
注册进来，而不必散落在主循环各处。

接入方只需实现 LifecycleHook 的 on_wake / on_standby 并注册：

    from lifecycle import LifecycleHook, get_lifecycle_manager

    class DockHook(LifecycleHook):
        def on_wake(self):    ...   # 激活时：藏 Dock
        def on_standby(self): ...   # 休眠时：还原 Dock

    get_lifecycle_manager().register(DockHook())

主循环侧只需在 is_awake 的 False↔True 边沿调用 manager.notify(awake)，
其余全部由本模块负责。

设计原则：
  - **边沿触发**：只有状态真正翻转才派发，重复赋值不会重复触发。
  - **不阻塞热路径**：派发交给单个后台串行 worker，notify() 立即返回，
    媒体 CLI 等耗时调用不会卡住音频主循环。
  - **串行有序**：所有事件经同一队列按顺序处理，避免 wake/standby
    抢跑导致的竞态（如恢复早于暂停完成）。
  - **软失败**：单个钩子抛异常只记日志，绝不影响其他钩子或主流程。
"""

import logging
import queue
import threading

logger = logging.getLogger(__name__)


class LifecycleHook:
    """激活联动钩子基类。子类按需重写其一或全部。"""

    def on_wake(self):
        """助手进入激活态（待机 → 激活的上升沿）时调用。"""

    def on_standby(self):
        """助手退回待机态（激活 → 待机的下降沿）时调用。"""


class LifecycleManager:
    """钩子注册表 + 单后台串行 worker。"""

    def __init__(self):
        self._hooks = []
        self._lock = threading.Lock()
        self._queue = queue.Queue()
        self._worker = threading.Thread(
            target=self._run, name="lifecycle-worker", daemon=True
        )
        self._worker.start()

    def register(self, hook: LifecycleHook):
        """注册一个联动钩子。重复注册同一实例会被忽略。"""
        with self._lock:
            if hook not in self._hooks:
                self._hooks.append(hook)
                logger.info("[联动] 已注册钩子: %s", type(hook).__name__)
        return hook

    def unregister(self, hook: LifecycleHook):
        with self._lock:
            if hook in self._hooks:
                self._hooks.remove(hook)

    def notify(self, awake: bool):
        """主循环在 is_awake 边沿调用。立即返回，实际派发在后台进行。"""
        self._queue.put(bool(awake))

    def _run(self):
        while True:
            awake = self._queue.get()
            with self._lock:
                hooks = list(self._hooks)
            method = "on_wake" if awake else "on_standby"
            for hook in hooks:
                try:
                    getattr(hook, method)()
                except Exception as e:  # 软失败：单钩子异常不波及其余
                    logger.warning(
                        "[联动] 钩子 %s.%s 执行失败: %s",
                        type(hook).__name__,
                        method,
                        e,
                    )


# ── 单例 ──────────────────────────────────────────────────
_manager = None
_manager_lock = threading.Lock()


def get_lifecycle_manager() -> LifecycleManager:
    global _manager
    with _manager_lock:
        if _manager is None:
            _manager = LifecycleManager()
        return _manager
