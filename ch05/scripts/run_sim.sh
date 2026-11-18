#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export PYTHONDONTWRITEBYTECODE=1
build_dir=$(mktemp -d /tmp/p3-05.XXXXXXXX)
for config in 32:8:8 32:16:4 16:8:0; do
  IFS=: read -r iw ow s <<< "$config"
  python3 reference/fixed_reference.py --in-width "$iw" --out-width "$ow" --shift "$s" --out "$build_dir"
  iverilog -g2012 -Wall -s tb_fixed_quantizer -Ptb_fixed_quantizer.IW="$iw" -Ptb_fixed_quantizer.OW="$ow" \
    -Ptb_fixed_quantizer.S="$s" -o "$build_dir/sim" rtl/fixed_quantizer.v tb/tb_fixed_quantizer.sv
  vvp "$build_dir/sim" +VECTORS="$build_dir/vectors.txt" +ACTUAL="$build_dir/actual.txt"
  python3 reference/fixed_reference.py --out "$build_dir" --actual "$build_dir/actual.txt"
done
