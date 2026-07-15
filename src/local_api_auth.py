"""Authentication for the project-owned loopback control API."""

from __future__ import annotations

import atexit
import hmac
import json
import os
import secrets
from pathlib import Path
from urllib.request import Request, urlopen

_ROOT = Path(__file__).resolve().parents[1]
RUNTIME_DIR = _ROOT / "data" / "runtime"
TOKEN_PATH = RUNTIME_DIR / "local_api.token"
HEADER_NAME = "X-Assistant-Token"
_active_token = ""


def _private_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    if os.name != "nt":
        path.chmod(0o700)


def rotate_runtime_token() -> str:
    """Create a new owner-only token before the HTTP server starts."""
    global _active_token
    _private_dir(RUNTIME_DIR)
    token = secrets.token_urlsafe(32)
    tmp = TOKEN_PATH.with_name(f".{TOKEN_PATH.name}.{os.getpid()}.tmp")
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    fd = os.open(tmp, flags, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="ascii") as stream:
            stream.write(token)
            stream.write("\n")
        os.replace(tmp, TOKEN_PATH)
        if os.name != "nt":
            TOKEN_PATH.chmod(0o600)
    finally:
        try:
            tmp.unlink()
        except FileNotFoundError:
            pass
    _active_token = token
    return token


def load_runtime_token() -> str:
    try:
        if TOKEN_PATH.is_symlink():
            return ""
        return TOKEN_PATH.read_text(encoding="ascii").strip()
    except OSError:
        return ""


def authorize_request(handler) -> bool:
    """Reject unauthenticated or browser-originated state-changing requests."""
    host = (handler.headers.get("Host") or "").split(":", 1)[0].strip("[]").lower()
    if host not in {"127.0.0.1", "localhost", "::1"}:
        _reject(handler, 403, "invalid host")
        return False
    if handler.headers.get("Origin"):
        _reject(handler, 403, "browser-originated requests are not allowed")
        return False
    supplied = handler.headers.get(HEADER_NAME) or ""
    if not _active_token or not hmac.compare_digest(supplied, _active_token):
        _reject(handler, 401, "authentication required")
        return False
    return True


def _reject(handler, status: int, message: str) -> None:
    payload = json.dumps({"error": message}, separators=(",", ":")).encode()
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(payload)))
    handler.end_headers()
    handler.wfile.write(payload)


def post_local_api(path: str, *, timeout: float = 5.0):
    token = load_runtime_token()
    if not token:
        raise RuntimeError("voice assistant authentication token is unavailable")
    request = Request(
        f"http://127.0.0.1:18790/{path.lstrip('/')}",
        method="POST",
        headers={HEADER_NAME: token},
    )
    return urlopen(request, timeout=timeout)


def _cleanup_own_token() -> None:
    if not _active_token:
        return
    try:
        if hmac.compare_digest(load_runtime_token(), _active_token):
            TOKEN_PATH.unlink()
    except OSError:
        pass


atexit.register(_cleanup_own_token)
