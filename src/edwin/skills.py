from __future__ import annotations

import os
import platform
import re
import shutil
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Skill:
    name: str
    description: str
    body: str
    allowed_tools: tuple[str, ...]
    available: bool
    reason: str = ""


def _frontmatter(text: str) -> tuple[dict, str]:
    if not text.startswith("---\n") or "\n---\n" not in text[4:]:
        return {}, text
    raw, body = text[4:].split("\n---\n", 1)
    data, current = {}, None
    for line in raw.splitlines():
        m = re.match(r"^([\w-]+):\s*(.*)$", line)
        if m:
            current = m.group(1); data[current] = m.group(2).strip().strip('"')
        elif current and line.strip().startswith("-"):
            data.setdefault(current, [])
            if not isinstance(data[current], list): data[current] = []
            data[current].append(line.strip()[1:].strip())
    return data, body.strip()


def load_skills(root: str | os.PathLike, tool_names: set[str]) -> list[Skill]:
    out = []
    for path in sorted(Path(root).glob("*/SKILL.md")):
        try: text = path.read_text(encoding="utf-8")
        except OSError: continue
        meta, body = _frontmatter(text)
        name = str(meta.get("name") or path.parent.name)
        desc = str(meta.get("description") or "")
        front = text.split("---", 2)[1] if text.startswith("---") else ""
        block = re.search(r"(?ms)^\s*allowed-tools:\s*\n((?:\s+-\s*[\w-]+\s*\n?)+)", front)
        allowed = tuple(re.findall(r"(?m)^\s*-\s*([\w-]+)\s*$", block.group(1))) if block else ()
        unknown = [x for x in allowed if x not in tool_names and x not in {"exec", "read"}]
        os_tags = re.findall(r'"(darwin|win32|linux)"', text[:1000])
        current = {"Darwin": "darwin", "Windows": "win32", "Linux": "linux"}.get(platform.system(), "")
        available = not unknown and (not os_tags or current in os_tags)
        reason = f"unknown tools: {', '.join(unknown)}" if unknown else ("unsupported platform" if os_tags and current not in os_tags else "")
        out.append(Skill(name, desc, body, allowed, available, reason))
    return out


def prompt_summary(skills: list[Skill], max_chars=5000) -> str:
    parts = []
    for skill in skills:
        if skill.available:
            parts.append(f"## Skill: {skill.name}\n{skill.description}\n{skill.body[:1800]}")
    return "\n\n".join(parts)[:max_chars]
