#!/usr/bin/env bash
# (추가) 26장: 8×8·3×3 합성곱 RTL 시뮬레이션과 Python 비트 단위 비교.
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
part03=$(cd -- "$chapter_dir/.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/p3-26.XXXXXXXX")
trap 'rm -rf "$build_dir"' EXIT
export PYTHONDONTWRITEBYTECODE=1
python3 --version
iverilog -V 2>&1 | sed -n '1p'
python3 "$chapter_dir/reference/conv_reference.py" --out "$build_dir"
iverilog -g2012 -Wall -s tb_p3_conv3x3_8x8 -o "$build_dir/sim" \
  "$part03/ch02/rtl/dsp_multiplier.v" "$chapter_dir/rtl/p3_conv3x3_8x8.v" "$chapter_dir/tb/tb_p3_conv3x3_8x8.sv"
vvp "$build_dir/sim" +VECTORS="$build_dir/vectors.txt" +ACTUAL="$build_dir/actual.txt"
python3 "$chapter_dir/reference/conv_reference.py" --out "$build_dir" --actual "$build_dir/actual.txt"
