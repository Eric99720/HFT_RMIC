# Results and evidence publication policy

This repository integrates a frozen HFT baseline with a frozen RMIC core. Performance and correctness claims must identify the evidence layer and exact source/config identities.

## Evidence layers

1. **Specification/source evidence**
   - authoritative TAIFEX documentation;
   - frozen HFT/RMIC source pins;
   - theses/papers used for comparison or design motivation.
2. **Functional simulation**
   - Icarus/XSim self-checking regression;
   - may establish state-transition and byte/field behavior within the simulated contract.
3. **Synthesis/OOC**
   - may establish synthesis feasibility, estimated utilization and constrained timing at the named boundary.
4. **Post-route**
   - may establish routed timing/resource/DRC and vectorless power estimate for the named top/part/clock.
5. **Hardware/live-system**
   - may establish board/link/network latency, live packet behavior and measured power only when the actual hardware method is documented.

Never merge these levels in wording. Every table/summary must say which layer produced the number.

## Provenance required for compact results

A reviewed committed result must state at minimum:

- Git commit SHA for `HFT_RMIC`;
- frozen HFT and RMIC submodule SHAs;
- tool and version;
- target part and clock where applicable;
- top/testbench/runner;
- important parameters;
- raw artifact/report location or package identity;
- pass/fail criteria;
- caveats and claim boundary.

## What stays local

Keep these ignored unless a dedicated decision approves a compact/redacted publication artifact:

- full Vivado run trees and DCPs;
- raw logs and wave databases;
- packet captures containing non-public traffic;
- exchange credentials/session data;
- proprietary/raw market datasets;
- host-specific absolute paths;
- large generated arrays and temporary debug dumps.

## Latency rules

- Simulation cycles are simulation latency.
- Synthesis slack is not routed timing.
- Routed WNS/TNS is not board latency.
- Derived Gao-style approximations must name their formula/components and remain distinct from direct timestamp measurements.
- Board latency requires a defined physical boundary and actual hardware timestamps/capture.

## Power rules

Vivado vectorless power is an estimate. Do not label it measured power. A board-power claim requires the measurement instrument/source, rail/boundary, idle/load method and uncertainty/conditions.

## Protocol/compliance rules

A field mapping or policy implemented from the project audit is not automatically official conformance. Exchange-specific claims must cite the authoritative document/version and demonstrate the required golden vectors or conformance evidence for the claimed scope.

The futures accounting v1 model is a host-configured risk-budget model and is not TAIFEX SPAN unless a future version explicitly implements and validates the authoritative methodology.

## Comparative claims

For HFT-without-RMIC vs HFT-with-RMIC A/B comparisons:

- use the same frozen HFT source and equivalent stimulus;
- state exactly where the RM path is inserted;
- report both latency and resource/timing tradeoffs;
- do not use old thesis whole-system latency as if it were the same boundary;
- separate functionality gained from pure speed comparisons.
