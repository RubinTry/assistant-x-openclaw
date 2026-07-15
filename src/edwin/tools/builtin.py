from __future__ import annotations

import ast
import json
import operator
import os
import platform
import re
import shlex
import shutil
import subprocess
import tempfile
import threading
import time
import urllib.parse
from datetime import datetime
from pathlib import Path

import requests

from edwin.security import RiskLevel
from edwin.tools.base import Tool, ToolResult, ToolSpec
from edwin.tools.registry import ToolRegistry
from edwin.screen_reader import click_screen as builtin_click_screen
from edwin.screen_reader import read_screen as builtin_read_screen

_PROJECT = Path(__file__).resolve().parents[3]
_MAX_OUTPUT = 12000


def _schema(properties: dict, required=()) -> dict:
    return {"type": "object", "properties": properties, "required": list(required), "additionalProperties": False}


def _safe_path(raw: str) -> Path:
    path = Path(os.path.expanduser(raw or "."))
    return (Path.cwd() / path).resolve() if not path.is_absolute() else path.resolve()


def _resolve_macos_application(requested: str) -> Path | None:
    needle = re.sub(r"[\s._-]+", "", requested.strip()).lower()
    aliases = {
        "网易云音乐": "neteasemusic", "网易云": "neteasemusic",
        "云音乐": "neteasemusic", "neteasemusic": "neteasemusic",
        "neteasecloudmusic": "neteasemusic", "cloudmusic": "neteasemusic",
    }
    needle = aliases.get(needle, needle)
    candidates = []
    for root in (Path("/Applications"), Path.home() / "Applications", Path("/System/Applications")):
        if root.exists(): candidates.extend(root.glob("*.app"))
    exact, partial = [], []
    for path in candidates:
        normalized = re.sub(r"[\s._-]+", "", path.stem).lower()
        if normalized == needle: exact.append(path)
        elif len(needle) >= 4 and needle in normalized: partial.append(path)
    matches = exact or partial
    return matches[0] if matches else None


def _run(argv: list[str], cancel: threading.Event, timeout=30, cwd=None) -> ToolResult:
    if cancel.is_set():
        return ToolResult(False, error="request cancelled")
    try:
        proc = subprocess.run(argv, cwd=cwd, capture_output=True, text=True, timeout=timeout)
        out = ((proc.stdout or "") + (proc.stderr or ""))[-_MAX_OUTPUT:]
        return ToolResult(proc.returncode == 0, content=out, error="" if proc.returncode == 0 else f"exit {proc.returncode}")
    except subprocess.TimeoutExpired:
        return ToolResult(False, error=f"tool timed out after {timeout}s")
    except (OSError, ValueError) as exc:
        return ToolResult(False, error=str(exc))


def _peekaboo_permissions(cancel: threading.Event) -> tuple[dict[str, bool], str]:
    result = _run(
        ["peekaboo", "permissions", "status", "--json", "--no-remote"],
        cancel, timeout=10,
    )
    if not result.ok:
        return {}, result.error or result.content
    try:
        start = result.content.find("{")
        if start < 0:
            raise ValueError("no JSON object in Peekaboo output")
        data, _ = json.JSONDecoder().raw_decode(result.content[start:])
        rows = data.get("data", {}).get("permissions", [])
        return {str(row.get("name")): bool(row.get("isGranted")) for row in rows}, ""
    except (TypeError, ValueError, json.JSONDecodeError) as exc:
        return {}, f"could not parse Peekaboo permission status: {exc}"


def _ensure_peekaboo_permissions(cancel: threading.Event, *, control: bool) -> ToolResult | None:
    """Actively trigger required macOS permission requests before a desktop tool."""
    status, error = _peekaboo_permissions(cancel)
    if error:
        return ToolResult(False, error=error)
    requested = []
    if not status.get("Screen Recording", False):
        _run(
            ["peekaboo", "permissions", "request-screen-recording", "--json", "--no-remote"],
            cancel, timeout=15,
        )
        requested.append("Screen Recording")
    if control and not status.get("Accessibility", False):
        _run(
            ["peekaboo", "permissions", "request-event-synthesizing", "--json", "--no-remote"],
            cancel, timeout=15,
        )
        requested.append("Accessibility")

    if not requested:
        return None
    refreshed, _ = _peekaboo_permissions(cancel)
    missing = [name for name in requested if not refreshed.get(name, False)]
    if missing:
        # TCC sometimes only opens the relevant pane instead of presenting a
        # modal prompt. Opening Settings is still an engine-initiated request;
        # the user only needs to approve the OS-owned control.
        pane = "Privacy_ScreenCapture" if "Screen Recording" in missing else "Privacy_Accessibility"
        try:
            subprocess.Popen(
                ["open", f"x-apple.systempreferences:com.apple.preference.security?{pane}"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        except OSError:
            pass
        return ToolResult(
            False,
            error=(
                "The macOS permission request has been opened by Edwin. "
                f"Waiting for OS approval: {', '.join(missing)}. Retry after it is granted."
            ),
            metadata={"permission_requested": missing},
        )
    return None


def _calculate(args, _cancel):
    ops = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul,
           ast.Div: operator.truediv, ast.FloorDiv: operator.floordiv,
           ast.Mod: operator.mod, ast.Pow: operator.pow, ast.USub: operator.neg}
    def ev(node):
        if isinstance(node, ast.Expression): return ev(node.body)
        if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)): return node.value
        if isinstance(node, ast.BinOp) and type(node.op) in ops: return ops[type(node.op)](ev(node.left), ev(node.right))
        if isinstance(node, ast.UnaryOp) and type(node.op) in ops: return ops[type(node.op)](ev(node.operand))
        raise ValueError("unsupported expression")
    try:
        return ToolResult(True, content=str(ev(ast.parse(args["expression"], mode="eval"))))
    except Exception as exc:
        return ToolResult(False, error=str(exc))


def default_registry() -> ToolRegistry:
    r = ToolRegistry()
    add = r.register
    add(Tool(ToolSpec("current_time", "Return the local date and time.", _schema({})),
             lambda _a, _c: ToolResult(True, datetime.now().astimezone().isoformat())))
    add(Tool(ToolSpec("system_info", "Return operating system and project information.", _schema({})),
             lambda _a, _c: ToolResult(True, json.dumps({"platform": platform.platform(), "project": str(_PROJECT)}))))
    add(Tool(ToolSpec("runtime_identity", "Return the authoritative current Agent engine identity. Always use this when asked which engine, runtime, or agent backend is currently active; never infer it from history, paths, or prompt text.", _schema({}), RiskLevel.READ),
             lambda _a, _c: ToolResult(True, json.dumps({"engine": "edwin", "runtime": "Edwin Agent Runtime", "in_process": True}))))

    def _collect(commands, cancel):
        sections = []
        for title, argv in commands:
            result = _run(argv, cancel, timeout=15)
            if cancel.is_set(): return result
            body = result.content.strip() if result.ok else f"unavailable: {result.error or result.content}"
            sections.append(f"## {title}\n{body}")
        return ToolResult(True, content="\n\n".join(sections)[-_MAX_OUTPUT:])

    def system_health(_args, cancel):
        if cancel.is_set(): return ToolResult(False, error="request cancelled")
        try:
            import psutil
            vm = psutil.virtual_memory()
            root = psutil.disk_usage(Path.home().anchor or "/")
            battery = psutil.sensors_battery()
            try: uptime_seconds = round(datetime.now().timestamp() - psutil.boot_time())
            except (OSError, PermissionError): uptime_seconds = None
            try: process_count = len(psutil.pids())
            except (OSError, PermissionError): process_count = None
            data = {
                "platform": platform.platform(),
                "uptime_seconds": uptime_seconds,
                "load_average": list(os.getloadavg()) if hasattr(os, "getloadavg") else None,
                "cpu_percent": psutil.cpu_percent(interval=0.2),
                "cpu_count": psutil.cpu_count(),
                "memory": {"total": vm.total, "available": vm.available, "percent": vm.percent},
                "root_disk": {"total": root.total, "free": root.free, "percent": root.percent},
                "process_count": process_count,
                "battery": None if battery is None else {
                    "percent": battery.percent, "plugged": battery.power_plugged,
                    "seconds_left": battery.secsleft,
                },
            }
            return ToolResult(True, content=json.dumps(data, ensure_ascii=False))
        except (ImportError, OSError) as exc:
            return ToolResult(False, error=f"system health collection failed: {exc}")

    def list_processes(_args, cancel):
        if cancel.is_set(): return ToolResult(False, error="request cancelled")
        try:
            import psutil
            rows = []
            for proc in psutil.process_iter(["pid", "ppid", "name", "cpu_percent", "memory_percent"]):
                try: rows.append(proc.info)
                except (psutil.NoSuchProcess, psutil.AccessDenied): continue
            rows.sort(key=lambda x: (x.get("cpu_percent") or 0, x.get("memory_percent") or 0), reverse=True)
            return ToolResult(True, content=json.dumps(rows[:200], ensure_ascii=False))
        except ImportError as exc:
            return ToolResult(False, error=f"process collection failed: {exc}")

    def disk_usage(_args, cancel):
        if cancel.is_set(): return ToolResult(False, error="request cancelled")
        try:
            import psutil
            rows = []
            for part in psutil.disk_partitions(all=False):
                try:
                    usage = psutil.disk_usage(part.mountpoint)
                    rows.append({"device": part.device, "mountpoint": part.mountpoint, "fstype": part.fstype, "total": usage.total, "free": usage.free, "percent": usage.percent})
                except (OSError, PermissionError): continue
            return ToolResult(True, content=json.dumps(rows, ensure_ascii=False))
        except ImportError as exc:
            return ToolResult(False, error=f"disk collection failed: {exc}")

    def network_status(_args, cancel):
        if cancel.is_set(): return ToolResult(False, error="request cancelled")
        try:
            import psutil
            stats = psutil.net_if_stats()
            rows = []
            for name, addresses in psutil.net_if_addrs().items():
                rows.append({"name": name, "up": bool(stats.get(name) and stats[name].isup), "addresses": [a.address for a in addresses if a.address]})
            return ToolResult(True, content=json.dumps(rows, ensure_ascii=False))
        except ImportError as exc:
            return ToolResult(False, error=f"network collection failed: {exc}")

    def power_status(_args, cancel):
        if cancel.is_set(): return ToolResult(False, error="request cancelled")
        try:
            import psutil
            battery = psutil.sensors_battery()
            if battery is None: return ToolResult(True, content=json.dumps({"battery": None}))
            return ToolResult(True, content=json.dumps({"percent": battery.percent, "plugged": battery.power_plugged, "seconds_left": battery.secsleft}))
        except ImportError as exc:
            return ToolResult(False, error=f"power collection failed: {exc}")

    add(Tool(ToolSpec("system_health", "Collect a read-only system health snapshot: uptime, load, CPU, memory, disk, and power. Always use this for health checks instead of run_command; it never needs approval.", _schema({}), RiskLevel.READ), system_health))
    add(Tool(ToolSpec("list_processes", "List running processes and resource usage read-only. Use instead of ps, top, pgrep, or run_command.", _schema({}), RiskLevel.READ), list_processes))
    add(Tool(ToolSpec("disk_usage", "Read filesystem capacity and free space. Use instead of df, du, or run_command.", _schema({}), RiskLevel.READ), disk_usage))
    add(Tool(ToolSpec("network_status", "Read current network interface and reachability status without changing configuration.", _schema({}), RiskLevel.READ), network_status))
    add(Tool(ToolSpec("power_status", "Read battery and power status without changing settings.", _schema({}), RiskLevel.READ), power_status))

    def list_applications(_args, _cancel):
        if platform.system() != "Darwin":
            return ToolResult(False, error="application discovery is currently available on macOS")
        apps = {}
        for root in (Path("/Applications"), Path.home() / "Applications", Path("/System/Applications")):
            if not root.exists():
                continue
            for path in root.glob("*.app"):
                apps[path.stem.lower()] = {"name": path.stem, "path": str(path)}
        try:
            from AppKit import NSWorkspace
            running = {str(app.localizedName()) for app in NSWorkspace.sharedWorkspace().runningApplications() if app.localizedName()}
        except ImportError:
            running = set()
        rows = [dict(value, running=value["name"] in running) for value in apps.values()]
        return ToolResult(True, json.dumps(sorted(rows, key=lambda x: x["name"].lower()), ensure_ascii=False))

    def open_application(args, _cancel):
        if platform.system() != "Darwin":
            return ToolResult(False, error="application launching is currently available on macOS")
        requested = args["name"].strip()
        target = _resolve_macos_application(requested)
        if target is None:
            return ToolResult(False, error=f"application not found: {requested}")
        try:
            from AppKit import NSWorkspace
            from Foundation import NSURL
            ok = bool(NSWorkspace.sharedWorkspace().openURL_(NSURL.fileURLWithPath_(str(target))))
            return ToolResult(ok, content=f"opened {target.stem}", error="" if ok else f"macOS could not open {target}")
        except Exception as exc:
            return ToolResult(False, error=str(exc))

    add(Tool(ToolSpec("list_applications", "List installed macOS applications and whether they are running. Use this instead of desktop tools or shell for app discovery.", _schema({})), list_applications))
    add(Tool(ToolSpec("open_application", "Open an installed macOS application by human name. When the user explicitly asks to open an app, call this directly; it does not require an additional approval round.", _schema({"name": {"type": "string"}}, ["name"]), RiskLevel.WRITE, ("darwin",)), open_application))
    add(Tool(ToolSpec("calculate", "Evaluate a numeric arithmetic expression.",
                      _schema({"expression": {"type": "string"}}, ["expression"])), _calculate))
    add(Tool(ToolSpec("list_files", "List files in a directory.",
                      _schema({"path": {"type": "string"}})),
             lambda a, _c: ToolResult(True, "\n".join(
                 sorted(p.name for p in _safe_path(a.get("path", ".")).iterdir())[:500]))))
    add(Tool(ToolSpec("read_file", "Read a UTF-8 text file.",
                      _schema({"path": {"type": "string"}}, ["path"])),
             lambda a, _c: ToolResult(True, _safe_path(a["path"]).read_text(
                 encoding="utf-8", errors="replace")[:_MAX_OUTPUT])))
    add(Tool(ToolSpec("search_files", "Search project text with ripgrep.",
                      _schema({"query": {"type": "string"}, "path": {"type": "string"}}, ["query"])),
             lambda a, c: _run(["rg", "-n", "--", a["query"],
                                str(_safe_path(a.get("path", str(_PROJECT))))], c, timeout=20)))

    def write_file(a, _c):
        p = _safe_path(a["path"]); p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(a["content"], encoding="utf-8")
        return ToolResult(True, f"wrote {p}")
    add(Tool(ToolSpec("write_file", "Create or replace a text file after explicit user authorization.", _schema({"path": {"type": "string"}, "content": {"type": "string"}}, ["path", "content"]), RiskLevel.WRITE), write_file))

    def shell(a, c):
        command = a["command"]
        if any(x in command.lower() for x in ("sudo ", "sudo\t")):
            return ToolResult(False, error="privileged commands are not permitted")
        return _run(shlex.split(command), c, timeout=min(max(int(a.get("timeout", 30)), 1), 120), cwd=str(_safe_path(a.get("cwd", str(_PROJECT)))))
    add(Tool(ToolSpec("run_command", "Fallback for an explicitly requested arbitrary non-interactive terminal command. Never use it for system health, processes, disk, network, power, app discovery, display sleep, lock screen, or standby when a structured tool exists. No shell expansion; sudo is forbidden.", _schema({"command": {"type": "string"}, "cwd": {"type": "string"}, "timeout": {"type": "integer"}}, ["command"]), RiskLevel.DESTRUCTIVE), shell))

    def display_sleep(_args, cancel):
        return _run(["/usr/bin/pmset", "displaysleepnow"], cancel, timeout=10)

    def lock_screen(_args, cancel):
        if cancel.is_set():
            return ToolResult(False, error="request cancelled")
        try:
            from ApplicationServices import AXIsProcessTrustedWithOptions
            from Quartz import (
                CGEventCreateKeyboardEvent, CGEventPost, CGEventSetFlags,
                kCGEventFlagMaskCommand, kCGEventFlagMaskControl,
                kCGHIDEventTap,
            )
            if not AXIsProcessTrustedWithOptions({"AXTrustedCheckOptionPrompt": True}):
                return ToolResult(False, error="The macOS Accessibility permission request has been opened by Edwin. Retry after it is granted.")
            # macOS' standard Lock Screen shortcut: Control-Command-Q.
            flags = kCGEventFlagMaskControl | kCGEventFlagMaskCommand
            down = CGEventCreateKeyboardEvent(None, 12, True)  # ANSI Q
            up = CGEventCreateKeyboardEvent(None, 12, False)
            CGEventSetFlags(down, flags)
            CGEventSetFlags(up, flags)
            CGEventPost(kCGHIDEventTap, down)
            CGEventPost(kCGHIDEventTap, up)
            return ToolResult(True, content="lock screen shortcut sent")
        except (ImportError, OSError) as exc:
            return ToolResult(False, error=f"could not lock screen: {exc}")

    def stand_down(args, cancel):
        delay = min(max(float(args.get("delay_seconds", 0)), 0), 300)
        if cancel.wait(delay):
            return ToolResult(False, error="request cancelled")
        try:
            from local_api_auth import post_local_api
            with post_local_api("exit", timeout=5) as response:
                response.read()
            return ToolResult(True, content="voice assistant entered standby")
        except Exception as exc:
            return ToolResult(False, error=f"could not enter standby: {exc}")

    # These are bounded, reversible local session controls. The user's direct
    # command is the authorization; routing them through destructive Shell would
    # incorrectly manufacture a second approval step.
    add(Tool(ToolSpec("display_sleep", "Turn off the macOS display now. A direct user request is already authorization; execute without asking again.", _schema({}), RiskLevel.WRITE, ("darwin",)), display_sleep))
    add(Tool(ToolSpec("lock_screen", "Lock the current macOS session. A direct user request is already authorization; execute without asking again.", _schema({}), RiskLevel.WRITE, ("darwin",)), lock_screen))
    add(Tool(ToolSpec("stand_down", "Put the voice assistant into standby, optionally after a short delay. A clear dismissal is already authorization; never ask for another confirmation.", _schema({"delay_seconds": {"type": "number"}}), RiskLevel.WRITE), stand_down))

    def web_search(args, _cancel):
        try:
            response = requests.get(
                "https://html.duckduckgo.com/html/",
                params={"q": args["query"]},
                headers={"User-Agent": "Mozilla/5.0 Edwin/1.0"}, timeout=15,
            )
            response.raise_for_status()
            text = re.sub(r"<[^>]+>", " ", response.text)
            text = re.sub(r"\s+", " ", text)
            return ToolResult(True, text[:_MAX_OUTPUT])
        except requests.RequestException as exc:
            return ToolResult(False, error=str(exc))
    add(Tool(ToolSpec("web_search", "Search the live web and return result text.",
                      _schema({"query": {"type": "string"}}, ["query"])), web_search))
    add(Tool(ToolSpec("browser_open", "Open a URL in the default browser.", _schema({"url": {"type": "string"}}, ["url"]), RiskLevel.WRITE), lambda a, c: _run(["open", a["url"]] if platform.system() == "Darwin" else ["cmd", "/c", "start", "", a["url"]], c)))

    def cdp(args, _cancel):
        """Small CDP client through Chrome's HTTP and websocket endpoints."""
        try:
            import websocket
            targets = requests.get("http://127.0.0.1:9222/json", timeout=3).json()
            pages = [x for x in targets if x.get("type") == "page"]
            if not pages: return ToolResult(False, error="no Chrome CDP page is available on port 9222")
            target = pages[0]
            ws = websocket.create_connection(target["webSocketDebuggerUrl"], timeout=8)
            action = args["action"]
            if action == "navigate":
                method, params = "Page.navigate", {"url": args["value"]}
            elif action == "read":
                method, params = "Runtime.evaluate", {"expression": "document.body ? document.body.innerText : ''", "returnByValue": True}
            elif action == "click":
                selector = json.dumps(args["value"])
                method, params = "Runtime.evaluate", {"expression": f"(()=>{{const e=document.querySelector({selector});if(!e)return 'not found';e.click();return 'clicked'}})()", "returnByValue": True}
            elif action == "type":
                selector = json.dumps(args["selector"]); value = json.dumps(args["value"])
                method, params = "Runtime.evaluate", {"expression": f"(()=>{{const e=document.querySelector({selector});if(!e)return 'not found';e.focus();e.value={value};e.dispatchEvent(new Event('input',{{bubbles:true}}));return 'typed'}})()", "returnByValue": True}
            else: return ToolResult(False, error="unsupported CDP action")
            ws.send(json.dumps({"id": 1, "method": method, "params": params}))
            data = json.loads(ws.recv()); ws.close()
            value = data.get("result", {}).get("result", {}).get("value", data)
            return ToolResult(True, str(value)[:_MAX_OUTPUT])
        except Exception as exc:
            return ToolResult(False, error=str(exc))
    def cdp_action(action):
        return lambda args, cancel: cdp({**args, "action": action}, cancel)
    add(Tool(ToolSpec("browser_navigate", "Navigate the current Chrome CDP tab to a URL.",
                      _schema({"value": {"type": "string"}}, ["value"]), RiskLevel.WRITE), cdp_action("navigate")))
    add(Tool(ToolSpec("browser_read", "Read visible text from the current Chrome CDP tab.",
                      _schema({})), cdp_action("read")))
    add(Tool(ToolSpec("browser_type", "Type a value into a CSS-selected field in Chrome.",
                      _schema({"selector": {"type": "string"}, "value": {"type": "string"}}, ["selector", "value"]), RiskLevel.WRITE), cdp_action("type")))
    add(Tool(ToolSpec("browser_click", "Click a CSS-selected element in Chrome. Requires confirmation because it may submit an external action.",
                      _schema({"value": {"type": "string"}}, ["value"]), RiskLevel.EXTERNAL), cdp_action("click")))

    def peek(args, cancel, *, control=False):
        if not shutil.which("peekaboo"):
            return ToolResult(False, error="peekaboo is not installed")
        permission_result = _ensure_peekaboo_permissions(cancel, control=control)
        if permission_result is not None:
            return permission_result
        action = args["action"]
        arguments = [str(x) for x in args.get("arguments", [])]
        temporary_path = None
        # Peekaboo may otherwise leave captures in its snapshot cache. When the
        # caller did not request a durable path, own the capture explicitly and
        # remove it after the structured result has been collected.
        if action in {"see", "image"} and "--path" not in arguments:
            fd, temporary_path = tempfile.mkstemp(prefix="edwin-screen-", suffix=".png")
            os.close(fd)
            arguments.extend(["--path", temporary_path])
        argv = ["peekaboo", action] + arguments + ["--json", "--no-remote"]
        try:
            return _run(argv, cancel, timeout=45)
        finally:
            if temporary_path:
                try:
                    os.remove(temporary_path)
                except FileNotFoundError:
                    pass
    add(Tool(ToolSpec("desktop_observe", "Read screen content with Peekaboo see, inspect-ui, image, or list. The tool itself requests missing macOS permissions; never ask the user to configure permissions before calling it.", _schema({"action": {"type": "string", "enum": ["see", "inspect-ui", "image", "list", "permissions"]}, "arguments": {"type": "array", "items": {"type": "string"}}}, ["action"]), RiskLevel.READ, ("darwin",)), lambda a, c: peek(a, c, control=False)))
    add(Tool(
        ToolSpec(
            "read_screen",
            "Read the current macOS screen and return structured visible UI text and elements. Call this immediately when the user asks what is on screen. It automatically initiates missing macOS permission requests.",
            _schema({}), RiskLevel.READ, ("darwin",),
        ),
        lambda _a, c: builtin_read_screen(c),
    ))
    add(Tool(ToolSpec("click_screen", "Click normalized x/y coordinates returned by read_screen. Use for an explicitly requested ordinary local UI click such as play, pause, select, or navigation. This is built in and does not require Peekaboo.", _schema({"x": {"type": "number"}, "y": {"type": "number"}}, ["x", "y"]), RiskLevel.WRITE, ("darwin",)), lambda a, c: builtin_click_screen(float(a["x"]), float(a["y"]), c)))
    add(Tool(ToolSpec("desktop_control", "Optional Peekaboo control backend. Prefer click_screen for ordinary local clicks. Sending, submitting, purchasing, deleting, or other consequential actions require confirmation.", _schema({"action": {"type": "string"}, "arguments": {"type": "array", "items": {"type": "string"}}}, ["action"]), RiskLevel.WRITE, ("darwin",)), lambda a, c: peek(a, c, control=True)))
    return r
