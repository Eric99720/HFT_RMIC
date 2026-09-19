#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build/iverilog"
mkdir -p "$BUILD"
iverilog -g2012 -I "$ROOT/rtl/include" -o "$BUILD/i5_prospective_cl_issue.vvp" \
  "$ROOT/rtl/integration/hft_rmic_cl2ex_parallel_admission_v1.sv" \
  "$ROOT/tb/tb_hft_rmic_prospective_cl_issue_v1.sv"
vvp "$BUILD/i5_prospective_cl_issue.vvp"
