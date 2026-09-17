# HFT_RMIC

Integration workspace for the frozen `hft-full-system-fpga` HFT baseline and the frozen `RMIC` risk-management core.

## Repository rule

This repository is the only place where HFT/RMIC integration glue, adapters, policy logic, integration tops, and cross-project verification are developed.

The two source repositories are treated as read-only upstream baselines:

- HFT baseline: `Eric99720/hft-full-system-fpga` @ `50217fad1fd580f8c451ba893f9035f4be1dc21a`
- RMIC baseline: `Eric99720/RMIC` @ `de6c300f4f18b18296f013287ab0eca70d3abb72`

Do not edit upstream source trees as part of integration work. Any required compatibility logic belongs under this repository's `rtl/integration/`, `rtl/policy/`, or `rtl/adapters/` hierarchy.

## Frozen source status

### HFT baseline

The selected HFT commit is the frozen pre-hardware dual-XGMII baseline before RMIC integration experiments. It includes the market/trading XGMII datapaths, RX-HOT speculative parsing, CDC, order book/strategy, R01 fast path, ARP/TCP connection management, TMP login/replay/maintenance/flow-control, byte-accurate network verification, and the accepted simulation-derived 83-cycle / 531.2 ns Gao-style nominal baseline.

### RMIC baseline

The selected RMIC commit is the M5.4 production-core baseline before protocol integration. It includes a 4096-entry collision-capable AMU, hazard-safe CL2EX II=1, concurrent CL2EX/EX2CL operation, same-account and same-order-ID interlocks, hardware compensation for fill/cancel/reject, and U50 post-route timing closure at 156.25 MHz.

## Intended integration boundary

```text
HFT market RX / protocol decode
        -> order book / strategy
        -> HFT order packing
        -> HFT_RMIC policy + field adapters
        -> RMIC M5.4 core
        -> accepted original HFT order payload
        -> existing TMP R01 encoder / trading network TX

TAIFEX execution reports
        -> existing HFT TMP decoder / report ownership
        -> HFT_RMIC execution adapter
        -> RMIC EX2CL fill/cancel/reject reconciliation
```

RMIC does not replace the HFT network layer, protocol decoder, order book, trading strategy, TMP session logic, encoder, TCP/IP stack, or PCS/PMA path.

## Current research decision

Before full integration, this repository will close risk-policy gaps identified by comparing the rebuilt RMIC with Chih-Yu Lin's 2023 thesis *FPGA-based Hardware Acceleration for Risk Management in High-Frequency Trading with Bidirectional Latencies under 600 ns* and related prior risk-control work.

See:

- `docs/rmic_gap_analysis.md`
- `docs/integration_architecture.md`
- `docs/source_baselines.md`

## Planned milestones

1. I0: freeze upstream commits and repository boundaries.
2. I1: normalized order/execution field adapters.
3. I2: risk-policy extension layer (rate/outstanding-order controls and exchange-specific policy hooks).
4. I3: CL2EX risk gate with byte-identical PASS path and explicit reject telemetry.
5. I4: EX2CL execution-report reconciliation integration.
6. I5: full dual-flow application/XGMII simulation.
7. I6: HFT-without-RMIC vs HFT-with-RMIC latency/resource A/B measurement.
8. I7: OOC/post-route closure at 156.25 MHz.
9. I8: U50/QSFP hardware validation when the board environment is available.

No simulation-derived latency will be presented as board-measured latency, and no exchange-specific rule will be claimed as compliant until validated against the authoritative exchange specification.
