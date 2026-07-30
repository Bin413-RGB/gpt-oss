"""Structured task contracts and requirement traceability."""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any


@dataclass(frozen=True)
class TraceabilityRecord:
    requirement: str
    architectural_decision: str = ""
    file: str = ""
    change: str = ""
    test: str = ""
    evidence: str = ""
    accepted: bool = False

    @property
    def complete(self) -> bool:
        return all(
            (
                self.requirement,
                self.architectural_decision,
                self.file,
                self.change,
                self.test,
                self.evidence,
            )
        ) and self.accepted


@dataclass
class TaskContract:
    task_id: str
    task_type: str
    objective: str
    scope: list[str]
    out_of_scope: list[str]
    functional_requirements: list[str]
    non_functional_requirements: list[str]
    platform: dict[str, str]
    risks: list[str]
    affected_files: list[str]
    test_plan: list[str]
    rollback_plan: list[str]
    acceptance_criteria: list[str]
    deliverables: list[str]
    required_evidence: list[str]
    traceability: list[TraceabilityRecord] = field(default_factory=list)

    def validate(self) -> list[str]:
        errors: list[str] = []
        required_strings = {
            "task_id": self.task_id,
            "task_type": self.task_type,
            "objective": self.objective,
        }
        errors.extend(f"{name} is required" for name, value in required_strings.items() if not value.strip())
        required_lists = {
            "scope": self.scope,
            "test_plan": self.test_plan,
            "rollback_plan": self.rollback_plan,
            "acceptance_criteria": self.acceptance_criteria,
            "deliverables": self.deliverables,
            "required_evidence": self.required_evidence,
        }
        errors.extend(f"{name} must not be empty" for name, value in required_lists.items() if not value)
        traced = {record.requirement for record in self.traceability}
        for requirement in self.functional_requirements + self.non_functional_requirements:
            if requirement not in traced:
                errors.append(f"requirement is not traceable: {requirement}")
        return errors

    @property
    def ready_for_acceptance(self) -> bool:
        return not self.validate() and all(record.complete for record in self.traceability)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)
