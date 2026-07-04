#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
IHistoryReader —— 从引擎读取 session（近期对话）与 memory（长期记忆），喂给快路径。

分流后轻消息由裸模型直答，默认丢了 agent 的 session 与 memory；本模块把两大引擎
各自的**本地存储**抽象成统一接口，让快路径也能拿到近期对话与相关记忆：

  - Hermes  : profiles/<agent>/state.db 的 messages 表 + memories/USER.md
  - OpenClaw: agents/<agent>/sessions/<id>.jsonl + memory/<agent>.sqlite (chunks)

设计取舍（已与用户确认）：
  - 本地直读（~ms，够快上热路径），不走引擎 API（RPC 太慢）
  - 一切 fail-open：读失败/schema 变化 → 返回空，快路径退化为无上下文，绝不报错
  - 只读不写：快路径的回答暂不写回引擎 session（轻轮多为闲聊，影响小）
  - 定位当前会话：Hermes 用 voice-<agent>-* 前缀取最新；OpenClaw 用 agent:<a>:<a> 键
"""

from __future__ import annotations

import json
import os
import re
import sqlite3
from abc import ABC, abstractmethod

_HERMES_HOME = os.path.expanduser(os.environ.get("HERMES_HOME", "~/.hermes"))
_OPENCLAW_HOME = os.path.expanduser("~/.openclaw")


def _norm(agent_id: str) -> str:
    return (agent_id or "").strip().replace("-", "_")


def _fts_query(text: str, max_tokens: int = 5) -> str | None:
    """把用户文本转成安全的 FTS5 MATCH 查询：取 2+ 字的词/CJK 片段，各自加引号 OR 连接。
    加引号可避免 FTS5 把标点当语法、抛 syntax error。"""
    tokens = re.findall(r"[\w一-鿿]{2,}", text or "")
    tokens = tokens[:max_tokens]
    if not tokens:
        return None
    return " OR ".join(f'"{t}"' for t in tokens)


def _connect_ro(path: str) -> sqlite3.Connection | None:
    """只读打开 SQLite（不加锁、短超时），失败返回 None。"""
    if not os.path.exists(path):
        return None
    try:
        return sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=1.0)
    except sqlite3.Error:
        return None


class IHistoryReader(ABC):
    """引擎无关的 session/memory 只读接口。"""

    @abstractmethod
    def is_available(self) -> bool:
        """底层存储是否就绪（供快路径决定是否注入上下文）。"""

    @abstractmethod
    def recent_turns(self, limit: int = 6) -> list[dict]:
        """当前会话最近 N 轮，按时间正序返回 [{"role","content"}]，只含 user/assistant。"""

    @abstractmethod
    def search_memory(self, query: str, limit: int = 5) -> list[str]:
        """按 query 检索相关长期记忆/历史片段，返回短文本列表。"""

    @abstractmethod
    def user_profile(self, limit_chars: int = 600) -> str:
        """稳定的用户画像/偏好（如 Hermes USER.md），截断到 limit_chars。"""


# ── Hermes ───────────────────────────────────────────────────────────

class HermesHistoryReader(IHistoryReader):
    def __init__(self, agent_id: str):
        self.aid = _norm(agent_id)
        base = os.path.join(_HERMES_HOME, "profiles", self.aid)
        self.state_db = os.path.join(base, "state.db")
        self.user_md = os.path.join(base, "memories", "USER.md")
        self._session_like = f"voice-{self.aid}-%"

    def is_available(self) -> bool:
        return os.path.exists(self.state_db)

    def recent_turns(self, limit: int = 6) -> list[dict]:
        conn = _connect_ro(self.state_db)
        if conn is None:
            return []
        try:
            rows = conn.execute(
                """
                SELECT role, content FROM messages
                WHERE session_id LIKE ? AND active = 1
                  AND role IN ('user','assistant')
                  AND content IS NOT NULL AND content != ''
                ORDER BY timestamp DESC LIMIT ?
                """,
                (self._session_like, limit),
            ).fetchall()
        except sqlite3.Error:
            return []
        finally:
            conn.close()
        # 倒序取出的，翻正为时间正序
        return [{"role": r[0], "content": r[1]} for r in reversed(rows)]

    def search_memory(self, query: str, limit: int = 5) -> list[str]:
        match = _fts_query(query)
        if not match:
            return []
        conn = _connect_ro(self.state_db)
        if conn is None:
            return []
        try:
            rows = conn.execute(
                """
                SELECT m.content FROM messages_fts f
                JOIN messages m ON m.id = f.rowid
                WHERE f.messages_fts MATCH ? AND m.role IN ('user','assistant')
                  AND m.content IS NOT NULL AND m.content != ''
                ORDER BY rank LIMIT ?
                """,
                (match, limit),
            ).fetchall()
            return [r[0][:300] for r in rows]
        except sqlite3.Error:
            return []
        finally:
            conn.close()

    def user_profile(self, limit_chars: int = 600) -> str:
        try:
            with open(self.user_md, "r", encoding="utf-8") as f:
                text = f.read()
        except OSError:
            return ""
        # USER.md 用 § 分隔条目；取前若干条拼到预算内
        entries = [e.strip() for e in text.split("§") if e.strip()]
        out, total = [], 0
        for e in entries:
            if total + len(e) > limit_chars and out:
                break
            out.append(e)
            total += len(e)
        return "\n".join(out).strip()


# ── OpenClaw ─────────────────────────────────────────────────────────

class OpenClawHistoryReader(IHistoryReader):
    def __init__(self, agent_id: str):
        self.aid = _norm(agent_id)
        self.sessions_dir = os.path.join(_OPENCLAW_HOME, "agents", self.aid, "sessions")
        self.sessions_json = os.path.join(self.sessions_dir, "sessions.json")
        self.memory_db = os.path.join(_OPENCLAW_HOME, "memory", f"{self.aid}.sqlite")
        self.user_md = os.path.join(_OPENCLAW_HOME, "workspace", self.aid, "USER.md")
        self._session_key = f"agent:{self.aid}:{self.aid}"

    def is_available(self) -> bool:
        return os.path.exists(self.sessions_json) or os.path.exists(self.memory_db)

    def _current_jsonl(self) -> str | None:
        try:
            with open(self.sessions_json, "r", encoding="utf-8") as f:
                sessions = json.load(f)
            meta = sessions.get(self._session_key)
            if not isinstance(meta, dict):
                return None
            sid = meta.get("sessionId")
            if not sid:
                return None
            p = os.path.join(self.sessions_dir, f"{sid}.jsonl")
            return p if os.path.exists(p) else None
        except (OSError, ValueError, json.JSONDecodeError):
            return None

    def recent_turns(self, limit: int = 6) -> list[dict]:
        path = self._current_jsonl()
        if not path:
            return []
        turns: list[dict] = []
        try:
            with open(path, "r", encoding="utf-8") as f:
                for line in f:
                    try:
                        obj = json.loads(line)
                    except (ValueError, json.JSONDecodeError):
                        continue
                    if obj.get("type") != "message":
                        continue
                    msg = obj.get("message") or {}
                    role = msg.get("role")
                    if role not in ("user", "assistant"):
                        continue
                    text = self._extract_text(msg.get("content"))
                    if text:
                        turns.append({"role": role, "content": text})
        except OSError:
            return []
        return turns[-limit:]

    @staticmethod
    def _extract_text(content) -> str:
        """OpenClaw content 可能是字符串或 [{type:text,text:...}] 块数组。"""
        if isinstance(content, str):
            return content.strip()
        if isinstance(content, list):
            parts = [
                b.get("text", "")
                for b in content
                if isinstance(b, dict) and b.get("type") == "text"
            ]
            return " ".join(p for p in parts if p).strip()
        return ""

    def search_memory(self, query: str, limit: int = 5) -> list[str]:
        conn = _connect_ro(self.memory_db)
        if conn is None:
            return []
        try:
            match = _fts_query(query)
            if match:
                try:
                    rows = conn.execute(
                        "SELECT text FROM chunks_fts WHERE chunks_fts MATCH ? "
                        "ORDER BY rank LIMIT ?",
                        (match, limit),
                    ).fetchall()
                    if rows:
                        return [r[0][:300] for r in rows if r[0]]
                except sqlite3.Error:
                    pass  # FTS 不可用 → 落到 LIKE
            # LIKE 兜底：用最长的一个关键词
            tokens = sorted(re.findall(r"[\w一-鿿]{2,}", query or ""),
                            key=len, reverse=True)
            if not tokens:
                return []
            rows = conn.execute(
                "SELECT text FROM chunks WHERE text LIKE ? LIMIT ?",
                (f"%{tokens[0]}%", limit),
            ).fetchall()
            return [r[0][:300] for r in rows if r[0]]
        except sqlite3.Error:
            return []
        finally:
            conn.close()

    def user_profile(self, limit_chars: int = 600) -> str:
        try:
            with open(self.user_md, "r", encoding="utf-8") as f:
                return f.read().strip()[:limit_chars]
        except OSError:
            return ""


# ── 工厂 ─────────────────────────────────────────────────────────────

def get_history_reader(engine: str, agent_id: str) -> IHistoryReader | None:
    """按引擎返回对应 reader；未知引擎返回 None（快路径退化为无上下文）。"""
    eng = (engine or "").strip().lower()
    if eng == "hermes":
        return HermesHistoryReader(agent_id)
    if eng == "openclaw":
        return OpenClawHistoryReader(agent_id)
    return None
