#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export PYTHONDONTWRITEBYTECODE=1
build_dir=$(mktemp -d /tmp/p3-07.XXXXXXXX)
for config in 16:40 8:32; do
  dw=${config%:*};aw=${config#*:}
  python3 reference/dot_reference.py --dw "$dw" --aw "$aw" --out "$build_dir"
  iverilog -g2012 -Wall -s tb_vector_dot -Ptb_vector_dot.DW="$dw" -Ptb_vector_dot.AW="$aw" \
    -o "$build_dir/sim" ../ch01/rtl/mac_core.v rtl/vector_dot_core.v tb/tb_vector_dot.sv
  vvp "$build_dir/sim" +VECTORS="$build_dir/vectors.txt" +ACTUAL="$build_dir/actual.txt"
  python3 reference/dot_reference.py --out "$build_dir" --actual "$build_dir/actual.txt"
done
