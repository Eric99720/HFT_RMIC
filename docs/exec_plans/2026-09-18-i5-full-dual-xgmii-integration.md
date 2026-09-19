# I5 — Full Dual-XGMII HFT + RMIC Integration

## 1. Phase identity

- Phase: `I5`
- Current status, observation time, branch, HEAD, PR and verification: [`../project_state.json`](../project_state.json), fields `phase`, `observed_at_utc` and `verification`.
- Historical phase-start branch: `codex/i5-full-dual-xgmii-integration`; recorded PR #4 in the 2026-09-18 state. This is provenance, not verified current PR ownership or live status.
- Historical I4 handoff referenced PR #3; local commit `bb2600d0c4b79d173645f1eb30c86550f0166391` records I4 closure. Do not carry that handoff forward as the I5 next gate.
- Tool: Vivado 2022.1
- HFT pin: `50217fad1fd580f8c451ba893f9035f4be1dc21a`
- RMIC pin: `de6c300f4f18b18296f013287ab0eca70d3abb72`
- Target clock: 156.25 MHz / 6.400 ns
- Target part: U50 `xcu50-fsvh2104-2-e`

## 2. Goal

Compose the closed I4 order-data→risk→R01 boundary into the pinned dual-XGMII HFT hierarchy without modifying either upstream. Preserve frozen ownership of network/TCP, TMP login/session/maintenance, replay/report-sequence continuity, order book and strategy. Risk owns only pre-trade admission plus committed execution/account-state reconciliation.

## 3. Frozen ownership contract

```text
market XGMII RX
 -> frozen network/market path
 -> frozen decoder/order book/strategy
 -> ordinary + prebuild order_data
 -> I4 shared futures risk
 -> frozen financial_protocol_encoder_session_top
 -> frozen TCP/XGMII TX

trading XGMII RX
 -> frozen TMP decoder
 -> frozen report sequence owner / replay
 -> committed R02/R32/R03
 -> integration metadata alignment
 -> I4 shared futures risk EX2CL
```

Session R04/R05/Lxx traffic is never routed through RM admission. RM only gates strategy R01 orders.

## 4. Execution metadata problem

The pinned `hft_rx_order_book_top` already owns de-dup/replay commit and exposes committed order-state fields, but the frozen app top drops most of those outputs. PositionEffect and before_qty are not exposed by the frozen decoder interface at all.

I5 therefore creates an integration-owned derivative/composition around pinned lower-level HFT modules. Raw live and replay R02/R32 streams are tapped for futures-only metadata; mutation occurs only after the frozen report-sequence owner commits the matching event. Metadata mismatch or absence fails closed and must not mutate futures state.

## 5. Work items

### I5-01 — Integration-owned round-chip composition

- reproduce the pinned round-chip application wiring from lower-level frozen modules;
- preserve ordinary/prebuild order priority and feed both into the closed I4 risk boundary;
- feed accepted order_data into the pinned `financial_protocol_encoder_session_top` so TMP session/maintenance remains frozen-owned;
- never edit files under `deps/`.

### I5-02 — Committed execution metadata path

- expose committed order report fields from an integration-owned RX/order-book composition;
- capture PositionEffect and before_qty for live and replay R02/R32;
- require report-seq/order-id agreement between sideband metadata and the frozen committed event;
- pass R03 as a committed terminal reject using stored context as authoritative side/PositionEffect;
- fail closed on metadata mismatch.

### I5-03 — Full-system functional closure

- market event → strategy → RM reserve/context → frozen R01;
- risk reject → no R01;
- committed R02/R32 fill → same futures state/order context;
- replay/duplicate/gap remains frozen-HFT-owned;
- R03 releases reservation exactly once;
- session/maintenance traffic remains functional and outside risk admission.

### I5-04 — Physical/latency evidence

- compile the combined integration composition at 6.400 ns;
- retain real XPM AMU/state RAM;
- document utilization/timing/DRC/power;
- measure latency only with explicit boundaries and label simulation vs routed vs board evidence separately.

## 6. Design constraints

- no upstream source edits;
- no risk bypass through R01 prebuild;
- no raw decoder event may mutate RM state;
- no duplicate/replay double application;
- no second account-position source of truth;
- accepted 256-bit order_data remains immutable;
- exclusive CL/EX transaction ownership is retained. Later I5 candidates parallelize operations inside the CL transaction; they must preserve execution priority, isolation, atomic accept and compensating rollback before rejection. This does not establish CL/EX II=1 or remove owner serialization.

## 7. Non-goals

- network/PHY candidate migration (N1 remains separate);
- TAIFEX SPAN implementation;
- board/QSFP/live-exchange claim;
- CL/EX II=1 optimization;
- changing frozen TMP packet bytes/session behavior.

## 8. Acceptance before merge

I5 may close only after exact-head CI and local/full-system evidence establish the stated functional boundaries and any physical claims are tied to reproducible reports.


Functional acceptance includes both R01 producers, byte/field preservation, reject suppression, committed R02/R32/R03 release-once behavior, replay/duplicate/gap safety, keyed metadata/cache-overrun and FIFO-overflow fail-closed behavior, and reset/recovery. Full-system Scenario 10 must emit `I5_FULL_SYSTEM_FILL_TO_CLOSE_PASS` and `TB_HFT_RMIC_DUAL_XGMII_FULL_SYSTEM PASS` without `TEST_FAIL`. The prospective issue path must also prove exclusive ownership, EX priority, no non-owner mutations, and rollback/fault handling through the focused candidate regressions.

Physical acceptance requires the combined top with real XPM RAM at the target above: full route, WNS >= 0, TNS = 0, zero routing errors, and reviewed utilization, DRC, power estimate and critical paths. Latency uses matched market-XGMII START to trading-XGMII R01 START boundaries across 0/1280/2560/3840/5120 ps phases, with source/config/package provenance. Earlier PASS metrics are comparison references, not a waiver for the current candidate. Required CI must pass on the reviewed head and phase delivery must be verified before closure.

## 9. Verification and recovery plan

For the source selected through canonical state, verify HEAD/configuration and unchanged dependency pins before relying on upstream interfaces. Obtain existing packages for that exact source or run the named gates in an authorized implementation session:

1. `pwsh .\scripts\preflight.ps1`, including the parallel admission, L0 state cache, fast AMU, fast success join and prospective CL issue focused regressions; verify required CI separately.
2. `pwsh .\scripts\run_i5_dual_xgmii_full_system_xsim.ps1`; review all functional markers and failed attempts.
3. `pwsh .\scripts\run_i5_latency_phase_sweep.ps1`; compare all five phases with the recorded 43-cycle reference and pinned-HFT baseline, retaining explicit shadow/prebuild marker semantics.
4. `pwsh .\scripts\run_i5_dual_xgmii_full_system_ooc.ps1`; review the real-XPM post-route package against physical acceptance.

These commands are future evidence gates, not commands executed by the 2026-09-20 instruction update. Preserve failed packages and compare their manifests before assigning causes. The historical measured commits remain recovery references; changing branch/worktree/history or upstream pins is not authorized by this plan update.

## 10. Execution log

- **2026-09-18 — preparation and correction history.** Local history records terminal-beat execution-metadata capture (`60cf3d6`), Scenario 10 report-sequence alignment (`d32c2cc`), helper namespace repair (`04b5d37`, `31fda29`), back-to-back CDC scenario isolation (`f22fa78`) and duplicate speculative R01 suppression (`4a78931`). OOC preparation then repaired the Tcl filelist parser (`71082f7`), changed the implementation flow (`2ff2693`), and introduced risk-ingress/CRC timing changes (`ef63824`, `5628eda`). These commits explain repairs; their existence is not independent proof of a successful run. Preserve failure logs when reviewing the corresponding packages.
- **2026-09-19 — historical functional/physical A/B.** The [durable result](../results/i5_latency_recovery_candidate.md) records full-system XSim and real-XPM routed OOC PASS at timing-safe source `52aa8b98c35b3de32b23d3cfe16c13e65e659a2f` (WNS +0.016 ns) and latency-recovery source `d788edb42b53d8c52771832e3eb7125101f7bfeb` (WNS +0.022 ns), both TNS 0. This update reads the summary; it does not rerun or independently recertify the raw packages.
- **2026-09-19 — completed historical SC5 sweep.** Package `HFT_RMIC_i5_latency_phase_sweep_20260919-040931.zip` names measured source `768296ed28b12c0d14e1fc4f8d115a94bad0e8ca`; all five phases PASS, 270.080–275.200 ns, 43 conservative cycles and +12 cycles against the pinned-HFT reference. Commit `ff28d11` records the sweep. It supersedes the earlier sweep-pending prose for that source only.
- **2026-09-19 — later candidate lineage.** Local history adds parallel atomic admission (`c0ecce8`, enabled by `75f8c17`), L0 state cache (`8f840eb`, `d75ebb2`), integration-owned fast AMU derivative (`932b31e`, `628625d`), fast success join (`1cc5996`, `1bd668b`), net-delay-aware placement (`7cab2a1`, guard `0530ae4`) and prospective CL issue (`18c38db`, `53dbadb`, guard `6991f79`). Source inspection shows all five candidate modes enabled in the I5 app. Presence of code, regression runners and CI configuration does not establish their PASS status.
- **2026-09-20 — instruction/governance-only reconciliation.** Local checkout inspection matched `6991f79f813f1b212d35014636793ba2ddb37d40`; current identity is owned by project state. Reconciled handoff/state/plan/index/result notes, retired expired I4 local-edit disposal instructions and corrected post-route evidence wording. Historical failures, AMU errata and measured source versions remain preserved. No RTL conversion, simulations, builds, dependency edits or Git publication are part of this change. Current PR/CI were not queried live; I5 remains VERIFYING.
- **2026-09-20 — RTL language and instruction policy.** [AGENTS.md](../../AGENTS.md) and [D-20260920-19](../../DECISIONS.md#d-20260920-19--verilog-only-integration-rtl-and-scoped-instruction-maintenance) require Verilog IEEE 1364-2005 for integration synthesizable RTL (`.v`/`.vh`). Existing 26 `.sv` and 4 `.svh` sources remain a legacy backlog; simulation-only testbenches may use SystemVerilog and frozen/vendor IP stays untouched. This policy does not establish existing RTL compliance. Source pins and protected instruction sections were checked during preparation. Instruction-update validation covers project-record synchronization, layout, Vivado Tcl compatibility, skill/frontmatter/reference consistency, exact diff and backup/restore integrity. It does not establish functional, latency or physical acceptance for the candidate.

## 11. Governance reconciliation and outcome limits

[D-20260920-20](../../DECISIONS.md#d-20260920-20--resume-the-observed-i5-branch-and-retire-historical-branch-creation-instructions) adopts the existing branch recorded in project state as the sole active I5 working branch. Historical stacked-candidate branches/commits remain provenance and recovery references. The 2026-09-19 instruction to create another stacked branch is superseded; continue phase work on the existing branch. No refs or history are changed by this record update.

Before Git publication, verify the current remote phase PR, base and CI, then reconcile delivery with the one-phase/one-branch/one-PR policy. Historical PR #4 is not proof of current candidate PR ownership. This delivery check does not block authorized local work or introduce a new per-step approval requirement.

Keep I5 functional and physical acceptance intact. Historical measurements remain source-specific; this governance update closes no implementation gate and does not complete I5. Preserve frozen upstreams, fail-closed recovery, committed execution authority, and the separation of simulation, post-route OOC and hardware claims.

## 12. GitHub synchronization and monitoring policy follow-up

2026-09-20: User authorized current GitHub synchronization and standing phase-completion delivery. Live inspection confirms draft PR #10, based on `codex/i5-fast-join`, with existing I5 PRs #4-#9 still open; preserve the stack. Governance/integration CI at source `6991f79` passed, while full-system/physical/latency acceptance remains unverified. D-20260920-21 and the owning workflow define phase delivery and low-frequency monitoring. This documentation delivery launches no Vivado run or active schedule. Validate with documentation preflight, synchronized records, reviewed diff and post-push remote/CI checks.
