#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build/iverilog"
mkdir -p "$BUILD"
iverilog -g2012 -o "$BUILD/i5_order_ingress_slice_v1.vvp" \
  "$ROOT/rtl/integration/hft_rmic_order_ingress_slice_v1.v" \
  "$ROOT/tb/tb_hft_rmic_order_ingress_slice_v1.sv"
vvp "$BUILD/i5_order_ingress_slice_v1.vvp"
