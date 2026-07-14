from __future__ import annotations

from edwin.tools.base import Tool


class ToolRegistry:
    def __init__(self):
        self._tools: dict[str, Tool] = {}

    def register(self, tool: Tool) -> None:
        if tool.spec.name in self._tools:
            raise ValueError(f"duplicate tool: {tool.spec.name}")
        self._tools[tool.spec.name] = tool

    def get(self, name: str) -> Tool | None:
        return self._tools.get(name)

    def available(self) -> list[Tool]:
        return [tool for tool in self._tools.values() if tool.supported()]

    def names(self) -> set[str]:
        return {tool.spec.name for tool in self.available()}
