# HFT_RMIC agent policy

Build a reproducible FPGA HFT + risk-management integration system whose functional and performance claims are traceable to source pins, commands, tests, and raw reports. These rules apply repository-wide to all agents and subagents.

## Standing authorization and scope

The active project goal grants standing authorization to design, implement, test, document, and iterate integration work inside `HFT_RMIC` using existing project resources. Prefer evidence-driven action over permission requests. Ask the user only when user-only input, credentials, paid resources, legal commitments, destructive/irreversible actions, or a genuinely unresolved architecture choice is required.

Complete the current phase deliverable and its necessary verification before expanding scope. Routine implementation choices, test fixes, documentation maintenance, CI repair, and bounded diagnostics inside the active phase do not require per-step approval.

## Immutable upstream boundaries

`HFT_RMIC` is the only integration workspace. The pinned upstream repositories under `deps/` are read-only baselines:

- `deps/hft-full-system-fpga` -> `50217fad1fd580f8c451ba893f9035f4be1dc21a`
- `deps/RMIC` -> `de6c300f4f18b18296f013287ab0eca70d3abb72`

Never edit, commit inside, retarget, or silently advance either submodule during an integration phase. Compatibility logic belongs in this repository. Changing an upstream pin requires an explicit durable decision, contract re-audit, and dedicated migration phase.

Run `pwsh .\scripts\setup.ps1` or `python -B scripts/check_dependency_contracts.py` after clone/update and before integration work that depends on upstream interfaces.

## Technical invariants

- **Fail closed.** Unmapped/ambiguous account or product identifiers, unsupported Side/OrdType/TIF/PositionEffect values, uninitialized accounting, recovery-required state, internal overflow, or missing authoritative semantics must reject rather than guess.
- **Committed execution only.** RM/accounting state may mutate only from execution reports that passed the frozen HFT report-sequence owner. Duplicate/replayed/gapped reports must not be applied twice.
- **Protocol ownership stays in HFT.** Do not reimplement TMP session, TCP, replay, checksum, encoder, order book, or network functions in RMIC integration unless a documented gap requires an integration-owned side-band adapter.
- **Risk transaction ownership stays explicit.** Exchange-specific policy and futures accounting are integration-layer responsibilities; the frozen M5.4 RMIC remains the generic transactional/order-lifecycle baseline unless a versioned migration is justified by evidence.
- **No silent semantic coercion.** Preserve explicit conversions such as TMP Side `1/2` to RMIC BUY/SELL, 16-bit TMP quantity to normalized width, and PositionEffect character semantics.
- **Configuration and readiness are transactional.** No order may be released to the exchange before mappings, product/account policy, futures accounting, RMIC AMU initialization, and recovery state are ready.
- **Reset/recovery is a safety boundary.** FPGA reset must not imply exchange outstanding orders disappeared. Keep the integration fail-closed until the selected recovery protocol re-establishes state.

## Evidence and claim boundaries

Keep these evidence levels separate:

1. **Source/spec evidence** — frozen upstream RTL, authoritative TAIFEX documentation, theses/papers.
2. **Functional simulation evidence** — Icarus/XSim self-checking regressions.
3. **Synthesis/OOC evidence** — resource and timing estimates after synthesis.
4. **Post-route evidence** — routed timing, resources, DRC, power estimate.
5. **Hardware evidence** — U50/QSFP/live-link measurements.

Never label simulation latency as board latency, synthesis timing as routed timing, vectorless power as measured power, or project policy as official TAIFEX compliance. Hardware or exchange-compliance claims require the corresponding evidence level.

For protocol semantics, prefer the frozen authoritative TAIFEX references under the pinned HFT repository. Record the exact document/version and field mapping. Project audit notes are navigation aids, not a substitute for the authoritative source when there is a discrepancy.

## Verification rules

Every functional state mutation requires a self-checking regression. Every integration milestone must define acceptance criteria before sign-off. Verify proportionally, but broaden tests for shared interfaces, accounting, replay/dedup, ordering, or timing-sensitive changes.

Core checks from repository root:

```powershell
pwsh .\scripts\setup.ps1
pwsh .\scripts\preflight.ps1
python -B scripts/sync_project_records.py --check
python -B scripts/check_repository_layout.py
python -B scripts/check_vivado_2022_tcl.py
git diff --check
```

Use Vivado 2022.1 / `xcu50-fsvh2104-2-e` / 156.25 MHz for sign-off unless a durable decision changes the toolchain or target. Preserve raw implementation reports locally under ignored `reports/` or `build/`; commit only compact reviewed summaries with provenance.

## Git lifecycle

Use one branch and one PR per coherent integration phase:

```text
codex/<phase-id>
```

Resume the existing phase branch across conversations. Do not create a new branch for each request, test fix, or documentation update within that phase.

Before publishing changes, inspect branch/HEAD and exact diff. Commit reviewable milestones, push the phase branch, open one draft PR early, and keep it updated. Merge only when phase acceptance criteria are satisfied and required CI passes on the reviewed head.

Do not commit feature work directly to `main`, force-push shared history, bypass required checks, merge failing CI, publish secrets/raw market data, or push changes into the two upstream source repositories.

Independent repository-governance maintenance may use `codex/repository-maintenance`; otherwise governance changes supporting an active phase remain on that phase branch.

## Project records and handoff

Before starting substantial work, changing material state, handing off, opening/merging a PR, or closing a phase, follow `docs/project_management_workflow.md`.

Canonical shared state lives in `docs/project_state.json`. Update it and the owning ExecPlan/decision, then run:

```powershell
python -B scripts/sync_project_records.py --write
python -B scripts/sync_project_records.py --check
```

Record roles:

- `CURRENT_PHASE.md` — current human handoff and active operational state.
- `TASKS.md` — current task/acceptance board.
- `PROGRESS.md` — chronological technical history.
- `DECISIONS.md` — append-only durable architecture/research decisions.
- `CHANGELOG.md` — concise delivered milestones.
- `PLANS.md` / `docs/exec_plans/` — phase plans, acceptance criteria, verification, outcomes, recovery.
- `docs/README.md` — documentation index.

Do not create duplicate ad-hoc `status`, `ready`, `pending`, `final2`, or backup notes. Update the canonical owner and link evidence.

## File/data hygiene

Follow `docs/repository_layout.md` and `docs/results_policy.md`.

- Keep generated logs, Vivado runs, waveforms, checkpoints, packet captures, raw market data, and temporary analyses out of Git.
- Never commit credentials, workstation-specific absolute paths, exchange credentials, proprietary datasets, or private network captures.
- Preserve exact frozen submodule pins and historical evidence.
- Prefer reversible changes and Git history over manual backup copies.
- Add durable documents to `docs/README.md` in the same change.

## Current project direction

The frozen RMIC M5.4 core is architecturally complete as a generic transactional RM engine, but TAIFEX futures semantics are integration responsibilities. Current priorities are futures-aware multi-account/product state, committed R02/R32 execution reconciliation, policy/rate/outstanding controls, then full HFT insertion and A/B latency/resource validation.

A separately audited junior U50/network bundle is a candidate for a later dedicated network/PHY migration phase only. Do not replace the frozen HFT submodule wholesale. Selectively port independently verified network fixes against the then-current source, preserve official TAIFEX BODY-LENGTH semantics, pin external PHY dependencies exactly, and require matched regression/hardware A/B evidence before any HFT source-pin change.

Do not claim complete TAIFEX risk compliance until the integration P0 contracts, authoritative field semantics, end-to-end tests, timing closure, recovery behavior, and required hardware validation are complete.
