# I3 — CL2EX Futures Risk Gate

## 1. Phase identity

- Phase: `I3`
- Status: COMPLETE
- Branch: `codex/i3-cl2ex-futures-risk-gate`
- PR: `#2`
- HFT pin: `50217fad1fd580f8c451ba893f9035f4be1dc21a`
- RMIC pin: `de6c300f4f18b18296f013287ab0eca70d3abb72`
- Target clock: 156.25 MHz / 6.400 ns
- Sign-off target: U50 `xcu50-fsvh2104-2-e`

## 2. Goal

Insert a fail-closed, futures-aware CL2EX risk admission transaction between the frozen HFT 256-bit order payload and the eventual frozen R01 encoder. An order is accepted only when policy, futures reservation, and outstanding-order context insertion all succeed. Any later-stage admission failure must deterministically roll back earlier state mutation before returning a normal reject.

## 3. Atomic admission contract

```text
order_data
  -> exact account/product mapping
  -> field adapter
  -> fail-closed policy
  -> futures state RESERVE
  -> AMU order-context INSERT
  -> both success: PASS original order_data unchanged

AMU INSERT fails after RESERVE
  -> futures state RELEASE same qty
  -> rollback succeeds: REJECT with store reason
  -> rollback fails: SYSTEM/RECOVERY_REQUIRED, never PASS
```

No rejected or half-admitted order is allowed to reach the future R01 path.

## 4. Acceptance closure

### I3-01 — Atomic normalized admission controller — COMPLETE

Verified:

- policy reject performs no state/store mutation;
- accounting reject performs no store mutation;
- successful reserve + insert returns accepted exactly once;
- duplicate/full/store failure after reserve triggers RELEASE rollback;
- rollback failure is fail-closed and reports explicit recovery-required failure;
- output remains stable under result backpressure.

### I3-02 — Frozen-HFT 256-bit order gate — COMPLETE

Verified:

- PASS output payload is bit-for-bit identical to input `order_data`;
- adapter/map/policy rejects never touch state/store;
- BUY/SELL, account, product, qty, OrdType, TIF and PositionEffect reach the normalized admission request correctly;
- configuration ambiguity/miss is fail-closed.

### I3-03 — Self-checking CL2EX regressions — COMPLETE

CI covers normal admission, margin/policy rejects, duplicate/full rollback, rollback-failure injection, mapping/policy failures, result backpressure, context correctness and payload identity.

### I3-04 — Physical composition gate — COMPLETE

Real pinned RMIC AMU + futures state + I3 order gate closes on U50 at 6.400 ns:

```text
Synth WNS    +3.023 ns
Placed WNS   +2.135 ns
Routed WNS   +1.583 ns
TNS           0 ns
LUT          2392
FF           2693
RAMB36         11
RAMB18          1
DSP             10
Routing errors    0
Power         2.278 W vectorless
```

The worst path remains inside the frozen AMU XPM BRAM candidate/match/forwarding path. See `docs/results/i3_atomic_cl2ex_ooc_postroute.md`.

## 5. Non-goals retained

- modifying either frozen upstream;
- full HFT top integration;
- multi-client CL/EX runtime arbitration;
- restoring conflict-free CL II=1 at the futures-state layer;
- TAIFEX SPAN;
- network/PHY migration from the junior bundle;
- board/live-exchange validation.

## 6. Evidence policy

Functional CI uses the AMU behavioral contract stub only for transaction semantics. Collision/XPM/physical claims use local Vivado with the real pinned RMIC AMU. The final full-system HFT latency remains outside I3.

## 7. Delivered files

- `rtl/integration/hft_rmic_cl2ex_admission_v1.sv`
- `rtl/integration/hft_rmic_order_gate_v1.sv`
- `tb/tb_hft_rmic_cl2ex_admission_v1.sv`
- `tb/tb_hft_rmic_cl2ex_admission_fault_v1.sv`
- `tb/tb_hft_rmic_order_gate_v1.sv`
- `rtl/ooc/hft_rmic_i3_cl2ex_ooc_top.sv`
- `vivado/i3_cl2ex_ooc_impl.tcl`
- `scripts/run_i3_cl2ex_ooc_impl.ps1`
- `docs/results/i3_atomic_cl2ex_ooc_postroute.md`

## 8. Phase decisions

- D-20260917-11: reserve-first atomic CL2EX admission with deterministic rollback.
- D-20260917-12: I3 U50 OOC closure accepted at 156.25 MHz.

## 9. Claim limit

I3 establishes atomic CL2EX admission and OOC physical feasibility. It does not establish full frozen-HFT R01 insertion, end-to-end HFT+RMIC latency, board packet latency, TAIFEX SPAN, network/PHY migration or exchange conformance.
