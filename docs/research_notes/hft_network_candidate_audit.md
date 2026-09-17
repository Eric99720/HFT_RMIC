# Junior U50 network / PHY candidate audit

## Scope and identity

This note audits the user-supplied archive `my_code-20260916T141751Z-1-001(1).zip` as a **candidate evidence bundle**, not as a trusted replacement source tree.

Archive SHA-256 observed during the audit:

```text
e39d5b9780e345238de3350dd36d5848bacf9ce0102b6d6cc1c3fc342941a19a
```

The archive contains three distinct kinds of material:

1. `hft-full-system-fpga-master/` — an HFT source snapshot without Git metadata;
2. `PHY_CUSTOMER/` — a replacement U50 10G PCS/PMA + board integration workspace with network RTL overrides;
3. packaged bitstream, PCAP, timing/utilization/DRC reports and XSim latency experiments.

No exact Git commit identity for the bundled HFT snapshot or the copied `verilog-ethernet` source was recorded in the archive. Therefore this bundle must not become a source pin by file-copying it wholesale.

## Comparison with the frozen HFT baseline

The HFT_RMIC frozen source remains:

```text
Eric99720/hft-full-system-fpga
50217fad1fd580f8c451ba893f9035f4be1dc21a
```

Selected Git-blob comparisons prove the bundled `hft-full-system-fpga-master` snapshot is **not byte-identical** to the frozen baseline, including outside the two intentionally overridden network modules:

| Path | bundled snapshot blob | frozen `50217fad...` blob | Same? |
| --- | --- | --- | --- |
| `rtl/network/rx/hft_network_rx_fast_path.v` | `cc2eecbf...` | `fde1f3cd...` | No |
| `rtl/network/connection/hft_unified_network_connection_manager.v` | `b7b3c7a2...` | `51d93311...` | No |
| `rtl/top/hft_dual_xgmii_full_system_top.v` | `1e46b030...` | `a20df7b8...` | No |
| `rtl/top/hft_round_chip_app_top.v` | `b8bd9074...` | `0703382b...` | No |
| `rtl/order_book/hft_rx_order_book_top.v` | `a1c08974...` | `6064abd8...` | No |
| `rtl/decoder/market/market_fast_decoder.v` | `052ba1df...` | `c37cdc89...` | No |

Because the archive lacks Git history, these differences establish **version drift**, not authorship. They do not prove the junior personally edited every differing file. They do prove that replacing the current frozen HFT tree with the bundled snapshot would be an uncontrolled regression/migration.

## Intentional candidate overrides

The bitstream build manifest deliberately skips two HFT files and replaces them with `PHY_CUSTOMER/src/overrides/` versions:

```text
rtl/network/rx/hft_network_rx_fast_path.v
rtl/network/connection/hft_unified_network_connection_manager.v
```

It also adds:

```text
hft_tcp_syn_retry_guard.v
```

The intentional network changes are narrow and technically separable.

### 1. TCP options-aware RX parsing — recommended for selective port

The frozen/current HFT RX path assumes a fixed 20-byte TCP header:

```text
payload starts at Ethernet byte 54
tcp_data_offset_words == 5
```

The candidate override instead computes the payload start from TCP Data Offset and accepts headers >= 5 words while checking the declared header length fits inside L4 length.

This is a real interoperability improvement: Linux SYN/SYN-ACK commonly carries TCP options. The change should be ported against the **current frozen source**, accompanied by dedicated option/no-option/malformed-header regressions, rather than by copying the old snapshot file.

### 2. SYN retry guard — recommended after regression

The candidate adds a one-cycle `connection_enable` drop after a configurable timeout while the controller remains in `SYN_SENT` (default `156250000` cycles at the 156.25 MHz design clock). This forces the existing connection owner to restart a stuck handshake.

This is useful board/network robustness and should be recreated against the frozen connection manager with tests for:

- ordinary successful handshake: no retry pulse;
- no SYN-ACK: bounded retry;
- link-down / disabled connection: counter reset;
- retry does not corrupt runtime seq/ack ownership after later success.

### 3. Static remote MAC mode — keep as optional lab mode only

The candidate can expose `REMOTE_MAC_FALLBACK` as immediately valid and bypass ARP when `HFT_STATIC_REMOTE_MAC` is defined. This fixed the supplied U25/U50 direct-link test setup and correctly propagates the selected destination MAC to downstream frame builders.

It should **not** become the production default. Preserve ARP as the normal behavior; static MAC belongs in a host/configuration or board-lab mode with an explicit enable.

### 4. `BODY-LENGTH + 22` — do not migrate as the production default

The supplied captured 2024 market PCAP is replayed with a compatibility condition:

```text
captured UDP payload length == TAIFEX BODY-LENGTH + 22
```

The frozen HFT market decoder intentionally uses official TMP semantics by default:

```text
total message length = BODY-LENGTH + 12
```

and retains `+22` only as a legacy compatibility mode. The candidate board wrapper sets the old compatibility behavior to make the supplied capture pass. That is valid for reproducing that capture but must not replace the official default.

If that PCAP remains useful for hardware regression, expose an explicit **test-vector compatibility setting** in a future board harness; do not change protocol conformance semantics globally.

### 5. Status UDP disable — test/build configuration, not core architecture

`HFT_DISABLE_STATUS_UDP` disables the diagnostic/status path in the candidate bitstream. Keep it as a build/profile choice if the status traffic interferes with board tests; it is not a functional HFT improvement.

## PHY / U50 hardware candidate

`PHY_CUSTOMER` is more substantial than a normal RTL patch. It contains:

- AU50/U50 GTY reference wrappers;
- copied `verilog-ethernet` 10G PCS RTL;
- an HFT-compatible PCS/PMA wrapper with TX/RX XGMII CDC FIFOs;
- a dual-lane U50 board top (market RX lane + trading RX/TX lane);
- constraints and GT generation Tcl;
- bitstream and board-test procedure;
- PCAP/exchange-model based U25/U50 functional test evidence;
- separate PHY and active-HFT XSim latency experiments.

The copied source files contain their source-level permissive license headers, but the archive does not pin the external `verilog-ethernet` Git commit. A future migration must register an exact external source revision instead of committing an unversioned copied vendor tree as the canonical dependency.

## Evidence found in the supplied bundle

### Board functional evidence (bundle-reported)

The supplied README records a clean-start U25/U50 test with:

```text
U25 market PCAP replay
 -> U50 Ethernet/XGMII RX
 -> IPv4/UDP + TAIFEX market decode
 -> order book / strategy
 -> TCP/TMP R01 TX
 -> U25 exchange model receives R01
 -> U25 sends R02
```

Reported pass criteria include TMP session establishment, maintenance, 13,573 replayed market packets with no tcpreplay failure, R01 observed, R02 transmitted, and 20 orders seen by the exchange model.

Treat this as **provided hardware evidence** from the archive. It is materially stronger than simulation-only evidence, but HFT_RMIC has not independently rerun the board experiment yet.

The provided bitstream SHA-256 matches the README identity:

```text
09a182ea7d48568a43c6bbcf4887b746ccc532ab6d6f42a87127776c4e6cc9f3
```

### Post-route evidence

The provided final timing report states all timing constraints are met. Overall summary shows zero setup/hold violations; the 156.25 MHz market RX clock group reports setup slack `+0.081 ns`. The overall WNS field is `0.000 ns` because another constrained group lands exactly at zero.

Provided utilization report:

```text
CLB LUTs       62,715
CLB Registers  28,639
Block RAM Tile      1
DSP                  0
```

Provided DRC report has zero errors and one `RTSTAT-10 No routable loads` warning.

These numbers are **not** used as a direct resource delta against the frozen HFT OOC baseline because the physical top/boundaries differ and this candidate includes a board/GT/PCS composition.

### Latency evidence

The archive contains two distinct simulation studies:

1. active HFT path: reported `398.9 ns` after endpoint-attribution adjustments;
2. isolated PHY study:
   - PCS-only TX+RX: `25.6 ns` for 25/25 frames;
   - two-endpoint PCS+GT wrapper: average `208.128 ns`, range `192.0–211.2 ns`;
   - GT+behavioral serial model boundary: `128.0 ns`.

These are **simulation results, not U50 hardware latency measurements**. The active-path document explicitly uses endpoint attribution estimates for parts of Network RX/TX, so its `398.9 ns` must not silently replace the frozen `531.2 ns` Gao-style baseline. A migration phase must rerun both old and candidate designs under the same latency boundary/method before making a latency-improvement claim.

## Disposition

### Do not do

- do not replace `deps/hft-full-system-fpga` with the bundled snapshot;
- do not advance the frozen HFT submodule pin during I2;
- do not make `BODY-LENGTH+22` the official/default protocol rule;
- do not treat `398.9 ns` as hardware-measured latency;
- do not commit the unversioned copied `verilog-ethernet` tree as a new canonical third-party source.

### Selectively migrate in a dedicated phase

After I2 physical closure, open a separate HFT network/hardware migration phase and rebuild the useful changes against the then-frozen source:

1. port TCP Data-Offset/options support and add focused parser regressions;
2. port SYN retry with connection-state regressions;
3. add optional static-MAC lab mode without removing ARP;
4. preserve official `BODY-LENGTH+12`; expose +22 only for the legacy PCAP test profile if still needed;
5. register/pin a reproducible 10G PCS/GT dependency and reconstruct the U50 board wrapper;
6. rerun frozen-HFT regressions;
7. reproduce U25/U50 R01/R02 board test;
8. perform matched old-vs-candidate latency/resource/timing A/B before changing the HFT_RMIC source pin.

Only after that phase passes should `HFT_RMIC` consider a source-pin migration. This preserves the current clean A/B baseline and avoids mixing a promising hardware bring-up package with unrelated source-version drift.
