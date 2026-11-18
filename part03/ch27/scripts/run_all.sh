#!/usr/bin/env bash
# (추가) 27장: 제3부 13~26장 결과를 한 번에 재현하는 실행기. 단계마다 PASS/FAIL/NOT_RUN을 표로 남긴다.
#   LEVEL=sim  (기본) RTL·Python·C 협동 시뮬레이션만 (약 10분)
#   LEVEL=pc   + MNIST 전체 평가 (MNIST_DIR 필요)
#   LEVEL=fpga + Vivado OOC·SoC Bitstream·Vitis ELF (VIVADO_SETTINGS·VITIS_SETTINGS·SOC11_DIR 필요, 1시간 이상)
#   LEVEL=full + SoC 전체 xsim(23장)·전력(25장) (수 시간)
# 실물(Basys3)은 이 실행기가 하지 않는다 — docs/BOARD_CHECKLIST.md를 사용자와 함께 진행.
set -uo pipefail
part03=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
out="$part03/ch27/validation"
level=${LEVEL:-sim}
summary="$out/run_all_summary.md"
declare -a rows
step() {  # name level_needed command...
  local name=$1 need=$2; shift 2
  local order="sim pc fpga full"
  if [[ " ${order%%$level*}$level " != *" $need "* && $need != sim ]]; then
    rows+=("| $name | NOT_RUN (LEVEL=$level) |"); echo "NOT_RUN $name"; return
  fi
  local log="$out/logs/$name.log"
  mkdir -p "$out/logs"
  if "$@" > "$log" 2>&1; then rows+=("| $name | PASS |"); echo "PASS $name"
  else
    local rc=$?
    if [[ $rc -eq 2 ]]; then rows+=("| $name | NOT_RUN (도구·데이터 없음) |"); echo "NOT_RUN $name"
    else rows+=("| $name | **FAIL** (rc=$rc) |"); echo "FAIL $name"; fi
  fi
  sed -i "s#$part03#part03#g; s#${TMPDIR:-/tmp}/p3-[0-9a-z]*\.[A-Za-z0-9]*#<tmp>#g" "$log"
}
export PYTHONDONTWRITEBYTECODE=1
step host_integer_reference sim python3 -m part03.host_tools.test_p3_integer_reference
step rtl_ch13_26 sim bash "$part03/scripts/run_ch13_19.sh"
step pc_eval_ch18 pc bash "$part03/ch18/scripts/run_eval.sh"
step synth_ch19 fpga bash "$part03/ch19/scripts/run_synth.sh"
step synth_ch20 fpga bash "$part03/ch20/scripts/run_synth.sh"
step package_ip_ch20 fpga bash "$part03/ch20/scripts/package_ip.sh"
step soc_build_ch21 fpga bash "$part03/ch21/scripts/build_soc.sh"
step vitis_ch22 fpga bash "$part03/ch22/scripts/build_vitis.sh"
step synth_ch26 fpga bash "$part03/ch26/scripts/run_synth.sh"
step sweep_ch24 full bash "$part03/ch24/scripts/run_sweep.sh"
step soc_sim_ch23 full bash "$part03/ch23/scripts/run_soc_bench.sh"
step power_ch25 full bash "$part03/ch25/scripts/run_power.sh"
{
  echo "# 27장 run_all 결과 (LEVEL=$level, $(date -u +%Y-%m-%dT%H:%MZ), commit $(git -C "$part03" rev-parse --short HEAD))"
  echo; echo "| 단계 | 결과 |"; echo "|---|---|"; printf '%s\n' "${rows[@]}"
  echo; echo "실물 Basys3 검증은 포함하지 않는다(docs/BOARD_CHECKLIST.md)."
} > "$summary"
cat "$summary"
! grep -q "FAIL" "$summary"
