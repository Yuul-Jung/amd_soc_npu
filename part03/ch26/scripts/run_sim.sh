#!/usr/bin/env bash
# 8×8·3×3 합성곱 RTL 시뮬레이션과 Python 비트 단위 비교.
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
part03=$(cd -- "$chapter_dir/.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/p3-26.XXXXXXXX")
trap 'rm -rf "$build_dir"' EXIT
export PYTHONDONTWRITEBYTECODE=1
source "$chapter_dir/../common/scripts/p3_sim.sh"   # Vivado 있으면 xsim, 없으면 iverilog (SIM=로 고정)
python3 --version
p3_sim_version
python3 "$chapter_dir/reference/conv_reference.py" --out "$build_dir"
p3_sim_build "$build_dir" tb_p3_conv3x3_8x8 -- \
  "$part03/ch02/rtl/dsp_multiplier.v" "$chapter_dir/rtl/p3_conv3x3_8x8.v" "$chapter_dir/tb/tb_p3_conv3x3_8x8.sv"
p3_sim_run "$build_dir" +VECTORS="$build_dir/vectors.txt" +ACTUAL="$build_dir/actual.txt"
python3 "$chapter_dir/reference/conv_reference.py" --out "$build_dir" --actual "$build_dir/actual.txt"
