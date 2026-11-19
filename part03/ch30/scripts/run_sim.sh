#!/usr/bin/env bash
# (추가) 30장: NPU 추천 + 독립 모터 안전 코어 PC 검증.
#   1) 기준모델 자체 시험 + 코어 클록 벡터(지정 + 무작위 운전, Python에서 안전 불변식 확인)
#   2) p3_motor_safety RTL = Python(클록마다 IN1·IN2·ENA·상태 32비트), RTL 변이 7종
#   3) 종단간 협동 시뮬레이션: 호스트(가상 센서·주입) → C 펌웨어(29장 guard·정책 재사용) → NPU RTL + 모터 코어 RTL,
#      브리지 TB가 모든 클록에서 핀 안전 불변식을 센다
#   4) 펌웨어 변이 6종이 모두 FAIL이어야 한다
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
part03=$(cd -- "$chapter_dir/.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/p3-30.XXXXXXXX")
trap 'rm -rf "$build_dir"' EXIT
export PYTHONDONTWRITEBYTECODE=1
python3 --version
gcc --version | sed -n '1p'
iverilog -V 2>&1 | sed -n '1p'
python3 "$chapter_dir/reference/motor_reference.py" --selftest --unit-vectors "$build_dir/unit.txt"
python3 "$part03/ch29/reference/sensor_reference.py" --header "$build_dir/sensor_model.h"

unit_run() {   # $1 = RTL 소스
  iverilog -g2012 -Wall -s tb_p3_motor_safety -o "$build_dir/unit" "$1" "$chapter_dir/tb/tb_p3_motor_safety.sv"
  vvp -n "$build_dir/unit" +VEC="$build_dir/unit.txt" | grep -v "finish called"
}
unit_run "$chapter_dir/rtl/p3_motor_safety.v" | tee "$build_dir/unit.log"
grep -q RTL_SIM_PASS "$build_dir/unit.log"
python3 - "$chapter_dir/rtl/p3_motor_safety.v" "$build_dir" <<'PY'
import sys
from pathlib import Path
src, out = Path(sys.argv[1]).read_text(), Path(sys.argv[2])
mutants = {
    "estop_not_combinational": ("wire       hard  = estop | fault | otemp | wd_exp | trip;",
                                "wire       hard  = fault | otemp | wd_exp | trip;"),
    "no_reset_latch": ("latched <= 5'b10000;", "latched <= 5'b00000;"),
    "no_dead_time": ("dead_cnt  <= DEAD_CYC;", "dead_cnt  <= 32'd0;"),
    "no_ramp": ("duty_cur <= duty_cur + 7'd1;", "duty_cur <= req_duty;"),
    "clear_while_running": ("else if (clr_ev && req_dir == STOP)", "else if (clr_ev)"),
    "limit_wrong_dir": ("(drive_dir == FWD && lim_f) || (drive_dir == REV && lim_r)",
                        "(drive_dir == FWD && lim_r) || (drive_dir == REV && lim_f)"),
    "watchdog_stuck": ("wd_cnt <= wd_cnt - 32'd1;", "wd_cnt <= wd_cnt;"),
}
for name, (a, b) in mutants.items():
    assert src.count(a) == 1, name
    (out / f"rtlmut_{name}.v").write_text(src.replace(a, b))
print("RTL_MUTANTS " + " ".join(mutants))
PY
rk=0; rt=0
for m in "$build_dir"/rtlmut_*.v; do
  rt=$((rt + 1)); n=$(basename "$m" .v)
  if unit_run "$m" | grep -q RTL_SIM_PASS; then echo "RTL_MUTANT ${n#rtlmut_} SURVIVED"; else rk=$((rk + 1)); echo "RTL_MUTANT ${n#rtlmut_} KILLED"; fi
done
echo "RTL_MUTATION_SUMMARY killed=$rk total=$rt"
[[ $rk -eq $rt ]]

# 3) 협동 시뮬레이션
iverilog -g2012 -Wall -s tb_p3_motor_bridge -o "$build_dir/sim" -I"$part03/ch20/tb" \
  "$part03/ch02/rtl/dsp_multiplier.v" "$part03/mini_npu/rtl/npu_dsp_mac_lane.v" \
  "$part03/ch04/rtl/bram_sync_buffer.v" "$part03/ch14/rtl/p3_group10_core.v" \
  "$part03/ch17/rtl/p3_tile784_10.v" "$part03/ch20/rtl/p3_npu_axi_lite.v" \
  "$chapter_dir/rtl/p3_motor_safety.v" "$chapter_dir/tb/tb_p3_motor_bridge.sv"
run_cosim() {   # $1 = 펌웨어 소스, $2 = 이름, 나머지 = 호스트 인자
  local app=$1 name=$2; shift 2
  local d="$build_dir/$name" werr=-Werror
  [[ $name == mut_* ]] && werr=-Wno-error
  mkdir -p "$d"
  gcc -std=c99 -D_DEFAULT_SOURCE -O2 -Wall -Wextra $werr -DNPU_HOST_SIM \
    -I"$part03/ch22/sw" -I"$part03/ch29/sw" -I"$chapter_dir/sw" -I"$build_dir" -o "$d/fw" \
    "$part03/ch22/sw/npu_driver.c" "$part03/ch29/sw/sensor_app.c" "$app" \
    "$part03/ch22/host/npu_io_cosim.c" "$part03/ch29/host/sensor_io_host.c" "$chapter_dir/host/motor_cosim_main.c"
  mkfifo "$d/cmd" "$d/rsp"
  vvp "$build_dir/sim" +CMD="$d/cmd" +RSP="$d/rsp" > "$d/sim.log" 2>&1 &
  local sim_pid=$! host_rc=0 sim_rc=0
  python3 "$chapter_dir/host/p3_motor_host.py" --cosim "$d/fw $d/cmd $d/rsp" "$@" > "$d/host.log" 2>&1 || host_rc=$?
  wait "$sim_pid" || sim_rc=$?
  COSIM_HOST_RC=$host_rc
  COSIM_SIM_RC=$sim_rc
}
run_cosim "$chapter_dir/sw/motor_app.c" golden \
  --csv "$chapter_dir/validation/rtl_cosim.csv" --log "$chapter_dir/validation/rtl_cosim_uart.log"
grep -vE "^STEP .* PASS" "$build_dir/golden/host.log" || true
echo "STEPS_PASS $(grep -cE '^STEP .* PASS' "$build_dir/golden/host.log")"
grep -v "finish called" "$build_dir/golden/sim.log"
if [[ $COSIM_HOST_RC -ne 0 || $COSIM_SIM_RC -ne 0 ]] || ! grep -q "RTL_SIM_PASS MOTOR_BRIDGE" "$build_dir/golden/sim.log"; then
  echo "MOTOR_COSIM_FAIL host_rc=$COSIM_HOST_RC sim_rc=$COSIM_SIM_RC"
  exit 1
fi

# 4) 펌웨어 변이
python3 - "$chapter_dir/sw/motor_app.c" "$build_dir" <<'PY'
import sys
from pathlib import Path
src, out = Path(sys.argv[1]).read_text(), Path(sys.argv[2])
mutants = {
    "ignore_policy": ("    if (state == ST_NORMAL || state == ST_WARNING) {", "    if (1) {"),
    "warning_full_speed": ("*duty = state == ST_NORMAL ? 80 : 30;", "*duty = 80;"),
    "clear_without_stop": ("        rec_dir = M_STOP;\n        rec_duty = 0;\n        motor_write();\n", ""),
    "no_kick": ("    kick ^= 1;\n    npu_io_write", "    npu_io_write"),
    "ignore_operator_dir": ("        op_dir = rx_buf[0];\n", ""),
    "display_duty": ("| MST_DUTY(st) |", "| (uint32_t)rec_duty |"),
}
for name, (a, b) in mutants.items():
    assert src.count(a) == 1, f"mutation pattern not unique: {name}"
    (out / f"mut_{name}.c").write_text(src.replace(a, b))
print("MUTANTS " + " ".join(mutants))
PY
killed=0; total=0
for src in "$build_dir"/mut_*.c; do
  name=$(basename "$src" .c)
  total=$((total + 1))
  run_cosim "$src" "$name" --csv "$build_dir/$name.csv" --log "$build_dir/$name.log"
  if [[ $COSIM_HOST_RC -ne 0 ]]; then
    killed=$((killed + 1))
    echo "MUTANT ${name#mut_} KILLED ($(grep -m1 -E '^STEP .* FAIL|MOTOR_HOST_FAIL|Traceback' "$build_dir/$name/host.log" | cut -c1-110))"
  else
    echo "MUTANT ${name#mut_} SURVIVED"
  fi
done
echo "MUTATION_SUMMARY killed=$killed total=$total"
[[ $total -gt 0 && $killed -eq $total ]]
echo "PYTHON_RTL_COMPARE_PASS ch30 motor_safety_rtl=reference(cycle) host->fw(ch29 policy)->npu_rtl+motor_rtl invariants=0"
