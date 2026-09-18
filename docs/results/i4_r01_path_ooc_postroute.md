# I4 Risk-to-Frozen-R01 — U50 OOC Post-route Result

## Scope

This result closes the final I4 physical gate for the focused order-to-risk-to-frozen-R01 composition.

Measured integration commit:

```text
9934fba3144bc33bcfaffda111bd544941489a2f
```

Frozen dependencies:

```text
HFT  50217fad1fd580f8c451ba893f9035f4be1dc21a
RMIC de6c300f4f18b18296f013287ab0eca70d3abb72
```

Target:

```text
Vivado 2022.1
xcu50-fsvh2104-2-e
156.25 MHz / 6.400 ns
```

Evidence package:

```text
HFT_RMIC_i4_r01_path_ooc_impl_20260918-134618.zip
```

## Timing

| Stage | WNS | TNS | Failing endpoints |
| --- | ---: | ---: | ---: |
| Synthesis | +2.310 ns | 0 ns | 0 |
| Placed | +0.966 ns | 0 ns | 0 |
| Routed | **+0.827 ns** | **0 ns** | **0** |

The design fully routes at the required 6.400 ns period.

The routed worst setup path remains inside the frozen RMIC AMU:

```text
source      u_risk/u_store/u_frozen_amu/fwd_addr_reg[7]
destination u_risk/u_store/u_frozen_amu/.../RAMB36E2/ADDRBWRADDR[11]
data path   5.244 ns
logic       1.400 ns
route       3.844 ns
levels      12
WNS         +0.827 ns
```

The path uses AMU forwarding/candidate/address logic into a block-RAM address input. Frozen encoder, policy/mapping, dual-source arbitration and CL/EX owner logic are not the routed critical path.

## Routed utilization

| Resource | I4 |
| --- | ---: |
| LUT | **5,596** |
| Logic LUT | **5,468** |
| LUTRAM | **128** |
| FF | **4,454** |
| RAMB36 | **19** |
| RAMB18 | **1** |
| DSP | **10** |

Hierarchy of interest:

- frozen financial encoder: 1,142 LUT / 755 FF / 128 LUTRAM;
- shared risk core: 4,452 LUT / 3,698 FF / 19 RAMB36 + 1 RAMB18 / 10 DSP;
- execution bridge: 394 LUT / 263 FF;
- order gate: 1,134 LUT / 1,311 FF;
- futures state manager: 1,246 LUT / 945 FF / 3 RAMB36 + 1 RAMB18 / 4 DSP;
- futures order store / frozen AMU: 1,679 LUT / 1,173 FF / 16 RAMB36 / 6 DSP.

The real pinned XPM memories are present. No behavioral-RAM define is used in this physical flow.

## Routing

```text
Fully routed nets: 11,255
Nets with routing errors: 0
Design state: Fully Routed
```

## DRC

The routed DRC contains **59 warnings and zero errors**:

| Rule | Severity | Count |
| --- | --- | ---: |
| DPIP-2 | Warning | 8 |
| DPOP-3 | Warning | 6 |
| DPOP-4 | Warning | 10 |
| DPOR-2 | Warning | 34 |
| RTSTAT-10 | Warning | 1 |

The DSP-pipelining warnings remain optimization opportunities. They do not block the 6.400 ns timing contract.

## Power

Vivado vectorless estimate:

```text
Total on-chip power  2.365 W
Dynamic              0.150 W
Device static        2.215 W
```

This is an implementation estimate, not board-measured power.

## I3 → I4 composition delta

I3 atomic CL2EX OOC was:

```text
WNS       +1.583 ns
LUT        2,392
FF         2,693
RAMB36        11
RAMB18         1
DSP           10
Power       2.278 W
```

I4 adds the committed-execution/shared-owner composition and the frozen HFT financial encoder boundary:

```text
WNS       +0.827 ns
LUT        5,596
FF         4,454
RAMB36        19
RAMB18         1
DSP           10
Power       2.365 W
```

The comparison is a composition delta, not an isolated cost decomposition: I4 contains modules not present in the I3 OOC top. The encoder alone accounts for 1,142 LUT / 755 FF / 128 LUTRAM in the routed hierarchy.

## I4 acceptance

Together with `docs/results/i4_r01_byte_parity_xsim.md`, I4 now satisfies both focused sign-off layers:

- ordinary and prebuild accepted R01 are exactly 80-byte identical to the direct frozen-encoder baseline;
- kill-switch reject emits no R01 bytes;
- real pinned XPM AMU/state BRAM are present;
- full route at 6.400 ns;
- routed WNS >= 0 and TNS = 0;
- zero routing errors;
- utilization, critical path, DRC and vectorless power reviewed.

## Claim boundary

I4 closes the focused frozen-HFT order-data → futures risk → frozen R01 encoder boundary. It does **not** yet establish full dual-XGMII top timing, market-packet-to-wire latency, board/QSFP latency, official TAIFEX SPAN, live exchange interoperability, or exchange conformance. Those belong to I5 and later hardware phases.
