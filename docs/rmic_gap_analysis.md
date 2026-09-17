# RMIC Functional Gap Analysis

## Purpose

This document compares the frozen RMIC M5.4 core against the functionality and future-work directions in:

- Chih-Yu Lin, *FPGA-based Hardware Acceleration for Risk Management in High-Frequency Trading with Bidirectional Latencies under 600 ns*, NTHU, 2023.

The purpose is not to reproduce the thesis architecture. The thesis targets TWSE FIX 4.4 stock trading, while the current HFT integration target is primarily TAIFEX TMP futures trading. Stock-specific rules must not be copied blindly into a futures risk engine.

## Architectural comparison

| Topic | 2023 thesis | RMIC M5.4 | Assessment |
| --- | --- | --- | --- |
| Core placement | Inline network/FIX risk server between client and exchange | Protocol-independent normalized RM core intended for insertion before encoder and behind execution decoder | RMIC layering is cleaner for reuse |
| Directions | CL2EX and EX2CL | CL2EX and EX2CL | Equivalent scope |
| CL2EX fund/position handling | Pre-deduction | Hardware reservation | RMIC covers this |
| EX2CL compensation | Software compensation program; FPGA compensation proposed as future work | Hardware fill/cancel/reject reconciliation | RMIC advances the thesis future work |
| Outstanding orders | Failed-order metadata plus software compensation-side order data | 4096-entry collision-capable AMU containing active orders | RMIC is stronger for active-order ownership |
| Collision handling | Not the central contribution of the 2023 thesis | 8-bank collision-capable AMU + stash | RMIC stronger |
| High-volume parallelism | Existing thesis system sequential; future work proposes multiple parsers and per-customer parallel risk | CL2EX II=1 for conflict-free requests; unrelated CL2EX/EX2CL may overlap; same-account/order interlocked | RMIC substantially addresses this future work |
| Per-customer memory | Thesis suggests independent dynamic DB/register replication | Shared Account/Product memories with scoreboard and hazard interlocks | RMIC is more resource-efficient, but scaling must be measured |
| Protocol handling | TWSE FIX 4.4 parsing and packet replacement are inside the overall system | Intentionally outside the RMIC core | Integration layer must provide exact protocol semantics |
| Reject behavior | Replace abnormal NOS with OSR and later replace exchange response with failure information | Core emits reject reason; no protocol packet synthesis | Correct separation, but integration must provide local reject/report behavior |
| Hardware validation | Connected to TWSE test environment; thesis reports 550/582 ns system latency | U50 post-route core timing; no live exchange/board end-to-end validation yet | Not directly comparable |

## 2023 thesis future work and RMIC status

### 1. Parallel network/financial parsing

The thesis identifies sequential packet processing as a high-volume bottleneck and proposes multiple packet parsers.

RMIC status: **outside RMIC core**. The frozen HFT source already has a highly optimized streaming protocol/network path. Parallel parsing belongs to HFT/integration architecture, not inside RMIC.

Decision: do not modify RMIC for this item.

### 2. Parallel risk processing for different customers

The thesis proposes replicating customer dynamic memories/registers because customers are independent.

RMIC status: **largely addressed architecturally**. M5.4 accepts conflict-free CL2EX at II=1 and permits unrelated CL2EX/EX2CL overlap. Same-account transactions are deliberately serialized by hazard logic to preserve account state correctness.

Remaining work:

- validate realistic account-count scaling,
- verify throughput under mixed-account skew/hot-account traffic,
- determine whether a single hot institutional account needs sub-account sharding or account-level accumulation forwarding.

Decision: current core is acceptable for integration; multi-lane account sharding is an optimization, not a blocker.

### 3. Additional risk types/rules

The thesis suggests liquidity risk and specifically mentions:

- order execution/rate limits,
- volatility-dependent controls,
- stop-loss mechanisms.

RMIC status: **not implemented today**. M5.4 currently performs product/account validity, price range, quantity range, cash/position checks, duplicate/order-table checks, and execution validity checks.

This is the largest remaining functional gap.

### 4. FPGA-side compensation

The thesis compensation path is software-based and explicitly proposes moving compensation into FPGA if HFT volume grows.

RMIC status: **completed**. Fill, partial fill, cancel, and reject state reconciliation are performed in hardware in EX2CL.

Decision: no additional software compensation architecture is needed for the integration baseline.

## Important differences that are not simply future work

### A. Stock-specific static policy vs futures policy

The thesis static database contains stock-oriented fields such as warning flags, day-trading eligibility, daily bull/bear prices, trade unit, short-sale flags, and financing limits.

These fields are useful evidence that a practical RM system requires richer product policy than only min/max price and max quantity. However, they are TWSE-stock semantics and should not be copied directly into TAIFEX futures RM.

For TAIFEX integration, the analogous policy layer should be designed around authoritative futures semantics, such as:

- contract/product enable,
- price/tick/price-band validation,
- quantity/order-value limits,
- position effect (open/close where applicable),
- long/short exposure,
- contract multiplier,
- initial/maintenance margin or the selected project margin model,
- order type/TIF support policy.

### B. Current RMIC cash model is generic, not yet a final futures-margin model

The current RMIC reserves a generic notional derived from price and quantity. This is sufficient for architecture and transaction-correctness research, but it must not be presented as an authoritative TAIFEX futures margin implementation.

Decision: do not rewrite the timing-closed M5.4 core immediately. Add a policy/calculation adapter in `HFT_RMIC` first. If the final margin model requires additional mutable account fields, extend RMIC through a versioned interface after the policy model is verified.

### C. Failed Order Buffer / packet replacement

The thesis needs a Failed Order Buffer and packet replacement because it sits on an already-formed FIX packet stream and must preserve network/session behavior when blocking an order.

Our target integration point is earlier: the HFT strategy/order packer produces an internal order before the TMP encoder emits R01. Therefore an invalid order can be blocked before a protocol message exists.

Decision:

- do not reproduce the thesis packet-replacement mechanism in the nominal TAIFEX path,
- do provide an explicit local reject event/telemetry path so the strategy/host/order-state logic knows that the order did not reach the exchange.

### D. Execution replay/idempotency

RMIC tracks remaining quantity and removes fully completed orders, but the core itself does not own TMP report sequence numbers or exchange `ExecID` replay filtering. A duplicated partial fill delivered twice could otherwise be applied twice.

The frozen HFT baseline already owns TMP report sequence/replay/duplicate handling.

Integration contract:

> Only committed, de-duplicated execution events from the HFT report-sequence owner may enter RMIC EX2CL.

This must be verified in integration tests.

## Missing risk controls prioritized for HFT_RMIC

### P0 — required before claiming a functionally complete TAIFEX HFT+RM system

1. **TAIFEX policy adapter**
   - explicit order type/TIF support,
   - product/contract mapping,
   - position-effect/open-close policy if required by the selected protocol/order model,
   - selected futures margin/notional semantics.

2. **Execution de-duplication contract**
   - prove that replayed/duplicate R02/R32 reports cannot mutate RMIC twice.

3. **Local reject ownership**
   - rejected order must generate a deterministic event to strategy/order-state/host telemetry,
   - rejected order must never reach R01/TCP TX.

4. **Initialization/readiness contract**
   - no order accepted before account/product policy and RMIC AMU initialization complete,
   - configuration updates must have defined atomicity.

5. **Kill switch / account disable behavior**
   - existing account-enable mechanism can serve as the primitive,
   - integration must define immediate disable semantics and observable status.

### P1 — strongly recommended risk completeness improvements

6. **Per-account outstanding-order limit**
   - current AMU has global capacity, but no per-account maximum open-order count.

7. **Order-rate limit**
   - orders per configurable time window, preferably per account and optionally global.

8. **Cancel/delete-rate limit**
   - useful when cancel traffic itself can become operational risk.

9. **Maximum order notional/exposure limit**
   - separate from available cash/margin and quantity checks.

10. **AMU occupancy/stash telemetry**
    - current bounded `ORDER_TABLE_FULL` is safe,
    - add occupancy/high-watermark/stash-use counters to detect operation close to capacity before hard failure.

### P2 — research/advanced controls, not blockers for first integration

11. **Volatility-aware dynamic limits**
    - consume normalized market state from HFT/order book,
    - tighten/loosen policy only through explicitly configured rules.

12. **Stop-loss / daily-loss kill logic**
    - requires a defined realized/unrealized PnL model.

13. **Liquidity-risk control**
    - requires market-depth/liquidity metrics and a clearly defined trading policy.

14. **Multiple EX2CL transactions in flight**
    - M5.4 has one active EX context but overlaps it with unrelated CL2EX,
    - only worth implementing if execution-return burst measurements show a bottleneck.

15. **Account/product metadata memory scaling**
    - large-account configurations should revisit resettable enabled metadata and hot-account arbitration.

## Controls from earlier literature worth adopting

The 2023 thesis cites prior risk work with these controls:

- order target/listed-product control,
- maximum order amount,
- maximum order quantity,
- order-flow limit in a time window,
- delete-order limit,
- unexecuted/outstanding-order limit.

RMIC currently covers product enable, quantity, price/cash/position constraints, and a global outstanding-order table, but not the per-account rate/delete/outstanding counters. These are good low-complexity additions because they are counter/threshold based and do not require redesigning the AMU.

## Recommended architecture decision

Do **not** expand the frozen M5.4 RTL with every policy rule.

Use a layered architecture:

```text
HFT internal order
    -> protocol/order-field adapter
    -> exchange-specific Risk Policy Layer
       - order type/TIF/product policy
       - rate/outstanding/notional limits
       - optional volatility/stop-loss hooks
       - futures margin calculation/normalization
    -> frozen RMIC M5.4 transactional core
       - account/product mutable state
       - reservation/reconciliation
       - outstanding-order AMU
       - CL2EX/EX2CL hazards and concurrency
    -> PASS / REJECT event
```

This preserves the measured/timing-closed RMIC architecture while allowing exchange policy to evolve independently.

## Definition of "RMIC core complete"

For this project, the M5.4 core is considered architecturally complete when judged as a protocol-independent transactional RM engine. It is **not** by itself a complete exchange-compliant risk product.

Full-system completeness requires the P0 integration contracts and policy layer above plus end-to-end validation in `HFT_RMIC`.
