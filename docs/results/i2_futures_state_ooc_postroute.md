# I2 Futures State + Execution OOC Post-route Result

Date: 2026-09-17  
Vivado: 2022.1  
Device: `xcu50-fsvh2104-2-e`  
Target clock: 156.25 MHz / 6.400 ns  
Measured integration commit: `61194b7b57aa87ddf99dba6ed19e257109f87d6f`  
Pinned HFT: `50217fad1fd580f8c451ba893f9035f4be1dc21a`  
Pinned RMIC: `de6c300f4f18b18296f013287ab0eca70d3abb72`

## Acceptance result

I2 OOC passes the physical acceptance gate using the real pinned RMIC XPM AMU plus the integration-owned futures state manager and committed-execution bridge.

| Metric | Result |
| --- | ---: |
| Synthesis WNS | **+2.318 ns** |
| Synthesis TNS | **0 ns** |
| Placed WNS | **+1.111 ns** |
| Placed TNS | **0 ns** |
| Routed WNS | **+1.078 ns** |
| Routed TNS | **0 ns** |
| Routable nets | 6,913 |
| Fully routed nets | 6,913 |
| Routing errors | **0** |
| LUT | 3,396 |
| FF | 2,383 |
| RAMB36 | 19 |
| RAMB18 | 1 |
| DSP | 10 |
| Vectorless total on-chip power | 2.324 W |
| Vectorless dynamic power | 0.110 W |

The implementation emitted `HFT_RMIC_I2_OOC_IMPL_DONE` and `MILESTONE=I2_FUTURES_STATE_AND_EXECUTION_OOC`.

## Timing root-cause and repair history

The first routed I2 composition failed at WNS **-6.866 ns** / TNS **-893.979 ns**. The state-manager path placed BRAM read, futures quantity transition, wide gross-exposure arithmetic, margin multiplication/budget decision, a second margin calculation, and BRAM writeback in one 6.400 ns cycle. The routed worst path was about 12.952 ns with 48 logic levels and multiple DSP/CARRY8 stages.

The repair did not relax timing constraints or add a multicycle exception. The microarchitecture was changed to a registered pipeline:

```text
state BRAM read
  -> capture
  -> quantity/OPEN-CLOSE transition
  -> registered exposure
  -> margin multiplication
  -> registered margin result
  -> decision/writeback
```

After that change, synthesis itself improved from **-6.232 ns to +2.318 ns**, demonstrating structural timing repair before placement/routing.

## Critical path after repair

The routed worst path is no longer in the futures state manager. It is inside the frozen AMU, from one XPM RAMB36 bank through AMU candidate/match/address selection to another RAMB36 enable/write path.

- Routed slack: **+1.078 ns**
- Data path delay: **4.909 ns**
- Logic delay: 1.979 ns
- Route delay: 2.930 ns
- Logic levels: 10
- SLR crossings: 0

This is consistent with the standalone frozen AMU/RMIC critical-path family and leaves positive setup margin at 156.25 MHz.

## Memory/resource ownership

Hierarchical routed utilization shows:

- futures state manager: 1,307 LUT / 946 FF / 3 RAMB36 + 1 RAMB18 / 4 DSP;
- futures order store + frozen AMU: 1,653 LUT / 1,173 FF / 16 RAMB36 / 6 DSP;
- committed-execution bridge: 434 LUT / 263 FF.

The real AMU remains block-RAM based; no LUTRAM regression is present.

## DRC / power claim limits

DRC reports warnings only, not implementation errors: DPIP-2 (8), DPOP-3 (6), DPOP-4 (10), DPOR-2 (34), RTSTAT-10 (1). The remaining DPIP/DPOP items identify optional DSP internal/input/output pipelining opportunities; they do not block the current 156.25 MHz closure.

Power is a Vivado vectorless estimate with medium confidence. It is not measured board power.

## Claim boundary

This result establishes post-route physical feasibility and timing closure for the **I2 OOC composition harness**, not the final full HFT+RMIC top, board packet latency, TAIFEX conformance, or live-exchange behavior. Full CL2EX admission integration begins in I3.