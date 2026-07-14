from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from enum import Enum


class RiskLevel(str, Enum):
    READ = "read"
    WRITE = "write"
    EXTERNAL = "external"
    DESTRUCTIVE = "destructive"
    PRIVILEGED = "privileged"


@dataclass(frozen=True)
class ApprovalRequest:
    request_id: str
    tool_call_id: str
    tool_name: str
    arguments: dict
    risk_level: RiskLevel
    summary: str

    @property
    def digest(self) -> str:
        raw = json.dumps(
            [self.request_id, self.tool_call_id, self.tool_name, self.arguments],
            sort_keys=True,
            ensure_ascii=False,
            separators=(",", ":"),
        )
        return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def requires_confirmation(risk: RiskLevel) -> bool:
    return risk in {RiskLevel.EXTERNAL, RiskLevel.DESTRUCTIVE}
