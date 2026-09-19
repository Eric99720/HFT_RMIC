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

Apply this transaction when evidence changes acceptance, architecture, protocol semantics, blocking status, the next action, or phase handoff. Record routine debugging outcomes at a reviewable milestone; an intermediate test failure alone does not require a full state update. Preserve failures that explain a design decision or invalidate earlier evidence.

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
6. Review and publish milestones according to the active phase's authorization and acceptance requirements. A failed intermediate check alone is not a publication trigger.

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

## Phase-completion synchronization

The user's standing instruction authorizes routine phase delivery without another per-step approval. At each completed research/integration phase:

1. Reconcile the owning ExecPlan, decisions, canonical state, task board and reviewed results with the actual outcome, including negative/inconclusive results and outstanding limits. Generate shared records and run scope-relevant checks.
2. Inspect the full diff, untracked files and artifact references. Include all publishable source, configuration, tests and documentation needed to reproduce the phase. Under `docs/results_policy.md`, keep secrets, raw/private data, full Vivado trees and local settings out of Git; publish compact provenance and artifact identities/hashes instead. Missing evidence must be recorded, not silently treated as synchronized.
3. Commit the reviewed file set, push the existing phase branch, and update its existing PR with results, verification and remaining acceptance gates. Inspect remote changes first; preserve other work and shared history. Existing stacked PRs remain intact until their dependencies and acceptance are reconciled; do not create more branches merely for routine follow-ups.
4. Verify local/remote commit equality and inspect CI on the delivered head. A push is not a merge or phase acceptance. Merge only under the existing acceptance/CI rules; if publication or required checks fail, record the delivery blocker and do not declare full phase closure.
5. Return the delivered commit, PR and check status. Live GitHub commit/check links own post-push delivery status; avoid repeated documentation commits solely to embed their own SHA or refresh a pending CI label.

## Low-frequency monitoring

At launch, record the run ID, source/configuration, command, PID/job identity, output paths, expected completion evidence and selected cadence in the owning ExecPlan or ignored run manifest. Let the process run independently of the conversation.

- Default to a check every 10 minutes for long jobs. Use 30-60 minutes for healthy multi-hour OOC/implementation runs; use 5 minutes when an expected transition is near. Adjust to observed duration and detection needs, and record the choice. Shorten temporarily only for a concrete anomaly.
- Prefer an existing deterministic watcher or process/job completion event. Read compact status, exit state and log freshness; inspect only the new relevant log tail when needed. A deterministic check need not invoke a model. Avoid repeated full-log reads, token-consuming polling loops, and short sleep/wake cycles.
- If model follow-up is necessary, use the available scheduler with the chosen interval and reuse/update an existing monitor for that run. Keep unchanged, healthy state quiet; notify only on completion, failure, a meaningful transition or required user action. Disable the monitor when the run ends. If scheduling is unavailable, provide the recorded check command and next check time without claiming autonomous follow-up.
- Confirm completion using the runner's exit code and required result/report markers. A missing PID, stale log or partial report alone is not success; investigate freshness against expected stage duration before declaring a stall.
- Monitoring observes the authorized run. Restarting, cancelling, changing sources/configuration or launching another attempt requires the active task's authority and preservation of prior evidence. After completion, review results and perform the applicable material-state/phase-delivery transaction.

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
