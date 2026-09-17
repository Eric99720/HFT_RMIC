#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build/iverilog"
mkdir -p "$BUILD"

iverilog -g2012 \
  -I "$ROOT/rtl/include" \
  -o "$BUILD/hft_order_to_rmic_tb.vvp" \
  "$ROOT/rtl/adapters/configurable_exact_map.sv" \
  "$ROOT/rtl/adapters/hft_order_to_rmic.sv" \
  "$ROOT/tb/tb_hft_order_to_rmic.sv"

vvp "$BUILD/hft_order_to_rmic_tb.vvp"
