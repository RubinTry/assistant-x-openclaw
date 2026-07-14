from __future__ import annotations

import json
import os
import sqlite3
import threading
import time
import uuid
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DB = _ROOT / "data" / "edwin" / "edwin.db"
SCHEMA_VERSION = 1


class EdwinMemoryStore:
    def __init__(self, path: str | os.PathLike = DEFAULT_DB, idle_gap: int = 1800):
        self.path = Path(path)
        self.idle_gap = idle_gap
        self._lock = threading.RLock()
        self._sessions: dict[str, tuple[str, float]] = {}
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._migrate()

    def _connect(self):
        conn = sqlite3.connect(self.path, timeout=5)
        conn.row_factory = sqlite3.Row
        return conn

    def _migrate(self):
        with self._lock, self._connect() as db:
            version = db.execute("PRAGMA user_version").fetchone()[0]
            if version > SCHEMA_VERSION:
                raise RuntimeError(f"Edwin database schema {version} is newer than supported {SCHEMA_VERSION}")
            if version < 1:
                db.executescript("""
                CREATE TABLE sessions(id TEXT PRIMARY KEY, assistant_id TEXT NOT NULL, created_at REAL NOT NULL, last_activity REAL NOT NULL, active INTEGER NOT NULL DEFAULT 1);
                CREATE INDEX sessions_agent_time ON sessions(assistant_id,last_activity DESC);
                CREATE TABLE messages(id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL, request_id TEXT, role TEXT NOT NULL, content TEXT NOT NULL, created_at REAL NOT NULL, active INTEGER NOT NULL DEFAULT 1);
                CREATE INDEX messages_session_time ON messages(session_id,created_at);
                CREATE TABLE tool_runs(id INTEGER PRIMARY KEY AUTOINCREMENT, request_id TEXT, tool_call_id TEXT, tool_name TEXT, arguments_json TEXT, risk_level TEXT, ok INTEGER, result TEXT, approval_status TEXT, duration_ms INTEGER, created_at REAL NOT NULL);
                CREATE TABLE memories(id INTEGER PRIMARY KEY AUTOINCREMENT, assistant_id TEXT NOT NULL, content TEXT NOT NULL, source TEXT NOT NULL, created_at REAL NOT NULL, updated_at REAL NOT NULL);
                CREATE VIRTUAL TABLE memories_fts USING fts5(content, content='memories', content_rowid='id');
                CREATE TRIGGER memories_ai AFTER INSERT ON memories BEGIN INSERT INTO memories_fts(rowid,content) VALUES(new.id,new.content); END;
                CREATE TRIGGER memories_ad AFTER DELETE ON memories BEGIN INSERT INTO memories_fts(memories_fts,rowid,content) VALUES('delete',old.id,old.content); END;
                CREATE TABLE approvals(id INTEGER PRIMARY KEY AUTOINCREMENT, request_id TEXT, tool_call_id TEXT, digest TEXT, status TEXT, created_at REAL NOT NULL, resolved_at REAL);
                PRAGMA user_version=1;
                """)

    def session(self, assistant_id: str) -> str:
        now = time.time()
        with self._lock:
            cached = self._sessions.get(assistant_id)
            if cached and now - cached[1] <= self.idle_gap:
                sid = cached[0]
            else:
                with self._connect() as db:
                    # Runtime/Bridge instances may be reconstructed on wake or
                    # after a process restart. Recover continuity from SQLite
                    # instead of treating the empty in-memory cache as a new
                    # conversation.
                    row = db.execute(
                        "SELECT id,last_activity FROM sessions "
                        "WHERE assistant_id=? AND active=1 "
                        "ORDER BY last_activity DESC LIMIT 1",
                        (assistant_id,),
                    ).fetchone()
                    if row and now - float(row["last_activity"]) <= self.idle_gap:
                        sid = row["id"]
                    else:
                        sid = f"edwin-{assistant_id}-{uuid.uuid4().hex[:12]}"
                        db.execute("INSERT INTO sessions VALUES(?,?,?,?,1)", (sid, assistant_id, now, now))
            self._sessions[assistant_id] = (sid, now)
            with self._connect() as db:
                db.execute("UPDATE sessions SET last_activity=? WHERE id=?", (now, sid))
            return sid

    def add_message(self, session_id, request_id, role, content):
        if not content:
            return
        now = time.time()
        with self._lock, self._connect() as db:
            db.execute("INSERT INTO messages(session_id,request_id,role,content,created_at) VALUES(?,?,?,?,?)", (session_id, request_id, role, content, now))
            db.execute("UPDATE sessions SET last_activity=? WHERE id=?", (now, session_id))
            row = db.execute("SELECT assistant_id FROM sessions WHERE id=?", (session_id,)).fetchone()
            if row:
                # Match Hermes' request-finish touch: a long-running turn starts
                # and ends in the same session, and the 30-minute idle clock
                # begins only after its latest persisted activity.
                self._sessions[row["assistant_id"]] = (session_id, now)

    def recent(self, assistant_id: str, limit=12):
        sid = self.session(assistant_id)
        with self._connect() as db:
            rows = db.execute("SELECT role,content FROM messages WHERE session_id=? AND active=1 AND role IN ('user','assistant') ORDER BY created_at DESC LIMIT ?", (sid, limit)).fetchall()
        return [dict(r) for r in reversed(rows)]

    def clear(self, assistant_id: str):
        sid = self.session(assistant_id)
        with self._lock, self._connect() as db:
            db.execute("UPDATE messages SET active=0 WHERE session_id=?", (sid,))
            db.execute("UPDATE sessions SET active=0 WHERE id=?", (sid,))
        self._sessions.pop(assistant_id, None)

    def add_memory(self, assistant_id: str, content: str, source="explicit_user"):
        now = time.time()
        with self._connect() as db:
            db.execute("INSERT INTO memories(assistant_id,content,source,created_at,updated_at) VALUES(?,?,?,?,?)", (assistant_id, content[:2000], source, now, now))

    def search(self, assistant_id: str, query: str, limit=5):
        tokens = [x for x in query.replace('"', " ").split() if len(x) >= 2][:5]
        if not tokens:
            return []
        match = " OR ".join(f'"{x}"' for x in tokens)
        try:
            with self._connect() as db:
                rows = db.execute("SELECT m.content FROM memories_fts f JOIN memories m ON m.id=f.rowid WHERE f.memories_fts MATCH ? AND m.assistant_id=? LIMIT ?", (match, assistant_id, limit)).fetchall()
            return [r[0] for r in rows]
        except sqlite3.Error:
            return []

    def record_tool(self, request_id, call_id, name, args, risk, result, approval, duration_ms):
        with self._connect() as db:
            db.execute("INSERT INTO tool_runs(request_id,tool_call_id,tool_name,arguments_json,risk_level,ok,result,approval_status,duration_ms,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)", (request_id, call_id, name, json.dumps(args, ensure_ascii=False), risk, int(result.ok), (result.content or result.error)[:4000], approval, duration_ms, time.time()))

    def record_approval(self, request_id, call_id, digest, status):
        now = time.time()
        with self._connect() as db:
            db.execute("INSERT INTO approvals(request_id,tool_call_id,digest,status,created_at,resolved_at) VALUES(?,?,?,?,?,?)", (request_id, call_id, digest, status, now, now if status != "pending" else None))
