# HFT + RMIC Integration Architecture

## Design objective

Integrate the frozen HFT baseline and frozen RMIC M5.4 core without modifying either upstream repository.

The integration repository owns only the glue, policy, mapping, wrappers, and cross-project verification required to connect the two frozen designs.

## Source boundaries

```text
deps/hft-full-system-fpga  (read-only submodule)
deps/RMIC                  (read-only submodule)

rtl/adapters/               HFT/TMP <-> normalized RMIC fields
rtl/policy/                 exchange/account/product policy
rtl/integration/            composition and handshakes
rtl/telemetry/              integration counters/status
```

## Nominal CL2EX path

```text
Market data
    -> frozen HFT RX / protocol decoder
    -> order book / strategy
    -> frozen HFT order_data packing
    -> hft_order_to_rmic adapter
    -> account/product mapping
    -> HFT_RMIC policy layer
    -> frozen RMIC M5.4 CL2EX
        -> PASS  -> forward the original 256-bit HFT order_data unchanged
        -> REJECT -> local reject event + counters; do not launch TMP R01
    -> frozen HFT financial/TMP encoder
    -> frozen HFT TCP/IP/XGMII TX
```

### Critical invariant

A risk-approved order must arrive at the existing HFT encoder as the **same 256-bit order payload** that entered the risk gate. The integration layer extracts fields for risk checking but does not rewrite the protocol payload on the PASS path.

This creates a byte-identity A/B verification target:

```text
R01_without_RMIC(order) == R01_with_RMIC_PASS(order)
```

## Nominal EX2CL path

```text
Trading-port RX
    -> frozen HFT TCP/TMP decoder
    -> frozen report sequence/replay owner
    -> committed, de-duplicated execution event
    -> tmp_exec_to_rmic adapter
    -> frozen RMIC M5.4 EX2CL
       - fill
       - partial fill
       - cancel
       - reject
    -> account/order state reconciliation
    -> integration telemetry / strategy-order-state notification
```

### Critical invariant: execution idempotency ownership

RMIC does not own TMP sequence/replay semantics. Only a report accepted/committed by the HFT report-sequence owner may be converted to an RMIC EX2CL event.

The integration regression must prove that replay/duplicate input at the HFT protocol layer cannot mutate RMIC state twice.

## Why no packet replacement in the nominal path

The 2023 TWSE FIX risk thesis inserts risk management after packets are already formed, so abnormal FIX messages are replaced and a Failed Order Buffer is needed to later reconstruct client-visible failure behavior.

This integration intercepts an HFT internal order **before** TMP R01 construction. Therefore the safer architecture is to suppress R01 entirely on reject and generate a local reject event.

A packet-replacement path should only be added if a future integration boundary requires RMIC to sit on an already-formed protocol stream.

## Risk policy layering

### Layer 1 — HFT field adapter

Protocol/order-format translation only:

- 256-bit order payload -> normalized fields,
- HFT/TMP side byte -> RMIC side encoding,
- investor account -> configured RMIC account id,
- symbol slot -> configured RMIC product id,
- preserve order type, TIF, position effect and flags as policy metadata.

No mutable risk state belongs here.

### Layer 2 — exchange-specific policy

The policy layer owns rules that are expected to change with exchange/product requirements:

- supported order types,
- supported TIF values,
- position-effect policy,
- futures contract multiplier / selected margin model,
- order notional/exposure thresholds,
- order-rate limits,
- cancel-rate limits,
- per-account outstanding-order limits,
- kill-switch policy,
- optional volatility/stop-loss/liquidity hooks.

The policy layer emits either:

1. a normalized request to M5.4, or
2. a local reject without mutating RMIC.

### Layer 3 — frozen RMIC M5.4 transactional engine

M5.4 remains responsible for:

- account/product mutable state,
- cash/position reservation under the selected normalized semantics,
- active order ownership,
- AMU insertion/lookup/update/delete,
- fill/cancel/reject reconciliation,
- same-account/order hazards,
- CL2EX II=1 and dual-flow concurrency.

## Initial field mapping

Frozen HFT `order_data` layout from `round_chip_defs.vh`:

| HFT field | Bit range | RMIC / policy use |
| --- | --- | --- |
| price | 31:0 | normalized price |
| quantity | 47:32 | zero-extend to RMIC 32-bit quantity |
| side byte | 55:48 | explicit TMP/HFT -> RMIC side conversion |
| TIF | 63:56 | policy metadata |
| position effect | 71:64 | policy metadata |
| investor flag | 79:72 | policy metadata / account policy |
| investor account | 111:80 | account-map key |
| order id | 143:112 | RMIC order id |
| order number | 183:144 | integration correlation / telemetry |
| symbol slot | 199:184 | product-map key |
| flags | 207:200 | policy metadata |
| order type | 215:208 | policy metadata |

### Side encoding warning

The packed HFT/TMP side byte is not the same encoding as `RMIC_SIDE_*`. Never wire it directly.

The adapter must explicitly decode supported HFT/TMP side bytes and generate a validity flag.

## Account mapping

Do not derive RMIC account id from low address bits of the 32-bit investor account.

Use a configured mapping table:

```text
investor_acno (32 bit) -> RMIC account_id (8 bit)
```

A lookup miss is a deterministic local/policy reject and must never alias another account.

## Product mapping

The initial frozen HFT baseline uses symbol slots for TXF/MXF/TMF. The integration layer will initially map configured symbol slots to RMIC product ids through an explicit table rather than relying on accidental numeric equivalence.

This makes later addition of other contracts/products safe.

## Readiness and reset

`integration_ready` must require all of:

- HFT trading/session path ready for orders,
- RMIC `order_store_init_done`,
- account map initialized,
- required RMIC account/product records configured,
- policy configuration valid,
- no global kill switch.

An order presented before `integration_ready` must not enter the RMIC or encoder.

## Local reject path

Every reject must produce an internal event containing at least:

- order id,
- reason source (`POLICY` or `RMIC`),
- reason code,
- account id if resolved,
- product id if resolved,
- cycle timestamp.

Initial integration behavior:

- suppress exchange R01,
- expose event to testbench/telemetry,
- later connect to strategy/order-state/host control as required.

## Verification milestones

### I1 — adapter unit tests

- exact bit-field extraction,
- side translation,
- account map hit/miss,
- product map hit/miss,
- unsupported metadata rejects.

### I2 — CL2EX risk gate

- approved order forwards byte-identical 256-bit payload,
- rejected order never reaches encoder,
- multiple independent approved orders retain M5.4 II=1 potential where downstream is ready,
- backpressure is lossless.

### I3 — EX2CL reconciliation

- full fill,
- partial fill,
- cancel,
- reject,
- duplicate/replay execution cannot mutate state twice.

### I4 — application-level HFT integration

- strategy -> RMIC -> R01,
- local reject visibility,
- accepted R01 golden bytes identical to frozen HFT baseline.

### I5 — full dual-XGMII system

- market-port event -> strategy -> RMIC -> trading-port R01,
- execution return -> de-dup -> RMIC reconciliation,
- reconnect/replay scenarios.

### I6 — A/B performance

Measure the same source workload with:

- frozen HFT baseline without RMIC,
- HFT_RMIC integration with RMIC enabled.

Report exact measurement boundaries and do not mix simulation, OOC/post-route, and board measurements.

## Upgrade policy

Any proposed change to upstream RMIC core semantics must first be prototyped and verified in this repository's policy/adapter layer. Only if the feature fundamentally requires new mutable transactional state should a future RMIC interface version be considered.
