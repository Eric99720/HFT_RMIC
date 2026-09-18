#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build/iverilog"
mkdir -p "$BUILD"
iverilog -g2012 -I "$ROOT/rtl/include" \
  -o "$BUILD/i5_exec_metadata_tap_v2.vvp" \
  "$ROOT/rtl/adapters/hft_tmp_exec_metadata_tap_v2.sv" \
  "$ROOT/tb/tb_hft_tmp_exec_metadata_tap_v2.sv"
vvp "$BUILD/i5_exec_metadata_tap_v2.vvp"
