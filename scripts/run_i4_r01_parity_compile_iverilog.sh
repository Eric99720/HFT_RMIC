#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mkdir -p build/iverilog
iverilog -g2012 -I rtl/include \
  -s tb_hft_rmic_i4_r01_byte_parity \
  -o build/iverilog/i4_r01_parity_compile.vvp \
  tb/stubs/amu_banked_double_hash_v2_stub.sv \
  tb/stubs/financial_protocol_encoder_stub.sv \
  rtl/adapters/configurable_exact_map.sv \
  rtl/adapters/hft_order_to_rmic.sv \
  rtl/policy/hft_rmic_policy_gate.sv \
  rtl/accounting/hft_rmic_futures_transition_v1.sv \
  rtl/accounting/hft_rmic_state_ram.sv \
  rtl/accounting/hft_rmic_futures_state_manager_v1.sv \
  rtl/integration/hft_rmic_futures_order_store_v1.sv \
  rtl/integration/hft_rmic_cl2ex_admission_v1.sv \
  rtl/integration/hft_rmic_order_gate_v1.sv \
  rtl/integration/hft_rmic_committed_execution_bridge_v1.sv \
  rtl/integration/hft_rmic_shared_core_v1.sv \
  rtl/integration/hft_rmic_dual_order_source_v1.sv \
  rtl/integration/hft_rmic_r01_path_v1.sv \
  tb/tb_hft_rmic_i4_r01_byte_parity.sv
printf '%s\n' 'HFT_RMIC_I4_R01_PARITY_COMPILE_PASS'
