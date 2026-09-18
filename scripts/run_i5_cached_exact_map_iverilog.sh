#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build/iverilog"
mkdir -p "$BUILD"
iverilog -g2012 -I "$ROOT/rtl/include" -o "$BUILD/i5_cached_exact_map_v1.vvp" \
  "$ROOT/rtl/adapters/configurable_exact_map.sv" \
  "$ROOT/rtl/integration/hft_rmic_cached_exact_map_v1.v" \
  "$ROOT/tb/tb_hft_rmic_cached_exact_map_v1.sv"
vvp "$BUILD/i5_cached_exact_map_v1.vvp"
