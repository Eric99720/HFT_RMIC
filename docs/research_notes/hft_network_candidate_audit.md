# Junior U50 network / PHY candidate audit

This durable note is complete. See decision `D-20260917-09` for the adopted disposition.

## Candidate identity and source risk

The audited user-supplied archive is `my_code-20260916T141751Z-1-001(1).zip`, observed SHA-256:

```text
e39d5b9780e345238de3350dd36d5848bacf9ce0102b6d6cc1c3fc342941a19a
```

It contains an unversioned `hft-full-system-fpga-master/` snapshot plus a separate `PHY_CUSTOMER/` U50/10G workspace, bitstream, PCAP, reports and XSim studies. No exact Git commit identity is recorded for the bundled HFT snapshot or copied `verilog-ethernet` source. It therefore cannot be promoted wholesale into a pinned baseline.

Selected Git-blob comparison against frozen HFT `50217fad1fd580f8c451ba893f9035f4be1dc21a` proves source-version drift outside the intentional network overrides as well as inside them. Examples include `hft_network_rx_fast_path.v`, `hft_unified_network_connection_manager.v`, `hft_dual_xgmii_full_system_top.v`, `hft_round_chip_app_top.v`, `hft_rx_order_book_top.v`, and `market_fast_decoder.v`. The archive has no history proving who changed each differing file.

## Intentional network changes worth selective migration

The candidate bitstream build explicitly replaces the frozen/snapshot network RX and unified connection-manager files and adds `hft_tcp_syn_retry_guard.v`.

### TCP Data-Offset/options support — recommended

The frozen HFT RX path assumes a 20-byte TCP header (`payload offset 54`, `tcp_data_offset_words == 5`). The candidate computes payload position from TCP Data Offset, accepts headers >=5 words and validates header length against L4 length. This is a real interoperability improvement for SYN/SYN-ACK packets carrying TCP options and should be reimplemented against the frozen/current HFT source with focused regressions.

### SYN retry — recommended

The candidate adds a bounded retry pulse while stuck in SYN_SENT. A migration must test successful-handshake/no-retry, missing-SYN-ACK retry, reset/link-down behavior and runtime seq/ack integrity after eventual success.

### Static remote MAC — optional lab mode only

The candidate supports a compile-time static remote MAC to bypass ARP in the supplied direct-link U25/U50 test. Preserve ARP as production/default behavior; static MAC may be retained only as an explicit lab/board profile.

### Market BODY-LENGTH +22 — legacy test compatibility only

The supplied PCAP is replayed with legacy `payload length = BODY-LENGTH + 22`. The frozen HFT market decoder deliberately uses official `BODY-LENGTH + 12` by default and keeps the old behavior only for compatibility vectors. Do not migrate +22 as the protocol default.

### Status UDP disable — build profile only

The candidate disables diagnostic/status UDP in its board build. This is a test profile, not a core HFT architecture improvement.

## PHY / board candidate

`PHY_CUSTOMER` includes AU50/U50 GTY wrappers, copied `verilog-ethernet` 10G PCS logic, XGMII CDC, a dual-lane board top, constraints/Tcl and board test tooling. A future migration must identify and pin the exact external PCS source revision rather than adopting an unversioned copied tree.

## Supplied evidence and limits

The bundle reports a clean-start U25/U50 main-path test:

```text
U25 market PCAP -> U50 Ethernet/XGMII -> IPv4/UDP -> TAIFEX market decode
 -> order book/strategy -> TCP/TMP R01 -> U25 exchange model -> R02
```

Reported evidence includes session/maintenance success, 13,573 replayed market packets without tcpreplay failure, R01 observation, R02 transmit and 20 orders seen by the exchange model. Treat this as **provided hardware evidence**, not an independently reproduced HFT_RMIC result.

Provided bitstream SHA-256:

```text
09a182ea7d48568a43c6bbcf4887b746ccc532ab6d6f42a87127776c4e6cc9f3
```

Provided post-route summary reports no setup/hold violation; market 156.25 MHz setup slack is `+0.081 ns` while overall WNS is `0.000 ns` due another group at exactly zero. Utilization is reported as 62,715 CLB LUTs, 28,639 CLB registers, 1 Block RAM tile and 0 DSP. DRC has zero errors and one RTSTAT-10 warning. These numbers are not directly comparable to the frozen HFT OOC boundary.

Latency evidence is simulation-only: the active-path document reports `398.9 ns` using endpoint-attribution estimates; separate PHY simulations report PCS-only 25.6 ns, two-endpoint PCS+GT average 208.128 ns (192.0–211.2 ns), and GT+behavioral serial boundary 128.0 ns. Do **not** replace the frozen 531.2 ns Gao-style baseline with 398.9 ns until both designs are rerun with the same boundary/method. None of these numbers is a board-measured latency result.

## Adopted disposition

Do not replace `deps/hft-full-system-fpga`, do not advance its pin during I2, and do not copy the candidate snapshot wholesale.

After I2 physical closure, open a separate phase tentatively named:

```text
N1 — HFT Network / U50 PHY Candidate Migration
codex/n1-network-phy-migration
```

N1 should:

1. port TCP Data-Offset/options support to the frozen/current source and add focused parser tests;
2. port SYN retry and add connection-state regressions;
3. add optional static-MAC lab mode while retaining ARP default;
4. preserve official `BODY-LENGTH+12`, with +22 only as an explicit legacy PCAP profile if still needed;
5. pin a reproducible 10G PCS/GT third-party source and reconstruct the U50 board wrapper;
6. rerun frozen-HFT regressions;
7. reproduce the U25/U50 R01/R02 board test;
8. perform matched old-vs-candidate latency/resource/timing A/B;
9. change the HFT_RMIC HFT source pin only if the migration phase closes successfully.
