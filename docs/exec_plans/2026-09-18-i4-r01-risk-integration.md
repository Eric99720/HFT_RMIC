# I4 — Frozen-HFT R01 Risk Integration

## 1. Phase identity

- Phase: `I4`
- Status: COMPLETE
- Branch: `codex/i4-r01-risk-integration`
- Draft PR: `#3`
- HFT pin: `50217fad1fd580f8c451ba893f9035f4be1dc21a`
- RMIC pin: `de6c300f4f18b18296f013287ab0eca70d3abb72`
- Target clock: 156.25 MHz / 6.400 ns
- Sign-off part: U50 `xcu50-fsvh2104-2-e`

## 2. Goal

Insert the I3 atomic futures risk gate into the frozen HFT R01 order boundary without editing either upstream repository. Both order producers used by the frozen HFT application path must traverse the same risk transaction before the frozen financial encoder can observe the payload:

```text
ordinary bridge order_data ----\
                                -> prebuild-priority source mux
R01 prebuild order_data --------/              |
                                               v
                                 shared futures risk core
                                 - atomic CL admission
                                 - committed EX reconciliation
                                 - one state owner
                                 - one AMU context owner
                                               |
                                         ACCEPT only
                                               v
                               frozen financial_protocol_encoder
                                               |
                                              R01
```

## 3. Why both sources are mandatory

The pinned HFT application has two mutually selected strategy-order paths. The ordinary bridge drives `bridge_strategy_order_valid/data`, while `ENABLE_R01_PREBUILD=1` allows `prebuild_direct_valid/prebuilt_order_data` to feed the encoder directly. The deployed XGMII-oriented baseline enables R01 prebuild, so gating only the ordinary bridge would create a risk-control bypass.

I4 therefore preserves the frozen producer priority but moves the risk handoff above both sources.

## 4. Shared CL/EX ownership contract

I3 admission and I2 committed execution were each verified as exclusive clients of futures state and the AMU order-context store. I4 composes them using transaction-level ownership rather than interleaving their individual memory operations.

- `OWNER_NONE`: execution commit has priority over a simultaneous new order.
- `OWNER_CL`: CL2EX admission owns both state and store until its result is consumed.
- `OWNER_EX`: committed execution reconciliation owns both state and store until its result is consumed.
- configuration is accepted only while no transaction owns the shared resources.
- any recovery-required condition stops further normal admission until explicit recovery/reset policy clears it.

This is correctness-first serialization. It is not an II=1 claim.

## 5. Work items

### I4-01 — Shared futures state/store ownership

Deliver `hft_rmic_shared_core_v1` around the closed I3 order gate, I2 committed-execution bridge, one pipelined futures-state manager and one real RMIC AMU order store.

Acceptance:

- an accepted BUY OPEN reservation/context is visible to EX reconciliation;
- a committed full fill updates the same state owner and removes the context;
- a later SELL CLOSE succeeds only because the preceding fill updated long position;
- simultaneous EX + CL acquisition gives EX priority;
- once an owner is chosen, the other client cannot interleave state/store requests;
- recovery-required remains fail-closed.

Status: COMPLETE in exact-head CI.

### I4-02 — Dual frozen-HFT order-source risk boundary

Deliver `hft_rmic_dual_order_source_v1` and `hft_rmic_r01_path_v1`.

Acceptance:

- ordinary bridge order payload traverses risk before encoder;
- R01-prebuild payload traverses the same risk path;
- when both are valid, prebuild retains frozen-HFT priority and legacy is backpressured;
- only `accepted_order_data` drives the frozen encoder;
- a policy/accounting/store reject never creates R01 traffic.

Status: COMPLETE in exact-head CI.

### I4-03 — Functional and byte-parity evidence

CI uses deterministic AMU/encoder contract stubs to close shared ownership and source/handshake semantics. Local Vivado XSim uses the pinned real RMIC AMU and pinned frozen encoder RTL and compares a direct-baseline encoder against the risk-integrated encoder.

Acceptance:

- shared-core closed-loop functional regression passes;
- dual-source risk-to-encoder regression passes;
- legacy accepted R01 is exactly 80-byte identical to direct frozen-encoder baseline;
- prebuild accepted R01 is exactly 80-byte identical to direct frozen-encoder baseline;
- kill-switch reject emits zero integrated R01 bytes.

Local command:

```powershell
pwsh .\scripts\run_i4_r01_parity_xsim.ps1
```

Status: COMPLETE. Corrected Vivado/XSim evidence at integration commit `8c8733e57f70eb752d55ddbecae8ec6018ecb614` passes exact 80-byte parity for both legacy and prebuild sources and proves kill-switch reject emits zero integrated R01 bytes. See `docs/results/i4_r01_byte_parity_xsim.md`.

### I4-04 — U50 physical composition gate

Implement the focused order→risk→frozen-R01 composition with the real pinned XPM AMU.

Acceptance:

- Vivado 2022.1;
- U50 `xcu50-fsvh2104-2-e`;
- 6.400 ns clock;
- real BRAM present;
- full route with zero routing errors;
- routed WNS >= 0 ns and TNS = 0;
- utilization, DRC, critical-path and vectorless-power reports packaged for review.

Local command:

```powershell
pwsh .\scripts\run_i4_r01_path_ooc_impl.ps1
```

Status: COMPLETE. Real-XPM U50 OOC at integration commit `9934fba3144bc33bcfaffda111bd544941489a2f` fully routes at 6.400 ns with synth WNS +2.310 ns, routed WNS +0.827 ns, TNS 0, 19 RAMB36 + 1 RAMB18, 10 DSP and zero routing errors. See `docs/results/i4_r01_path_ooc_postroute.md`.

## 6. Unexpected real-AMU contract discovery and correction

The first local parity package (`HFT_RMIC_i4_r01_parity_xsim_20260918-024121.zip`) compiled and elaborated successfully with the pinned real RMIC AMU and frozen HFT encoder. The direct baseline encoder emitted all 80 R01 bytes, but the integrated path emitted none and held a fail-closed risk reject.

Source audit identified the real cause. The frozen AMU's new-key INSERT response is:

```text
rsp_ok     = 1
rsp_status = OK
rsp_found  = 0
```

`rsp_found=1` on INSERT means a pre-existing key was found and the status is `EXISTS`. The original HFT_RMIC CI stub incorrectly returned `found=1` for successful new INSERT, and `hft_rmic_cl2ex_admission_v1` therefore incorrectly required `store_rsp_found` in its success predicate. With the real AMU, every valid new order was reserved, INSERTed successfully, then falsely interpreted as store failure, RELEASE-rolled back and rejected.

Corrections made in I4:

1. CL admission accepts INSERT on `rsp_ok && rsp_status==OK`; `found` is not required.
2. CI AMU stub now matches the frozen operation-specific `found` semantics.
3. Order-store regression verifies INSERT success as `found=0`, then LOOKUP verifies payload.
4. Execution-bridge preload helpers use the same real INSERT contract.
5. UPDATE payload is verified through a subsequent LOOKUP rather than assuming the response returns the newly written value.
6. Parity TB has bounded waits and fails immediately with reject source/code if the integrated path is rejected.
7. Windows parity runner writes console capture to distinct filenames rather than competing with Vivado simulator native log files.

After these changes, the full CI lifecycle stack passes again: order context, committed execution, atomic admission, order gate, shared CL/EX owner, dual-source risk boundary, I2/I3/I4 composition compile-smokes and parity-testbench compile.

Research-integrity handling:

- I3 timing/resource/routing/power evidence remains valid.
- The I3 result document and `D-20260918-14` explicitly narrow the earlier real-AMU functional-closure wording because the old CI stub encoded different INSERT semantics.
- frozen RMIC and frozen HFT source pins remain unchanged.

## 7. Corrected local parity closure

The rerun package `HFT_RMIC_i4_r01_parity_xsim_20260918-125059.zip` completes normally with:

```text
I4_R01_BYTE_PARITY_PASS label=legacy bytes=80
I4_R01_BYTE_PARITY_PASS label=prebuild bytes=80
I4_R01_REJECT_NO_PACKET_PASS
HFT_RMIC_I4_R01_BYTE_PARITY_TB_PASS
```

The parity flow uses behavioral synchronous RAM fallbacks for XSim only; physical OOC remains real-XPM. The full result and claim boundary are recorded in `docs/results/i4_r01_byte_parity_xsim.md`.

## 8. Evidence closed before U50 OOC

Exact-head GitHub CI covers:

- adapter/policy/execution metadata;
- futures accounting and multi-key state manager;
- real-AMU-contract-aligned order-context wrapper semantics;
- committed execution reconciliation;
- atomic CL admission including rollback/fault injection;
- frozen-HFT order gate;
- I4 shared CL2EX/EX2CL ownership;
- I4 dual-source risk-to-encoder boundary;
- I2/I3/I4 composition compile-smokes;
- I4 parity-testbench compile;
- project governance and Vivado 2022.1 Tcl compatibility.

The remaining evidence is deliberately local because it uses the pinned private submodules and Vivado/XSim implementation stack.

## 9. Non-goals

- editing either pinned upstream;
- changing frozen TMP R01 field packing/checksum behavior;
- full dual-XGMII top replacement in this phase;
- network/PHY candidate migration;
- TAIFEX SPAN;
- CL2EX II=1 optimization;
- board/live-exchange latency claim.

## 10. I4 closure

I4 is complete. Functional byte parity and physical U50 OOC are both closed at their stated evidence layers. PR #3 may be merged after exact-head CI remains green.

## 11. Claim limits

I4 closes the focused order-to-R01 risk boundary only after both corrected local gates pass. Routed OOC timing is not packet latency. XSim byte parity is not board traffic. Full network/PCS-PMA timing and physical end-to-end latency remain later phases.
