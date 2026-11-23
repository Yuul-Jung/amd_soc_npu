#!/usr/bin/env bash
# 64→8→10 정수 MLP RTL 시뮬레이션과 Python mlp_64_8_10 비트 단위 비교.
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
part03=$(cd -- "$chapter_dir/.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/p3-16.XXXXXXXX")
trap 'rm -rf "$build_dir"' EXIT
export PYTHONDONTWRITEBYTECODE=1
python3 --version
iverilog -V 2>&1 | sed -n '1p'
python3 "$chapter_dir/reference/mlp_reference.py" --out "$build_dir"
iverilog -g2012 -Wall -s tb_p3_mlp_64_8_10 -o "$build_dir/sim" \
  "$part03/ch02/rtl/dsp_multiplier.v" "$part03/mini_npu/rtl/npu_dsp_mac_lane.v" \
  "$part03/ch13/rtl/p3_frame64_buffer.v" "$part03/ch14/rtl/p3_group10_core.v" \
  "$chapter_dir/rtl/p3_relu_requant.v" "$chapter_dir/rtl/p3_mlp_64_8_10.v" \
  "$chapter_dir/tb/tb_p3_mlp_64_8_10.sv"
vvp "$build_dir/sim" +OPS="$build_dir/ops.txt" +ACTUAL="$build_dir/actual.txt"
python3 "$chapter_dir/reference/mlp_reference.py" --out "$build_dir" --actual "$build_dir/actual.txt"
