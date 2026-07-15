#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Shared voice context store.

FastRouter replies and engine replies live in different systems. This module
keeps a small, project-owned JSONL log so both lanes can see the same recent
voice conversation without writing into Hermes/OpenClaw internal databases.
"""

from __future__ import annotations

import json
import os
import threading
import time
import stat
from collections import deque

_PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_STORE_DIR = os.path.join(_PROJECT_DIR, "data", "voice_context")
_MAX_CONTENT_CHARS = 4000
_MAX_FILE_BYTES = 2 * 1024 * 1024
_TRIM_KEEP_LINES = 1200
_lock = threading.RLock()


def _ensure_private_store() -> None:
    os.makedirs(_STORE_DIR, mode=0o700, exist_ok=True)
    if os.name != "nt":
        os.chmod(_STORE_DIR, 0o700)


def _reject_symlink(path: str) -> None:
    try:
        if stat.S_ISLNK(os.lstat(path).st_mode):
            raise OSError("refusing to use a symlinked voice context file")
    except FileNotFoundError:
        return


def _open_private(path: str, *, append: bool):
    _ensure_private_store()
    _reject_symlink(path)
    flags = os.O_WRONLY | os.O_CREAT | (os.O_APPEND if append else os.O_TRUNC)
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    fd = os.open(path, flags, 0o600)
    if os.name != "nt":
        os.fchmod(fd, 0o600)
    return os.fdopen(fd, "a" if append else "w", encoding="utf-8")


def _norm(agent_id: str) -> str:
    keep = []
    for ch in (agent_id or "main").strip().replace("-", "_"):
        if ch.isalnum() or ch in ("_", "-"):
            keep.append(ch)
    return "".join(keep) or "main"


def _path(agent_id: str) -> str:
    return os.path.join(_STORE_DIR, f"{_norm(agent_id)}.jsonl")


def append_turn(
    agent_id: str,
    lane: str,
    role: str,
    content: str,
    *,
    session_id: str = "",
    session_key: str = "",
) -> None:
    """Append one clean voice turn. Fail-open: storage must never break chat."""
    text = (content or "").strip()
    if not text or role not in ("user", "assistant"):
        return
    item = {
        "ts": time.time(),
        "agent_id": _norm(agent_id),
        "lane": (lane or "unknown").strip() or "unknown",
        "role": role,
        "content": text[:_MAX_CONTENT_CHARS],
        "session_id": session_id or "",
        "session_key": session_key or "",
    }
    try:
        with _lock:
            p = _path(agent_id)
            with _open_private(p, append=True) as f:
                f.write(json.dumps(item, ensure_ascii=False, separators=(",", ":")))
                f.write("\n")
            _trim_if_needed(p)
    except Exception:
        return


def recent_turns(
    agent_id: str,
    *,
    limit: int = 8,
    lanes: set[str] | None = None,
    since_ts: float | None = None,
) -> list[dict]:
    """Return recent turns in chronological order."""
    rows = _read_tail(agent_id, max_lines=max(limit * 8, 80))
    if lanes:
        rows = [r for r in rows if r.get("lane") in lanes]
    if since_ts is not None:
        rows = [r for r in rows if float(r.get("ts") or 0) >= since_ts]
    normalized_agent = _norm(agent_id)
    rows = [
        {
            "role": r.get("role"),
            "content": r.get("content") or "",
            "lane": r.get("lane") or "",
            "ts": r.get("ts") or 0,
        }
        for r in rows
        if r.get("role") in ("user", "assistant") and r.get("content")
        and not _obvious_cross_persona_leak(normalized_agent, r.get("role"), r.get("content") or "")
    ]
    return rows[-limit:]


def _obvious_cross_persona_leak(agent_id: str, role: str, content: str) -> bool:
    """Quarantine known impossible assistant identities without deleting audit data."""
    if role != "assistant":
        return False
    low = content.lower()
    if agent_id == "jarvis":
        return "哥哥" in content or "妹妹在" in content or "自称妹妹" in content
    if agent_id == "lin_meimei":
        return "i am jarvis" in low or "at your service, sir" in low
    return False


def recent_fast_router_context(agent_id: str, *, limit: int = 8) -> list[dict]:
    # Read legacy "fast" rows so existing conversations remain continuous;
    # every new row is written with the FastRouter lane name.
    return recent_turns(agent_id, limit=limit, lanes={"fast_router", "fast"})


def _read_tail(agent_id: str, max_lines: int = 200) -> list[dict]:
    p = _path(agent_id)
    if not os.path.exists(p):
        return []
    out = []
    try:
        with _lock:
            _ensure_private_store()
            _reject_symlink(p)
            if os.name != "nt":
                os.chmod(p, 0o600)
            with open(p, "r", encoding="utf-8") as f:
                lines = deque(f, maxlen=max_lines)
        for line in lines:
            try:
                obj = json.loads(line)
            except (ValueError, json.JSONDecodeError):
                continue
            if isinstance(obj, dict):
                out.append(obj)
    except OSError:
        return []
    return out


def _trim_if_needed(path: str) -> None:
    try:
        if os.path.getsize(path) <= _MAX_FILE_BYTES:
            return
        with open(path, "r", encoding="utf-8") as f:
            lines = deque(f, maxlen=_TRIM_KEEP_LINES)
        tmp = f"{path}.tmp"
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass
        with _open_private(tmp, append=False) as f:
            f.writelines(lines)
        os.replace(tmp, path)
        if os.name != "nt":
            os.chmod(path, 0o600)
    except OSError:
        return
