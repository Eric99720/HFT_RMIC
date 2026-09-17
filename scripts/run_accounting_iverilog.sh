#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build/iverilog"
mkdir -p "$BUILD"

iverilog -g2012 \
  -I "$ROOT/rtl/include" \
  -o "$BUILD/hft_rmic_futures_accounting_v1_tb.vvp" \
  "$ROOT/rtl/accounting/hft_rmic_futures_accounting_v1.sv" \
  "$ROOT/tb/tb_hft_rmic_futures_accounting_v1.sv"

vvp "$BUILD/hft_rmic_futures_accounting_v1_tb.vvp"
