# I5 — Full Dual-XGMII HFT + RMIC Integration

## 1. Phase identity

- Phase: `I5`
- Status: ACTIVE
- Branch: `codex/i5-full-dual-xgmii-integration`
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
- correctness-first owner serialization is retained until a later throughput optimization phase.

## 7. Non-goals

- network/PHY candidate migration (N1 remains separate);
- TAIFEX SPAN implementation;
- board/QSFP/live-exchange claim;
- CL/EX II=1 optimization;
- changing frozen TMP packet bytes/session behavior.

## 8. Acceptance before merge

I5 may close only after exact-head CI and local/full-system evidence establish the stated functional boundaries and any physical claims are tied to reproducible reports.
