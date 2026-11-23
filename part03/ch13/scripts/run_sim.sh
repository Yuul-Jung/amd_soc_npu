#!/usr/bin/env bash
# 8×8 INT8 프레임 버퍼 RTL 시뮬레이션 + Python 기준모델 비트 단위 비교.
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/p3-13.XXXXXXXX")
trap 'rm -rf "$build_dir"' EXIT
export PYTHONDONTWRITEBYTECODE=1
source "$chapter_dir/../common/scripts/p3_sim.sh"   # Vivado 있으면 xsim, 없으면 iverilog (SIM=로 고정)
python3 --version
p3_sim_version
python3 "$chapter_dir/reference/frame64_reference.py" --out "$build_dir"
p3_sim_build "$build_dir" tb_p3_frame64_buffer -- \
  "$chapter_dir/rtl/p3_frame64_buffer.v" "$chapter_dir/tb/tb_p3_frame64_buffer.sv"
p3_sim_run "$build_dir" +STREAM="$build_dir/stream.txt" +ACTUAL="$build_dir/actual.txt"
python3 "$chapter_dir/reference/frame64_reference.py" --out "$build_dir" --actual "$build_dir/actual.txt"
