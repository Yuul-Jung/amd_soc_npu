#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export PYTHONDONTWRITEBYTECODE=1
build_dir=$(mktemp -d /tmp/p3-10.XXXXXXXX)
for config in 16:40 8:32; do
  dw=${config%:*};aw=${config#*:}
  python3 reference/npu_reference.py --dw "$dw" --aw "$aw" --out "$build_dir"
  iverilog -g2012 -Wall -s tb_npu_core -Ptb_npu_core.DW="$dw" -Ptb_npu_core.AW="$aw" \
    -o "$build_dir/sim" ../ch01/rtl/mac_core.v ../ch04/rtl/bram_sync_buffer.v \
    ../ch05/rtl/fixed_quantizer.v ../ch07/rtl/vector_dot_core.v ../ch08/rtl/pe_array4.v \
    ../ch09/rtl/dense_layer4.v rtl/npu_core.v tb/tb_npu_core.sv
  vvp "$build_dir/sim" +VECTORS="$build_dir/vectors.txt" +ACTUAL="$build_dir/actual.txt"
  python3 reference/npu_reference.py --out "$build_dir" --actual "$build_dir/actual.txt"
done
