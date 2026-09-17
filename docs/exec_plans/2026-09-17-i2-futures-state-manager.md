# I2 — Futures State Manager

## 1. Phase identity

- Phase: `I2`
- Status: RUNNING
- Branch: `codex/i2-futures-state-manager`
- Draft PR: `#1`
- HFT pin: `50217fad1fd580f8c451ba893f9035f4be1dc21a`
- RMIC pin: `de6c300f4f18b18296f013287ab0eca70d3abb72`
- Sign-off tool: Vivado 2022.1
- Target: `xcu50-fsvh2104-2-e`
- Clock: 156.25 MHz / 6.400 ns

## 2. Goal

Turn the verified stateless futures accounting v1 transition primitive into a bounded multi-account/multi-product state subsystem, then bind only committed/de-duplicated R02/R32 execution events to it.

The phase closes the semantic/state-management gap between a single transition function and a usable futures RM subsystem without modifying either upstream repository.

### Non-goals

- full HFT datapath insertion;
- official TAIFEX SPAN implementation;
- volatility/stop-loss/liquidity policy;
- board/QSFP validation;
- upstream RMIC/HFT source modifications;
- multi-leg/options PositionEffect A/7 support unless separately decided.

## 3. Architecture

Verified state path after I2-02:

```text
(account_id, product_id, event)
    -> fail-closed configured-key lookup
    -> XPM-backed futures state record
    -> hft_rmic_futures_accounting_v1
    -> atomic full-record commit
    -> response / readback
```

State record owns:

```text
enabled
margin_budget
margin_per_contract
long_position
short_position
pending_open_long
pending_open_short
reserved_close_long
reserved_close_short
```

Reset clears only the entry-ownership/configured bitmap. Stale BRAM contents are therefore inaccessible until explicit host/recovery configuration restores the entry.

I2-03 target:

```text
raw R02/R32
  -> frozen HFT decoder + integration PositionEffect tap
  -> frozen HFT report-sequence owner
  -> COMMIT only
  -> order_id lookup in integration-owned futures order context
  -> exact account/product/side/PositionEffect + remaining quantity
  -> futures state-manager FILL/RELEASE
  -> order-context UPDATE/DELETE
```

A committed report contains `order_id`, but futures state is keyed by `(account_id, product_id)`. Therefore I2-03 requires explicit outstanding-order metadata ownership rather than attempting to infer state keys from the report.

## 4. Contracts and authority

- Side inside frozen HFT decoder: BID/BUY=`0`, ASK/SELL=`1`; matches normalized RMIC side.
- R01/R02/R32 quantity is 16-bit TMP quantity, zero-extended internally.
- PositionEffect v1: only ASCII `O` OPEN and `C` CLOSE are admitted to accounting.
- Margin v1 is project-configured `margin_per_contract × gross open exposure`; no SPAN claim.
- R02/R32 PositionEffect comes from the integration-owned fixed-offset tap because the frozen HFT decoder does not expose it.
- Only the frozen report-sequence owner commit authorizes execution mutation.
- The frozen RMIC stock-like account state is **not** a second futures-accounting source of truth. I2/I3 integration may reuse RMIC AMU/order-lifecycle primitives while futures mutable account/product state remains owned by the integration layer.

Authoritative protocol interpretation comes from the pinned HFT reference tree under `docs/references/taifex/期交所TCPIP_TMP_v2.18.7/`.

## 5. Acceptance criteria

### I2-01 governance — COMPLETE

- required governance files exist;
- project-state sync check passes;
- repository layout check passes;
- CI runs governance plus functional regressions;
- one branch/PR owns the phase.

Evidence: governance job passes on phase branch; draft PR #1 is open.

### I2-02 state manager — COMPLETE

Self-checking simulation proves:

1. account/product configuration/readiness is fail-closed;
2. `(account A, product X)` mutation cannot affect `(account B, product X)` or `(account A, product Y)`;
3. BUY OPEN reserve/fill/release updates pending long/long correctly;
4. SELL OPEN reserve/fill/release updates pending short/short correctly;
5. SELL CLOSE reserves/releases/fills long only;
6. BUY CLOSE rejects when short inventory is insufficient;
7. margin limit rejects without mutation;
8. response identifies exact key and state;
9. configuration has deterministic priority over simultaneous request;
10. reset removes configured ownership until explicit recovery/configuration.

Exact-head push CI `35212246246` passes governance and integration-regression. State-manager markers:

```text
HFT_RMIC_STATE_KEY_ISOLATION_PASS
HFT_RMIC_STATE_SHORT_OPEN_PASS
HFT_RMIC_STATE_LONG_CLOSE_PASS
HFT_RMIC_STATE_MARGIN_REJECT_PASS
HFT_RMIC_STATE_FAIL_CLOSED_PASS
HFT_RMIC_STATE_CFG_PRIORITY_PASS
HFT_RMIC_STATE_RESET_RECOVERY_PASS
HFT_RMIC_FUTURES_STATE_MANAGER_TB_PASS
```

### I2-03 committed execution/order-context bridge — RUNNING

Simulation must prove:

- accepted CL2EX order context records exact `account_id/product_id/side/PositionEffect/remaining_qty` under `order_id`;
- committed R02/R32 trade event resolves the exact context and mutates futures state exactly once;
- duplicate old report does not mutate;
- sequence gap does not mutate;
- replayed report accepted by the frozen sequence-owner semantics mutates once;
- PositionEffect metadata belongs to the same committed report/order context;
- partial fills update remaining quantity;
- final fill deletes outstanding context;
- cancel/reduce/reject release behavior is enabled only where authoritative quantity semantics are explicitly implemented and tested; unsupported report semantics fail closed.

### I2-04 OOC

- declared OOC scope uses 6.400 ns;
- WNS >= 0 ns, TNS = 0;
- utilization reviewed;
- RAM implementation reviewed;
- evidence level clearly labeled OOC/post-route as appropriate.

## 6. Implementation milestones

1. Governance + project-state enforcement — complete.
2. `hft_rmic_futures_state_manager_v1.sv` + XPM state RAM — complete.
3. Multi-key self-checking regression — complete.
4. Integration-owned futures order context keyed by `order_id` — active.
5. Committed execution bridge / metadata alignment — active after order context.
6. Replay/dedup self-checking regression using frozen-owner semantics or exact pinned module — pending.
7. Vivado OOC runner and packaged results — pending.
8. Phase evidence/decision update and PR closure — pending.

## 7. Verification plan

Fast CI:

```text
scripts/run_adapter_iverilog.sh
scripts/run_accounting_iverilog.sh
scripts/run_state_manager_iverilog.sh
project record sync check
repository layout check
```

I2-03 will add focused order-context/committed-execution regression before being considered complete.

Local Vivado gate after functional closure:

```text
Vivado 2022.1
xcu50-fsvh2104-2-e
6.400 ns
```

No full-system HFT latency claim in I2.

## 8. Execution log

### 2026-09-17 — phase start

- User setup confirmed exact frozen submodule pins.
- Reviewed `LOB-SOTA-Research` governance and adopted project-state/phase/decision/layout concepts adapted for FPGA/HFT; ML/training-specific rules were intentionally excluded.
- Created `codex/i2-futures-state-manager` from integration main head `51d8219...`.
- Opened draft PR #1 for the complete I2 lifecycle.
- I1 functional CI entering I2 was green: adapters/policy, futures accounting v1 and execution PositionEffect tap.

### 2026-09-17 — governance milestone

- Added `AGENTS.md`, canonical `docs/project_state.json`, synchronized root ledgers, append-only decisions, living ExecPlan workflow, repository layout/results policy, preflight and governance CI.
- Governance job passed on the phase branch.

### 2026-09-17 — state manager implementation

- Added explicit XPM-backed state RAM and `hft_rmic_futures_state_manager_v1`.
- State is indexed by `(account_id, product_id)` and configuration can restore complete mutable state for recovery.
- Reset clears configured ownership rather than trusting stale RAM contents.
- Initial CI `35211960262` passed all state-transition checks through fail-closed ownership, then timed out in the simultaneous config/request test.
- Root cause was a **testbench ready/valid race**, not a state-manager RTL failure: after cfg deassertion, ready changed in the same delta-cycle and the old TB loop missed the next posedge request handshake.
- Rewrote the TB driver to observe handshakes on clock edges. Fix commit: `b889527...`.
- Exact-head push CI `35212246246` then passed both governance and integration-regression including all state-manager cases.

### 2026-09-17 — I2-03 entry analysis

- A committed execution report alone does not contain the integration `(account_id, product_id)` key needed by the futures state table.
- Frozen RMIC M5.4 order-store payload is 81 bits inside a 96-bit AMU value, leaving enough width to carry futures PositionEffect if an integration-owned packing is used.
- I2-03 will therefore evaluate an integration-owned futures order-context wrapper over the frozen RMIC AMU primitive, rather than using frozen stock-like account mutation as a second source of truth.

## 9. Phase decisions

- D-20260917-04: futures accounting v1 semantics.
- D-20260917-05: committed report owner is sole execution mutation authority.
- D-20260917-06: phase-based repository governance.
- A future durable decision will freeze the exact order-context/RMIC primitive reuse boundary after I2-03 implementation evidence.

## 10. Current claim limit

I2-02 establishes functional-simulation correctness of the multi-account/product futures state manager only. It does not establish OOC timing, post-route timing, full HFT+RMIC behavior, board latency, official TAIFEX margin methodology, or exchange conformance.
