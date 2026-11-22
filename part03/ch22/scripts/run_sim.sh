#!/usr/bin/env bash
# (추가) 22장: C 드라이버 PC 협동 시뮬레이션. gcc로 드라이버·응용을 PC용으로 빌드하고 FIFO로 Icarus RTL과 연결한다.
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
part03=$(cd -- "$chapter_dir/.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/p3-22.XXXXXXXX")
trap 'rm -rf "$build_dir"' EXIT
export PYTHONDONTWRITEBYTECODE=1
python3 --version
gcc --version | sed -n '1p'
iverilog -V 2>&1 | sed -n '1p'
python3 "$chapter_dir/reference/gen_model.py" --out "$build_dir/model_data.h"
gcc -std=c99 -O2 -Wall -Wextra -Werror -DNPU_HOST_SIM -I"$chapter_dir/sw" -I"$build_dir" -o "$build_dir/cosim" \
  "$chapter_dir/sw/npu_driver.c" "$chapter_dir/sw/app.c" \
  "$chapter_dir/host/npu_io_cosim.c" "$chapter_dir/host/cosim_main.c"
iverilog -g2012 -Wall -s tb_p3_npu_bridge -o "$build_dir/sim" -I"$part03/ch20/tb" \
  "$part03/ch02/rtl/dsp_multiplier.v" "$part03/mini_npu/rtl/npu_dsp_mac_lane.v" \
  "$part03/ch04/rtl/bram_sync_buffer.v" "$part03/ch14/rtl/p3_group10_core.v" \
  "$part03/ch17/rtl/p3_tile784_10.v" "$part03/ch20/rtl/p3_npu_axi_lite.v" \
  "$chapter_dir/tb/tb_p3_npu_bridge.sv"
mkfifo "$build_dir/cmd" "$build_dir/rsp"
vvp "$build_dir/sim" +CMD="$build_dir/cmd" +RSP="$build_dir/rsp" > "$build_dir/sim.log" 2>&1 &
sim_pid=$!
host_rc=0
"$build_dir/cosim" "$build_dir/cmd" "$build_dir/rsp" || host_rc=$?
sim_rc=0
wait "$sim_pid" || sim_rc=$?
grep -v "finish called" "$build_dir/sim.log"
if [[ $host_rc -ne 0 || $sim_rc -ne 0 ]] || ! grep -q RTL_SIM_PASS "$build_dir/sim.log"; then
  echo "COSIM_FAIL host_rc=$host_rc sim_rc=$sim_rc"
  exit 1
fi
echo "PYTHON_RTL_COMPARE_PASS c_driver_cosim npu=cpu=python_scores class_match=1"
