from __future__ import annotations

import json
import platform
import threading
from dataclasses import dataclass, field
from typing import Any, Callable

from edwin.security import RiskLevel


@dataclass(frozen=True)
class ToolSpec:
    name: str
    description: str
    input_schema: dict[str, Any]
    risk_level: RiskLevel = RiskLevel.READ
    supported_platforms: tuple[str, ...] = ()

    def as_openai_tool(self) -> dict:
        return {
            "type": "function",
            "function": {
                "name": self.name,
                "description": self.description,
                "parameters": self.input_schema,
            },
        }


@dataclass
class ToolResult:
    ok: bool
    content: str = ""
    error: str = ""
    metadata: dict[str, Any] = field(default_factory=dict)

    def model_text(self) -> str:
        return json.dumps(
            {"ok": self.ok, "content": self.content, "error": self.error},
            ensure_ascii=False,
        )


@dataclass
class Tool:
    spec: ToolSpec
    handler: Callable[[dict, threading.Event], ToolResult]

    def supported(self) -> bool:
        if not self.spec.supported_platforms:
            return True
        key = {"Darwin": "darwin", "Windows": "win32", "Linux": "linux"}.get(
            platform.system(), platform.system().lower()
        )
        return key in self.spec.supported_platforms
