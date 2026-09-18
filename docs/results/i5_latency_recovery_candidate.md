# I5 Latency-Recovery Candidate — Functional and Physical A/B

Date: 2026-09-19

## Scope

This note compares the verified timing-safe I5 baseline against the latency-recovery candidate. Both use the same pinned upstreams:

- HFT: `50217fad1fd580f8c451ba893f9035f4be1dc21a`
- RMIC: `de6c300f4f18b18296f013287ab0eca70d3abb72`
- U50 part: `xcu50-fsvh2104-2-e`
- target clock: 156.25 MHz / 6.400 ns

The comparison is local Vivado 2022.1 simulation/OOC evidence. It is not a board, QSFP, optics, live-exchange, or hardware latency claim.

## Candidates

| Item | Timing-safe baseline | Latency-recovery candidate |
| --- | --- | --- |
| Commit | `52aa8b98c35b3de32b23d3cfe16c13e65e659a2f` | `d788edb42b53d8c52771832e3eb7125101f7bfeb` |
| Branch | `codex/i5-full-dual-xgmii-integration` | `codex/i5-latency-recovery` |
| Active risk ingress slice | yes | no |
| Hot account/product map cache | no | yes |
| Full-system XSim | PASS | PASS |
| Real-XPM routed OOC | PASS | PASS |

## Functional evidence

The latency-recovery XSim is clean and preserves the full I5 contract:

- byte-exact ARP/TCP/TMP traffic;
- UDP market -> R01;
- BUY OPEN -> live R02 full fill -> same RMIC futures state -> SELL CLOSE;
- committed execution FIFO/metadata safety;
- back-to-back market CDC with no duplicate R01;
- source reset recovery;
- bad-FCS drop;
- trading-port market isolation;
- `TB_HFT_RMIC_DUAL_XGMII_FULL_SYSTEM PASS`.

The direct R01 stream still reports `app_to_start_cycles=1` in Scenario 3 and both Scenario 10 orders.

Absolute testbench cycle numbers are not used as the latency-recovery proof because configuration/cache warm-up changes scenario setup time. The dedicated five-phase SC5 measurement is the required next gate.

## Physical A/B

| Metric | Timing-safe baseline | Latency-recovery | Delta |
| --- | ---: | ---: | ---: |
| Routed WNS | +0.016 ns | +0.022 ns | +0.006 ns |
| TNS | 0.000 ns | 0.000 ns | 0 |
| market_rx_clk WNS | +0.054 ns | +0.168 ns | +0.114 ns |
| trading_clk WNS | +0.016 ns | +0.022 ns | +0.006 ns |
| Failing endpoints | 0 | 0 | 0 |
| Routing errors | 0 | 0 | 0 |
| LUTs | 56,668 | 57,025 | +357 (+0.63%) |
| FFs | 31,209 | 31,151 | -58 (-0.19%) |
| RAMB36 | 20 | 20 | 0 |
| RAMB18 | 1 | 1 | 0 |
| DSP | 10 | 10 | 0 |
| Estimated on-chip power | 2.553 W | 2.686 W | +0.133 W (+5.21%) |

The power values are Vivado vectorless estimates and must not be treated as measured board power.

## Timing-path interpretation

The candidate's routed worst path is inside the pinned HFT trading network RX path:

`u_trading_core/u_network_rx_fast_path/u_legacy/ip_total_len_reg[3]`
-> `u_trading_core/u_network_rx_fast_path/u_legacy/state_reg[2]_rep__1`

with routed WNS +0.022 ns.

The previously critical speculative-strategy -> RMIC exact-map/admission path is no longer the routed worst path, and the one-cycle `hft_rmic_order_ingress_slice_v1` is no longer active in the I5 composition.

The hot-map cache keeps the generic exact maps as the configuration source of truth, caches only the bridge-owned hot account/product keys, invalidates on configuration writes, and still requires the packed order keys to match the cached keys before reporting a map hit.

## Current conclusion

The latency-recovery candidate has passed functional and physical closure and is therefore a valid candidate to replace the timing-safe baseline.

It is **not yet proven** that the intended 6.4 ns market-to-R01 latency recovery is realized across asynchronous market/trading clock phase. The next acceptance gate is a five-phase SC5 sweep at 0/1280/2560/3840/5120 ps using `scripts/run_i5_latency_phase_sweep.ps1`.

Promotion should occur only after that sweep is reviewed against the timing-safe baseline and the pinned-HFT latency reference.
