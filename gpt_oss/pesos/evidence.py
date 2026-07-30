"""Append-only, hash-chained execution evidence ledger."""

from __future__ import annotations

import hashlib
import json
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


GENESIS_HASH = "0" * 64


def _canonical_hash(record: dict[str, Any]) -> str:
    payload = json.dumps(record, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(payload.encode()).hexdigest()


class EvidenceLedger:
    def __init__(self, path: str | Path):
        self.path = Path(path)

    def append(
        self,
        *,
        task_id: str,
        action: str,
        reason: str,
        result: str,
        changed_files: list[str] | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        records = self.read_all()
        record = {
            "sequence": len(records) + 1,
            "timestamp": datetime.now(UTC).isoformat(),
            "task_id": task_id,
            "action": action,
            "reason": reason,
            "result": result,
            "changed_files": changed_files or [],
            "metadata": metadata or {},
            "previous_hash": records[-1]["record_hash"] if records else GENESIS_HASH,
        }
        record["record_hash"] = _canonical_hash(record)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.path.open("a", encoding="utf-8", newline="\n") as ledger:
            ledger.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")
            ledger.flush()
        return record

    def read_all(self) -> list[dict[str, Any]]:
        if not self.path.exists():
            return []
        return [json.loads(line) for line in self.path.read_text(encoding="utf-8").splitlines() if line]

    def verify(self) -> tuple[bool, int | None]:
        previous_hash = GENESIS_HASH
        for index, stored in enumerate(self.read_all(), start=1):
            record = dict(stored)
            record_hash = record.pop("record_hash", None)
            if record.get("sequence") != index or record.get("previous_hash") != previous_hash:
                return False, index
            if record_hash != _canonical_hash(record):
                return False, index
            previous_hash = record_hash
        return True, None
