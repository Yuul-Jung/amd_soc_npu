#!/usr/bin/env bash
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$chapter_dir"
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/p3-01-sim.XXXXXXXX")
# 임시 벡터와 실행 파일은 Git에 올리지 않고 재조사용 경로만 표시한다.
printf 'Simulation artifacts: %s\n' "$build_dir"
python3 --version
iverilog -V 2>&1 | sed -n '1p'
for config in 16:40 8:32; do
    dw=${config%:*}
    aw=${config#*:}
    prefix="$build_dir/int$dw"
    python3 "$chapter_dir/reference/mac_reference.py" --data-width "$dw" --acc-width "$aw" \
        --vectors "$prefix.vec" --expected "$prefix.expected"
    iverilog -g2012 -Wall -s tb_mac_core \
        -Ptb_mac_core.DATA_WIDTH="$dw" -Ptb_mac_core.ACC_WIDTH="$aw" \
        -o "$prefix.vvp" rtl/mac_core.v tb/tb_mac_core.sv
    vvp "$prefix.vvp" +VECTORS="$prefix.vec" +ACTUAL="$prefix.actual"
    python3 "$chapter_dir/reference/mac_reference.py" \
        --expected "$prefix.expected" --actual "$prefix.actual"
done
