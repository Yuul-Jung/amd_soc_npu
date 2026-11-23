#!/usr/bin/env bash
# 8×8 INT8 프레임 버퍼 RTL 시뮬레이션 + Python 기준모델 비트 단위 비교.
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/p3-13.XXXXXXXX")
trap 'rm -rf "$build_dir"' EXIT
export PYTHONDONTWRITEBYTECODE=1
python3 --version
iverilog -V 2>&1 | sed -n '1p'
python3 "$chapter_dir/reference/frame64_reference.py" --out "$build_dir"
iverilog -g2012 -Wall -s tb_p3_frame64_buffer -o "$build_dir/sim" \
  "$chapter_dir/rtl/p3_frame64_buffer.v" "$chapter_dir/tb/tb_p3_frame64_buffer.sv"
vvp "$build_dir/sim" +STREAM="$build_dir/stream.txt" +ACTUAL="$build_dir/actual.txt"
python3 "$chapter_dir/reference/frame64_reference.py" --out "$build_dir" --actual "$build_dir/actual.txt"
