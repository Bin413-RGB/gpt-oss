import json

import pytest

from gpt_oss.pesos import (
    Decision,
    EvidenceLedger,
    ExecutionState,
    PolicyEngine,
    StateMachine,
    TaskContract,
    TraceabilityRecord,
)


def test_state_machine_persists_and_resumes(tmp_path):
    state = StateMachine("TASK-001")
    state.transition(ExecutionState.CLASSIFIED, "risk profile recorded")
    state.transition(ExecutionState.DISCOVERED, "capabilities discovered")

    state_path = tmp_path / "state.json"
    state.save(state_path)
    resumed = StateMachine.load(state_path)

    assert resumed.state is ExecutionState.DISCOVERED
    assert resumed.transitions == state.transitions


def test_state_machine_rejects_skipped_stage():
    state = StateMachine("TASK-002")

    with pytest.raises(ValueError, match="invalid transition"):
        state.transition(ExecutionState.EXECUTING, "skip controls")


def test_task_contract_requires_end_to_end_traceability():
    contract = _contract(
        traceability=[
            TraceabilityRecord(
                requirement="FR-1",
                architectural_decision="ADR-1",
                file="app.py",
                change="Add health check",
                test="test_health",
                evidence="report.xml",
                accepted=True,
            )
        ]
    )

    assert contract.validate() == []
    assert contract.ready_for_acceptance


def test_task_contract_reports_untraced_requirement():
    contract = _contract(traceability=[])

    assert "requirement is not traceable: FR-1" in contract.validate()
    assert not contract.ready_for_acceptance


def test_policy_enforces_command_and_path_boundaries():
    policy = PolicyEngine(
        denied_commands={"format.com"},
        approval_commands={"shutdown.exe"},
        protected_paths=["C:/Windows/**"],
        writable_paths=["C:/Projects/**"],
    )

    assert policy.evaluate_command(r'C:\Windows\System32\format.com C:').decision is Decision.DENY
    assert policy.evaluate_command("shutdown.exe /r").decision is Decision.REQUIRE_APPROVAL
    assert policy.evaluate_command("git status").decision is Decision.ALLOW
    assert policy.evaluate_write("C:/Windows/System32/config").decision is Decision.DENY
    assert policy.evaluate_write("c:/windows/system32/config").decision is Decision.DENY
    assert policy.evaluate_write("C:/Projects/demo/app.py").decision is Decision.ALLOW
    assert policy.evaluate_write("D:/external/file.txt").decision is Decision.REQUIRE_APPROVAL


def test_evidence_ledger_detects_tampering(tmp_path):
    path = tmp_path / "evidence.jsonl"
    ledger = EvidenceLedger(path)
    ledger.append(task_id="TASK-003", action="build", reason="verify", result="passed")
    ledger.append(task_id="TASK-003", action="test", reason="accept", result="passed")

    assert ledger.verify() == (True, None)

    records = ledger.read_all()
    records[0]["result"] = "failed"
    path.write_text("\n".join(json.dumps(item) for item in records) + "\n", encoding="utf-8")
    assert ledger.verify() == (False, 1)


def _contract(*, traceability):
    return TaskContract(
        task_id="TASK-001",
        task_type="build",
        objective="Create a verified application",
        scope=["application"],
        out_of_scope=["deployment"],
        functional_requirements=["FR-1"],
        non_functional_requirements=[],
        platform={"os": "Windows 11"},
        risks=["unsigned package"],
        affected_files=["app.py"],
        test_plan=["run unit tests"],
        rollback_plan=["restore checkpoint"],
        acceptance_criteria=["tests pass"],
        deliverables=["package"],
        required_evidence=["test report"],
        traceability=traceability,
    )
