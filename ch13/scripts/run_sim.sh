#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export PYTHONDONTWRITEBYTECODE=1
build_dir=$(mktemp -d /tmp/p3-13.XXXXXXXX)
iverilog -V 2>&1 | sed -n 1p
python3 reference/mnist8x8_reference.py --out "$build_dir" --show 7
iverilog -g2012 -Wall -s tb_npu10_input_loader -o "$build_dir/sim" \
  ../ch04/rtl/bram_sync_buffer.v rtl/npu10_input_loader.v tb/tb_npu10_input_loader.sv
vvp -n "$build_dir/sim" +VECTORS="$build_dir/vectors.txt" +ACTUAL="$build_dir/actual.txt"
python3 reference/mnist8x8_reference.py --actual "$build_dir/actual.txt"
