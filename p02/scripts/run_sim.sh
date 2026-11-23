#!/usr/bin/env bash
# 2장 보드 Top RTL 시뮬레이션: 기준 모델 → 사례 파일 → 시뮬레이터(STAGE마다) → 판정
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
build="$(mktemp -d "${TMPDIR:-/tmp}/p02.XXXXXXXX")"
trap 'rm -rf "$build"' EXIT
source tools/sim/sim_top.sh
stages="${1:-1 2 3 4 5 6 7 8}"                 # 인자 없으면 전 STAGE, 숫자를 주면 그 STAGE만 (예: run_sim.sh 2)
if [ "$(sim_kind)" = xsim ]; then log="p02/validation/xsim_rtl_$(date -u +%Y%m%d).log"; else log="p02/validation/rtl_sim_$(date -u +%Y%m%d).log"; fi
[ $# -gt 0 ] && log="$build/stage.log"   # 한 STAGE만 돌릴 때는 기록 파일을 남기지 않는다
{
  echo "# p02 RTL simulation $(date -u +%Y-%m-%dT%H:%MZ)"
  echo "# tool: $(sim_tool_version)"
  python3 p02/reference/p02_model.py
  for stage in $stages; do      # STAGE = 끝낸 서브젝트 수
    echo "## STAGE=$stage"
    sim_top tb_p02_top "$stage" "$build" \
      common/rtl/uart_rx.v common/rtl/uart_tx.v common/rtl/uart_core.v \
      p01/rtl/p01_reset_sync.v p01/rtl/p01_hex4_display.v \
      ch01/rtl/mac_core.v ch04/rtl/bram_sync_buffer.v ch05/rtl/fixed_quantizer.v \
      ch07/rtl/vector_dot_core.v ch08/rtl/pe_array4.v ch09/rtl/dense_layer4.v ch10/rtl/npu_core.v \
      mini_npu/rtl/uart_npu_command_controller.v \
      ch02/rtl/dsp_multiplier.v mini_npu/rtl/npu_dsp_mac_lane.v mini_npu/rtl/npu_engine4.v \
      mini_npu/rtl/npu_display_controller.v \
      p02/rtl/p02_bank.v p02/rtl/p02_console.v p02/rtl/p02_uart_switch.v p02/rtl/p02_npu_path.v \
      p02/rtl/p02_view.v p02/rtl/basys3_p02_top.v p02/tb/tb_p02_top.sv
  done
} 2>&1 | sed "s|$root|<repo>|g" > "$build/out.log" || true
want=$(echo $stages | wc -w)
if [ "$(grep -c '^P02_TOP_RTL_SIM_PASS' "$build/out.log")" = "$want" ] && ! grep -qiE 'FATAL|_FAIL|^ERROR' "$build/out.log"; then
  echo "RTL_SIM_PASS stages=$want" >> "$build/out.log"
else
  echo "RTL_SIM_FAIL" >> "$build/out.log"
fi
[ "$log" = "$build/stage.log" ] || cp "$build/out.log" "$log"
log="$build/out.log"
if [ $# -gt 0 ]; then grep -E '^(P02_CASE_PASS|P02_TOP|RTL_SIM|FATAL)' "$log"; else grep -E '^(PYTHON_P02_(SELF|VEC)|P02_TOP|RTL_SIM|FATAL)' "$log"; fi
grep -q '^RTL_SIM_PASS' "$log"
