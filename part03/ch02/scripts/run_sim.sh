#!/usr/bin/env bash
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$chapter_dir"
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/p3-02-sim.XXXXXXXX")
python3 --version
iverilog -V 2>&1 | sed -n '1p'
export PYTHONDONTWRITEBYTECODE=1
for config in 16:16:40 8:8:32 25:18:56; do
  IFS=: read -r a_width b_width acc_width <<< "$config"
  prefix="$build_dir/a${a_width}_b${b_width}"
  python3 reference/dsp_reference.py --a-width "$a_width" --b-width "$b_width" \
    --acc-width "$acc_width" --vectors "$prefix.vec" --expected "$prefix.expected"
  iverilog -g2012 -Wall -s tb_dsp_multiplier \
    -Ptb_dsp_multiplier.A_WIDTH="$a_width" -Ptb_dsp_multiplier.B_WIDTH="$b_width" \
    -Ptb_dsp_multiplier.ACC_WIDTH="$acc_width" -o "$prefix.vvp" \
    rtl/dsp_multiplier.v ../ch01/rtl/mac_core.v tb/tb_dsp_multiplier.sv
  vvp "$prefix.vvp" +VECTORS="$prefix.vec" +ACTUAL="$prefix.actual"
  python3 reference/dsp_reference.py --a-width "$a_width" --b-width "$b_width" \
    --acc-width "$acc_width" --expected "$prefix.expected" --actual "$prefix.actual"
done
