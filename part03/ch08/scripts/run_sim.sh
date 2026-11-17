#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export PYTHONDONTWRITEBYTECODE=1
build_dir=$(mktemp -d /tmp/p3-08.XXXXXXXX)
for config in 16:40 8:32; do
  dw=${config%:*};aw=${config#*:}
  python3 reference/pe_reference.py --dw "$dw" --aw "$aw" --out "$build_dir"
  iverilog -g2012 -Wall -s tb_pe_array4 -Ptb_pe_array4.DW="$dw" -Ptb_pe_array4.AW="$aw" \
    -o "$build_dir/sim" ../ch01/rtl/mac_core.v ../ch07/rtl/vector_dot_core.v rtl/pe_array4.v tb/tb_pe_array4.sv
  vvp "$build_dir/sim" +VECTORS="$build_dir/vectors.txt" +ACTUAL="$build_dir/actual.txt"
  python3 reference/pe_reference.py --out "$build_dir" --actual "$build_dir/actual.txt"
done
