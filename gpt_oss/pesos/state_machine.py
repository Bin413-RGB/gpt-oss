"""Persistent AEES execution state machine."""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from datetime import UTC, datetime
from enum import StrEnum
from pathlib import Path


class ExecutionState(StrEnum):
    RECEIVED = "RECEIVED"
    CLASSIFIED = "CLASSIFIED"
    DISCOVERED = "DISCOVERED"
    BASELINED = "BASELINED"
    PLANNED = "PLANNED"
    APPROVED = "APPROVED"
    EXECUTING = "EXECUTING"
    VERIFYING = "VERIFYING"
    ACCEPTED = "ACCEPTED"
    DELIVERED = "DELIVERED"
    BLOCKED = "BLOCKED"
    FAILED = "FAILED"
    ROLLING_BACK = "ROLLING_BACK"
    ROLLED_BACK = "ROLLED_BACK"
    RECOVERY_REQUIRED = "RECOVERY_REQUIRED"


NORMAL_FLOW = (
    ExecutionState.RECEIVED,
    ExecutionState.CLASSIFIED,
    ExecutionState.DISCOVERED,
    ExecutionState.BASELINED,
    ExecutionState.PLANNED,
    ExecutionState.APPROVED,
    ExecutionState.EXECUTING,
    ExecutionState.VERIFYING,
    ExecutionState.ACCEPTED,
    ExecutionState.DELIVERED,
)

ALLOWED_TRANSITIONS: dict[ExecutionState, set[ExecutionState]] = {
    state: {NORMAL_FLOW[index + 1], ExecutionState.BLOCKED, ExecutionState.FAILED}
    for index, state in enumerate(NORMAL_FLOW[:-1])
}
ALLOWED_TRANSITIONS[ExecutionState.DELIVERED] = set()
ALLOWED_TRANSITIONS[ExecutionState.BLOCKED] = set(NORMAL_FLOW) | {ExecutionState.FAILED}
ALLOWED_TRANSITIONS[ExecutionState.FAILED] = {
    ExecutionState.ROLLING_BACK,
    ExecutionState.RECOVERY_REQUIRED,
}
ALLOWED_TRANSITIONS[ExecutionState.ROLLING_BACK] = {
    ExecutionState.ROLLED_BACK,
    ExecutionState.RECOVERY_REQUIRED,
}
ALLOWED_TRANSITIONS[ExecutionState.ROLLED_BACK] = {ExecutionState.PLANNED}
ALLOWED_TRANSITIONS[ExecutionState.RECOVERY_REQUIRED] = {
    ExecutionState.ROLLING_BACK,
    ExecutionState.BLOCKED,
}


@dataclass(frozen=True)
class Transition:
    source: ExecutionState
    target: ExecutionState
    reason: str
    timestamp: str


@dataclass
class StateMachine:
    task_id: str
    state: ExecutionState = ExecutionState.RECEIVED
    transitions: list[Transition] = field(default_factory=list)

    def transition(self, target: ExecutionState, reason: str) -> Transition:
        if target not in ALLOWED_TRANSITIONS[self.state]:
            raise ValueError(f"invalid transition: {self.state} -> {target}")
        if not reason.strip():
            raise ValueError("transition reason must not be empty")
        event = Transition(
            source=self.state,
            target=target,
            reason=reason,
            timestamp=datetime.now(UTC).isoformat(),
        )
        self.transitions.append(event)
        self.state = target
        return event

    def save(self, path: str | Path) -> None:
        """Atomically persist state so interrupted work can resume safely."""
        destination = Path(path)
        destination.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "schema_version": 1,
            "task_id": self.task_id,
            "state": self.state,
            "transitions": [
                {
                    "source": event.source,
                    "target": event.target,
                    "reason": event.reason,
                    "timestamp": event.timestamp,
                }
                for event in self.transitions
            ],
        }
        temporary = destination.with_suffix(destination.suffix + ".tmp")
        temporary.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        os.replace(temporary, destination)

    @classmethod
    def load(cls, path: str | Path) -> StateMachine:
        payload = json.loads(Path(path).read_text(encoding="utf-8"))
        if payload.get("schema_version") != 1:
            raise ValueError("unsupported state schema version")
        return cls(
            task_id=payload["task_id"],
            state=ExecutionState(payload["state"]),
            transitions=[
                Transition(
                    source=ExecutionState(event["source"]),
                    target=ExecutionState(event["target"]),
                    reason=event["reason"],
                    timestamp=event["timestamp"],
                )
                for event in payload["transitions"]
            ],
        )
