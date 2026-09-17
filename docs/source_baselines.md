# Frozen Source Baselines

This integration repository deliberately pins two read-only upstream designs. Integration work must not be committed back into either source repository.

## HFT baseline

Repository: `Eric99720/hft-full-system-fpga`

Pinned commit:

```text
50217fad1fd580f8c451ba893f9035f4be1dc21a
```

Commit message:

```text
docs(cleanup): refresh source and testbench inventory
```

Why this commit is selected:

- It is the frozen pre-hardware dual-XGMII HFT baseline before RMIC integration experiments were added.
- It records the accepted dual-port market-to-order latency baseline and source/testbench inventory.
- It contains the active market/trading XGMII paths, RX-HOT speculative parser, market-to-trading CDC, order book/strategy, R01 prebuild/fast TX lane, ARP/TCP connection management, TMP session/replay/maintenance/flow-control, and validation runners.
- It does **not** contain the later standalone RMIC gate experiments.

Accepted source-repository baseline numbers are simulation/OOC results, not hardware measurements:

- dual-XGMII internal market-to-order maximum: 31 cycles / 198.4 ns,
- Gao-style simulation approximation: 83 cycles / 531.2 ns,
- application-valid to trading-port XGMII START: 1 cycle / 6.4 ns,
- OOC timing WNS: +0.047 ns at 156.25 MHz.

## RMIC baseline

Repository: `Eric99720/RMIC`

Pinned commit:

```text
de6c300f4f18b18296f013287ab0eca70d3abb72
```

Commit message:

```text
docs: freeze M5.4 dual-flow U50 baseline
```

Why this commit is selected:

- M5.4 is explicitly frozen as the production-core baseline before protocol integration.
- It has collision-capable outstanding-order storage, CL2EX II=1, concurrent CL2EX/EX2CL, same-account and same-order-ID interlocks, and FPGA-side fill/cancel/reject compensation.
- It passed U50 post-route timing at 156.25 MHz.

M5.4 post-route baseline:

- LUT: 4,884
- FF: 5,533
- RAMB36: 21
- RAMB18: 1
- DSP: 18
- WNS: +1.291 ns
- TNS: 0
- routing errors: 0

## Dependency policy

Integration source consumption should use one of the following reproducible mechanisms:

1. Git submodules pinned to the exact commits above, or
2. a setup script that clones/fetches the two repositories and checks out the exact SHAs.

The integration build must fail if either dependency is at a different commit unless the baseline manifest is intentionally updated and the full integration regression is rerun.

## Upstream ownership rule

`HFT_RMIC` owns:

- field adapters,
- risk-policy extensions,
- account/product mapping,
- HFT-to-RMIC handshakes,
- reject/report adaptation,
- integration tops,
- integration testbenches,
- A/B performance experiments,
- integration-specific constraints/scripts.

It does **not** own or modify the internals of the pinned HFT or RMIC source repositories.
