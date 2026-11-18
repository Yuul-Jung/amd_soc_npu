#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export PYTHONDONTWRITEBYTECODE=1
build_dir=$(mktemp -d /tmp/p3-14.XXXXXXXX)
iverilog -V 2>&1 | sed -n 1p
python3 reference/group10_reference.py --out "$build_dir"
iverilog -g2012 -Wall -s tb_npu10_group_scheduler -o "$build_dir/sim" \
  ../ch01/rtl/mac_core.v ../ch04/rtl/bram_sync_buffer.v ../ch07/rtl/vector_dot_core.v \
  ../ch08/rtl/pe_array4.v ../ch13/rtl/npu10_input_loader.v \
  rtl/npu10_group_scheduler.v tb/tb_npu10_group_scheduler.sv
vvp -n "$build_dir/sim" +VECTORS="$build_dir/vectors.txt" +ACTUAL="$build_dir/actual.txt"
python3 reference/group10_reference.py --actual "$build_dir/actual.txt"
