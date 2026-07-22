#!/usr/bin/env python3
"""Cross-platform OS credential storage for model API keys.

macOS uses Keychain and Windows uses Credential Manager through ``keyring``.
The model table stores only the account identifier, never an encrypted secret.
"""

from __future__ import annotations

import sys


SERVICE_NAME = "assistant-x-openclaw.models"
ACCOUNT_PREFIX = "model:"


class CredentialStoreError(RuntimeError):
    pass


def _backend():
    try:
        import keyring
        from keyring.errors import KeyringError, NoKeyringError
    except ImportError as exc:
        raise CredentialStoreError(
            "缺少 keyring 依赖；请先安装 requirements.txt"
        ) from exc

    backend = keyring.get_keyring()
    priority = getattr(backend, "priority", 0)
    if sys.platform in {"darwin", "win32"} and priority <= 0:
        raise CredentialStoreError(
            "系统凭据库不可用；macOS 需要 Keychain，Windows 需要 Credential Manager"
        )
    return keyring, (KeyringError, NoKeyringError)


def credential_id(entry_id: str) -> str:
    entry_id = str(entry_id or "").strip()
    if not entry_id:
        raise CredentialStoreError("模型 ID 不能为空")
    return f"{ACCOUNT_PREFIX}{entry_id}"


def set_secret(account: str, secret: str) -> None:
    if not account or not secret:
        raise CredentialStoreError("凭据标识和密钥不能为空")
    keyring, errors = _backend()
    try:
        keyring.set_password(SERVICE_NAME, account, secret)
    except errors as exc:
        raise CredentialStoreError(f"写入系统凭据库失败: {exc}") from exc


def get_secret(account: str) -> str | None:
    if not account:
        return None
    keyring, errors = _backend()
    try:
        return keyring.get_password(SERVICE_NAME, account)
    except errors as exc:
        raise CredentialStoreError(f"读取系统凭据库失败: {exc}") from exc


def delete_secret(account: str) -> None:
    if not account:
        return
    keyring, errors = _backend()
    try:
        keyring.delete_password(SERVICE_NAME, account)
    except errors as exc:
        # Deleting an already-missing credential is harmless across backends.
        if exc.__class__.__name__ != "PasswordDeleteError":
            raise CredentialStoreError(f"删除系统凭据失败: {exc}") from exc
