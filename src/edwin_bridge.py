#!/usr/bin/env python3
"""Drop-in bridge for the in-process Edwin agent runtime."""

from __future__ import annotations

import logging
import re
import threading
import uuid

from edwin import AgentRuntime, ApprovalRequired, Cancelled

logger = logging.getLogger(__name__)

_YES = re.compile(r"^(yes|yes please|approve|approved|confirm|do it|go ahead|可以|同意|确认|批准|执行|继续)[。.!！ ]*$", re.I)
_NO = re.compile(r"^(no|deny|denied|cancel|do not|don't|不|不要|拒绝|取消|不同意)[。.!！ ]*$", re.I)


class EdwinBridge:
    def __init__(self, agent_id="main", namespace="main", **_kwargs):
        self.agent_id = (agent_id or "main").replace("-", "_")
        self.namespace = namespace
        self.runtime = AgentRuntime(self.agent_id)
        self.available_tools = []
        self._lock = threading.RLock()
        self._current_request_id = None
        self._cancel_events: dict[str, threading.Event] = {}
        self._soft_stopped: set[str] = set()
        self._pending = None
        self._unclear_count = 0
        self._last_user_text = ""

    def precheck_async(self):
        def run():
            result = self.runtime.precheck()
            if result.get("ok"):
                self.available_tools = result.get("tools", [])
                print(f"[Edwin] ✓ 内置引擎就绪 | 模型: {result.get('model')} | 工具: {len(self.available_tools)}")
            else:
                print(f"[Edwin] ✗ {result.get('error')}")
        threading.Thread(target=run, daemon=True).start()

    def close(self):
        self.cancel_task()
        self._pending = None

    def has_inflight_task(self):
        with self._lock:
            return bool(self._soft_stopped)

    def pending_task_hint(self): return self._last_user_text
    def mark_previous_task_abandoned(self): pass

    def send_stop_command(self):
        with self._lock:
            if self._current_request_id:
                self._soft_stopped.add(self._current_request_id)
                return True
            # A normal TTS/turn soft-stop may arrive after ApprovalRequired has
            # returned. It must not revoke the approval before the next utterance.
        return False

    def clear_pending_approval(self):
        """Explicit lifecycle edge (standby/role switch), never ordinary soft-stop."""
        with self._lock:
            self._pending = None
            self._unclear_count = 0

    def cancel_current_request(self):
        with self._lock:
            rid = self._current_request_id
            if rid and rid in self._cancel_events:
                self._cancel_events[rid].set()
            self._current_request_id = None
            self._pending = None
            self._unclear_count = 0
            return bool(rid)

    def cancel_task(self): return self.cancel_current_request()

    def send_clear_command(self):
        self.runtime.clear()
        self.clear_pending_approval()
        return True

    def send_and_wait(self, text): return self.send_and_wait_stream(text)

    def _approval_decision(self, text):
        value = (text or "").strip()
        if _YES.match(value): return "approve"
        if _NO.match(value): return "deny"
        return "unclear"

    def send_and_wait_stream(self, text, on_chunk=None, on_start=None, on_end=None, on_tool_call=None):
        if not text or not text.strip(): return None
        self._last_user_text = text
        with self._lock:
            pending = self._pending
        if pending:
            decision = self._approval_decision(text)
            if decision == "unclear" and self._unclear_count == 0:
                self._unclear_count = 1
                answer = "Please answer yes or no. " + pending.approval.summary
                if on_start: on_start()
                if on_chunk: on_chunk(answer)
                if on_end: on_end()
                return answer
            approved = decision == "approve"
            with self._lock:
                self._pending = None
                self._unclear_count = 0
            return self._run(text, on_chunk, on_start, on_end, on_tool_call, resume=pending, approved=approved)
        return self._run(text, on_chunk, on_start, on_end, on_tool_call)

    def _run(self, text, on_chunk, on_start, on_end, on_tool_call, resume=None, approved=False):
        rid = resume.request_id if resume else str(uuid.uuid4())
        cancel = threading.Event()
        started = False
        def emit(chunk):
            nonlocal started
            with self._lock: muted = rid in self._soft_stopped
            if muted: return
            if not started:
                started = True
                if on_start: on_start()
            if on_chunk: on_chunk(chunk)
        with self._lock:
            self._current_request_id = rid
            self._cancel_events[rid] = cancel
        try:
            return self.runtime.run(text, cancel, on_text=emit, on_tool=on_tool_call, request_id=rid, resume=resume, approved=approved)
        except ApprovalRequired as exc:
            with self._lock: self._pending = exc.state
            emit(exc.state.approval.summary)
            return exc.state.approval.summary
        except Cancelled:
            return None
        finally:
            with self._lock:
                muted = rid in self._soft_stopped
                self._soft_stopped.discard(rid)
                self._cancel_events.pop(rid, None)
                if self._current_request_id == rid: self._current_request_id = None
            if on_end and not muted: on_end()


def get_bridge(**kwargs): return EdwinBridge(**kwargs)
