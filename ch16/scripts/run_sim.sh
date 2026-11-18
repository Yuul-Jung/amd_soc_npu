#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export PYTHONDONTWRITEBYTECODE=1
build_dir=$(mktemp -d /tmp/p3-16.XXXXXXXX)
iverilog -V 2>&1 | sed -n 1p
python3 reference/mlp_reference.py --out "$build_dir"
iverilog -g2012 -Wall -s tb_npu_mlp -o "$build_dir/sim" \
  ../ch01/rtl/mac_core.v ../ch04/rtl/bram_sync_buffer.v ../ch05/rtl/fixed_quantizer.v ../ch07/rtl/vector_dot_core.v \
  ../ch08/rtl/pe_array4.v ../ch15/rtl/npu_dense_core.v ../ch15/rtl/npu_dense_store.v ../ch15/rtl/npu_dense.v \
  rtl/npu_argmax.v rtl/npu_mlp_64_8_10.v tb/tb_npu_mlp.sv
vvp -n "$build_dir/sim" +VECTORS="$build_dir/vectors.txt" +ACTUAL="$build_dir/actual.txt"
python3 reference/mlp_reference.py --actual "$build_dir/actual.txt"
