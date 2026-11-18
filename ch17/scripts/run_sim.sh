#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export PYTHONDONTWRITEBYTECODE=1
build_dir=$(mktemp -d /tmp/p3-17.XXXXXXXX)
iverilog -V 2>&1 | sed -n 1p
python3 reference/tiled_reference.py --out "$build_dir"
iverilog -g2012 -Wall -s tb_npu_tiled_784 -o "$build_dir/sim" \
  ../ch01/rtl/mac_core.v ../ch04/rtl/bram_sync_buffer.v ../ch07/rtl/vector_dot_core.v ../ch08/rtl/pe_array4.v \
  ../ch15/rtl/npu_dense_core.v ../ch16/rtl/npu_argmax.v rtl/npu_tiled_784.v tb/tb_npu_tiled_784.sv
vvp -n "$build_dir/sim" +VECTORS="$build_dir/vectors.txt" +ACTUAL="$build_dir/actual.txt"
python3 reference/tiled_reference.py --actual "$build_dir/actual.txt"
