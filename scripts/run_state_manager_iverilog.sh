#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build/iverilog"
mkdir -p "$BUILD"

iverilog -g2012 -DHFT_RMIC_BEHAVIORAL_RAM \
  -I "$ROOT/rtl/include" \
  -o "$BUILD/hft_rmic_futures_state_manager_tb.vvp" \
  "$ROOT/rtl/accounting/hft_rmic_state_ram.sv" \
  "$ROOT/rtl/accounting/hft_rmic_futures_accounting_v1.sv" \
  "$ROOT/rtl/accounting/hft_rmic_futures_state_manager_v1.sv" \
  "$ROOT/tb/tb_hft_rmic_futures_state_manager_v1.sv"

vvp "$BUILD/hft_rmic_futures_state_manager_tb.vvp"
