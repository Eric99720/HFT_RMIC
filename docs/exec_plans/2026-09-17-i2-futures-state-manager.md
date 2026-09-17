# I2 — Futures State Manager

## 1. Phase identity

- Phase: `I2`
- Status: VERIFYING
- Branch: `codex/i2-futures-state-manager`
- Draft PR: `#1`
- HFT pin: `50217fad1fd580f8c451ba893f9035f4be1dc21a`
- RMIC pin: `de6c300f4f18b18296f013287ab0eca70d3abb72`
- Sign-off tool: Vivado 2022.1
- Target: `xcu50-fsvh2104-2-e`
- Clock: 156.25 MHz / 6.400 ns

## 2. Goal

Turn the verified stateless futures accounting transition primitive into a bounded multi-account/multi-product state subsystem, bind only admitted TAIFEX execution/error events to exact outstanding-order context, and demonstrate physical feasibility with the real pinned RMIC AMU without modifying either upstream repository.

### Non-goals

- full HFT datapath insertion;
- official TAIFEX SPAN implementation;
- volatility/stop-loss/liquidity policy;
- board/QSFP validation;
- upstream RMIC/HFT source modifications;
- multi-leg/options PositionEffect A/7 support;
- final CL2EX policy/risk-gate arbitration.

## 3. Architecture

### Futures state

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

Reset clears only configured ownership. Stale BRAM contents are inaccessible until explicit host/recovery configuration restores the entry.

### Futures outstanding-order context

```text
order_id (AMU key)
  -> account_id
  -> product_id
  -> side
  -> PositionEffect
  -> OrdType
  -> TIF
  -> limit_price
  -> remaining_qty
```

The payload is 89 bits inside the frozen RMIC 96-bit AMU value. The integration layer reuses the frozen collision-capable AMU/hash/BRAM primitive but does **not** reuse the frozen stock-like account mutation as a second futures-accounting source.

### Committed execution lifecycle

```text
raw R02/R32
  -> frozen HFT TMP decoder
  -> integration PositionEffect + before_qty tap
  -> frozen HFT report-sequence owner
  -> COMMIT only
  -> order_id AMU lookup
  -> validate context + quantity invariants
  -> futures FILL / RELEASE state transition(s)
  -> order-context UPDATE / DELETE

checksum-valid committed R03
  -> order_id AMU lookup
  -> RELEASE stored remaining quantity
  -> order-context DELETE
```

The bridge input is explicitly named `commit_valid`; raw decoder valid is not a legal state-mutation source.

## 4. Protocol/accounting contracts

- Frozen HFT decoder side: BID/BUY=`0`, ASK/SELL=`1`; matches normalized RMIC side.
- R01/R02/R32 quantity is TMP `uint16`, zero-extended where needed.
- PositionEffect v1 admits ASCII `O` OPEN and `C` CLOSE only.
- Margin v1 is project-configured `margin_per_contract × gross open exposure`; no SPAN claim.
- R02 PositionEffect byte 75; before_qty bytes 94..95.
- R32 PositionEffect byte 95; before_qty bytes 114..115.
- R02/R32 mutation requires frozen sequence-owner commit.
- R03 release requires the already checksum-valid/committed HFT error path and an existing outstanding-order context.
- `before_qty` is pre-match remaining quantity, `LastQty` is the last execution quantity, `LeavesQty` is the current remaining quantity.
- The frozen RMIC stock-like account state is not a second futures source of truth.

Authoritative protocol interpretation comes from the pinned HFT reference tree under `docs/references/taifex/期交所TCPIP_TMP_v2.18.7/`.

## 5. Acceptance criteria

### I2-01 governance — COMPLETE

- required governance files exist;
- project-state sync and repository-layout checks pass;
- CI separates governance from functional regression;
- one branch/PR owns the phase.

### I2-02 state manager — COMPLETE

Self-checking simulation proves:

1. configured/readiness ownership is fail-closed;
2. account/product keys are isolated;
3. BUY OPEN reserve/fill/release updates pending long/long correctly;
4. SELL OPEN reserve/fill/release updates pending short/short correctly;
5. SELL CLOSE affects long only;
6. BUY CLOSE requires sufficient short inventory;
7. margin rejection is atomic;
8. configuration has deterministic priority;
9. reset invalidates ownership until recovery.

Initial CI `35211960262` exposed a testbench ready/valid delta-cycle race after all core state-transition cases had passed. The edge-based driver fix at `b889527...` preserved the original failure and exact-head CI subsequently passed.

### I2-03 committed execution/order-context lifecycle — COMPLETE

Self-checking simulation proves:

- futures order context INSERT/LOOKUP/UPDATE/DELETE packing;
- exact duplicate context does not overwrite;
- R02/R32 partial fill mutates account state and updates remaining context;
- stale/duplicate event with old `before_qty` fails closed without mutation;
- next valid/replayed-then-committed event mutates once;
- terminal fill can perform FILL plus RELEASE for the exchange-cancelled remainder;
- final lifecycle deletes context and duplicate terminal report becomes context miss;
- cancel releases the complete outstanding reservation and deletes context;
- reduce releases `before_qty - LeavesQty` and updates remaining context;
- R03 releases stored remaining quantity once and deletes context;
- side/PositionEffect/context or quantity mismatch does not mutate state;
- unexpected second-stage/account-store failure returns recovery-required rather than guessing.

Exact-head functional CI passes at `1ab7bbe...` and remains green after the OOC compile-smoke addition.

### I2-04 real-AMU OOC — VERIFYING

Prepared implementation must be run locally with the private pinned RMIC submodule. Acceptance:

- source pins verified before Vivado;
- true `deps/RMIC` XPM AMU compiled, not the CI stub;
- RAMB36/RAMB18 count > 0 after synthesis;
- place/route completes;
- routed WNS >= 0 ns at 6.400 ns;
- TNS = 0 and no routing errors;
- utilization/RAM/critical path/DRC/power reviewed;
- packaged manifest records integration commit plus both dependency SHAs.

The OOC composition SystemVerilog compile-smoke passes GitHub CI. Actual Vivado evidence remains pending user machine execution.

## 6. Implementation milestones

1. Governance + project-state enforcement — **complete**.
2. XPM-backed multi-account/product futures state manager — **complete**.
3. Multi-key self-checking regression — **complete**.
4. Futures order context over frozen 96-bit AMU contract — **complete**.
5. PositionEffect + before_qty execution metadata tap — **complete**.
6. Committed execution/R03 reconciliation regression — **complete**.
7. Real-AMU Vivado OOC runner, hard timing/BRAM gates and result packaging — **prepared / verifying**.
8. Review actual routed package, publish compact result, close PR #1 — **pending**.

## 7. Verification entry points

GitHub CI runs:

```text
scripts/run_adapter_iverilog.sh
scripts/run_accounting_iverilog.sh
scripts/run_state_manager_iverilog.sh
scripts/run_order_context_iverilog.sh
scripts/run_execution_bridge_iverilog.sh
scripts/run_i2_ooc_compile_iverilog.sh
project record sync check
repository layout check
git diff --check
```

Local preflight:

```powershell
pwsh .\scripts\preflight.ps1
```

Local real-AMU Vivado gate:

```powershell
pwsh .\scripts\run_i2_ooc_impl.ps1
```

The local runner packages `HFT_RMIC_i2_ooc_impl_*.zip` for evidence review. No full-system HFT latency claim is made in I2.

## 8. Execution log

### 2026-09-17 — phase start / governance

- User setup confirmed exact frozen submodule pins.
- Reviewed `LOB-SOTA-Research` governance and adopted canonical project state, phase branch/PR, append-only decisions, living ExecPlan, repository layout and evidence boundaries while excluding ML/training-specific rules.
- Created `codex/i2-futures-state-manager` and draft PR #1.
- Added governance CI and local preflight.

### 2026-09-17 — state manager

- Added explicit XPM-backed state RAM and `hft_rmic_futures_state_manager_v1`.
- State is indexed by `(account_id, product_id)`; complete state can be restored by recovery/configuration.
- Reset clears configured ownership rather than trusting stale RAM contents.
- Initial CI timeout in simultaneous config/request TB was traced to testbench delta-cycle handshake timing, not accounting/state RTL. Rewrote driver to clock-edge ready/valid semantics; exact-head CI passed.

### 2026-09-17 — order context

- Added `hft_rmic_futures_order_store_v1` over the frozen AMU module contract.
- Payload uses 89/96 bits: account/product/side/PositionEffect/OrdType/TIF/limit price/remaining qty; order_id remains hash key.
- GitHub CI uses an integration-contract AMU stub only because the private sibling RMIC repo is not assumed readable by `GITHUB_TOKEN`. This stub is not physical/hash evidence.

### 2026-09-17 — committed execution reconciliation

- Expanded the execution side-band tap to capture authoritative `before_qty` in addition to PositionEffect.
- Added `hft_rmic_committed_execution_bridge_v1`.
- Implemented R02/R32 trade/new+trade, cancel, reduce and price-change lifecycle rules, plus R03 release/delete behavior.
- Trade reconciliation uses `before_qty`, `LastQty`, and `LeavesQty`; nonzero implicit remainder becomes a RELEASE after FILL, supporting terminal IOC-like behavior.
- Duplicate/stale events are blocked by local remaining-quantity mismatch even in the regression scenario where an already-old event is deliberately presented again.
- Exact-head GitHub CI run `35216105188` passed governance and all functional regressions.

### 2026-09-17 — OOC preparation

- Added `hft_rmic_i2_ooc_top` to compose real order-store/state/bridge logic without claiming it as a production top.
- Added non-project Vivado 2022.1 flow with XPM auto-detection, RAMB gate, staged reports/checkpoints, route/DRC/power analysis and routed-WNS hard gate.
- Added recursive result packaging with integration SHA and both dependency SHAs.
- Added Icarus compile-smoke for the same OOC composition structure.
- Exact-head CI run `35216656155` passed both governance and integration-regression, including the OOC composition compile-smoke.
- Actual Vivado route is intentionally left as the sole external evidence gate because the execution environment with Vivado/U50 part database is the user's Windows workstation.

## 9. Phase decisions

- D-20260917-04: futures accounting v1 semantics.
- D-20260917-05: frozen HFT commit ownership controls R02/R32 mutation.
- D-20260917-06: phase-based repository governance.
- D-20260917-07: futures state is the sole account-position source; frozen RMIC reuse is limited to transactional primitives such as AMU/order context.
- D-20260917-08: execution reconciliation uses order context plus authoritative `before_qty`/`LastQty`/`LeavesQty` invariants and delete-on-terminal behavior.

## 10. Current claim limit

I2 functional simulation is closed. This establishes deterministic integration-owned futures state transitions and order/report lifecycle behavior under self-checking simulation. It does **not** yet establish integration OOC/post-route timing or resources, final HFT+RMIC application behavior, board latency, official TAIFEX margin methodology, or exchange conformance. Those claims remain gated by the corresponding later evidence levels.
