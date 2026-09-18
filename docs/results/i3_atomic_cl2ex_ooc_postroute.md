# I3 Atomic CL2EX Risk Gate — U50 OOC Post-route Result

## Scope

This result signs off the I3 CL2EX admission composition only. It combines the frozen-HFT 256-bit order gate, integration-owned mapping/policy, pipelined futures state reservation/rollback, and the real pinned RMIC XPM AMU order-context store. It is not yet the final full HFT datapath.

Measured integration commit:

```text
75e06d17396d9c9f234f175013d090f329f965df
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

## Post-I3 functional-contract erratum

The physical implementation numbers in this document remain valid, but I4 frozen-encoder XSim later exposed a functional contract mismatch that the original I3 CI stub had hidden.

The real frozen RMIC AMU defines successful **new-key INSERT** as:

```text
rsp_ok     = 1
rsp_found  = 0
rsp_status = OK
```

`rsp_found=1` on INSERT instead denotes that an existing key was found (duplicate / `EXISTS`). The original integration CI stub incorrectly returned `found=1` for a successful new INSERT, and the original I3 admission controller incorrectly required `rsp_found=1` for INSERT success. Consequently, I3's routed design was physically valid but its actual-AMU INSERT success predicate was not functionally correct.

The mismatch was discovered in I4 by running the real pinned AMU together with the frozen R01 encoder: the baseline encoder emitted all 80 bytes while the integrated path rolled back and rejected the order. I4 corrects the controller to accept `rsp_ok && status==OK` for INSERT, corrects the CI stub and order-store/execution tests to the frozen AMU response contract, and re-runs the full regression stack.

Therefore:

- the I3 timing, utilization, routing, DRC and power results below remain valid physical evidence;
- the original statement that exact-head I3 CI plus OOC alone closed the **real-AMU functional INSERT contract** is superseded by the I4 correction/evidence;
- no frozen RMIC RTL was modified.

## Timing

| Stage | WNS | TNS |
| --- | ---: | ---: |
| Synthesis | +3.023 ns | 0 ns |
| Placed | +2.135 ns | 0 ns |
| Routed | **+1.583 ns** | **0 ns** |

No setup endpoint fails timing.

The routed worst reg-to-reg path is still inside the frozen AMU, from one XPM `RAMB36E2` bank through candidate/match/forwarding selection into another `RAMB36E2` input. The path is 4.461 ns with 8 logic levels (logic 1.683 ns, route 2.778 ns). Mapping, policy, futures reservation and rollback logic are not the routed critical path.

## Routed utilization

| Resource | Result |
| --- | ---: |
| LUT | **2,392** |
| FF | **2,693** |
| LUTRAM | **0** |
| RAMB36 | **11** |
| RAMB18 | **1** |
| DSP | **10** |

Hierarchy of interest:

- order gate: 926 LUT / 1,343 FF;
- futures state manager: 937 LUT / 929 FF / 3 RAMB36 + 1 RAMB18 / 4 DSP;
- futures order store / frozen AMU: 529 LUT / 420 FF / 8 RAMB36 / 6 DSP.

The I3 AMU uses one 96-bit order-context word over 8 banks; compared with the I2 execution/reconciliation composition this OOC top does not instantiate the I2 execution bridge ownership harness, so BRAM count is lower and should not be interpreted as a reduction of the frozen AMU architecture itself.

## Routing

```text
Routing errors: 0
```

The design completed place and route and produced a routed checkpoint.

## DRC

The routed DRC contains warnings only, no errors. The principal warnings are DSP pipelining guidance (`DPIP-2`, `DPOP-3`, `DPOP-4`), asynchronous-load checks (`DPOR-2`) and one no-routable-load warning (`RTSTAT-10`). None blocks the 6.400 ns timing contract.

The DSP warnings remain optimization opportunities, not I3 acceptance failures. Any later optimization must preserve the functional/atomicity regressions and be remeasured rather than assumed beneficial.

## Power

Vectorless Vivado estimate:

```text
Total on-chip power  2.278 W
Dynamic              0.065 W
Device static        2.213 W
Confidence           Medium
```

This is an implementation estimate, not board-measured power.

## I3 physical acceptance

I3 physical acceptance is satisfied:

- real pinned RMIC XPM AMU compiled;
- real block RAM present;
- complete route;
- routed WNS >= 0 at 6.400 ns;
- TNS = 0;
- zero routing errors;
- utilization, critical path, DRC and power reviewed.

The later I4 erratum above narrows the original functional claim; I3 remains valid as physical/OOC evidence for this composition.

## Claim boundary

This result does **not** establish final HFT+RMIC end-to-end packet latency, R01 byte emission timing, board/QSFP latency, official TAIFEX SPAN behavior, live exchange interoperability, or exchange conformance. Those require the later full frozen-HFT integration and hardware evidence phases.
