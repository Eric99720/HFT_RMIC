#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build/iverilog"
mkdir -p "$BUILD"

# CI deliberately uses an integration test stub for the private RMIC AMU
# dependency.  The wrapper/packing contract is verified here; local Vivado OOC
# later compiles the actual pinned deps/RMIC AMU RTL.
iverilog -g2012 \
  -I "$ROOT/rtl/include" \
  -o "$BUILD/hft_rmic_futures_order_store_tb.vvp" \
  "$ROOT/tb/stubs/amu_banked_double_hash_v2_stub.sv" \
  "$ROOT/rtl/integration/hft_rmic_futures_order_store_v1.sv" \
  "$ROOT/tb/tb_hft_rmic_futures_order_store_v1.sv"

vvp "$BUILD/hft_rmic_futures_order_store_tb.vvp"
