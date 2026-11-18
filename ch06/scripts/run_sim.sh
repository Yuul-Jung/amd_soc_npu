#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export PYTHONDONTWRITEBYTECODE=1
build_dir=$(mktemp -d /tmp/p3-06.XXXXXXXX)
python3 reference/precision_reference.py --out "$build_dir"
iverilog -g2012 -Wall -s tb_precision_compare -o "$build_dir/sim" \
  ../ch05/rtl/fixed_quantizer.v rtl/precision_compare.v tb/tb_precision_compare.sv
vvp "$build_dir/sim" +VECTORS="$build_dir/vectors.txt" +ACTUAL="$build_dir/actual.txt"
python3 reference/precision_reference.py --out "$build_dir" --actual "$build_dir/actual.txt"
if [[ ${1:-} == --save-csv ]]; then cp "$build_dir/comparison.csv" validation/precision_comparison.csv; fi
