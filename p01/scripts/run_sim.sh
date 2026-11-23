#!/usr/bin/env bash
# 1장 보드 Top RTL 시뮬레이션: 기준 모델 → 사례 파일 → 시뮬레이터(STAGE마다) → 판정
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
build="$(mktemp -d "${TMPDIR:-/tmp}/p01.XXXXXXXX")"
trap 'rm -rf "$build"' EXIT
source tools/sim/sim_top.sh
stages="${1:-1 2 3 4}"                 # 인자 없으면 전 STAGE, 숫자를 주면 그 STAGE만 (예: run_sim.sh 2)
if [ "$(sim_kind)" = xsim ]; then log="p01/validation/xsim_rtl_$(date -u +%Y%m%d).log"; else log="p01/validation/rtl_sim_$(date -u +%Y%m%d).log"; fi
[ $# -gt 0 ] && log="$build/stage.log"   # 한 STAGE만 돌릴 때는 기록 파일을 남기지 않는다
{
  echo "# p01 RTL simulation $(date -u +%Y-%m-%dT%H:%MZ)"
  echo "# tool: $(sim_tool_version)"
  python3 p01/reference/p01_model.py
  for stage in $stages; do      # STAGE = 끝낸 서브젝트 수
    echo "## STAGE=$stage"
    sim_top tb_p01_top "$stage" "$build" \
      common/rtl/uart_rx.v common/rtl/uart_tx.v common/rtl/uart_core.v \
      ch01/rtl/mac_core.v ch02/rtl/dsp_multiplier.v ch03/rtl/mac_pipeline_core.v \
      p01/rtl/p01_reset_sync.v p01/rtl/p01_mac_bank.v p01/rtl/p01_calc_controller.v \
      p01/rtl/p01_hex4_display.v p01/rtl/basys3_p01_top.v p01/tb/tb_p01_top.sv
  done
} 2>&1 | sed "s|$root|<repo>|g" > "$build/out.log" || true
want=$(echo $stages | wc -w)
if [ "$(grep -c '^P01_TOP_RTL_SIM_PASS' "$build/out.log")" = "$want" ] \
   && grep -q '^PYTHON_P01_SELF_TEST_PASS' "$build/out.log" \
   && ! grep -qiE 'FATAL|_FAIL|^ERROR|Traceback' "$build/out.log"; then   # 기준 모델이 죽었거나 자기 시험을 못 냈으면 실패
  echo "RTL_SIM_PASS stages=$want" >> "$build/out.log"
else
  echo "RTL_SIM_FAIL" >> "$build/out.log"
fi
[ "$log" = "$build/stage.log" ] || cp "$build/out.log" "$log"
log="$build/out.log"
if [ $# -gt 0 ]; then grep -E '^(P01_CASE_PASS|P01_TOP|RTL_SIM|FATAL)' "$log"; else grep -E '^(PYTHON_P01_(SELF|VEC)|P01_TOP|RTL_SIM|FATAL)' "$log"; fi
grep -q '^RTL_SIM_PASS' "$log"
