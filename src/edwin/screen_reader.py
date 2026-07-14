from __future__ import annotations

import os
import platform
import tempfile

from edwin.tools.base import ToolResult


def _request_macos_screen_permission() -> bool:
    """Use CoreGraphics to preflight and actively request Screen Recording."""
    try:
        import Quartz
        if Quartz.CGPreflightScreenCaptureAccess():
            return True
        Quartz.CGRequestScreenCaptureAccess()
        return bool(Quartz.CGPreflightScreenCaptureAccess())
    except (ImportError, AttributeError):
        return False


def _vision_ocr(path: str) -> list[str]:
    import Vision
    from Foundation import NSURL

    request = Vision.VNRecognizeTextRequest.alloc().init()
    request.setRecognitionLevel_(Vision.VNRequestTextRecognitionLevelAccurate)
    request.setUsesLanguageCorrection_(True)
    try:
        request.setRecognitionLanguages_(["zh-Hans", "en-US"])
    except Exception:
        pass
    handler = Vision.VNImageRequestHandler.alloc().initWithURL_options_(
        NSURL.fileURLWithPath_(path), None
    )
    ok, error = handler.performRequests_error_([request], None)
    if not ok:
        raise RuntimeError(str(error or "Vision OCR failed"))
    rows = []
    for observation in request.results() or []:
        candidates = observation.topCandidates_(1)
        if candidates:
            text = str(candidates[0].string()).strip()
            if text:
                box = observation.boundingBox()
                nx = float(box.origin.x + box.size.width / 2)
                ny = float(1.0 - (box.origin.y + box.size.height / 2))
                rows.append(f"[x={nx:.3f},y={ny:.3f}] {text}")
    return rows


def read_screen(cancel) -> ToolResult:
    if platform.system() != "Darwin":
        return ToolResult(False, error="Built-in screen OCR is currently available on macOS")
    if cancel.is_set():
        return ToolResult(False, error="request cancelled")
    if not _request_macos_screen_permission():
        return ToolResult(
            False,
            error=(
                "Edwin initiated the macOS Screen Recording permission request. "
                "Approve the OS prompt, then retry the screen-reading request."
            ),
            metadata={"permission_requested": ["Screen Recording"]},
        )

    path = None
    try:
        from PIL import ImageGrab
        fd, path = tempfile.mkstemp(prefix="edwin-screen-", suffix=".png")
        os.close(fd)
        image = ImageGrab.grab(all_screens=True)
        image.save(path, format="PNG")
        if cancel.is_set():
            return ToolResult(False, error="request cancelled")
        rows = _vision_ocr(path)
        if not rows:
            return ToolResult(True, content="No readable text was detected on the screen.")
        return ToolResult(True, content="\n".join(rows)[:12000], metadata={"ocr_lines": len(rows)})
    except ImportError as exc:
        return ToolResult(False, error=f"Built-in screen dependency is missing: {exc}")
    except Exception as exc:
        return ToolResult(False, error=f"Screen reading failed: {exc}")
    finally:
        if path:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass


def click_screen(x: float, y: float, cancel) -> ToolResult:
    """Click normalized screen coordinates through CoreGraphics, no external CLI."""
    if platform.system() != "Darwin":
        return ToolResult(False, error="Built-in screen clicking is currently available on macOS")
    if cancel.is_set():
        return ToolResult(False, error="request cancelled")
    if not (0.0 <= x <= 1.0 and 0.0 <= y <= 1.0):
        return ToolResult(False, error="x and y must be normalized values between 0 and 1")
    try:
        import Quartz
        from ApplicationServices import AXIsProcessTrustedWithOptions, kAXTrustedCheckOptionPrompt
        if not AXIsProcessTrustedWithOptions({kAXTrustedCheckOptionPrompt: True}):
            return ToolResult(
                False,
                error=(
                    "Edwin initiated the macOS Accessibility permission request. "
                    "Approve the OS prompt, then retry the click."
                ),
                metadata={"permission_requested": ["Accessibility"]},
            )
        bounds = Quartz.CGDisplayBounds(Quartz.CGMainDisplayID())
        point = (bounds.origin.x + x * bounds.size.width, bounds.origin.y + y * bounds.size.height)
        for event_type, button in (
            (Quartz.kCGEventMouseMoved, Quartz.kCGMouseButtonLeft),
            (Quartz.kCGEventLeftMouseDown, Quartz.kCGMouseButtonLeft),
            (Quartz.kCGEventLeftMouseUp, Quartz.kCGMouseButtonLeft),
        ):
            event = Quartz.CGEventCreateMouseEvent(None, event_type, point, button)
            Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)
        return ToolResult(True, content=f"clicked screen at normalized ({x:.3f}, {y:.3f})")
    except ImportError as exc:
        return ToolResult(False, error=f"Built-in desktop dependency is missing: {exc}")
    except Exception as exc:
        return ToolResult(False, error=f"Screen click failed: {exc}")
