#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build/iverilog"
mkdir -p "$BUILD"
iverilog -g2012 -o "$BUILD/i5_exec_commit_fifo.vvp" "$ROOT/rtl/integration/hft_rmic_exec_commit_fifo_v1.sv" "$ROOT/tb/tb_hft_rmic_exec_commit_fifo_v1.sv"
vvp "$BUILD/i5_exec_commit_fifo.vvp"
