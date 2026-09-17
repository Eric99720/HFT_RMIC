#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build/iverilog"
mkdir -p "$BUILD"

iverilog -g2012 \
  -DHFT_RMIC_BEHAVIORAL_RAM \
  -I "$ROOT/rtl/include" \
  -s hft_rmic_i2_ooc_top \
  -o "$BUILD/i2_ooc_compile.vvp" \
  "$ROOT/tb/stubs/amu_banked_double_hash_v2_stub.sv" \
  "$ROOT/rtl/integration/hft_rmic_futures_order_store_v1.sv" \
  "$ROOT/rtl/accounting/hft_rmic_futures_transition_v1.sv" \
  "$ROOT/rtl/accounting/hft_rmic_futures_accounting_v1.sv" \
  "$ROOT/rtl/accounting/hft_rmic_state_ram.sv" \
  "$ROOT/rtl/accounting/hft_rmic_futures_state_manager_v1.sv" \
  "$ROOT/rtl/integration/hft_rmic_committed_execution_bridge_v1.sv" \
  "$ROOT/rtl/ooc/hft_rmic_i2_ooc_top.sv"

echo "HFT_RMIC_I2_OOC_COMPILE_PASS"
