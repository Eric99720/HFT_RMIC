#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build/iverilog"
mkdir -p "$BUILD"
iverilog -g2012 -DAMU_BEHAVIORAL_RAM -o "$BUILD/i5_fast_amu.vvp" \
  "$ROOT/deps/RMIC/rtl/amu_bank_ram.sv" \
  "$ROOT/rtl/integration/hft_rmic_amu_banked_double_hash_fast_v1.sv" \
  "$ROOT/tb/tb_hft_rmic_fast_amu_v1.sv"
vvp "$BUILD/i5_fast_amu.vvp"
