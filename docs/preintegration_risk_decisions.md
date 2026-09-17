# Pre-Integration Risk Decisions

## Status

This document records the items that must be resolved before `HFT_RMIC` can be called a functionally complete TAIFEX HFT + risk-management system.

The frozen RMIC M5.4 remains accepted as a **generic transactional risk-management core**. The issues below are exchange/accounting/integration semantics that must not be hidden by the fact that M5.4 is functionally tested and timing-closed.

## P0-1 — Futures position semantics

### Finding

Frozen RMIC M5.4 currently uses one unsigned position quantity plus pending-buy and reserved-sell quantities.

CL2EX behavior is stock/inventory-like:

- BUY checks `position + pending_buy + qty <= max_position`.
- SELL checks that current position is at least `reserved_sell + qty`.

EX2CL behavior is also stock/inventory-like:

- BUY fill increases position.
- SELL fill decreases position.

This means the frozen core cannot, by itself, represent all futures cases such as sell-to-open / buy-to-close or independent long/short exposure.

### Decision

Do not claim TAIFEX futures position-risk completeness until a futures position model is defined from authoritative protocol/business rules.

Candidate versioned normalized state for later evaluation:

```text
long_position
short_position
pending_buy_open
pending_sell_open
pending_buy_close
pending_sell_close
max_long_position
max_short_position
```

A signed net-position model may be smaller, but it must be shown to preserve all required open/close semantics before selection.

The frozen HFT `order_data` already carries `position_effect`; the integration adapter must preserve it and the policy/accounting design must decide how it affects state.

## P0-2 — Futures margin/fund accounting

### Finding

Frozen M5.4 calculates CL2EX reservation from `price * quantity` and uses the same limit price later for BUY fill refund and SELL proceeds. This is a coherent generic/stock-style accounting model, but it is not an authoritative futures margin model.

A simple outer threshold cannot fully correct this because the accounting semantics are embedded in:

- pre-trade reservation,
- partial fill reconciliation,
- cancel/reject release,
- execution-price compensation.

### Decision

Before full integration, define a versioned accounting contract that separates market price from risk reservation amount.

Preferred interface direction for a future RMIC accounting version:

```text
order_limit_price        // exchange/order semantics
reservation_per_contract // risk/margin semantics
qty
position_effect
```

The current `price` field must not be overloaded to carry margin because RMIC also uses it for execution-price validity checks.

Until this contract is finalized, the frozen M5.4 core may be used for integration plumbing and A/B architecture tests, but the results must be labeled as generic-accounting mode rather than final TAIFEX futures-margin mode.

## P0-3 — Execution replay/idempotency

### Finding

M5.4 correctly rejects execution quantity beyond remaining order quantity and deletes completed orders, but it does not own TMP report sequence numbers or exchange execution identifiers.

A duplicated *partial fill* could be valid against the still-open remaining quantity and therefore must be filtered before entering RMIC.

### Decision

The frozen HFT report-sequence/replay owner is authoritative for execution-event commitment.

Only a committed and de-duplicated execution event may cross the `HFT_RMIC` EX2CL adapter.

Required regression:

1. accept a partial fill once,
2. replay the same protocol report,
3. prove that HFT drops/does not recommit the duplicate,
4. prove RMIC state mutates exactly once.

## P0-4 — Local reject ownership

### Finding

The 2023 TWSE thesis replaces already-formed FIX packets and uses a Failed Order Buffer because its RM sits on the packet stream. `HFT_RMIC` is inserted before TMP R01 encoding, so rejected orders need not create an exchange packet.

### Decision

Every locally rejected order must create a deterministic reject event even though no R01 is transmitted.

Reject event minimum fields:

```text
order_id
order_number
reason_source
reason_code
account_id + valid
product_id + valid
cycle_timestamp
```

The HFT order-state owner/host telemetry must be able to distinguish:

- order accepted by strategy but rejected locally,
- order transmitted to exchange,
- exchange-side reject/cancel/fill.

## P0-5 — Reason-code namespace

### Finding

The frozen RMIC 4-bit reason field uses all 16 values. New adapter/policy/system errors cannot be safely squeezed into that namespace.

### Decision

Do not modify M5.4 reason encoding.

Integration uses a two-level reason namespace:

```text
reason_source
  0 = RMIC
  1 = ADAPTER
  2 = POLICY
  3 = SYSTEM

reason_code
  8 bits within the selected source
```

RMIC source zero-extends the original 4-bit M5.4 reason code.

## P0-6 — Quantity-width contract

### Finding

The frozen HFT order packer accepts a 32-bit strategy quantity but writes only `qty[15:0]` into the frozen 256-bit encoder-side order payload.

### Decision

Do not silently assume 32-bit quantity survives the HFT order-data boundary.

Before exchange sign-off:

- confirm the authoritative TMP R01 quantity width and encoding,
- assert/reject any upstream quantity that cannot be represented by the packed field,
- keep the adapter's 16->32 zero extension explicit.

## P0-7 — Initialization and configuration atomicity

### Required readiness

No order may enter the integration path until all of these are true:

- HFT order/session path is ready,
- RMIC AMU initialization is complete,
- investor-account mapping is configured,
- product mapping is configured,
- required RMIC account/product records are configured,
- risk policy configuration is valid,
- kill switch is deasserted.

### Runtime configuration

A configuration update must not race with an in-flight transaction affecting the same account/product. The initial integration may enforce a simple global configuration quiesce; later work may add versioned/double-buffered policy tables if runtime changes are required without pausing orders.

## P0-8 — Reset / warm-restart recovery

### Finding

RMIC reset clears/invalidates the outstanding-order store and runtime account reservations. In a real trading session, the exchange may still own live orders when FPGA state is lost.

### Decision

After any state-losing reset, `integration_ready` remains false until one explicit recovery policy completes.

Acceptable policies to evaluate:

1. cancel-all / session reset, then restart from a clean exchange state;
2. host-driven state restore from an authoritative order/account snapshot;
3. exchange replay/query-based reconstruction where the protocol supports it.

The integration must never resume trading by silently assuming an empty outstanding-order table after a mid-session reset.

## P1 — Low-complexity controls recommended before final research freeze

These controls are strongly recommended because the 2023 thesis/follow-on literature identifies them and they can be implemented mostly with counters/thresholds outside the frozen M5.4 AMU:

- per-account outstanding-order maximum,
- global/per-account order-rate limit,
- cancel/delete-rate limit,
- maximum normalized exposure or margin request,
- AMU occupancy/high-watermark/stash-use telemetry,
- explicit account/global kill switch telemetry.

## P2 — Advanced research controls

These should be added only after the baseline integrated system is measured:

- volatility-aware dynamic limits,
- stop-loss / daily-loss controls with a defined PnL source,
- liquidity/depth-aware limits,
- multiple EX2CL transactions in flight,
- hot-account forwarding/sharding to remove same-account serialization.

## Integration sequence consequence

The implementation sequence is therefore:

```text
I1 adapters/mapping
I2 reject namespace + policy shell + readiness
I3 generic M5.4 CL2EX integration and byte-identity validation
I4 execution de-dup / EX2CL integration
I5 define and validate TAIFEX futures position+margin accounting
I6 integrate the selected accounting version
I7 add P1 operational controls
I8 full dual-XGMII A/B latency + post-route
I9 board/live validation when available
```

This ordering preserves useful integration progress without pretending that the current stock-like accounting model is a final futures risk model.
