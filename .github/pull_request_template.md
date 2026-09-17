# Pull request checklist

Begin the PR title with the phase ID, for example `I2: ...`. Keep one PR for the entire phase: architecture, implementation, fixes, Vivado evidence, documentation and phase closure.

## Phase / source identity

- Phase ID / active ExecPlan:
- HFT submodule SHA:
- RMIC submodule SHA:
- Head branch / reviewed head SHA:

## Scope and concrete outcome

Describe what changed in `HFT_RMIC`, what frozen behavior must remain unchanged, and what question this phase is intended to close.

## Evidence level

Mark every level actually produced; do not imply higher evidence.

- [ ] Authoritative source/spec review
- [ ] Self-checking functional simulation
- [ ] Synthesis/OOC
- [ ] Post-route
- [ ] U50/QSFP/live-system hardware

## Verification

List exact commands/runners and PASS evidence. State skipped checks and why.

```text
python -B scripts/sync_project_records.py --check
python -B scripts/check_repository_layout.py
git diff --check
```

Add phase-specific regressions and Vivado commands below.

## Safety / integration checks

- [ ] Frozen HFT/RMIC submodule pins unchanged unless this is an explicit migration phase.
- [ ] No integration edits were made inside `deps/`.
- [ ] New state mutation has a self-checking regression.
- [ ] Execution mutation uses only committed/de-duplicated report ownership.
- [ ] Unsupported/unconfigured semantics fail closed.
- [ ] No raw market data, credentials, packet captures, workstation paths or generated Vivado trees are committed.

## Project records

For material changes:

- [ ] active ExecPlan updated;
- [ ] `DECISIONS.md` appended if durable rationale changed;
- [ ] `docs/project_state.json` updated;
- [ ] `python -B scripts/sync_project_records.py --write` run;
- [ ] sync/layout/diff checks pass.

## Acceptance / claim limits

State the phase closure criteria, what the evidence proves, what it does **not** prove, and the next coherent phase/question.

Do not mark the PR ready until the exact reviewed head satisfies the phase acceptance criteria and required CI is green.
