#!/usr/bin/env bash
# 64→8→10 정수 MLP RTL 시뮬레이션과 Python mlp_64_8_10 비트 단위 비교.
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
part03=$(cd -- "$chapter_dir/.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/p3-16.XXXXXXXX")
trap 'rm -rf "$build_dir"' EXIT
export PYTHONDONTWRITEBYTECODE=1
source "$chapter_dir/../common/scripts/p3_sim.sh"   # Vivado 있으면 xsim, 없으면 iverilog (SIM=로 고정)
python3 --version
p3_sim_version
python3 "$chapter_dir/reference/mlp_reference.py" --out "$build_dir"
p3_sim_build "$build_dir" tb_p3_mlp_64_8_10 -- \
  "$part03/ch02/rtl/dsp_multiplier.v" "$part03/mini_npu/rtl/npu_dsp_mac_lane.v" \
  "$part03/ch13/rtl/p3_frame64_buffer.v" "$part03/ch14/rtl/p3_group10_core.v" \
  "$chapter_dir/rtl/p3_relu_requant.v" "$chapter_dir/rtl/p3_mlp_64_8_10.v" \
  "$chapter_dir/tb/tb_p3_mlp_64_8_10.sv"
p3_sim_run "$build_dir" +OPS="$build_dir/ops.txt" +ACTUAL="$build_dir/actual.txt"
python3 "$chapter_dir/reference/mlp_reference.py" --out "$build_dir" --actual "$build_dir/actual.txt"
