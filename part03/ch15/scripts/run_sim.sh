#!/usr/bin/env bash
# 3-2 코어 재사용 정수 Dense 계층 64→10(분류기)·64→8·8→10 RTL 시뮬레이션과 Python 비교.
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
part03=$(cd -- "$chapter_dir/.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/p3-15.XXXXXXXX")
trap 'rm -rf "$build_dir"' EXIT
export PYTHONDONTWRITEBYTECODE=1
python3 --version
iverilog -V 2>&1 | sed -n '1p'
for shape in 64:10 64:8 8:10; do
  n_in=${shape%:*}; n_out=${shape#*:}
  dir="$build_dir/d${n_in}x${n_out}"; mkdir -p "$dir"
  python3 "$chapter_dir/reference/dense_reference.py" --out "$dir" --in-len "$n_in" --out-n "$n_out"
  iverilog -g2012 -Wall -s tb_p3_dense_layer \
    -Ptb_p3_dense_layer.IN_LEN="$n_in" -Ptb_p3_dense_layer.OUT_N="$n_out" -o "$dir/sim" \
    "$part03/ch02/rtl/dsp_multiplier.v" "$part03/mini_npu/rtl/npu_dsp_mac_lane.v" \
    "$part03/ch13/rtl/p3_frame64_buffer.v" "$part03/ch14/rtl/p3_group10_core.v" \
    "$chapter_dir/tb/tb_p3_dense_layer.sv"
  vvp "$dir/sim" +OPS="$dir/ops.txt" +ACTUAL="$dir/actual.txt"
  python3 "$chapter_dir/reference/dense_reference.py" --out "$dir" --actual "$dir/actual.txt"
done
