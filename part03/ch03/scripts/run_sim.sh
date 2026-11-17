#!/usr/bin/env bash
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$chapter_dir"
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/p3-03-sim.XXXXXXXX")
export PYTHONDONTWRITEBYTECODE=1
python3 --version
iverilog -V 2>&1 | sed -n '1p'
for config in 16:40 8:32; do
  dw=${config%:*}
  aw=${config#*:}
  prefix="$build_dir/int$dw"
  python3 reference/mac_pipeline_reference.py --data-width "$dw" --acc-width "$aw" \
    --vectors "$prefix.vec" --expected "$prefix.expected" --timing "$prefix.timing.csv"
  iverilog -g2012 -Wall -s tb_mac_pipeline_core \
    -Ptb_mac_pipeline_core.DATA_WIDTH="$dw" -Ptb_mac_pipeline_core.ACC_WIDTH="$aw" \
    -o "$prefix.vvp" rtl/mac_pipeline_core.v tb/tb_mac_pipeline_core.sv
  vvp "$prefix.vvp" +VECTORS="$prefix.vec" +ACTUAL="$prefix.actual"
  python3 reference/mac_pipeline_reference.py --expected "$prefix.expected" --actual "$prefix.actual"
  printf 'TIMING_TRACE INT%s/%s (first 28 edges, Python model matched to RTL)\n' "$dw" "$aw"
  sed -n '1,29p' "$prefix.timing.csv"
done
