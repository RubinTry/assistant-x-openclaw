"""Cross-platform system-audio reference capture contract.

Native helpers must write 48 kHz mono little-endian float32 PCM to stdout in
10 ms (480-sample) frames and write a single ``ready`` line to stderr after
capture starts.  Platform implementations therefore stay outside the AEC
algorithm; adding Windows only requires a helper that follows this protocol.
"""

from __future__ import annotations

import os
import subprocess
import sys
import threading
from abc import ABC, abstractmethod
from collections.abc import Callable, Sequence
from pathlib import Path

import numpy as np

ReferenceFrameCallback = Callable[[np.ndarray], None]
StatusCallback = Callable[[str], None]


class SystemAudioReferenceProvider(ABC):
    """Standard interface implemented by every platform reference source."""

    sample_rate = 48_000
    channels = 1
    frame_samples = 480
    sample_dtype = np.dtype("<f4")

    @property
    @abstractmethod
    def name(self) -> str:
        """Stable provider name used in logs and diagnostics."""

    @property
    @abstractmethod
    def healthy(self) -> bool:
        """Whether reference frames can currently be consumed."""

    @abstractmethod
    def start(
        self,
        on_frame: ReferenceFrameCallback,
        on_status: StatusCallback | None = None,
    ) -> None:
        """Start capture and deliver exact 10 ms float32 frames."""

    @abstractmethod
    def close(self) -> None:
        """Stop capture and release platform resources. Must be idempotent."""


class SubprocessSystemAudioReferenceProvider(SystemAudioReferenceProvider):
    """Reference provider backed by a native helper using the shared protocol."""

    def __init__(self, name: str, command: Sequence[str]):
        if not command:
            raise ValueError("system audio helper command is empty")
        executable = os.path.abspath(os.fspath(command[0]))
        if not os.path.isfile(executable) or not os.access(executable, os.X_OK):
            raise RuntimeError(f"system audio helper 不存在或不可执行: {executable}")
        self._name = str(name)
        self._command = [executable, *(os.fspath(arg) for arg in command[1:])]
        self._process: subprocess.Popen[bytes] | None = None
        self._reader: threading.Thread | None = None
        self._stderr_reader: threading.Thread | None = None
        self._on_status: StatusCallback | None = None
        self._healthy = False
        self._closed = False

    @property
    def name(self) -> str:
        return self._name

    @property
    def healthy(self) -> bool:
        process = self._process
        return (
            self._healthy
            and process is not None
            and process.poll() is None
            and not self._closed
        )

    def start(
        self,
        on_frame: ReferenceFrameCallback,
        on_status: StatusCallback | None = None,
    ) -> None:
        if self._process is not None:
            raise RuntimeError(f"{self.name} reference provider already started")
        if self._closed:
            raise RuntimeError(f"{self.name} reference provider is closed")
        self._on_status = on_status
        self._process = subprocess.Popen(
            self._command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            bufsize=0,
        )
        self._reader = threading.Thread(
            target=self._read_frames, args=(on_frame,), daemon=True
        )
        self._stderr_reader = threading.Thread(
            target=self._read_status, args=(on_status,), daemon=True
        )
        self._reader.start()
        self._stderr_reader.start()

    def _read_frames(self, on_frame: ReferenceFrameCallback) -> None:
        assert self._process is not None and self._process.stdout is not None
        frame_bytes = self.frame_samples * self.sample_dtype.itemsize
        pending = bytearray()
        while not self._closed:
            chunk = self._process.stdout.read(4096)
            if not chunk:
                break
            pending.extend(chunk)
            while len(pending) >= frame_bytes:
                frame = np.frombuffer(
                    bytes(pending[:frame_bytes]),
                    dtype=self.sample_dtype,
                    count=self.frame_samples,
                ).copy()
                del pending[:frame_bytes]
                try:
                    on_frame(frame)
                except Exception as exc:
                    self._emit_status(f"frame callback failed: {exc}")
                    self._healthy = False
                    return
        self._healthy = False

    def _read_status(self, on_status: StatusCallback | None) -> None:
        assert self._process is not None and self._process.stderr is not None
        for raw in iter(self._process.stderr.readline, b""):
            message = raw.decode("utf-8", "replace").strip()
            if message == "ready":
                self._healthy = True
            if message:
                self._emit_status(message, on_status)
        self._healthy = False

    def _emit_status(
        self, message: str, on_status: StatusCallback | None = None
    ) -> None:
        callback = on_status if on_status is not None else self._on_status
        if callback is not None:
            callback(message)

    def close(self) -> None:
        if self._closed:
            return
        self._closed = True
        self._healthy = False
        process = self._process
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=1.0)
            except subprocess.TimeoutExpired:
                process.kill()
                try:
                    process.wait(timeout=1.0)
                except subprocess.TimeoutExpired:
                    self._emit_status("helper did not exit after kill")
        if process is not None:
            if process.stdout is not None:
                process.stdout.close()
            if process.stderr is not None:
                process.stderr.close()


def default_system_audio_helper_path(project_root: str | os.PathLike[str]) -> Path:
    """Return the conventional helper path for the running platform."""
    native_dir = Path(project_root) / "native"
    if sys.platform == "darwin":
        return native_dir / "macos_system_audio_capture"
    if sys.platform == "win32":
        return native_dir / "windows_system_audio_capture.exe"
    raise RuntimeError(f"system audio reference is unsupported on {sys.platform}")


def create_system_audio_reference_provider(
    project_root: str | os.PathLike[str],
    helper_path: str | os.PathLike[str] | None = None,
) -> SystemAudioReferenceProvider:
    """Create the platform provider without exposing platform details to AEC."""
    helper = (
        Path(helper_path)
        if helper_path
        else default_system_audio_helper_path(project_root)
    )
    if sys.platform == "darwin":
        name = "screen-capture-kit"
    elif sys.platform == "win32":
        name = "wasapi-loopback"
    else:
        raise RuntimeError(f"system audio reference is unsupported on {sys.platform}")
    return SubprocessSystemAudioReferenceProvider(name=name, command=[str(helper)])
