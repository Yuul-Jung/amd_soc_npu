#!/usr/bin/env bash
# (추가) 28장: 숫자 인식 시스템 PC 검증.
#   1) 기준모델 자체 시험(CRC16·프레임·FND 표시 규칙)
#   2) FND 스캔 RTL 시험(Python 기대값과 핀 단위 비교)
#   3) 종단간 협동 시뮬레이션: Python 호스트(전처리·UART 프레임·CSV) → 표준 입출력 → 보드와 같은 C 펌웨어
#      → 22장 FIFO 브리지 → 20장 AXI NPU RTL(Icarus). 표본 22장 + 오류 시험 묶음.
#   결과: validation/rtl_cosim.csv, validation/rtl_cosim_uart.log (+ 표준 출력)
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
part03=$(cd -- "$chapter_dir/.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/p3-28.XXXXXXXX")
trap 'rm -rf "$build_dir"' EXIT
export PYTHONDONTWRITEBYTECODE=1
python3 --version
gcc --version | sed -n '1p'
iverilog -V 2>&1 | sed -n '1p'
ref="$chapter_dir/reference/digit_reference.py"
python3 "$ref" --selftest --header "$build_dir/digit_model.h" --fnd-vectors "$build_dir/fnd_vectors.txt"

# 2) FND 스캔
iverilog -g2012 -Wall -s tb_p3_fnd_scan -o "$build_dir/fnd" "$chapter_dir/rtl/p3_fnd_scan.v" "$chapter_dir/tb/tb_p3_fnd_scan.sv"
vvp -n "$build_dir/fnd" +VEC="$build_dir/fnd_vectors.txt" | grep -v "finish called"

# 3) 협동 시뮬레이션
iverilog -g2012 -Wall -s tb_p3_npu_bridge -o "$build_dir/sim" -I"$part03/ch20/tb" \
  "$part03/ch02/rtl/dsp_multiplier.v" "$part03/mini_npu/rtl/npu_dsp_mac_lane.v" \
  "$part03/ch04/rtl/bram_sync_buffer.v" "$part03/ch14/rtl/p3_group10_core.v" \
  "$part03/ch17/rtl/p3_tile784_10.v" "$part03/ch20/rtl/p3_npu_axi_lite.v" \
  "$part03/ch22/tb/tb_p3_npu_bridge.sv"
# 협동 시뮬레이션 1회: $1 = 펌웨어 소스(digit_app.c), $2 = 이름, 나머지 = 호스트 인자
run_cosim() {
  local app=$1 name=$2; shift 2
  local d="$build_dir/$name"
  local werr=-Werror
  [[ $name == mut_* ]] && werr=-Wno-error      # 변이 소스는 경고(항상 거짓 비교 등)를 허용
  mkdir -p "$d"
  gcc -std=c99 -D_DEFAULT_SOURCE -O2 -Wall -Wextra $werr -DNPU_HOST_SIM \
    -I"$part03/ch22/sw" -I"$chapter_dir/sw" -I"$build_dir" -o "$d/fw" \
    "$part03/ch22/sw/npu_driver.c" "$app" \
    "$part03/ch22/host/npu_io_cosim.c" "$chapter_dir/host/digit_io_host.c" "$chapter_dir/host/digit_cosim_main.c"
  mkfifo "$d/cmd" "$d/rsp"
  vvp "$build_dir/sim" +CMD="$d/cmd" +RSP="$d/rsp" > "$d/sim.log" 2>&1 &
  local sim_pid=$! host_rc=0 sim_rc=0
  python3 "$chapter_dir/host/p3_digit_host.py" --cosim "$d/fw $d/cmd $d/rsp" "$@" > "$d/host.log" 2>&1 || host_rc=$?
  wait "$sim_pid" || sim_rc=$?
  COSIM_HOST_RC=$host_rc
  COSIM_SIM_RC=$sim_rc
}

run_cosim "$chapter_dir/sw/digit_app.c" golden --error-suite \
  --csv "$chapter_dir/validation/rtl_cosim.csv" --log "$chapter_dir/validation/rtl_cosim_uart.log"
cat "$build_dir/golden/host.log"
grep -v "finish called" "$build_dir/golden/sim.log"
if [[ $COSIM_HOST_RC -ne 0 || $COSIM_SIM_RC -ne 0 ]] || ! grep -q RTL_SIM_PASS "$build_dir/golden/sim.log"; then
  echo "DIGIT_COSIM_FAIL host_rc=$COSIM_HOST_RC sim_rc=$COSIM_SIM_RC"
  exit 1
fi

# 변이 시험: 펌웨어 결함을 하나씩 넣으면 호스트 판정이 FAIL이어야 한다(표본 3장 + 오류 시험 묶음)
python3 - "$chapter_dir/sw/digit_app.c" "$build_dir" <<'PY'
import sys
from pathlib import Path
src, out = Path(sys.argv[1]).read_text(), Path(sys.argv[2])
mutants = {
    "display_class": ("(uint32_t)ncls | FND_ON(0xD)", "(uint32_t)((ncls + 1) % 10) | FND_ON(0xD)"),
    "error_display_code": ("uint32_t fnd = (0xEu << 4) | (uint32_t)code;", "uint32_t fnd = (0xEu << 4) | (uint32_t)(code + 1);"),
    "no_crc_check": ("if (crc != 0) {", "if (crc == 0xFFFFu) {"),
    "no_range_check": ("if (v > DIGIT_PIX_MAX) {", "if (v > 255u) {"),
    "no_model_check": ("if (mid != DIGIT_MODEL_ID || !model_ok) {", "if (!model_ok) {"),
    "no_selftest_recover": ("    s = npu_recover(npu);\n    recovered", "    s = npu_io_read(npu->base + NPU_STATUS);\n    recovered"),
    "no_junk_count": ("            junk++;", "            junk += 0;"),
    "no_resync": ("        if (prev == 'P' && c == '3')", "        if (prev == 'P' && c == '3' && junk == 0)"),
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
  run_cosim "$src" "$name" --limit 3 --error-suite --csv "$build_dir/$name.csv" --log "$build_dir/$name.log"
  if [[ $COSIM_HOST_RC -ne 0 ]]; then
    killed=$((killed + 1))
    echo "MUTANT ${name#mut_} KILLED ($(grep -m1 -E 'ERRCASE .* FAIL|DIGIT_HOST_FAIL' "$build_dir/$name/host.log" | cut -c1-100))"
  else
    echo "MUTANT ${name#mut_} SURVIVED"
  fi
done
echo "MUTATION_SUMMARY killed=$killed total=$total"
[[ $total -gt 0 && $killed -eq $total ]]
echo "PYTHON_RTL_COMPARE_PASS ch28 host->uart_frame->c_firmware->axi_npu_rtl scores=golden display=rule"
