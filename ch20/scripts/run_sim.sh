#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export PYTHONDONTWRITEBYTECODE=1
build_dir=$(mktemp -d /tmp/p3-20.XXXXXXXX)
iverilog -V 2>&1 | sed -n 1p
python3 ../ch19/reference/pe_compare.py --out "$build_dir/v.txt"
iverilog -g2012 -Wall -s tb_npu_axi_lite -o "$build_dir/sim" \
  ../ch01/rtl/mac_core.v ../ch04/rtl/bram_sync_buffer.v ../ch07/rtl/vector_dot_core.v ../ch16/rtl/npu_argmax.v \
  ../ch19/rtl/npu_tiled_784_npe.v rtl/npu_axi_lite.v tb/tb_npu_axi_lite.sv
vvp -n "$build_dir/sim" +VECTORS="$build_dir/v.txt" +ACTUAL="$build_dir/a.txt" +NCASES=2
python3 ../ch19/reference/pe_compare.py --npe 4 --actual "$build_dir/a.txt"
