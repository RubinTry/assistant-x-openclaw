from __future__ import annotations

import json
from dataclasses import dataclass


@dataclass
class ModelTurn:
    content: str
    tool_calls: list[dict]


class OpenAIModelProvider:
    def __init__(self, config: dict):
        if (config.get("provider") or "").lower() == "openai-codex":
            raise ValueError("OpenAI Codex CLI models cannot be used by Edwin")
        try:
            from openai import OpenAI
        except ImportError as exc:
            raise RuntimeError("openai Python package is not installed") from exc
        self.config = config
        self.client = OpenAI(api_key=config["api_key"], base_url=config["base_url"].rstrip("/"), timeout=90)

    def generate(self, messages: list[dict], tools: list[dict], cancel, on_text=None, on_tool=None) -> ModelTurn:
        stream = self.client.chat.completions.create(
            model=self.config["model"], messages=messages, tools=tools or None,
            tool_choice="auto" if tools else None, stream=True,
        )
        content, calls = [], {}
        for chunk in stream:
            if cancel.is_set():
                close = getattr(stream, "close", None)
                if callable(close): close()
                break
            if not chunk.choices: continue
            delta = chunk.choices[0].delta
            text = getattr(delta, "content", None)
            if text:
                content.append(text)
                if on_text: on_text(text)
            for tc in getattr(delta, "tool_calls", None) or []:
                idx = tc.index
                slot = calls.setdefault(idx, {"id": "", "name": "", "arguments": ""})
                if tc.id: slot["id"] = tc.id
                fn = getattr(tc, "function", None)
                if fn:
                    if fn.name: slot["name"] += fn.name
                    if fn.arguments: slot["arguments"] += fn.arguments
        ordered = []
        for slot in [calls[k] for k in sorted(calls)]:
            try: args = json.loads(slot["arguments"] or "{}")
            except json.JSONDecodeError: args = {"_raw": slot["arguments"]}
            ordered.append({"id": slot["id"], "name": slot["name"], "arguments": args, "arguments_json": slot["arguments"] or "{}"})
            if on_tool: on_tool(slot["name"], slot["arguments"] or "{}")
        return ModelTurn("".join(content), ordered)
