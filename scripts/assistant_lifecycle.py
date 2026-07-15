#!/usr/bin/env python3
"""Structured lifecycle actions for external Agent engines.

This CLI intentionally accepts only a small fixed action set.  It is the
OpenClaw/Hermes counterpart of Edwin's built-in lifecycle tools and must not
grow into an arbitrary shell-command wrapper.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from local_api_auth import post_local_api

MAX_DELAY_SECONDS = 300.0


def _emit(payload: dict, *, stream=sys.stdout) -> None:
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), file=stream)


def _run(argv: list[str], *, timeout: float = 10.0) -> None:
    subprocess.run(
        argv,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
        check=True,
    )


def display_sleep() -> dict:
    if sys.platform != "darwin":
        raise RuntimeError(f"display-sleep is unsupported on {platform.system()}")
    _run(["/usr/bin/pmset", "displaysleepnow"])
    return {"ok": True, "action": "display-sleep"}


def lock_screen() -> dict:
    if sys.platform == "darwin":
        session = Path(
            "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
        )
        if session.is_file():
            _run([str(session), "-suspend"])
        else:
            _run([
                "/usr/bin/osascript",
                "-e",
                'tell application "System Events" to keystroke "q" using {control down, command down}',
            ])
        return {"ok": True, "action": "lock-screen"}
    if os.name == "nt":
        import ctypes

        if not ctypes.windll.user32.LockWorkStation():
            raise RuntimeError("Windows refused the lock request")
        return {"ok": True, "action": "lock-screen"}
    raise RuntimeError(f"lock-screen is unsupported on {platform.system()}")


def stand_down(delay_seconds: float) -> dict:
    delay = float(delay_seconds)
    if not 0 <= delay <= MAX_DELAY_SECONDS:
        raise ValueError(f"delay-seconds must be between 0 and {MAX_DELAY_SECONDS:g}")
    if delay:
        time.sleep(delay)
    with post_local_api("exit", timeout=5) as response:
        raw = response.read().decode("utf-8", errors="replace")
    try:
        result = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise RuntimeError("voice assistant returned an invalid response") from exc
    if result.get("status") != "ok":
        raise RuntimeError("voice assistant did not accept the standby request")
    return {"ok": True, "action": "stand-down", "delay_seconds": delay}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run a fixed voice-assistant lifecycle action")
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("display-sleep", help="turn off the current macOS display")
    sub.add_parser("lock-screen", help="lock the current desktop session")
    stand_down_parser = sub.add_parser("stand-down", help="put the voice assistant into standby")
    stand_down_parser.add_argument("--delay-seconds", type=float, default=0.0)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.action == "display-sleep":
            result = display_sleep()
        elif args.action == "lock-screen":
            result = lock_screen()
        else:
            result = stand_down(args.delay_seconds)
    except (OSError, subprocess.SubprocessError, RuntimeError, ValueError) as exc:
        _emit({"ok": False, "action": args.action, "error": str(exc)}, stream=sys.stderr)
        return 1
    _emit(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
