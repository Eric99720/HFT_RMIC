# Project records and phase workflow

Use this workflow when starting substantial work, changing material architecture/state, handing off, opening/merging a PR, or closing a phase. `AGENTS.md` owns authorization, safety, evidence, and Git boundaries.

## Record ownership

| Owner | Purpose |
|---|---|
| `docs/project_state.json` | Single authored source for current phase, goal, handoff, next action, task states, source pins and recent milestones. |
| `CURRENT_PHASE.md` | Human operational handoff generated from project state plus phase-specific detail. |
| `TASKS.md` | Current task/acceptance board. |
| `PROGRESS.md` | Chronological technical history and evidence pointers. |
| `DECISIONS.md` | Append-only durable choices, alternatives, rationale, evidence and supersession. |
| `CHANGELOG.md` | Concise delivered milestones. |
| `PLANS.md` | ExecPlan format and lifecycle. |
| `docs/exec_plans/` | One living plan per coherent substantial phase. |
| `docs/README.md` | Documentation index and navigation. |
| `docs/results_policy.md` | Evidence publication and claim-level rules. |
| ignored `reports/`, `build/`, `sim/` | Raw logs, waveforms, Vivado products, local audits and implementation reports. |

Do not create duplicate `*-status`, `*-ready`, `*-pending`, `*-final2`, or backup notes. Put information in the canonical owner and link to detailed evidence.

## Phase start transaction

1. Read `CURRENT_PHASE.md`, the active ExecPlan and applicable decisions.
2. Inspect branch/HEAD and submodule SHAs.
3. Run dependency contract verification before relying on upstream interfaces.
4. Confirm phase scope, acceptance criteria, evidence level and rollback path in the ExecPlan.
5. Work on the existing `codex/<phase-id>` branch; create it only if the phase has none.
6. Open one draft PR early for the phase when practical.

## Material state update

On implementation completion, discovered architecture gap, failed test, protocol-semantic correction, timing result, or phase transition:

1. Update the owning ExecPlan with observed evidence and limits.
2. Append `DECISIONS.md` only if the rationale or durable architecture choice changed.
3. Update `docs/project_state.json` with actual status, next action, affected tasks and milestone pointer.
4. Run:

```powershell
python -B scripts/sync_project_records.py --write
python -B scripts/sync_project_records.py --check
python -B scripts/check_repository_layout.py
git diff --check
```

5. Run scope-relevant functional/timing checks.
6. Review the diff and publish one reviewable milestone commit to the phase branch.

## Task lifecycle

Use only:

- `PLANNED`
- `READY`
- `RUNNING`
- `VERIFYING`
- `COMPLETE`
- `BLOCKED`
- `SUPERSEDED`
- `INVALID`

`COMPLETE` requires its stated acceptance criteria. If Git/PR delivery is part of the phase acceptance, merge must be verified before phase closure. A technically negative or inconclusive experiment may still be COMPLETE if its declared question and validation were completed.

## Git lifecycle

One coherent integration phase uses one branch and one PR from design through implementation, fixes, Vivado runs, evidence review and phase closure.

- Branch: `codex/<phase-id>`.
- Resume the branch across conversations.
- Do not split test fixes, docs, runner changes or evidence review into separate phase branches.
- Independent repository governance may use `codex/repository-maintenance`; governance supporting an active phase stays on the phase branch.
- Merge only exact reviewed head with required CI passing and acceptance criteria satisfied.
- Never force-push shared history or feature-commit directly to `main`.

After merge, update/prune local refs only after verifying the branch is contained in main and no worktree/PR still needs it.

## Handoff content

A handoff must state:

- current phase/status and branch/PR;
- upstream pinned SHAs;
- what changed;
- exact verification completed and evidence limits;
- any failed attempts that matter;
- next action;
- commands the user must run only when local Vivado/hardware resources are required.

Do not describe simulation as hardware validation or a queued/running CI job as passed.
