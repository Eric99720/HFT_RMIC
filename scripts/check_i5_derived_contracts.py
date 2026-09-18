#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
pin = "50217fad1fd580f8c451ba893f9035f4be1dc21a"
errors = []

checks = {
    "rtl/integration/hft_rmic_rx_order_book_top_v1.sv": [
        pin,
        "module hft_rmic_rx_order_book_top_v1",
        "hft_tmp_exec_metadata_tap_v2 u_i5_live_exec_meta",
        "hft_tmp_exec_metadata_tap_v2 u_i5_replay_exec_meta",
        "hft_rmic_committed_exec_event_adapter_v1",
        "hft_report_sequence_owner",
    ],
    "rtl/integration/hft_rmic_round_chip_app_top_v1.sv": [
        pin,
        "module hft_rmic_round_chip_app_top_v1",
        "hft_rmic_rx_order_book_top_v1",
        "hft_rmic_dual_order_source_v1",
        "hft_rmic_exec_commit_fifo_v1",
        "hft_rmic_shared_core_v1",
        "financial_protocol_encoder_session_top",
    ],
    "rtl/integration/hft_rmic_xgmii_network_layer_e2e_top_v1.sv": [
        pin,
        "module hft_rmic_xgmii_network_layer_e2e_top_v1",
        "hft_rmic_round_chip_app_top_v1",
    ],
    "rtl/integration/hft_rmic_dual_xgmii_full_system_top_v1.sv": [
        pin,
        "module hft_rmic_dual_xgmii_full_system_top_v1",
        "hft_rmic_xgmii_network_layer_e2e_top_v1",
        "hft_market_transaction_cdc",
    ],
}

for rel, required in checks.items():
    path = root / rel
    if not path.exists():
        errors.append(f"missing derived source: {rel}")
        continue
    text = path.read_text(encoding="utf-8")
    for token in required:
        if token not in text:
            errors.append(f"{rel}: missing required provenance/ownership token: {token}")

# Explicit bypass guards at each derived hierarchy layer.
app = (root / "rtl/integration/hft_rmic_round_chip_app_top_v1.sv").read_text(encoding="utf-8")
if ".strategy_order_valid(ENABLE_R01_PREBUILD ? prebuild_direct_valid : bridge_strategy_order_valid)" in app:
    errors.append("I5 app still contains frozen direct strategy->encoder bypass")
if ".strategy_order_valid(risk_accepted_valid)" not in app:
    errors.append("I5 app does not drive frozen session encoder from risk accepted stream")
if ".encoder_strategy_order_ready(risk_legacy_ready)" not in app:
    errors.append("I5 ordinary bridge is not backpressured by risk admission")
if "wire prebuild_direct_accept = risk_prebuild_accept;" not in app:
    errors.append("I5 prebuild acceptance is not owned by the risk boundary")
if "risk_exec_queue_overflow" not in app or "execq_overflow_sticky" not in app:
    errors.append("I5 app lacks fail-closed committed-execution FIFO overflow path")

net = (root / "rtl/integration/hft_rmic_xgmii_network_layer_e2e_top_v1.sv").read_text(encoding="utf-8")
if "hft_round_chip_app_top #(" in net:
    errors.append("I5 trading-port top instantiates frozen app directly instead of risk-aware app")
if "module hft_axis_reverse_byte_order_64_e2e (" in net:
    errors.append("I5 trading-port derivative redefines frozen byte-order helper module name")
if "module hft_rmic_axis_reverse_byte_order_64_e2e_v1 (" not in net:
    errors.append("I5 trading-port derivative lacks namespaced byte-order helper")

if ".cfg_position_effect(8'h4f)" in net:
    errors.append("I5 trading-port top still hard-codes PositionEffect OPEN")
if ".cfg_position_effect(cfg_position_effect)" not in net:
    errors.append("I5 trading-port top does not propagate configurable PositionEffect")
if "input  wire [7:0]             cfg_position_effect" not in net:
    errors.append("I5 trading-port top lacks PositionEffect host input")

dual = (root / "rtl/integration/hft_rmic_dual_xgmii_full_system_top_v1.sv").read_text(encoding="utf-8")
if "hft_xgmii_network_layer_e2e_top #(" in dual:
    errors.append("I5 dual-XGMII top instantiates frozen trading core directly instead of risk-aware core")

if ".cfg_position_effect(cfg_position_effect)" not in dual:
    errors.append("I5 dual-XGMII top does not propagate PositionEffect to trading core")
if "input  wire [7:0]             cfg_position_effect" not in dual:
    errors.append("I5 dual-XGMII top lacks PositionEffect host input")

if errors:
    print("I5_DERIVED_CONTRACT_CHECK_FAIL")
    for e in errors:
        print(e)
    raise SystemExit(1)

print("I5_DERIVED_CONTRACT_CHECK_PASS")
