# I4 — Frozen-HFT R01 Risk Integration

## 1. Phase identity

- Phase: `I4`
- Status: VERIFYING
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

### I4-02 — Dual frozen-HFT order-source risk boundary

Deliver `hft_rmic_dual_order_source_v1` and `hft_rmic_r01_path_v1`.

Acceptance:

- ordinary bridge order payload traverses risk before encoder;
- R01-prebuild payload traverses the same risk path;
- when both are valid, prebuild retains frozen-HFT priority and legacy is backpressured;
- only `accepted_order_data` drives the frozen encoder;
- a policy/accounting/store reject never creates R01 traffic.

### I4-03 — Functional and byte-parity evidence

CI uses deterministic AMU/encoder contract stubs to close shared ownership and source/handshake semantics. Local Vivado XSim uses the pinned frozen encoder RTL and compares a direct-baseline encoder against the risk-integrated encoder.

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

## 6. Evidence already closed before local sign-off

GitHub CI now contains:

- I3 atomic admission regressions;
- I3 order-gate regressions;
- I4 shared CL2EX/EX2CL ownership regression;
- I4 dual-source risk-to-encoder regression;
- I4 focused composition compile-smoke;
- Vivado 2022.1 Tcl compatibility guard.

The shared-core regression specifically proves a BUY OPEN -> committed full fill -> SELL CLOSE closed loop against one state/store owner and checks execution priority under simultaneous acquisition.

## 7. Non-goals

- editing either pinned upstream;
- changing frozen TMP R01 field packing/checksum behavior;
- full dual-XGMII top replacement in this phase;
- network/PHY candidate migration;
- TAIFEX SPAN;
- CL2EX II=1 optimization;
- board/live-exchange latency claim.

## 8. Claim limits

I4 closes the focused order-to-R01 risk boundary when both local gates pass. Routed OOC timing is not packet latency. XSim byte parity is not board traffic. Full network/PCS-PMA timing and physical end-to-end latency remain later phases.
