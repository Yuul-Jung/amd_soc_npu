#!/usr/bin/env bash
# 3-2 코어로 만든 PE1·PE4·PE8 구성의 부분합·사이클 RTL 측정과 Python 모델 비교.
# 학습된 4-3 MNIST 모델(INT8)과 고정 표본 4개 × 13타일 = 52개 타일 작업. 데이터셋 불필요.
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
part03=$(cd -- "$chapter_dir/.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/p3-19.XXXXXXXX")
trap 'rm -rf "$build_dir"' EXIT
export PYTHONDONTWRITEBYTECODE=1
source "$chapter_dir/../common/scripts/p3_sim.sh"   # Vivado 있으면 xsim, 없으면 iverilog (SIM=로 고정)
python3 --version
p3_sim_version
python3 "$chapter_dir/reference/arch_reference.py" --out "$build_dir"
p3_sim_build "$build_dir" tb_p3_pe_scale -- \
  "$part03/ch02/rtl/dsp_multiplier.v" "$part03/mini_npu/rtl/npu_dsp_mac_lane.v" \
  "$part03/ch13/rtl/p3_frame64_buffer.v" "$part03/ch14/rtl/p3_group10_core.v" \
  "$chapter_dir/tb/tb_p3_pe_scale.sv"
p3_sim_run "$build_dir" +VECTORS="$build_dir/vectors.txt" +ACTUAL="$build_dir/actual.txt"
python3 "$chapter_dir/reference/arch_reference.py" --out "$build_dir" --actual "$build_dir/actual.txt"
python3 "$chapter_dir/reference/arch_reference.py" --report
