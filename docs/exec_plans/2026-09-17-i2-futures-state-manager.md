# I2 — Futures State Manager

## 1. Phase identity

- Phase: `I2`
- Status: RUNNING
- Branch: `codex/i2-futures-state-manager`
- PR: open after first governance + implementation milestone is green
- HFT pin: `50217fad1fd580f8c451ba893f9035f4be1dc21a`
- RMIC pin: `de6c300f4f18b18296f013287ab0eca70d3abb72`
- Sign-off tool: Vivado 2022.1
- Target: `xcu50-fsvh2104-2-e`
- Clock: 156.25 MHz / 6.400 ns

## 2. Goal

Turn the verified stateless futures accounting v1 transition primitive into a bounded multi-account/multi-product state subsystem, then bind only committed/de-duplicated R02/R32 execution events to it.

The phase exists to close the semantic/state-management gap between a single transition function and a usable futures RM subsystem without modifying either upstream repository.

### Non-goals

- full HFT datapath insertion;
- official TAIFEX SPAN implementation;
- volatility/stop-loss/liquidity policy;
- board/QSFP validation;
- upstream RMIC/HFT source modifications;
- multi-leg/options PositionEffect A/7 support unless separately decided.

## 3. Architecture

Current v1 primitive:

```text
current state + event
    -> hft_rmic_futures_accounting_v1
    -> next state / pass-reject
```

I2 target:

```text
(account_id, product_id, event)
    -> state-manager request queue / hazard gate
    -> read configured account-product state
    -> futures accounting v1 transition
    -> atomic state commit
    -> response
```

The first implementation may serialize same-state-key mutations while allowing a later pipeline optimization. Correctness and explicit ownership precede throughput.

Execution integration:

```text
raw R02/R32
  -> frozen HFT decoder + PositionEffect tap
  -> frozen HFT report-sequence owner
  -> COMMIT only
  -> integration execution event
  -> futures state manager
```

## 4. Contracts and authority

- Side inside frozen HFT decoder: BID/BUY=`0`, ASK/SELL=`1`; matches normalized RMIC side.
- R01/R02/R32 quantity is 16-bit TMP quantity, zero-extended internally.
- PositionEffect v1: only ASCII `O` OPEN and `C` CLOSE are admitted to accounting.
- Margin v1 is project-configured `margin_per_contract × gross open exposure`; no SPAN claim.
- R02/R32 PositionEffect comes from the integration-owned fixed-offset tap because the frozen HFT decoder does not expose it.
- Only the frozen report-sequence owner commit authorizes execution mutation.

Authoritative protocol interpretation comes from the pinned HFT reference tree under `docs/references/taifex/期交所TCPIP_TMP_v2.18.7/`.

## 5. Acceptance criteria

### I2-01 governance

- required governance files exist;
- project-state sync check passes;
- repository layout check passes;
- CI runs governance plus functional regressions.

### I2-02 state manager

Self-checking simulation must prove:

1. account/product configuration/readiness is fail-closed;
2. `(account A, product X)` mutation cannot affect `(account B, product X)` or `(account A, product Y)`;
3. BUY OPEN reserve/fill/release updates pending long/long correctly;
4. SELL OPEN reserve/fill/release updates pending short/short correctly;
5. SELL CLOSE reserves/releases/fills long only;
6. BUY CLOSE reserves/releases/fills short only;
7. insufficient close and margin overflow/limit reject without mutation;
8. response identifies exact key and reason;
9. configuration write cannot race an active state mutation;
10. reset returns manager to not-ready state.

### I2-03 committed execution bridge

Simulation must prove:

- committed R02/R32 trade event mutates exactly once;
- duplicate old report does not mutate;
- sequence gap does not mutate;
- replayed report accepted by sequence owner mutates once;
- PositionEffect metadata is associated with the same committed report;
- cancel/reject remaining-order release semantics are explicit and tested.

### I2-04 OOC

- synth/place/route or at minimum declared OOC scope uses 6.400 ns;
- WNS >= 0 ns, TNS = 0;
- utilization reviewed;
- evidence level clearly labeled OOC/post-route as appropriate.

## 6. Implementation milestones

1. Governance + project-state enforcement.
2. `hft_rmic_futures_state_manager_v1.sv` with configurable state table.
3. Multi-key self-checking regression.
4. Committed execution bridge / metadata alignment.
5. Replay/dedup self-checking regression using frozen-owner semantics or a contract-equivalent harness.
6. Vivado OOC runner and packaged results.
7. Phase evidence/decision update and PR closure.

## 7. Verification plan

Fast CI:

```text
scripts/run_adapter_iverilog.sh
scripts/run_accounting_iverilog.sh
state-manager Icarus regression
project record sync check
repository layout check
```

Local Vivado gate after functional closure:

```text
Vivado 2022.1
xcu50-fsvh2104-2-e
6.400 ns
```

No full-system HFT latency claim in I2.

## 8. Execution log

### 2026-09-17

- User setup confirmed exact frozen submodule pins.
- Reviewed `LOB-SOTA-Research` governance and adopted project-state/phase/decision/layout concepts adapted for FPGA/HFT.
- Created `codex/i2-futures-state-manager` from integration main head `51d8219...`.
- I1 functional CI entering I2 is green: adapters/policy, futures accounting v1 and execution PositionEffect tap.

## 9. Phase decisions

- D-20260917-04: futures accounting v1 semantics.
- D-20260917-05: committed report owner is sole execution mutation authority.
- D-20260917-06: phase-based repository governance.

## 10. Current claim limit

I2 has not yet established a full multi-account state subsystem or HFT+RMIC end-to-end path. Upstream RMIC M5.4 post-route timing remains valid only for the frozen standalone core. Futures accounting remains a project risk-budget model rather than official margin methodology.
