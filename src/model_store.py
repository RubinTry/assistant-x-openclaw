#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
模型表存储（快路径直连模型的配置源）。

设计要点：
  - 单一 JSON 文件存在项目根目录 model_table.json，只经本模块读写，
    用户不直接编辑——写入统一由 Control Center 通过后端 18790 端点触发。
  - provider 按 OpenAI 标准描述：base_url + model + api_key（走 /v1/chat/completions）。
  - api_key 加密落盘（Fernet / AES-128-CBC + HMAC），用时才解密；
    加解密全部在 Python 后端一侧完成，Control Center 只传明文到本地回环端口，
    避免 Dart/Python 跨语言加密互通。
  - master key 存在 data/.model_key（0600，gitignore），随机生成一次后长期复用。
  - 对外读取（供 UI 展示）一律掩码 api_key，绝不回传明文；
    仅 get_current_decrypted() 在进程内为 LLM 调用解出明文。

表结构：
  {
    "version": 1,
    "current": "<entry id>",          # 指定当前使用哪条
    "models": [
      {
        "id": "deepseek-chat",
        "label": "DeepSeek Chat",
        "provider": "deepseek",       # 展示用标签
        "base_url": "https://api.deepseek.com/v1",
        "model": "deepseek-chat",
        "api_key_enc": "<fernet token>",
        "created_at": "...", "updated_at": "..."
      }
    ]
  }
"""

import json
import os
import tempfile
import threading
import uuid
from datetime import datetime, timezone

from cryptography.fernet import Fernet, InvalidToken

_PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL_TABLE_PATH = os.path.join(_PROJECT_DIR, "model_table.json")
_KEY_PATH = os.path.join(_PROJECT_DIR, "data", ".model_key")

_TABLE_VERSION = 1
_lock = threading.RLock()
_fernet = None


# ── 加密密钥 ─────────────────────────────────────────────────────────

def _get_fernet() -> Fernet:
    """加载或首次生成 master key（0600），返回 Fernet 实例（进程内缓存）。"""
    global _fernet
    if _fernet is not None:
        return _fernet
    with _lock:
        if _fernet is not None:
            return _fernet
        os.makedirs(os.path.dirname(_KEY_PATH), exist_ok=True)
        if os.path.exists(_KEY_PATH):
            key = open(_KEY_PATH, "rb").read().strip()
        else:
            key = Fernet.generate_key()
            # 原子写 + 0600，避免半截密钥或组内可读
            fd = os.open(_KEY_PATH, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            try:
                os.write(fd, key)
            finally:
                os.close(fd)
            try:
                os.chmod(_KEY_PATH, 0o600)
            except OSError:
                pass
        _fernet = Fernet(key)
        return _fernet


def _encrypt(plaintext: str) -> str:
    return _get_fernet().encrypt(plaintext.encode("utf-8")).decode("ascii")


def _decrypt(token: str) -> str:
    return _get_fernet().decrypt(token.encode("ascii")).decode("utf-8")


def _mask(plaintext: str) -> str:
    """掩码展示：保留尾 4 位，其余打码；短串全打码。"""
    if not plaintext:
        return ""
    if len(plaintext) <= 4:
        return "•" * len(plaintext)
    return "•" * min(len(plaintext) - 4, 12) + plaintext[-4:]


# ── 读写 ─────────────────────────────────────────────────────────────

def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _empty_table() -> dict:
    return {"version": _TABLE_VERSION, "current": None, "models": []}


def _load() -> dict:
    """读原始表（含 api_key_enc）；文件缺失/损坏返回空表。"""
    if not os.path.exists(MODEL_TABLE_PATH):
        return _empty_table()
    try:
        with open(MODEL_TABLE_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return _empty_table()
    if not isinstance(data, dict):
        return _empty_table()
    data.setdefault("version", _TABLE_VERSION)
    data.setdefault("current", None)
    if not isinstance(data.get("models"), list):
        data["models"] = []
    return data


def _save(data: dict) -> None:
    """原子写：临时文件 + rename，避免读到半截 JSON。"""
    os.makedirs(os.path.dirname(MODEL_TABLE_PATH), exist_ok=True)
    fd, tmp = tempfile.mkstemp(
        dir=os.path.dirname(MODEL_TABLE_PATH), prefix=".model_table.", suffix=".tmp"
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        os.replace(tmp, MODEL_TABLE_PATH)
    finally:
        if os.path.exists(tmp):
            try:
                os.remove(tmp)
            except OSError:
                pass


def _public_entry(entry: dict) -> dict:
    """对外视图：不含 api_key_enc，api_key 字段给掩码串。"""
    out = {k: v for k, v in entry.items() if k != "api_key_enc"}
    try:
        out["api_key"] = _mask(_decrypt(entry.get("api_key_enc", "")))
    except (InvalidToken, ValueError, TypeError):
        out["api_key"] = ""
    out["api_key_set"] = bool(entry.get("api_key_enc"))
    return out


# ── 对外 API ─────────────────────────────────────────────────────────

def list_models() -> dict:
    """供 UI 展示：所有条目（api_key 掩码）+ current。绝不回传明文 key。"""
    with _lock:
        data = _load()
        return {
            "version": data.get("version", _TABLE_VERSION),
            "current": data.get("current"),
            "models": [_public_entry(e) for e in data.get("models", [])],
        }


def upsert_model(entry: dict) -> dict:
    """新增/更新一条模型。

    必填（OpenAI 标准）：base_url、model。api_key 新增时必填；
    更新时留空表示保持原 key 不变。id 缺省时按 label / uuid 生成。
    返回该条目的对外视图（掩码）。
    """
    if not isinstance(entry, dict):
        raise ValueError("entry 必须是对象")
    base_url = (entry.get("base_url") or "").strip()
    model = (entry.get("model") or "").strip()
    if not base_url or not model:
        raise ValueError("base_url 与 model 为必填")

    entry_id = (entry.get("id") or "").strip()
    label = (entry.get("label") or "").strip() or model
    provider = (entry.get("provider") or "").strip()
    api_key = entry.get("api_key")

    with _lock:
        data = _load()
        models = data["models"]
        if not entry_id:
            entry_id = _slug(label) or uuid.uuid4().hex[:8]
        existing = next((e for e in models if e.get("id") == entry_id), None)

        if existing is None:
            if not api_key:
                raise ValueError("新增模型必须提供 api_key")
            record = {
                "id": entry_id,
                "label": label,
                "provider": provider,
                "base_url": base_url,
                "model": model,
                "api_key_enc": _encrypt(str(api_key)),
                "created_at": _now(),
                "updated_at": _now(),
            }
            models.append(record)
        else:
            existing.update({
                "label": label,
                "provider": provider,
                "base_url": base_url,
                "model": model,
                "updated_at": _now(),
            })
            # api_key 留空 = 保持原值不变；非空 = 重新加密覆盖
            if api_key:
                existing["api_key_enc"] = _encrypt(str(api_key))
            record = existing

        # 首条自动设为 current
        if not data.get("current"):
            data["current"] = entry_id
        _save(data)
        return _public_entry(record)


def delete_model(entry_id: str) -> dict:
    with _lock:
        data = _load()
        before = len(data["models"])
        data["models"] = [e for e in data["models"] if e.get("id") != entry_id]
        if len(data["models"]) == before:
            raise KeyError(f"模型 {entry_id} 不存在")
        # 删掉的正好是 current → 回退到第一条（或 None）
        if data.get("current") == entry_id:
            data["current"] = data["models"][0]["id"] if data["models"] else None
        _save(data)
        return list_models()


def set_current(entry_id: str) -> dict:
    with _lock:
        data = _load()
        if not any(e.get("id") == entry_id for e in data["models"]):
            raise KeyError(f"模型 {entry_id} 不存在")
        data["current"] = entry_id
        _save(data)
        return list_models()


def get_current_decrypted() -> dict | None:
    """进程内使用：返回 current 条目并解出明文 api_key（供 LLM 调用）。

    返回 {id,label,provider,base_url,model,api_key} 或 None（未配置/解密失败）。
    这是唯一解出明文的入口，绝不经由任何对外端点暴露。
    """
    with _lock:
        data = _load()
        cur = data.get("current")
        if not cur:
            return None
        entry = next((e for e in data["models"] if e.get("id") == cur), None)
        if entry is None:
            return None
        try:
            api_key = _decrypt(entry.get("api_key_enc", ""))
        except (InvalidToken, ValueError, TypeError):
            return None
        return {
            "id": entry.get("id"),
            "label": entry.get("label"),
            "provider": entry.get("provider"),
            "base_url": entry.get("base_url"),
            "model": entry.get("model"),
            "api_key": api_key,
        }


def _slug(text: str) -> str:
    keep = []
    for ch in text.lower().strip():
        if ch.isalnum():
            keep.append(ch)
        elif ch in " -_":
            keep.append("-")
    slug = "".join(keep).strip("-")
    while "--" in slug:
        slug = slug.replace("--", "-")
    return slug[:40]
