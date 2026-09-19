# HFT_RMIC documentation index

Start here for durable project context. Current execution state is in [`../CURRENT_PHASE.md`](../CURRENT_PHASE.md); repository-wide behavior is governed by [`../AGENTS.md`](../AGENTS.md).

## Project management

- [`project_state.json`](project_state.json) — canonical shared phase/task/milestone state.
- [`project_management_workflow.md`](project_management_workflow.md) — state synchronization, phase lifecycle and handoff workflow.
- [`repository_layout.md`](repository_layout.md) — canonical file placement and cleanup rules.
- [`results_policy.md`](results_policy.md) — evidence layers, provenance and claim boundaries.
- [`../PLANS.md`](../PLANS.md) — ExecPlan format.
- [`exec_plans/`](exec_plans/) — living phase plans.

## Frozen source and architecture

- [`source_baselines.md`](source_baselines.md) — exact read-only HFT/RMIC source identities.
- [`integration_architecture.md`](integration_architecture.md) — intended HFT → policy/accounting → RMIC → TMP composition.
- [`rmic_gap_analysis.md`](rmic_gap_analysis.md) — 2023 bidirectional-risk thesis vs frozen RMIC gap analysis and prioritized P0/P1/P2 controls.
- [`preintegration_risk_decisions.md`](preintegration_risk_decisions.md) — pre-integration safety/accounting decisions.
- [`research_notes/hft_network_candidate_audit.md`](research_notes/hft_network_candidate_audit.md) — completed audit and selective-migration disposition for the supplied junior U50 network/PHY bundle; no upstream pin change is implied.

## TAIFEX / risk contracts

- [`taifex_futures_accounting_contract_v1.md`](taifex_futures_accounting_contract_v1.md) — futures OPEN/CLOSE long/short accounting v1 and margin-model limits.

The authoritative TAIFEX protocol references themselves remain in the pinned HFT submodule under `deps/hft-full-system-fpga/docs/references/taifex/`. This repository records integration interpretations and tests; it does not duplicate or edit the upstream reference library.

## Results

- [`results/i2_futures_state_ooc_postroute.md`](results/i2_futures_state_ooc_postroute.md) — I2 real-AMU U50 OOC/post-route closure, timing-repair history, resources, DRC and claim limits.
- [`results/i3_atomic_cl2ex_ooc_postroute.md`](results/i3_atomic_cl2ex_ooc_postroute.md) — I3 atomic CL2EX mapping/policy/reserve/rollback plus real-AMU U50 OOC closure.

- [`results/i4_r01_byte_parity_xsim.md`](results/i4_r01_byte_parity_xsim.md) — commit-specific corrected-AMU R01 byte parity and reject suppression.
- [`results/i4_r01_path_ooc_postroute.md`](results/i4_r01_path_ooc_postroute.md) — I4 real-XPM U50 post-route OOC evidence and claim limits.
- [`results/i5_latency_recovery_candidate.md`](results/i5_latency_recovery_candidate.md) — historical I5 functional/physical A/B and completed 43-cycle SC5 sweep; later candidate acceptance remains separate.
- [`exec_plans/2026-09-18-i5-full-dual-xgmii-integration.md`](exec_plans/2026-09-18-i5-full-dual-xgmii-integration.md) — owning I5 acceptance gates, candidate provenance and governance reconciliation.

## Historical/current ledgers

At repository root:

- [`../TASKS.md`](../TASKS.md) — current task/acceptance board.
- [`../PROGRESS.md`](../PROGRESS.md) — chronological integration history.
- [`../DECISIONS.md`](../DECISIONS.md) — append-only durable decisions.
- [`../CHANGELOG.md`](../CHANGELOG.md) — concise delivered milestones.

When adding a durable document, add it to the appropriate section here in the same change.
