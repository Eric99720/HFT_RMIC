# I5 Latency-Recovery Candidate — Functional and Physical A/B

Date: 2026-09-19

Record reconciliation: 2026-09-20 (instruction/governance-only). All PASS and timing values below apply to the listed measured commits. Current branch, HEAD, PR and verification status are owned by [`../project_state.json`](../project_state.json); later candidate source changes are logged in the [I5 plan](../exec_plans/2026-09-18-i5-full-dual-xgmii-integration.md). No current-HEAD acceptance is inferred from this historical note.

## Scope

This note compares the verified timing-safe I5 baseline against the latency-recovery candidate. Both use the same pinned upstreams:

- HFT: `50217fad1fd580f8c451ba893f9035f4be1dc21a`
- RMIC: `de6c300f4f18b18296f013287ab0eca70d3abb72`
- U50 part: `xcu50-fsvh2104-2-e`
- target clock: 156.25 MHz / 6.400 ns

The comparison is local Vivado 2022.1 simulation/OOC evidence. It is not a board, QSFP, optics, live-exchange, or hardware latency claim.

## Candidates

| Item | Timing-safe baseline | Latency-recovery candidate |
| --- | --- | --- |
| Commit | `52aa8b98c35b3de32b23d3cfe16c13e65e659a2f` | `d788edb42b53d8c52771832e3eb7125101f7bfeb` |
| Branch | `codex/i5-full-dual-xgmii-integration` | `codex/i5-latency-recovery` |
| Active risk ingress slice | yes | no |
| Hot account/product map cache | no | yes |
| Full-system XSim | PASS | PASS |
| Real-XPM routed OOC | PASS | PASS |

## Functional evidence

The latency-recovery XSim is clean and preserves the full I5 contract:

- byte-exact ARP/TCP/TMP traffic;
- UDP market -> R01;
- BUY OPEN -> live R02 full fill -> same RMIC futures state -> SELL CLOSE;
- committed execution FIFO/metadata safety;
- back-to-back market CDC with no duplicate R01;
- source reset recovery;
- bad-FCS drop;
- trading-port market isolation;
- `TB_HFT_RMIC_DUAL_XGMII_FULL_SYSTEM PASS`.

The direct R01 stream still reports `app_to_start_cycles=1` in Scenario 3 and both Scenario 10 orders.

Absolute testbench cycle numbers are not used as the latency-recovery proof because configuration/cache warm-up changes scenario setup time. At the initial A/B write-up, the dedicated five-phase SC5 measurement was the next gate. The completed measurement below supersedes that pending statement for source `768296e`.

## Physical A/B

| Metric | Timing-safe baseline | Latency-recovery | Delta |
| --- | ---: | ---: | ---: |
| Routed WNS | +0.016 ns | +0.022 ns | +0.006 ns |
| TNS | 0.000 ns | 0.000 ns | 0 |
| market_rx_clk WNS | +0.054 ns | +0.168 ns | +0.114 ns |
| trading_clk WNS | +0.016 ns | +0.022 ns | +0.006 ns |
| Failing endpoints | 0 | 0 | 0 |
| Routing errors | 0 | 0 | 0 |
| LUTs | 56,668 | 57,025 | +357 (+0.63%) |
| FFs | 31,209 | 31,151 | -58 (-0.19%) |
| RAMB36 | 20 | 20 | 0 |
| RAMB18 | 1 | 1 | 0 |
| DSP | 10 | 10 | 0 |
| Estimated on-chip power | 2.553 W | 2.686 W | +0.133 W (+5.21%) |

The power values are Vivado vectorless estimates and must not be treated as measured board power.

## Timing-path interpretation

The candidate's routed worst path is inside the pinned HFT trading network RX path:

`u_trading_core/u_network_rx_fast_path/u_legacy/ip_total_len_reg[3]`
-> `u_trading_core/u_network_rx_fast_path/u_legacy/state_reg[2]_rep__1`

with routed WNS +0.022 ns.

The previously critical speculative-strategy -> RMIC exact-map/admission path is no longer the routed worst path, and the one-cycle `hft_rmic_order_ingress_slice_v1` is no longer active in the I5 composition.

The hot-map cache keeps the generic exact maps as the configuration source of truth, caches only the bridge-owned hot account/product keys, invalidates on configuration writes, and still requires the packed order keys to match the cached keys before reporting a map hit.

## Historical A/B conclusion (2026-09-19; superseded in part)

The recorded `d788edb` candidate passed the functional and physical checks listed above. Those results supported further latency evaluation; they did not accept subsequent candidates or close the full I5 phase.

**2026-09-20 supersession:** the initial write-up left the intended 6.4 ns recovery across asynchronous phase unproven and requested a five-phase SC5 sweep. That sweep was subsequently recorded for `768296e` in `ff28d11`, as detailed below. The measured 43-cycle boundary is now historical evidence, not a pending sweep. It does not establish the latency or physical acceptance of the later candidate lineage; retain the complete I5 gates in the owning plan.


## Five-phase latency recertification

Measurement package for the historical measured head:
`HFT_RMIC_i5_latency_phase_sweep_20260919-040931.zip`

Manifest:

- commit: `768296ed28b12c0d14e1fc4f8d115a94bad0e8ca`
- branch: `codex/i5-latency-recovery`
- HFT pin: `50217fad1fd580f8c451ba893f9035f4be1dc21a`
- RMIC pin: `de6c300f4f18b18296f013287ab0eca70d3abb72`
- clean worktree
- all five SC5 phases PASS

Measured market-XGMII START -> trading-XGMII R01 START:

| Phase | Internal latency | Conservative cycles | CDC commit delta |
| ---: | ---: | ---: | ---: |
| 0 ps | 275.200 ns | 43 | 57.600 ns |
| 1280 ps | 273.920 ns | 43 | 56.320 ns |
| 2560 ps | 272.640 ns | 43 | 55.040 ns |
| 3840 ps | 271.360 ns | 43 | 53.760 ns |
| 5120 ps | 270.080 ns | 43 | 52.480 ns |

Summary:

- min: **270.080 ns**
- max: **275.200 ns**
- conservative max: **43 cycles**
- phase jitter: **5.120 ns**
- application first-valid -> trading XGMII START: **6.400 ns** for every phase

The pinned HFT reference at the same boundary is 31 cycles, 193.280-198.400 ns, with the same 5.120 ns phase jitter. Therefore the integrated I5 path adds a deterministic **76.800 ns / 12 cycles** across every sampled phase.

This is a useful decomposition result:

- asynchronous CDC behavior is unchanged in shape; the phase jitter remains exactly 5.120 ns;
- the application-valid -> XGMII START path remains one 6.4-ns cycle;
- all 12 added cycles are therefore upstream of application first-valid and downstream of the frozen speculative market decision, i.e. in the risk-admission/handoff portion of the integrated path.

The SC5 log also shows the speculative shadow-decision marker exactly one cycle before the pinned-HFT reference XGMII-start point would occur. On I5, shadow decision -> application first-valid is 76.800 ns and shadow decision -> trading XGMII START is 83.200 ns. The original frozen HFT path reaches trading XGMII START 6.400 ns after that decision boundary. The difference is again exactly 76.800 ns / 12 cycles.

Note: the sweep runner's fields named `MarketToPrebuildNs`, `PrebuildToAppNs` and `PrebuildToStartNs` were derived from the `shadow_decision_ns` marker, not `prebuild_accept_ns`. The raw sample data is authoritative; future runner output should use explicit `shadow_*` names.

## Historical next latency target and later provenance

The one-cycle I5 risk-ingress slice has been successfully removed without losing 156.25-MHz post-route closure, but the remaining atomic admission sequence is still serialized:

`order capture -> futures RESERVE -> AMU INSERT -> accepted R01`

The next optimization target is therefore the transaction protocol itself, not another routing tweak. A safe candidate is to issue futures RESERVE and order-context INSERT in parallel while the shared CL owner lock prevents EX from observing either speculative mutation. Acceptance remains gated on both responses; if exactly one side succeeds, the successful side is rolled back before returning a reject. This can reduce the success path from the sum of state-manager and AMU latencies toward their maximum while preserving fail-closed atomicity.

The original 2026-09-19 note proposed a new stacked branch to preserve this 43-cycle reference. **2026-09-20 governance supersession:** retain that suggestion as historical provenance only. Local history now contains parallel admission and subsequent cache/AMU/join/prospective-issue changes; see the owning plan. D-20260920-20 resolves the working-branch direction: resume the existing I5 candidate branch identified by canonical project state, retain earlier candidates as references, and verify remote phase PR/base/CI before publication. This historical note authorizes neither a new branch nor a migration. Preserve the measured commits and failed evidence as references.

The earlier I4 failed new-INSERT assumption and narrowed I3 claim remain documented in the [I3 erratum](i3_atomic_cl2ex_ooc_postroute.md) and [corrected I4 parity result](i4_r01_byte_parity_xsim.md). Later I5 repair commits and verification gaps are recorded in the owning plan; no failed package is erased or reclassified as PASS by this reconciliation.
