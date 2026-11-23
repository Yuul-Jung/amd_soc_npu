#!/usr/bin/env bash
# AXI4-Lite NPU 제어 IP RTL 시뮬레이션(BFM)과 Python 비트 단위 비교.
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
part03=$(cd -- "$chapter_dir/.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/p3-20.XXXXXXXX")
trap 'rm -rf "$build_dir"' EXIT
export PYTHONDONTWRITEBYTECODE=1
python3 --version
iverilog -V 2>&1 | sed -n '1p'
python3 "$chapter_dir/reference/axi_reference.py" --out "$build_dir"
iverilog -g2012 -Wall -s tb_p3_npu_axi_lite -o "$build_dir/sim" \
  "$part03/ch02/rtl/dsp_multiplier.v" "$part03/mini_npu/rtl/npu_dsp_mac_lane.v" \
  "$part03/ch04/rtl/bram_sync_buffer.v" "$part03/ch14/rtl/p3_group10_core.v" \
  "$part03/ch17/rtl/p3_tile784_10.v" "$chapter_dir/rtl/p3_npu_axi_lite.v" \
  -I"$chapter_dir/tb" "$chapter_dir/tb/tb_p3_npu_axi_lite.sv"
vvp "$build_dir/sim" +VECTORS="$build_dir/vectors.txt" +ACTUAL="$build_dir/actual.txt"
python3 "$chapter_dir/reference/axi_reference.py" --out "$build_dir" --actual "$build_dir/actual.txt"
