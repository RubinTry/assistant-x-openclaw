from dataclasses import dataclass, field
from typing import Any


@dataclass(frozen=True)
class AgentEvent:
    type: str
    data: dict[str, Any] = field(default_factory=dict)
