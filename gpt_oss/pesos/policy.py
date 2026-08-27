"""Policy-as-code evaluator for commands and filesystem targets."""

from __future__ import annotations

import fnmatch
import shlex
from dataclasses import dataclass, field
from enum import StrEnum
from pathlib import PurePosixPath, PureWindowsPath


class Decision(StrEnum):
    ALLOW = "allow"
    REQUIRE_APPROVAL = "require_approval"
    DENY = "deny"


@dataclass(frozen=True)
class PolicyResult:
    decision: Decision
    reasons: tuple[str, ...]


@dataclass
class PolicyEngine:
    denied_commands: set[str] = field(default_factory=set)
    approval_commands: set[str] = field(default_factory=set)
    protected_paths: list[str] = field(default_factory=list)
    writable_paths: list[str] = field(default_factory=list)

    @classmethod
    def from_dict(cls, config: dict[str, object]) -> PolicyEngine:
        return cls(
            denied_commands=set(config.get("denied_commands", [])),
            approval_commands=set(config.get("approval_commands", [])),
            protected_paths=list(config.get("protected_paths", [])),
            writable_paths=list(config.get("writable_paths", [])),
        )

    def evaluate_command(self, command: str) -> PolicyResult:
        try:
            token = shlex.split(command, posix=False)[0].strip('"')
            executable = min(
                PurePosixPath(token).name,
                PureWindowsPath(token).name,
                key=len,
            ).lower()
        except (IndexError, ValueError):
            return PolicyResult(Decision.DENY, ("command is empty or malformed",))
        if executable in {item.lower() for item in self.denied_commands}:
            return PolicyResult(Decision.DENY, (f"command is denied: {executable}",))
        if executable in {item.lower() for item in self.approval_commands}:
            return PolicyResult(
                Decision.REQUIRE_APPROVAL,
                (f"command requires approval: {executable}",),
            )
        return PolicyResult(Decision.ALLOW, ("command is permitted",))

    def evaluate_write(self, path: str) -> PolicyResult:
        normalized = path.replace("\\", "/").casefold()
        protected_paths = (pattern.casefold() for pattern in self.protected_paths)
        if any(fnmatch.fnmatch(normalized, pattern) for pattern in protected_paths):
            return PolicyResult(Decision.DENY, (f"path is protected: {path}",))
        writable_paths = (pattern.casefold() for pattern in self.writable_paths)
        if not any(fnmatch.fnmatch(normalized, pattern) for pattern in writable_paths):
            return PolicyResult(
                Decision.REQUIRE_APPROVAL,
                (f"path is outside configured writable roots: {path}",),
            )
        return PolicyResult(Decision.ALLOW, ("path is writable",))
