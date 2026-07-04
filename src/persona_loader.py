#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
人设加载：从当前角色的 SOUL 文件取一段精简人格，注入快路径。

快路径是裸模型直连，默认丢角色人格；读角色权威的 SOUL 文件补上，让闲聊也像
jarvis / 林妹妹本人。同时适配两大引擎（SOUL 存放位置不同）：

  - hermes  : ~/.hermes/profiles/<agent>/SOUL.md   （HERMES_HOME 可覆盖）
  - openclaw: <agent.workspace>/SOUL.md            （读 openclaw.json 的 workspace，
              取不到时回退 ~/.openclaw/workspace/<agent>/SOUL.md）

SOUL 可能很大（jarvis 24KB），整段塞进快路径会拖慢、费 token。这里只取**顶部**
——角色圣经的开头恒为身份/语气精华——按字符预算在 `## ` 小节边界断开，不切半句。
"""

import json
import os

_DEFAULT_BUDGET = 1400  # 精简人设字符预算（软上限，在小节边界断）
_HARD_CAP = 2400        # 硬上限：单个超长开头小节也不许突破


def _hermes_home() -> str:
    return os.path.expanduser(os.environ.get("HERMES_HOME", "~/.hermes"))


def _norm_agent(agent_id: str) -> str:
    # profile / workspace 目录用下划线形式（lin-meimei → lin_meimei）
    return (agent_id or "").strip().replace("-", "_")


def _openclaw_soul_path(agent_id: str) -> str | None:
    """优先读 openclaw.json 的 agent.workspace；回退到约定目录。"""
    aid = _norm_agent(agent_id)
    # 1) openclaw.json 里该 agent 的 workspace
    try:
        cfg = os.path.expanduser("~/.openclaw/openclaw.json")
        d = json.load(open(cfg, encoding="utf-8"))
        for a in d.get("agents", {}).get("list", []):
            if isinstance(a, dict) and _norm_agent(a.get("id", "")) == aid:
                ws = a.get("workspace")
                if ws:
                    p = os.path.join(os.path.expanduser(ws), "SOUL.md")
                    if os.path.exists(p):
                        return p
    except (OSError, ValueError, json.JSONDecodeError):
        pass
    # 2) 约定回退
    p = os.path.expanduser(f"~/.openclaw/workspace/{aid}/SOUL.md")
    return p if os.path.exists(p) else None


def _soul_path(engine: str, agent_id: str) -> str | None:
    aid = _norm_agent(agent_id)
    if (engine or "").strip().lower() == "hermes":
        p = os.path.join(_hermes_home(), "profiles", aid, "SOUL.md")
        return p if os.path.exists(p) else None
    return _openclaw_soul_path(aid)


def _compact(text: str, budget: int = _DEFAULT_BUDGET) -> str:
    """从顶部按预算取整节：累计超预算后，遇下一个 `## ` 小节即停；带硬上限。"""
    lines = text.replace("\r\n", "\n").split("\n")
    out = []
    total = 0
    for line in lines:
        # 超软预算且到了新小节边界 → 收尾（保证已含开头完整小节）
        if total >= budget and line.lstrip().startswith("## ") and out:
            break
        out.append(line)
        total += len(line) + 1
        if total >= _HARD_CAP:
            break
    return "\n".join(out).strip()


def load_persona(engine: str, agent_id: str, budget: int = _DEFAULT_BUDGET) -> str:
    """返回该引擎下该角色的精简人设；找不到 / 读失败返回空串（快路径退化为无人格）。"""
    path = _soul_path(engine, agent_id)
    if not path:
        return ""
    try:
        with open(path, "r", encoding="utf-8") as f:
            raw = f.read()
    except OSError:
        return ""
    return _compact(raw, budget)
