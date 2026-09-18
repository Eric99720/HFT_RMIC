# I4 Frozen R01 Byte-Parity XSim Result

## Scope

This result closes the I4 focused functional byte-parity gate between the pinned frozen HFT encoder baseline and the risk-integrated R01 path.

Measured integration commit:

```text
8c8733e57f70eb752d55ddbecae8ec6018ecb614
```

Frozen dependencies:

```text
HFT  50217fad1fd580f8c451ba893f9035f4be1dc21a
RMIC de6c300f4f18b18296f013287ab0eca70d3abb72
```

Tool:

```text
Vivado Simulator 2022.1
156.25 MHz testbench clock
```

Evidence package:

```text
HFT_RMIC_i4_r01_parity_xsim_20260918-125059.zip
```

## Result

The corrected run compiled and elaborated the pinned frozen HFT encoder together with the integration-owned risk path, then completed all required markers:

```text
I4_R01_BYTE_PARITY_PASS label=legacy bytes=80
I4_R01_BYTE_PARITY_PASS label=prebuild bytes=80
I4_R01_REJECT_NO_PACKET_PASS
HFT_RMIC_I4_R01_BYTE_PARITY_TB_PASS
```

Simulation completed at 3936 ns with a normal `$finish`.

## What is proven

For identical frozen-HFT 256-bit order payload and identical R01 metadata:

1. ordinary/legacy order source -> risk -> frozen encoder emits an R01 payload exactly identical to the direct frozen-encoder baseline for all 80 bytes;
2. R01-prebuild order source -> risk -> frozen encoder also emits an exactly identical 80-byte payload;
3. a kill-switch-rejected order emits zero integrated R01 bytes;
4. accepted orders therefore preserve the frozen R01 byte contract while both active producer classes remain inside the risk boundary.

This run occurred after correcting the frozen RMIC AMU INSERT response contract: successful insertion of a new key is `ok=1, status=OK, found=0`.

## Simulation-memory boundary

The direct XSim flow defines:

```text
AMU_BEHAVIORAL_RAM
HFT_RMIC_BEHAVIORAL_RAM
```

so the AMU bank storage and integration futures-state RAM use behavioral synchronous-memory fallbacks during functional simulation. The control/state/accounting/order-lifecycle RTL and pinned frozen encoder RTL remain the actual design modules.

This result therefore establishes functional byte parity, not physical BRAM implementation.

## Remaining I4 physical gate

I4 is not complete until the real U50 OOC composition is implemented with no behavioral-RAM defines and real XPM block RAM:

```powershell
pwsh .\scripts\run_i4_r01_path_ooc_impl.ps1
```

Acceptance remains full route at 6.400 ns, WNS >= 0, TNS = 0, real BRAM present, zero routing errors, and reviewed utilization/critical-path/DRC/power evidence.

## Claim boundary

This is XSim functional evidence. It is not board traffic, physical packet latency, full dual-XGMII timing, official TAIFEX SPAN, live-exchange interoperability, or exchange conformance.
