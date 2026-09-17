# TAIFEX Futures Accounting Contract v1

## Scope

This contract defines the first hardware-verifiable futures accounting model used by HFT_RMIC. It is an integration risk-budget model and **is not a claim of implementing TAIFEX SPAN or any broker-specific margin methodology**.

Authoritative protocol reference for field encodings:

- Taiwan Futures Exchange, TCP/IP TMP Messaging Specifications v2.18.7, 2025-08-18.

The specification establishes that the R01 order quantity is `uint16`, Side is `1=Buy / 2=Sell`, order type is Market/Limit/MWP, TIF includes ROD/IOC/FOK, and PositionEffect includes `O` (open), `C` (close), `D` (daytrade), `A` (options-specific open/offset), and `7` (offset by FCM). Execution reports provide fields including LastQty, LeavesQty and before_qty.

## Why the frozen RMIC accounting cannot be used unchanged

Frozen RMIC M5.4 is a correct generic transactional engine, but its account model is stock-like:

- BUY increases one unsigned position,
- SELL requires an existing position and decreases it,
- BUY cash reservation is derived from price * quantity.

A futures order must distinguish opening from closing and long from short. In particular, `SELL OPEN` must not require an existing long position. Therefore the integration must not claim TAIFEX futures correctness by wiring TMP side directly into the frozen account model.

## v1 state

For each account/product pair:

- `long_position`
- `short_position`
- `pending_open_long`
- `pending_open_short`
- `reserved_close_long`
- `reserved_close_short`

For each account/product risk policy:

- `margin_per_contract` -- host-configured project risk parameter
- `margin_budget` -- account/product or derived account budget supplied by the control plane

The first RTL transition primitive is `rtl/accounting/hft_rmic_futures_accounting_v1.sv`.

## v1 margin rule

The conservative project risk requirement is:

```text
required_margin = margin_per_contract *
    (long_position + short_position +
     pending_open_long + pending_open_short)
```

A new OPEN order is accepted only when the resulting required margin does not exceed `margin_budget`.

This deliberately does not model spread offsets, portfolio offsets, variation margin, broker house margin, or exchange SPAN internals. Those can be supplied in later versions without changing TMP field parsing.

## Order reservation semantics

### BUY OPEN

- requires margin capacity,
- increments `pending_open_long`.

### SELL OPEN

- requires margin capacity,
- increments `pending_open_short`,
- does **not** require an existing long position.

### SELL CLOSE

- requires `long_position >= reserved_close_long + qty`,
- increments `reserved_close_long`.

### BUY CLOSE

- requires `short_position >= reserved_close_short + qty`,
- increments `reserved_close_short`.

## Execution semantics

### OPEN fill

BUY OPEN fill:

```text
pending_open_long -= LastQty
long_position     += LastQty
```

SELL OPEN fill:

```text
pending_open_short -= LastQty
short_position     += LastQty
```

The gross margin requirement remains unchanged by moving a contract from pending-open state to filled-open state.

### CLOSE fill

SELL CLOSE fill:

```text
reserved_close_long -= LastQty
long_position        -= LastQty
```

BUY CLOSE fill:

```text
reserved_close_short -= LastQty
short_position        -= LastQty
```

### Cancel/reject release

The unfilled remaining quantity is removed from the corresponding pending-open or reserved-close state. The integration execution adapter should use committed, de-duplicated execution/report state and the exchange report's remaining quantity contract.

## PositionEffect support in v1

Implemented accounting semantics:

- `O` open
- `C` close

Explicitly fail-closed in v1:

- `D` daytrade
- `A` options-only open/offset
- `7` offset by FCM
- quote-specific semantics

These values may be enabled only after their position and margin semantics are defined and regression-tested.

## Relationship to frozen RMIC M5.4

M5.4 remains immutable as a generic reference core. The v1 accounting model is integration-owned.

The final composition is not yet frozen. Two possible implementation approaches remain under evaluation:

1. derive a futures-aware integration core that reuses the frozen RMIC AMU/order-store components while replacing stock-like account transitions, or
2. use a separate futures accounting owner with explicit atomic coordination around the RMIC transaction/order lifecycle engine.

The decision will be made only after accounting-state regression, execution replay tests, and integrated timing/resource measurements.

## Required next validation

1. Multi-account/product state memory manager around the transition primitive.
2. Order-ID metadata contract for PositionEffect across CL2EX and EX2CL.
3. R02/R32 committed execution adapter using LastQty/LeavesQty.
4. Duplicate/replay test proving the same partial execution mutates accounting exactly once.
5. Reset/warm-restart recovery contract.
6. Integrated U50 timing and resource comparison against frozen RMIC M5.4.
