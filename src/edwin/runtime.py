from __future__ import annotations

import json
import re
import threading
import time
import uuid
from dataclasses import dataclass
from pathlib import Path

import model_store
import voice_context_store
from edwin.memory import EdwinMemoryStore
from edwin.model import OpenAIModelProvider
from edwin.security import ApprovalRequest, RiskLevel, requires_confirmation
from edwin.skills import load_skills, prompt_summary
from edwin.tools import default_registry

_ROOT = Path(__file__).resolve().parents[2]


class Cancelled(RuntimeError): pass


@dataclass
class PendingState:
    request_id: str
    session_id: str
    messages: list[dict]
    call: dict
    approval: ApprovalRequest


class ApprovalRequired(RuntimeError):
    def __init__(self, state: PendingState):
        super().__init__(state.approval.summary)
        self.state = state


class AgentRuntime:
    def __init__(self, assistant_id: str, max_iterations=12, memory=None, registry=None):
        self.assistant_id = assistant_id.replace("-", "_")
        self.max_iterations = max_iterations
        self.memory = memory or EdwinMemoryStore()
        self.registry = registry or default_registry()
        self.skills = load_skills(_ROOT / "skills", self.registry.names())

    def precheck(self) -> dict:
        cfg = model_store.get_agent_decrypted()
        if not cfg: return {"ok": False, "error": "No Edwin Agent model is selected"}
        if model_store.is_codex_provider(cfg.get("provider", "")):
            return {"ok": False, "error": "OpenAI Codex CLI cannot be used as the Edwin Agent model"}
        try:
            import model_probe
            probe = model_probe.probe_model(
                cfg["base_url"], cfg["model"], cfg["api_key"], provider=cfg.get("provider", "")
            )
            if not probe.get("ok") or not probe.get("tool_support"):
                return {"ok": False, "error": f"Edwin Agent model probe failed: {probe.get('message', 'tool calls unsupported')}"}
        except Exception as exc:
            return {"ok": False, "error": f"Edwin Agent model probe failed: {exc}"}
        return {"ok": True, "model": cfg.get("label") or cfg.get("model"), "tools": sorted(self.registry.names()), "skills": {s.name: (s.available, s.reason) for s in self.skills}}

    def _system_prompt(self, text: str) -> str:
        soul_path = _ROOT / "prompts" / self.assistant_id.replace("_", "-") / "SOUL.md"
        if not soul_path.exists(): soul_path = _ROOT / "prompts" / self.assistant_id / "SOUL.md"
        try: soul = soul_path.read_text(encoding="utf-8")[:18000]
        except OSError: soul = f"You are {self.assistant_id}, a capable personal assistant."
        memories = self.memory.search(self.assistant_id, text, limit=4)
        safety = (
            "You are running inside Edwin, the local project-owned agent runtime. Use tools when the task requires live data or action. "
            "Never claim an action succeeded unless its tool result says ok. Privileged actions are forbidden. "
            "The current Agent engine is Edwin Agent Runtime, running in process. If asked about the current engine, runtime, or backend, use runtime_identity and report its result; never infer identity from conversation history, project paths, SOUL compatibility instructions, or older Hermes/OpenClaw turns. "
            "External and destructive actions require approval, which the runtime enforces. "
            "For screen reading or desktop control, call the desktop tool immediately; never reply with permission setup instructions before the tool runs. "
            "The desktop tool initiates any required macOS permission request itself. "
            "For requests to open a native application, use open_application directly instead of browser, desktop automation, or shell. "
            "An explicit user request to open an app is already authorization for that reversible action. Keep final replies concise and suitable for speech."
            " Use display_sleep, lock_screen, and stand_down for those exact lifecycle actions, never run_command. "
            "A clear direct request for these bounded local actions is already authorization: execute the whole requested sequence without another confirmation."
        )
        parts = [safety, soul]
        skills = prompt_summary(self.skills)
        if skills: parts.append("# Available skill guidance\n" + skills)
        router_turns = voice_context_store.recent_fast_router_context(self.assistant_id, limit=8)
        if router_turns:
            lines = [
                f"{row.get('role')}: {(row.get('content') or '').strip()[:500]}"
                for row in router_turns
                if row.get("role") in ("user", "assistant") and (row.get("content") or "").strip()
            ]
            if lines:
                # Same continuity bridge used by Hermes: router-lane turns do not
                # exist in the agent database, so inject a bounded, fail-open
                # summary into the next heavy turn.
                parts.append(
                    "# Recent voice FastRouter context\n"
                    "Use these turns only for conversational continuity. Do not mention this internal note.\n"
                    + "\n".join(lines)
                )
        if memories: parts.append("# Relevant durable memory\n" + "\n".join(f"- {m}" for m in memories))
        return "\n\n".join(parts)

    def _provider(self):
        cfg = model_store.get_agent_decrypted()
        if not cfg: raise RuntimeError("No Edwin Agent model is selected in Control Center")
        return OpenAIModelProvider(cfg)

    def run(self, text: str, cancel: threading.Event, on_text=None, on_tool=None, request_id=None, resume: PendingState | None=None, approved=False) -> str:
        request_id = request_id or str(uuid.uuid4())
        provider = self._provider()
        if resume:
            session_id, messages = resume.session_id, resume.messages
            result = self._execute(
                resume.call, request_id, cancel,
                "approved" if approved else "denied",
                effective_risk=resume.approval.risk_level,
            ) if approved else None
            if not approved:
                result_text = json.dumps({"ok": False, "error": "User denied this action"})
                self.memory.record_approval(request_id, resume.call["id"], resume.approval.digest, "denied")
            else:
                result_text = result.model_text()
                self.memory.record_approval(request_id, resume.call["id"], resume.approval.digest, "approved")
            messages.append({"role": "tool", "tool_call_id": resume.call["id"], "content": result_text})
        else:
            session_id = self.memory.session(self.assistant_id)
            history = self.memory.recent(self.assistant_id, limit=10)
            messages = [{"role": "system", "content": self._system_prompt(text)}, *history, {"role": "user", "content": text}]
            self.memory.add_message(session_id, request_id, "user", text)
            voice_context_store.append_turn(self.assistant_id, "edwin", "user", text, session_id=session_id)

        final = ""
        for _ in range(self.max_iterations):
            if cancel.is_set(): raise Cancelled("request cancelled")
            turn = provider.generate(messages, [t.spec.as_openai_tool() for t in self.registry.available()], cancel, on_text, on_tool)
            if turn.content: final += turn.content
            if not turn.tool_calls:
                if turn.content: break
                raise RuntimeError("Edwin model returned an empty response")
            assistant = {"role": "assistant", "content": turn.content or None, "tool_calls": [
                {"id": c["id"], "type": "function", "function": {"name": c["name"], "arguments": c["arguments_json"]}} for c in turn.tool_calls
            ]}
            messages.append(assistant)
            for call_index, call in enumerate(turn.tool_calls):
                tool = self.registry.get(call["name"])
                if not tool or not tool.supported():
                    messages.append({"role": "tool", "tool_call_id": call["id"], "content": json.dumps({"ok": False, "error": "tool unavailable"})})
                    continue
                preferred = self._preferred_tool_for_command(call)
                if preferred:
                    messages.append({
                        "role": "tool", "tool_call_id": call["id"],
                        "content": json.dumps({
                            "ok": False,
                            "error": f"Do not use run_command for this capability. Call {preferred} instead; it is structured and read-only and requires no approval.",
                        }),
                    })
                    continue
                risk = self._effective_risk(tool.spec.risk_level, call)
                if risk == RiskLevel.PRIVILEGED:
                    messages.append({"role": "tool", "tool_call_id": call["id"], "content": json.dumps({"ok": False, "error": "privileged actions are forbidden"})})
                    continue
                if requires_confirmation(risk):
                    summary = (
                        "This action needs your confirmation: "
                        f"{call['name']} with {json.dumps(call['arguments'], ensure_ascii=False)[:300]}. "
                        "Shall I proceed?"
                    )
                    approval = ApprovalRequest(request_id, call["id"], call["name"], call["arguments"], risk, summary)
                    self.memory.record_approval(request_id, call["id"], approval.digest, "pending")
                    self.memory.add_message(session_id, request_id, "assistant", summary)
                    voice_context_store.append_turn(
                        self.assistant_id, "edwin", "assistant", summary,
                        session_id=session_id,
                    )
                    # OpenAI requires one tool response for every call in the assistant
                    # message. Defer sibling calls so approval remains bound to exactly
                    # one action; the model may request them again after this resumes.
                    for deferred in turn.tool_calls[call_index + 1:]:
                        messages.append({
                            "role": "tool", "tool_call_id": deferred["id"],
                            "content": json.dumps({"ok": False, "error": "deferred until the current approval is resolved"}),
                        })
                    raise ApprovalRequired(PendingState(request_id, session_id, messages, call, approval))
                result = self._execute(call, request_id, cancel, "implicit", effective_risk=risk)
                messages.append({"role": "tool", "tool_call_id": call["id"], "content": result.model_text()})
        else:
            final = "I could not complete the task within the twelve-step safety limit."
            if on_text: on_text(final)

        self.memory.add_message(session_id, request_id, "assistant", final)
        voice_context_store.append_turn(self.assistant_id, "edwin", "assistant", final, session_id=session_id)
        self._capture_explicit_memory(text)
        return final

    def _execute(self, call, request_id, cancel, approval, effective_risk=None):
        tool = self.registry.get(call["name"])
        started = time.monotonic()
        validation_error = self._validate_arguments(tool.spec.input_schema, call["arguments"])
        if validation_error:
            from edwin.tools.base import ToolResult
            result = ToolResult(False, error=validation_error)
        else:
            try: result = tool.handler(call["arguments"], cancel)
            except Exception as exc:
                from edwin.tools.base import ToolResult
                result = ToolResult(False, error=str(exc))
        risk = effective_risk or tool.spec.risk_level
        self.memory.record_tool(request_id, call["id"], call["name"], call["arguments"], risk.value, result, approval, int((time.monotonic() - started) * 1000))
        return result

    @staticmethod
    def _validate_arguments(schema, arguments):
        if not isinstance(arguments, dict): return "tool arguments must be an object"
        for key in schema.get("required", []):
            if key not in arguments: return f"missing required argument: {key}"
        if schema.get("additionalProperties") is False:
            unknown = set(arguments) - set(schema.get("properties", {}))
            if unknown: return f"unknown arguments: {', '.join(sorted(unknown))}"
        expected_types = {"string": str, "integer": int, "number": (int, float), "array": list, "object": dict, "boolean": bool}
        for key, value in arguments.items():
            kind = schema.get("properties", {}).get(key, {}).get("type")
            if kind in expected_types and not isinstance(value, expected_types[kind]):
                return f"argument {key} must be {kind}"
        return ""

    @staticmethod
    def _effective_risk(default, call):
        """Elevate consequential UI actions without re-approving ordinary clicks."""
        if call.get("name") != "desktop_control":
            return default
        text = json.dumps(call.get("arguments") or {}, ensure_ascii=False).lower()
        consequential = (
            "send", "submit", "purchase", "buy", "delete", "remove", "confirm order",
            "发送", "提交", "购买", "付款", "删除", "清空", "确认订单",
        )
        return RiskLevel.EXTERNAL if any(word in text for word in consequential) else RiskLevel.WRITE

    @staticmethod
    def _preferred_tool_for_command(call):
        """Route known capabilities away from destructive arbitrary Shell.

        This runs before approval. It never executes or downgrades a command;
        the model must retry with the bounded structured tool.
        """
        if call.get("name") != "run_command": return None
        command = str((call.get("arguments") or {}).get("command") or "").strip()
        try: argv = __import__("shlex").split(command)
        except ValueError: return None
        if not argv: return None
        program = Path(argv[0]).name.lower()
        low = command.lower()
        if program == "pmset":
            if "displaysleepnow" in argv[1:]: return "display_sleep"
            if "-g" in argv[1:]: return "power_status"
        if program in {"top", "uptime", "vm_stat", "system_profiler"}: return "system_health"
        if program == "sysctl" and "-w" not in argv[1:]: return "system_health"
        if program in {"ps", "pgrep"}: return "list_processes"
        if program in {"df", "du"}: return "disk_usage"
        if program in {"ifconfig", "ipconfig", "netstat"}: return "network_status"
        if program == "scutil" and "--nwi" in argv[1:]: return "network_status"
        if program == "curl" and "127.0.0.1:18790/exit" in low: return "stand_down"
        return None

    def _capture_explicit_memory(self, text):
        if re.search(r"(?:记住|请记得|remember that|remember this)", text, re.I):
            self.memory.add_memory(self.assistant_id, text, "explicit_user")

    def clear(self): self.memory.clear(self.assistant_id)
