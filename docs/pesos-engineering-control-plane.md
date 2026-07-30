# PESOS Engineering Control Plane

This repository includes a small, executable PESOS foundation rather than a
prompt-only protocol. It is intentionally platform-neutral; Windows-specific
diagnostics and remediation should be added as separately approved profiles.

## Implemented control-plane primitives

- **AEES state machine:** enforces normal execution stages, explicit failure and
  rollback paths, and atomic persistence for interrupted-task recovery.
- **Task contracts:** model scope, requirements, risks, tests, rollback,
  acceptance, deliverables, evidence, and end-to-end traceability.
- **Policy as code:** classifies commands and writes as allowed, denied, or
  approval-required using versioned policy data.
- **Evidence ledger:** records actions in append-only JSON Lines with a SHA-256
  hash chain and verifies accidental or unauthorized record modification.

The Python API is available under `gpt_oss.pesos`. Default policy and task
contract schema files live under `.pesos/`.

## Execution lifecycle

```text
RECEIVED -> CLASSIFIED -> DISCOVERED -> BASELINED -> PLANNED -> APPROVED
         -> EXECUTING -> VERIFYING -> ACCEPTED -> DELIVERED

FAILED -> ROLLING_BACK -> ROLLED_BACK
       -> RECOVERY_REQUIRED
```

`BLOCKED` preserves an explicit interruption point. A blocked task may only
resume through a recorded transition with a reason.

## Safety boundary

The policy engine is an application-level control and does not replace the
operating system sandbox, user authorization, backups, or Codex approval
settings. The default policy is conservative around Windows system paths and
commands. A production remediation profile must additionally provide a
pre-check, backup, apply, verification, rollback, and recovery report for every
operation.

## Next implementation slices

1. Capability discovery with a signed environment manifest.
2. Read-only Windows diagnostic collectors and confidence-ranked findings.
3. Transactional remediation definitions with mandatory rollback tests.
4. Build, packaging, signing, SBOM, and install/uninstall verification profiles.
5. Evaluation fixtures that compare proposed policy changes before adoption.

These slices should remain separate so read-only diagnostics never inherit
remediation permissions and build jobs never receive machine-wide privileges.
