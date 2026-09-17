# ExecPlan format

Use one living ExecPlan under `docs/exec_plans/YYYY-MM-DD-<phase>.md` for each substantial or multi-session integration phase. The plan evolves with observed evidence; it is not a one-time proposal.

## Required sections

### 1. Phase identity

- phase ID/name;
- branch/PR;
- active upstream pins;
- target tool/part/clock where applicable;
- status and observation time.

### 2. Goal and non-goals

State the exact integration/research question. Explicitly name what is outside scope so the phase does not silently expand.

### 3. Architecture / hypothesis

Describe the mechanism being changed, why it should work, and what existing frozen behavior must remain invariant.

### 4. Contracts and source authority

List interface widths/encodings, relevant authoritative TAIFEX document/version, frozen upstream files and any assumptions that remain project-specific rather than official.

### 5. Acceptance criteria

Define pass/fail before sign-off. Include:

- functional cases;
- replay/order/account hazard requirements;
- byte/field preservation where relevant;
- timing/resource requirements where relevant;
- required CI/local evidence;
- claim limits.

### 6. Implementation plan

Use small ordered milestones with rollback/recovery points. Name integration-owned files; do not plan edits inside `deps/`.

### 7. Verification plan

State exact testbench/runner and evidence level:

- Icarus/XSim;
- OOC synthesis;
- post-route;
- hardware/live link.

Do not rely on a later evidence level to compensate for missing functional tests.

### 8. Execution log

Append dated observations, failed attempts, fixes, commands, CI/runner results and important SHAs. Preserve failures that explain later design choices.

### 9. Decision log

Record phase-local decisions and point to durable `DECISIONS.md` IDs when a choice should survive phase closure.

### 10. Outcome / claim limits

At closure, record what was proven, what was not proven, exact evidence, resource/timing deltas and the next phase. A negative/inconclusive result can close a phase if the question was answered.

## Phase lifecycle

1. Create/resume `codex/<phase-id>`.
2. Create/update the ExecPlan and project state.
3. Implement + self-checking verification.
4. Commit/push reviewable milestones; one draft PR for the phase.
5. Run broader validation required by acceptance criteria.
6. Update state, decisions, progress and compact results.
7. Mark PR ready only when acceptance criteria and exact-head CI pass.
8. Merge; update main; close phase state and start a new branch only for the next coherent question.
