# Decisions

Append-only durable architecture/research decisions. Do not rewrite old decisions to make later work look planned; append a superseding decision that names the prior one.

## D-20260917-01 — Separate integration repository with frozen upstreams

**Status:** Adopted.

**Decision:** `HFT_RMIC` is the sole integration workspace. `hft-full-system-fpga` and `RMIC` are pinned read-only submodules and are not modified by integration work.

**Why:** Both upstreams already contain valuable validated baselines. Mixing integration changes into either source destroys clean A/B comparison, source provenance and rollback clarity.

**Evidence:** `docs/source_baselines.md`, `.gitmodules`, dependency-contract checker.

---

## D-20260917-02 — Insert RM before the existing TMP encoder; do not replace HFT subsystems

**Status:** Adopted.

**Decision:** The nominal CL2EX path is strategy/order packer -> integration policy/accounting/RM -> original payload -> existing TMP R01 encoder. Existing network, order book, trading logic, session, encoder, TCP/IP and PCS/PMA remain owned by frozen HFT.

**Why:** RM is an inline safety gate, not a replacement for the trading stack. This preserves byte-identical accepted-order behavior and isolates integration risk.

**Evidence:** `docs/integration_architecture.md`, frozen HFT architecture, prior integrated-HFT/RM literature review.

---

## D-20260917-03 — Keep frozen RMIC M5.4 as generic transactional core; add exchange policy outside

**Status:** Adopted.

**Decision:** Product/exchange-specific order type, TIF, PositionEffect, rate, kill-switch and future volatility/liquidity policy live in `HFT_RMIC`. Do not add every rule to frozen RMIC M5.4.

**Why:** M5.4 has timing-closed AMU/order lifecycle/hazard behavior; policy evolves faster and needs a wider reject namespace than the frozen 4-bit RMIC reason field.

**Evidence:** `docs/rmic_gap_analysis.md`, `rtl/policy/hft_rmic_policy_gate.sv`.

---

## D-20260917-04 — Futures accounting v1 is long/short OPEN/CLOSE with configurable margin budget, not SPAN

**Status:** Adopted for integration research baseline.

**Decision:** Maintain separate long/short positions, pending OPEN orders and reserved CLOSE orders. OPEN margin uses host-configured `margin_per_contract`; CLOSE does not increase required margin. Unsupported PositionEffect values fail closed.

**Why:** Frozen RMIC stock-like unsigned position semantics cannot correctly represent SELL OPEN / BUY CLOSE. A deterministic versioned model is needed before full HFT integration, but it must not be misrepresented as official TAIFEX SPAN.

**Evidence:** `docs/taifex_futures_accounting_contract_v1.md`, `rtl/accounting/hft_rmic_futures_accounting_v1.sv`, self-checking accounting regression.

---

## D-20260917-05 — Frozen HFT report owner is the only R02/R32 execution mutation authority

**Status:** Adopted.

**Decision:** R02/R32 field decoding may happen earlier, but futures/RMIC state mutation occurs only from the frozen HFT report-sequence owner's committed event. Duplicate, replayed-old and gap reports must not mutate state. R03 error/reject processing uses the separate checksum-valid committed error path and is idempotent through order-context deletion.

**Why:** Applying raw decoder events can double-apply partial fills during replay/reconnect. The HFT baseline already owns sequence continuity/deduplication and should remain the single authority for R02/R32.

**Evidence:** frozen `hft_report_sequence_owner.v`, `hft_rx_order_book_top.v`, integration execution metadata tap and committed-execution regression.

---

## D-20260917-06 — Adopt phase-based repository governance

**Status:** Adopted.

**Decision:** `docs/project_state.json` is the shared-state source; current root summaries are synchronized mechanically. Substantial work uses one `codex/<phase-id>` branch and one PR through phase closure. Feature work no longer commits directly to `main`.

**Why:** Long-running FPGA/research integration needs durable state, clear task acceptance, reproducible handoff and protection from branch/document drift.

**Reference model:** adapted from `Eric99720/LOB-SOTA-Research` project governance, excluding ML/training-specific rules.

---

## D-20260917-07 — Futures state is the sole account-position source; RMIC reuse is limited to transactional primitives

**Status:** Adopted.

**Decision:** The integration-owned futures state manager is the sole source of truth for long/short position, pending OPEN, reserved CLOSE and margin-budget state. The frozen RMIC stock-like account record is not chained as a second account-state owner. Integration reuses the frozen RMIC AMU/hash/BRAM order-context primitive and its proven collision architecture, but futures account semantics remain integration-owned.

**Why:** Running both the stock-like M5.4 account mutation and futures OPEN/CLOSE accounting would create contradictory double accounting. The frozen AMU is independently useful and its 96-bit value is sufficient for the 89-bit futures order context without modifying the upstream.

**Alternatives considered:** reinterpret RMIC cash/position fields as futures state; modify frozen RMIC account record; maintain both state models. All were rejected because they either corrupt price-versus-margin semantics, violate the frozen-upstream boundary, or create dual mutable sources of truth.

**Evidence:** `rtl/integration/hft_rmic_futures_order_store_v1.sv`, `rtl/accounting/hft_rmic_futures_state_manager_v1.sv`, frozen RMIC AMU post-route evidence.

---

## D-20260917-08 — Reconcile execution with order context and authoritative quantity invariants

**Status:** Adopted.

**Decision:** Committed execution reconciliation first looks up `order_id` context, then validates report metadata before mutating futures state. R02/R32 trade uses `before_qty`, `LastQty` and `LeavesQty`; cancel and reduce use `before_qty`/`LeavesQty`; R03 releases the stored remaining reservation. Final/terminal lifecycle removes the order context, making repeated terminal events no-ops through context miss. Any mismatch fails closed.

For a trade report with active quantities:

```text
before_qty = stored_remaining_qty
before_qty >= LastQty + LeavesQty
auto_release = before_qty - LastQty - LeavesQty
```

`LastQty` becomes a FILL transition, `auto_release` becomes a RELEASE transition, and the order context is updated to `LeavesQty` or deleted at zero. This explicitly supports terminal IOC-style fill plus exchange-cancelled remainder without guessing.

**Why:** TAIFEX TMP v2.18.7 defines `before_qty` as pre-match remaining quantity, `LastQty` as the last execution quantity, and `LeavesQty` as current remaining quantity. Binding these fields to locally stored remaining quantity provides both correct lifecycle accounting and a second fail-closed defense against stale/duplicate reports.

**Evidence:** authoritative pinned TMP v2.18.7 section 2.4.2; `rtl/adapters/hft_tmp_exec_position_tap.sv`; `rtl/integration/hft_rmic_committed_execution_bridge_v1.sv`; `tb/tb_hft_rmic_committed_execution_bridge_v1.sv`; exact-head CI.

---

## Decision format for future entries

Each new decision should record:

- ID/date and status;
- decision;
- alternatives considered when material;
- reason;
- evidence/source references;
- superseded decision ID if applicable;
- verification/claim limitations.
