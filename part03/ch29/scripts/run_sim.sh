#!/usr/bin/env bash
# 센서 융합 상태 감시 PC 검증.
#   1) 기준모델 자체 시험 + 합성 데이터 정확도(float·INT8, 훈련·시험셋)
#   2) 경보 정책 RTL(p3_alarm_policy) = Python 정책, 클록 단위 벡터 + RTL 변이 4종
#   3) 종단간 PC 시뮬레이션: Python 호스트(가상 센서·고장 주입) → 표준 입출력 → 보드와 같은 C 펌웨어
#      → 5-3 FIFO 브리지 → 5-1 AXI NPU RTL. 시나리오 + 시험셋 60창 + 오류 시험
#   4) 펌웨어 변이 12종이 모두 호스트 판정에서 FAIL이어야 한다
#   결과: validation/rtl_cosim.csv, validation/rtl_cosim_uart.log (+ 표준 출력 → validation/rtl_sim.log)
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
part03=$(cd -- "$chapter_dir/.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/p3-29.XXXXXXXX")
trap 'rm -rf "$build_dir"' EXIT
export PYTHONDONTWRITEBYTECODE=1
python3 --version
gcc --version | sed -n '1p'
iverilog -V 2>&1 | sed -n '1p'
ref="$chapter_dir/reference/sensor_reference.py"
python3 "$ref" --selftest --eval --header "$build_dir/sensor_model.h" --policy-vectors "$build_dir/policy.txt"

# 2) 경보 정책 RTL
pol_run() {   # $1 = RTL 소스
  iverilog -g2012 -Wall -s tb_p3_alarm_policy -o "$build_dir/pol" "$1" "$chapter_dir/tb/tb_p3_alarm_policy.sv"
  vvp -n "$build_dir/pol" +VEC="$build_dir/policy.txt" | grep -v "finish called"
}
pol_run "$chapter_dir/rtl/p3_alarm_policy.v" | tee "$build_dir/pol.log"
grep -q RTL_SIM_PASS "$build_dir/pol.log"
python3 - "$chapter_dir/rtl/p3_alarm_policy.v" "$build_dir" <<'PY'
import sys
from pathlib import Path
src, out = Path(sys.argv[1]).read_text(), Path(sys.argv[2])
mutants = {
    "reset_normal": ("            state  <= UNKNOWN;", "            state  <= NORMAL;"),
    "no_latch": ("                        latch <= 1'b1;", "                        latch <= 1'b0;"),
    "ack_with_cand": ("            end else if (ack && latch) begin", "            end if (ack && latch) begin"),
    "hold_min": ("(cnt == 2'd0 || s_cand > hold)", "(cnt == 2'd0 || s_cand < hold)"),
}
for name, (a, b) in mutants.items():
    assert src.count(a) == 1, name
    (out / f"rtlmut_{name}.v").write_text(src.replace(a, b))
print("RTL_MUTANTS " + " ".join(mutants))
PY
rk=0; rt=0
for m in "$build_dir"/rtlmut_*.v; do
  rt=$((rt + 1)); n=$(basename "$m" .v)
  if pol_run "$m" | grep -q RTL_SIM_PASS; then echo "RTL_MUTANT ${n#rtlmut_} SURVIVED"; else rk=$((rk + 1)); echo "RTL_MUTANT ${n#rtlmut_} KILLED"; fi
done
echo "RTL_MUTATION_SUMMARY killed=$rk total=$rt"
[[ $rk -eq $rt ]]

# 3) PC 시뮬레이션
iverilog -g2012 -Wall -s tb_p3_npu_bridge -o "$build_dir/sim" -I"$part03/ch20/tb" \
  "$part03/ch02/rtl/dsp_multiplier.v" "$part03/mini_npu/rtl/npu_dsp_mac_lane.v" \
  "$part03/ch04/rtl/bram_sync_buffer.v" "$part03/ch14/rtl/p3_group10_core.v" \
  "$part03/ch17/rtl/p3_tile784_10.v" "$part03/ch20/rtl/p3_npu_axi_lite.v" \
  "$part03/ch22/tb/tb_p3_npu_bridge.sv"
run_cosim() {   # $1 = 펌웨어 소스, $2 = 이름, 나머지 = 호스트 인자
  local app=$1 name=$2; shift 2
  local d="$build_dir/$name" werr=-Werror
  [[ $name == mut_* ]] && werr=-Wno-error
  mkdir -p "$d"
  gcc -std=c99 -D_DEFAULT_SOURCE -O2 -Wall -Wextra $werr -DNPU_HOST_SIM \
    -I"$part03/ch22/sw" -I"$chapter_dir/sw" -I"$build_dir" -o "$d/fw" \
    "$part03/ch22/sw/npu_driver.c" "$app" \
    "$part03/ch22/host/npu_io_cosim.c" "$chapter_dir/host/sensor_io_host.c" "$chapter_dir/host/sensor_cosim_main.c"
  mkfifo "$d/cmd" "$d/rsp"
  vvp "$build_dir/sim" +CMD="$d/cmd" +RSP="$d/rsp" > "$d/sim.log" 2>&1 &
  local sim_pid=$! host_rc=0 sim_rc=0
  python3 "$chapter_dir/host/p3_sensor_host.py" --cosim "$d/fw $d/cmd $d/rsp" "$@" > "$d/host.log" 2>&1 || host_rc=$?
  wait "$sim_pid" || sim_rc=$?
  COSIM_HOST_RC=$host_rc
  COSIM_SIM_RC=$sim_rc
}
run_cosim "$chapter_dir/sw/sensor_app.c" golden \
  --csv "$chapter_dir/validation/rtl_cosim.csv" --log "$chapter_dir/validation/rtl_cosim_uart.log"
grep -vE "^STEP .* PASS" "$build_dir/golden/host.log" || true
echo "STEPS_PASS $(grep -cE '^STEP .* PASS' "$build_dir/golden/host.log")"
grep -v "finish called" "$build_dir/golden/sim.log"
if [[ $COSIM_HOST_RC -ne 0 || $COSIM_SIM_RC -ne 0 ]] || ! grep -q RTL_SIM_PASS "$build_dir/golden/sim.log"; then
  echo "SENSOR_COSIM_FAIL host_rc=$COSIM_HOST_RC sim_rc=$COSIM_SIM_RC"
  exit 1
fi

# 4) 펌웨어 변이(시나리오 + 오류 시험 + 시험셋 10창)
python3 - "$chapter_dir/sw/sensor_app.c" "$build_dir" <<'PY'
import sys
from pathlib import Path
src, out = Path(sys.argv[1]).read_text(), Path(sys.argv[2])
mutants = {
    "boot_normal": ("    p->state = ST_UNKNOWN;", "    p->state = ST_NORMAL;"),
    "clear_immediate": ("        if (p->cnt == POLICY_CLEAR_N - 1) {", "        if (1) {"),
    "no_latch": ("            p->latch = 1;", "            p->latch = 0;"),
    "ack_always": ("    if (!p->latch)\n        return 0;", "    if (0)\n        return 0;"),
    "hold_min": ("sev_of[c] > p->hold", "sev_of[c] < p->hold"),
    "no_missing_check": ("        miss |= s->t[i] == T_MISS;", "        miss |= 0;"),
    "no_stale_check": ("        if (s->age[i] > STALE_MS)", "        if (s->age[i] > 60000u)"),
    "no_stuck_check": ("        lo &= s->v[i] <= 15u;", "        lo &= 0;"),
    "npu_before_guard": ("    if (fmask || umask) {", "    if (0) {"),
    "no_link_timeout": ("        if (c == SIO_TIMEOUT) {", "        if (c == SIO_TIMEOUT && 0) {"),
    "no_bad_streak": ("    if (bad_streak >= LINK_BAD_N)", "    if (bad_streak >= 1000)"),
    "feature_scale": ("s->t[0] - 16, 160);", "s->t[0] - 16, 128);"),
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
  run_cosim "$src" "$name" --limit 10 --csv "$build_dir/$name.csv" --log "$build_dir/$name.log"
  if [[ $COSIM_HOST_RC -ne 0 ]]; then
    killed=$((killed + 1))
    echo "MUTANT ${name#mut_} KILLED ($(grep -m1 -E '^STEP .* FAIL|SENSOR_HOST_FAIL|Traceback' "$build_dir/$name/host.log" | cut -c1-110))"
  else
    echo "MUTANT ${name#mut_} SURVIVED"
  fi
done
echo "MUTATION_SUMMARY killed=$killed total=$total"
[[ $total -gt 0 && $killed -eq $total ]]
echo "PYTHON_RTL_COMPARE_PASS ch29 host->uart_frame->c_firmware(guard,policy)->axi_npu_rtl state=reference policy_rtl=reference"
