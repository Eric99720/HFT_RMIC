# Decisions

Append-only durable architecture/research decisions. Do not rewrite old decisions to make later work look planned; append a superseding decision that names the prior one.

## D-20260917-01 — Separate integration repository with frozen upstreams

**Status:** Adopted.

**Decision:** `HFT_RMIC` is the sole integration workspace. `hft-full-system-fpga` and `RMIC` are pinned read-only submodules and are not modified by integration work.

**Why:** Both upstreams already contain valuable validated baselines. Mixing integration changes into either source destroys clean A/B comparison, source provenance and rollback clarity.

**Evidence:** `docs/source_baselines.md`, `.gitmodules`, dependency-contract checker.

---

## D-20260917-02 — Insert RM before the existing TMP encoder; do not replace HFT subsystems

**Status:** Adopted.

**Decision:** The nominal CL2EX path is strategy/order packer -> integration policy/accounting/RM -> original payload -> existing TMP R01 encoder. Existing network, order book, trading logic, session, encoder, TCP/IP and PCS/PMA remain owned by frozen HFT.

**Why:** RM is an inline safety gate, not a replacement for the trading stack. This preserves byte-identical accepted-order behavior and isolates integration risk.

**Evidence:** `docs/integration_architecture.md`, frozen HFT architecture, prior integrated-HFT/RM literature review.

---

## D-20260917-03 — Keep frozen RMIC M5.4 as generic transactional core; add exchange policy outside

**Status:** Adopted.

**Decision:** Product/exchange-specific order type, TIF, PositionEffect, rate, kill-switch and future volatility/liquidity policy live in `HFT_RMIC`. Do not add every rule to frozen RMIC M5.4.

**Why:** M5.4 has timing-closed AMU/order lifecycle/hazard behavior; policy evolves faster and needs a wider reject namespace than the frozen 4-bit RMIC reason field.

**Evidence:** `docs/rmic_gap_analysis.md`, `rtl/policy/hft_rmic_policy_gate.sv`.

---

## D-20260917-04 — Futures accounting v1 is long/short OPEN/CLOSE with configurable margin budget, not SPAN

**Status:** Adopted for integration research baseline.

**Decision:** Maintain separate long/short positions, pending OPEN orders and reserved CLOSE orders. OPEN margin uses host-configured `margin_per_contract`; CLOSE does not increase required margin. Unsupported PositionEffect values fail closed.

**Why:** Frozen RMIC stock-like unsigned position semantics cannot correctly represent SELL OPEN / BUY CLOSE. A deterministic versioned model is needed before full HFT integration, but it must not be misrepresented as official TAIFEX SPAN.

**Evidence:** `docs/taifex_futures_accounting_contract_v1.md`, `rtl/accounting/hft_rmic_futures_accounting_v1.sv`, self-checking accounting regression.

---

## D-20260917-05 — Frozen HFT report owner is the only R02/R32 execution mutation authority

**Status:** Adopted.

**Decision:** R02/R32 field decoding may happen earlier, but futures/RMIC state mutation occurs only from the frozen HFT report-sequence owner's committed event. Duplicate, replayed-old and gap reports must not mutate state. R03 error/reject processing uses the separate checksum-valid committed error path and is idempotent through order-context deletion.

**Why:** Applying raw decoder events can double-apply partial fills during replay/reconnect. The HFT baseline already owns sequence continuity/deduplication and should remain the single authority for R02/R32.

**Evidence:** frozen `hft_report_sequence_owner.v`, `hft_rx_order_book_top.v`, integration execution metadata tap and committed-execution regression.

---

## D-20260917-06 — Adopt phase-based repository governance

**Status:** Adopted.

**Decision:** `docs/project_state.json` is the shared-state source; current root summaries are synchronized mechanically. Substantial work uses one `codex/<phase-id>` branch and one PR through phase closure. Feature work no longer commits directly to `main`.

**Why:** Long-running FPGA/research integration needs durable state, clear task acceptance, reproducible handoff and protection from branch/document drift.

**Reference model:** adapted from `Eric99720/LOB-SOTA-Research` project governance, excluding ML/training-specific rules.

---

## D-20260917-07 — Futures state is the sole account-position source; RMIC reuse is limited to transactional primitives

**Status:** Adopted.

**Decision:** The integration-owned futures state manager is the sole source of truth for long/short position, pending OPEN, reserved CLOSE and margin-budget state. The frozen RMIC stock-like account record is not chained as a second account-state owner. Integration reuses the frozen RMIC AMU/hash/BRAM order-context primitive and its proven collision architecture, but futures account semantics remain integration-owned.

**Why:** Running both the stock-like M5.4 account mutation and futures OPEN/CLOSE accounting would create contradictory double accounting. The frozen AMU is independently useful and its 96-bit value is sufficient for the 89-bit futures order context without modifying the upstream.

**Alternatives considered:** reinterpret RMIC cash/position fields as futures state; modify frozen RMIC account record; maintain both state models. All were rejected because they either corrupt price-versus-margin semantics, violate the frozen-upstream boundary, or create dual mutable sources of truth.

**Evidence:** `rtl/integration/hft_rmic_futures_order_store_v1.sv`, `rtl/accounting/hft_rmic_futures_state_manager_v1.sv`, frozen RMIC AMU post-route evidence.

---

## D-20260917-08 — Reconcile execution with order context and authoritative quantity invariants

**Status:** Adopted.

**Decision:** Committed execution reconciliation first looks up `order_id` context, then validates report metadata before mutating futures state. R02/R32 trade uses `before_qty`, `LastQty` and `LeavesQty`; cancel and reduce use `before_qty`/`LeavesQty`; R03 releases the stored remaining reservation. Final/terminal lifecycle removes the order context, making repeated terminal events no-ops through context miss. Any mismatch fails closed.

For a trade report with active quantities:

```text
before_qty = stored_remaining_qty
before_qty >= LastQty + LeavesQty
auto_release = before_qty - LastQty - LeavesQty
```

`LastQty` becomes a FILL transition, `auto_release` becomes a RELEASE transition, and the order context is updated to `LeavesQty` or deleted at zero. This explicitly supports terminal IOC-style fill plus exchange-cancelled remainder without guessing.

**Why:** TAIFEX TMP v2.18.7 defines `before_qty` as pre-match remaining quantity, `LastQty` as the last execution quantity, and `LeavesQty` as current remaining quantity. Binding these fields to locally stored remaining quantity provides both correct lifecycle accounting and a second fail-closed defense against stale/duplicate reports.

**Evidence:** authoritative pinned TMP v2.18.7 section 2.4.2; `rtl/adapters/hft_tmp_exec_position_tap.sv`; `rtl/integration/hft_rmic_committed_execution_bridge_v1.sv`; `tb/tb_hft_rmic_committed_execution_bridge_v1.sv`; exact-head CI.

---

## D-20260917-09 — Treat the junior U50 bundle as a selective network/PHY migration candidate, not a replacement baseline

**Status:** Adopted.

**Decision:** Do not replace the frozen HFT submodule with the user-supplied junior bundle and do not advance the HFT source pin during I2. After I2 closure, evaluate a dedicated network/hardware migration phase that selectively recreates the candidate's useful behavior against the current pinned HFT source: TCP Data-Offset/options support, SYN retry, optional static-MAC lab mode, and a reproducibly pinned U50 10G PCS/GT backend. Preserve official TAIFEX `BODY-LENGTH+12`; the candidate's `+22` mode is legacy captured-PCAP compatibility only.

**Why:** The bundle contains meaningful board-level R01/R02 evidence and timing-clean U50 artifacts, but its embedded HFT snapshot has no Git identity and differs from the frozen baseline in both network and non-network files. Wholesale copying would combine promising network fixes with uncontrolled source-version regression. The copied `verilog-ethernet` tree also lacks an exact Git revision in the bundle.

**Migration acceptance:** port each functional change onto the frozen/current HFT source with focused regressions; register exact third-party PHY source identity; reproduce board R01/R02; perform matched old-vs-candidate timing/resource/latency comparison; then consider a separate HFT_RMIC source-pin migration.

**Evidence and limitations:** `docs/research_notes/hft_network_candidate_audit.md`; supplied archive reports/bitstream/PCAP and XSim studies. The archive's hardware PASS is provided evidence, not yet independently rerun by HFT_RMIC; the `398.9 ns` latency result is simulation/endpoint-attribution evidence, not hardware-measured latency.

---

## D-20260917-10 — Pipeline futures margin/state evaluation to meet the 6.400 ns hardware contract

**Status:** Adopted.

**Decision:** Keep the 156.25 MHz / 6.400 ns target and pipeline the integration-owned futures state path across BRAM capture, quantity/OPEN-CLOSE transition, registered exposure, margin multiplication, registered margin result, and decision/writeback. Do not hide the original failure with a multicycle exception or lower the clock target.

**Why:** The first real-AMU I2 route completed physically but failed setup at WNS `-6.866 ns` / TNS `-893.979 ns`. Its worst state path combined BRAM read, wide quantity arithmetic, margin DSP multiplication/comparison, next-state selection, another margin calculation, and BRAM writeback in one cycle. The pipelined implementation moved synthesis WNS from `-6.232 ns` to `+2.318 ns` and routed WNS to `+1.078 ns` with TNS `0`, proving structural timing closure rather than route luck.

**Evidence:** `docs/results/i2_futures_state_ooc_postroute.md`; `rtl/accounting/hft_rmic_futures_transition_v1.sv`; `rtl/accounting/hft_rmic_futures_state_manager_v1.sv`; packaged Vivado I2 OOC reports at integration commit `61194b7b57aa87ddf99dba6ed19e257109f87d6f`.

**Claim limit:** This decision closes the I2 OOC composition at 156.25 MHz. It does not establish timing or latency for the final full HFT+RMIC top.

---

## D-20260917-11 — CL2EX admission is an atomic reserve-plus-context transaction

**Status:** Adopted, with AMU response semantics clarified by D-20260918-14.

**Decision:** A policy-approved HFT order is not accepted until both the futures-state RESERVE and the outstanding-order AMU INSERT succeed. The ordering is RESERVE first, then INSERT. If INSERT fails because the key exists, the table is full, or another store error occurs, the controller must issue an exact RELEASE rollback before returning the reject. If rollback itself fails, the order remains rejected and the result is escalated to `ADMISSION_ROLLBACK_FAILED`; explicit recovery is required.

The original frozen-HFT 256-bit payload is carried alongside the transaction and is never rewritten. It may be released toward the future R01 path only after the atomic transaction commits.

**Why:** Reserving without an order context creates unowned exposure; inserting context without a reservation creates an exchange-visible order that is absent from risk state. Either partial state is unacceptable. Reserve-first allows the existing futures state engine to make the authoritative risk decision, while deterministic rollback restores atomicity if the AMU cannot take ownership.

**Alternatives considered:** INSERT first then RESERVE; parallel optimistic state/store mutation; treating an INSERT failure as a reject without rollback. INSERT-first requires deleting a context after an accounting reject and briefly creates an unreserved outstanding order; parallel mutation requires a more complex two-resource commit protocol; no-rollback leaks margin/position reservation. All are rejected for I3.

**Evidence:** `rtl/integration/hft_rmic_cl2ex_admission_v1.sv`, `tb/tb_hft_rmic_cl2ex_admission_v1.sv`, `tb/tb_hft_rmic_cl2ex_admission_fault_v1.sv`, `rtl/integration/hft_rmic_order_gate_v1.sv`, exact-head CI.

**Claim limit:** I3 remains serialized/correctness-first at the futures-state transaction level. This decision defines admission atomicity; it does not claim CL2EX II=1 for the integrated futures gate or final full-HFT latency.

---

## D-20260917-12 — Close I3 atomic CL2EX admission at the U50 OOC evidence layer

**Status:** Physical/OOC closure remains adopted; original actual-AMU functional-closure wording is narrowed by D-20260918-14.

**Decision:** Accept the I3 frozen-HFT mapping/policy + futures RESERVE/rollback + real pinned RMIC AMU INSERT composition as physically closed at 156.25 MHz. Preserve the I3 architecture for the next full-datapath insertion phase rather than reworking mapping or admission for additional timing margin.

**Why:** The real U50 OOC implementation at integration commit `75e06d17396d9c9f234f175013d090f329f965df` closes with synth WNS `+3.023 ns`, placed WNS `+2.135 ns`, routed WNS `+1.583 ns`, TNS `0`, and zero routing errors. The routed worst path remains in the frozen AMU BRAM candidate/match/forwarding path; the new mapping, policy and rollback logic are not the timing bottleneck.

**Evidence:** `docs/results/i3_atomic_cl2ex_ooc_postroute.md`; I3 atomic/order-gate/fault-injection regressions; packaged Vivado I3 OOC reports.

**Claim limit:** The physical timing/resource result is valid. D-20260918-14 records a later-discovered actual-AMU INSERT response contract mismatch that the original CI stub hid; real-AMU functional admission closure is therefore established only after that correction is exercised in I4.

---

## D-20260918-13 — Gate both frozen R01 producers and serialize CL/EX ownership of shared risk state

**Status:** Adopted for I4 correctness closure.

**Decision:** The ordinary frozen-HFT bridge order stream and the R01-prebuild stream must merge before risk; neither producer may feed the frozen R01 encoder without first completing the same I3 atomic admission transaction. Preserve the frozen source preference by giving prebuild priority at this merge.

CL admission and committed execution reconciliation share exactly one futures-state manager and one AMU order-context store. Arbitration is at the transaction boundary, not per memory operation: when no owner is active, a committed execution and new order arriving together select committed execution; the selected owner retains both state/store resources until its result is consumed. The non-owner remains backpressured throughout that transaction.

**Why:** The pinned XGMII-oriented HFT baseline enables `ENABLE_R01_PREBUILD=1`; intercepting only `bridge_strategy_order_data` would leave a real risk-control bypass. Separately, interleaving CL and EX operations on the same state/store can create lookup/update races and contradictory account mutations. Transaction-level ownership reuses the already-verified exclusive-client FSMs without modifying frozen upstreams and gives deterministic correctness before throughput optimization.

**Alternatives considered:** gate only the ordinary bridge path; gate after R01 formatting; per-request arbitration between CL and EX; duplicate futures state/store instances; optimistic parallel CL/EX mutation. These are rejected because they respectively allow prebuild bypass, move risk too late, permit multi-step transaction interleaving, create multiple mutable sources of truth, or require a more complex recovery protocol.

**Evidence:** `rtl/integration/hft_rmic_dual_order_source_v1.sv`; `rtl/integration/hft_rmic_shared_core_v1.sv`; `rtl/integration/hft_rmic_r01_path_v1.sv`; `tb/tb_hft_rmic_shared_core_v1.sv`; `tb/tb_hft_rmic_r01_path_stub_v1.sv`; PR #3 CI.

**Claim limit:** The I4 owner lock is correctness-first serialization and does not claim CL2EX/EX2CL concurrency or II=1. Exact frozen R01 byte parity and the real-AMU U50 risk-to-R01 physical composition remain separate local gates until their packaged evidence is reviewed.

---

## D-20260918-14 — Bind integration tests to the frozen AMU response contract

**Status:** Adopted; clarifies D-20260917-11 and narrows the functional portion of D-20260917-12.

**Decision:** Treat the pinned RMIC AMU's operation-specific `rsp_found` meaning as authoritative. A successful INSERT of a new key is `rsp_ok=1`, `rsp_status=OK`, `rsp_found=0`; INSERT with an existing key reports `rsp_ok=0`, `rsp_status=EXISTS`, `rsp_found=1`. LOOKUP/UPDATE/DELETE success reports `found=1`. CL2EX admission therefore accepts INSERT on `rsp_ok && status==OK` and must not require `found=1`.

The HFT_RMIC AMU CI stub and all order-store setup tests must reproduce this contract. UPDATE response payload is not used as the source of the newly written context; a subsequent LOOKUP verifies the new value.

**Why:** I4 real pinned-AMU/frozen-encoder XSim produced 80 baseline R01 bytes but zero integrated bytes with a held risk reject. Source audit showed the frozen AMU intentionally leaves `found=0` on a new INSERT, while the integration stub had incorrectly returned `found=1` and the admission controller required it. The mismatch caused every real-AMU new INSERT to be rolled back and rejected even though synthesis/place/route were healthy.

**Evidence:** pinned `deps/RMIC/rtl/amu_banked_double_hash_v2.sv`; uploaded `HFT_RMIC_i4_r01_parity_xsim_20260918-024121.zip`; corrected `rtl/integration/hft_rmic_cl2ex_admission_v1.sv`; corrected `tb/stubs/amu_banked_double_hash_v2_stub.sv`; corrected order-context/execution regressions; exact-head CI after the correction.

**Claim correction:** I3's reported WNS/TNS/resource/power/routing evidence remains valid. Its original CI did not prove the real-AMU new-INSERT functional response contract because the stub encoded different semantics. Real-AMU functional admission evidence must come from I4 parity/combined tests after this correction.

---

## D-20260918-15 — Preserve frozen R01 bytes across the focused risk boundary

**Status:** Adopted; closes I4-03 functional byte parity.

**Decision:** Keep the frozen HFT 256-bit order payload immutable across risk admission and feed the accepted original payload into the pinned frozen `financial_protocol_encoder`. Both the ordinary bridge producer and the R01-prebuild producer are covered by this same rule. Risk rejection must emit no R01 traffic.

**Why:** The corrected local Vivado/XSim A/B test instantiates a direct frozen-encoder baseline and a risk-integrated frozen encoder with identical R01 metadata. Both accepted producer classes produce complete 80-byte payloads that are bit-for-bit identical to the direct baseline, while a kill-switch reject produces zero integrated R01 bytes. This closes the protocol-byte-preservation question without changing the frozen encoder.

**Evidence:** `docs/results/i4_r01_byte_parity_xsim.md`; package `HFT_RMIC_i4_r01_parity_xsim_20260918-125059.zip`; integration commit `8c8733e57f70eb752d55ddbecae8ec6018ecb614`.

**Verification boundary:** XSim uses behavioral synchronous-memory fallbacks for AMU bank storage and futures-state RAM. This decision establishes functional R01 byte parity, not physical BRAM mapping, routed timing, board packet behavior, or packet latency. I4-04 remains the real-XPM U50 physical gate.

---

## D-20260918-16 — Close the focused risk-to-frozen-R01 boundary on U50

**Status:** Adopted; closes I4.

**Decision:** Accept the focused HFT order-data → futures risk → pinned frozen R01 encoder composition as closed at both functional-byte and physical-OOC evidence layers. Preserve the I4 architecture as the insertion boundary for I5 rather than reopening the encoder/risk contract.

**Why:** Corrected XSim proves exact 80-byte R01 parity for ordinary and prebuild accepted orders and zero integrated R01 bytes on kill-switch reject. The real-XPM U50 OOC composition fully routes at 156.25 MHz / 6.400 ns with synth WNS `+2.310 ns`, placed WNS `+0.966 ns`, routed WNS `+0.827 ns`, TNS `0`, and zero routing errors. The routed worst path remains inside the frozen AMU rather than policy, dual-source arbitration, shared CL/EX ownership or frozen encoder logic.

**Resources:** 5,596 LUT, 4,454 FF, 128 LUTRAM, 19 RAMB36, 1 RAMB18 and 10 DSP. Vectorless Vivado estimate is 2.365 W total on-chip power.

**Evidence:** `docs/results/i4_r01_byte_parity_xsim.md`; `docs/results/i4_r01_path_ooc_postroute.md`; packages `HFT_RMIC_i4_r01_parity_xsim_20260918-125059.zip` and `HFT_RMIC_i4_r01_path_ooc_impl_20260918-134618.zip`.

**Claim limit:** I4 does not establish the full dual-XGMII top timing or market-packet-to-wire latency. It also does not establish board/QSFP latency, TAIFEX SPAN, live-exchange interoperability, or exchange conformance. I5 must integrate this closed boundary into the pinned full-system hierarchy and remeasure the combined top.

---
## D-20260918-17 — Key committed execution metadata and queue exchange events before serialized risk

**Status:** Adopted for I5 full-system integration.

**Decision:** Futures-only R02/R32 metadata is captured from both the live TMP stream and the frozen replay stream, then matched to the frozen report-sequence owner's committed event by `msg_type + order_id + report_seq`. A committed R02/R32 may reach RM state mutation only when that identity match succeeds. R03 does not require raw PositionEffect/before_qty because the stored order context is authoritative for release semantics.

The frozen report owner emits committed events as pulses, while the I4 shared risk core can be temporarily busy with CL admission. I5 therefore inserts a committed-execution FIFO between the frozen committed event and the serialized shared risk core. FIFO overflow is sticky, blocks new admission through recovery-required, and may only be cleared as part of explicit recovery/state reconstruction; exchange events must never be silently dropped.

**Why:** Time-coincidence between raw decoder output and later replay commit is not a safe metadata contract, and direct pulse-to-ready/valid wiring can lose an execution when CL owns the risk transaction. Keyed alignment preserves frozen replay/de-dup authority; buffering preserves event delivery across short-lived RM backpressure.

**Evidence:** `rtl/adapters/hft_tmp_exec_metadata_tap_v2.sv`; `rtl/integration/hft_rmic_committed_exec_event_adapter_v1.sv`; `rtl/integration/hft_rmic_exec_commit_fifo_v1.sv`; associated I5 self-checking regressions; `rtl/integration/hft_rmic_rx_order_book_top_v1.sv`; `rtl/integration/hft_rmic_round_chip_app_top_v1.sv`.

**Claim limit:** Current evidence is unit/integration-source level until the pinned private HFT/RMIC sources are compiled in local full-system XSim and real-XPM U50 OOC. Queue depth 8 is a correctness buffer, not a throughput proof or exchange burst guarantee.

---
## D-20260918-18 — Require bidirectional full-system futures-state closure before I5 functional sign-off

**Status:** Adopted for I5 full-system acceptance.

**Decision:** I5 functional closure requires a single full dual-XGMII scenario that proves both directions of the integrated state loop, not only market-to-R01 transmission. The required sequence is:

```text
market update
 -> frozen strategy BUY OPEN
 -> futures risk RESERVE + order context
 -> frozen/session/network R01
 -> live R02 full fill
 -> frozen report-sequence owner commit
 -> keyed futures metadata match
 -> committed-event FIFO
 -> shared RM EX2CL mutation (long_position becomes available)
 -> later market update produces SELL
 -> PositionEffect CLOSE
 -> the same futures state accepts SELL CLOSE
 -> second frozen/session/network R01
```

The integration-owned XGMII/full-system derivatives expose `cfg_position_effect` so OPEN/CLOSE can be selected without modifying the pinned HFT upstream. A second metadata event may not silently overwrite an unconsumed live/replay metadata cache; overrun is fail-closed and escalates recovery-required. Same-cycle consume-plus-next-metadata is allowed as an atomic cache replace.

**Why:** A market-to-R01 smoke proves only CL2EX insertion. It does not prove that committed exchange reports reach the same futures state used by later admission. Likewise, relying on implicit timing between raw metadata and committed report delivery is weaker than an explicit cache ownership rule. The fill-to-close sequence makes the shared-state dependency observable: without a successful committed BUY OPEN fill, the subsequent SELL CLOSE must fail with insufficient long position.

**Evidence before local XSim:** `rtl/integration/hft_rmic_committed_exec_event_adapter_v1.sv`; metadata overrun/atomic-replace unit regression; `tb/tb_hft_rmic_dual_xgmii_full_system.sv` Scenario 10; derived hierarchy contract checker; exact-head CI.

**Claim limit:** The Scenario 10 source and unit contracts are not themselves full-system simulation evidence. I5-03 remains VERIFYING until local pinned-source XSim emits `I5_FULL_SYSTEM_FILL_TO_CLOSE_PASS` and the overall full-system PASS marker without `TEST_FAIL`.

---

## D-20260920-19 — Verilog-only integration RTL and scoped instruction maintenance

**Status:** Adopted by explicit user instruction on 2026-09-20 (Asia/Taipei).

**Decision:** Integration-owned synthesizable RTL uses Verilog (IEEE 1364-2005), `.v` modules and `.vh` headers. This covers adapters, wrappers and OOC tops. Simulation-only SystemVerilog testbenches are outside the RTL language restriction. Frozen upstream sources and vendor-generated IP retain their pinned/original language; integration-owned wrappers follow the rule. `AGENTS.md` owns the detailed implementation requirements.

**Migration boundary:** The current repository still contains integration-owned `.sv`/`.svh` sources. They remain an explicit legacy backlog. Changing their synthesizable logic requires a scoped migration of the affected module and required integration headers, updated source lists/includes/runners, a Verilog-mode check and the existing behavior/timing acceptance. This policy change does not rename sources, convert RTL, change upstream pins or recertify prior results. Broad conversion requires its own implementation scope and evidence.

**Why:** The user requires Verilog RTL. Explicit arithmetic, clock/reset crossings, assignment ownership and transfer/backpressure contracts address concrete FPGA failure modes while preserving the existing safety/evidence boundaries. Instruction maintenance also narrows routine record-update triggers and removes stale operational commands without weakening acceptance criteria.

**Alternatives:** Immediate repository-wide conversion was not selected for this instruction-only task because it would change source identities, build references and verification scope. Allowing new SystemVerilog RTL was rejected by the user's language requirement.

**Verification / limits:** Validate instruction consistency, source pins, project records, references, layout and diffs for this change. Existing `.sv` filenames and mixed-language regression success do not prove Verilog compliance. Functional simulation, post-route and hardware evidence remain tied to their recorded source versions; no new hardware or compliance claim is made.

---

## D-20260920-20 — Resume the observed I5 branch and retire historical branch-creation instructions

**Status:** Adopted as record reconciliation; no Git operation performed.

**Decision:** `docs/project_state.json` identifies the existing I5 candidate branch as the sole active working branch for continued phase work. Earlier timing-safe, latency-recovery and stacked-candidate branches/commits are historical comparison and recovery references. The former result-note instruction to create another stacked branch is superseded. Resume the existing branch under the one-phase/one-branch/one-PR policy; do not create another branch solely because a new conversation or optimization subtask begins.

**Why:** Local history already contains the later candidate. Treating an old branch-creation suggestion as a current instruction would reproduce the drift instead of repairing it. This decision reconciles operational records while preserving all existing refs, unique evidence and source pins.

**Delivery boundary:** Current PR ownership and CI are unverified. Before Git publication, inspect the remote phase PR, base and reviewed head, and reconcile delivery against the existing phase PR rather than assuming historical PR #4 owns the current candidate. That delivery check does not block already-authorized local investigation, implementation or verification. No merge, push, branch deletion, history rewrite or new branch is authorized by this documentation update.

**Evidence / limits:** The local checkout at `6991f79f813f1b212d35014636793ba2ddb37d40` and the I5 result/ExecPlan lineage establish the observed working state. Historical PASS remains commit-specific; phase acceptance remains unchanged and I5 remains VERIFYING. This decision supersedes only the obsolete branch-creation direction in `docs/results/i5_latency_recovery_candidate.md`, not its measurements or recovery value.

---

## D-20260920-21 — Phase delivery and low-frequency long-job monitoring

**Status:** Adopted by explicit user instruction on 2026-09-20 (Asia/Taipei).

**Decision:** Synchronize publishable project work and reviewed evidence to GitHub at every completed research/integration phase, using the existing phase branch/PR and verifying the delivered remote commit and CI. This grants routine scoped Git delivery authority; merge still requires phase acceptance and passing required checks. Raw/private artifacts retain the results-policy boundary and are represented by compact provenance where appropriate.

**Monitoring:** Use deterministic completion/status checks where possible, normally every 10 minutes or every 30-60 minutes for stable multi-hour jobs. Model/scheduler follow-up is reserved for meaningful changes or completion/failure; stop monitoring when the run ends. Detailed procedure is owned by `docs/project_management_workflow.md`.

**Current delivery context:** Live GitHub inspection found PR #10 for the active prospective-CL branch, based on `codex/i5-fast-join`, with earlier I5 PRs #4-#9 still open. Preserve this existing stack during synchronization; no phase merge or PR restructuring is part of this update. The prior source `6991f79` has successful governance/integration CI; that does not establish full-system XSim, post-route or latency acceptance for I5.

**Why / limits:** Durable phase delivery prevents stale repository handoffs. Low-frequency deterministic monitoring avoids spending model tokens on healthy unchanged processes. This policy update launches no OOC job or live monitoring schedule.

---

## Decision format for future entries

Each new decision should record:

- ID/date and status;
- decision;
- alternatives considered when material;
- reason;
- evidence/source references;
- superseded decision ID if applicable;
- verification/claim limitations.
