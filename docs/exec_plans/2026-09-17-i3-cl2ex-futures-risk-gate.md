# I3 — CL2EX Futures Risk Gate

## 1. Phase identity

- Phase: `I3`
- Status: ACTIVE
- Branch: `codex/i3-cl2ex-futures-risk-gate`
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

## 4. Work items

### I3-01 — Atomic normalized admission controller

Implement `hft_rmic_cl2ex_admission_v1` as an exclusive client of the I2 futures state manager and order-context store.

Acceptance:

- policy reject performs no state/store mutation;
- accounting reject performs no store mutation;
- successful reserve + insert returns accepted exactly once;
- duplicate/full/store failure after reserve triggers RELEASE rollback;
- rollback failure is fail-closed and reports recovery required;
- output remains stable under result backpressure.

### I3-02 — Frozen-HFT 256-bit order gate

Implement `hft_rmic_order_gate_v1` around existing exact maps, field adapter and policy shell.

Acceptance:

- PASS output payload is bit-for-bit identical to input `order_data`;
- adapter/map/policy rejects never touch state/store;
- BUY/SELL, account, product, qty, OrdType, TIF and PositionEffect reach the normalized admission request correctly;
- configuration ambiguity/miss is fail-closed.

### I3-03 — Self-checking CL2EX regressions

Cover:

- BUY OPEN accepted;
- SELL OPEN accepted without long inventory;
- BUY/SELL CLOSE inventory checks;
- margin reject;
- kill-switch/not-ready/unsupported policy reject;
- duplicate order ID rollback;
- order-store-full rollback;
- downstream result backpressure;
- accepted payload identity;
- no leaked reservation on any recoverable store failure.

### I3-04 — Physical composition gate

Compose the real pinned RMIC AMU, pipelined futures state manager and I3 admission controller in an OOC harness. Require BRAM use, full route and WNS >= 0 at 6.400 ns. Full frozen-HFT datapath insertion remains a later phase.

## 5. Non-goals

- modifying either frozen upstream;
- full HFT top integration;
- multi-client CL/EX runtime arbitration;
- restoring conflict-free CL II=1 at the futures-state layer;
- TAIFEX SPAN;
- network/PHY migration from the junior bundle;
- board/live-exchange validation.

## 6. Evidence policy

CI may use the AMU behavioral contract stub for functional transaction semantics. Collision/XPM/physical claims require local Vivado using the real pinned RMIC AMU. The final full-system HFT latency remains outside I3.

## 7. Planned deliverables

- `rtl/integration/hft_rmic_cl2ex_admission_v1.sv`
- `rtl/integration/hft_rmic_order_gate_v1.sv`
- dedicated self-checking TBs and runners
- I3 OOC top/Tcl/PowerShell package runner
- durable I3 result document and decision records
