#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build/iverilog"
mkdir -p "$BUILD"
iverilog -g2012 -I "$ROOT/rtl/include" -o "$BUILD/i5_fast_success_join.vvp" \
  "$ROOT/rtl/integration/hft_rmic_cl2ex_parallel_admission_v1.sv" \
  "$ROOT/tb/tb_hft_rmic_fast_success_join_v1.sv"
vvp "$BUILD/i5_fast_success_join.vvp"
