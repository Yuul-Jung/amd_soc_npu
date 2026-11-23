#!/usr/bin/env bash
# 4장 보드 Top RTL 시뮬레이션: 기준 모델 → 사례 파일 → 시뮬레이터(STAGE마다) → 판정
# 시연 그림은 part03/ch18/reference/mnist_rtl_samples.txt (MNIST 원본 불필요).
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
build="$(mktemp -d "${TMPDIR:-/tmp}/p04.XXXXXXXX")"
trap 'rm -rf "$build"' EXIT
source tools/sim/sim_top.sh
stages="${1:-1 2 3 4}"                 # 인자 없으면 전 STAGE, 숫자를 주면 그 STAGE만 (예: run_sim.sh 2)
if [ "$(sim_kind)" = xsim ]; then log="p04/validation/xsim_rtl_$(date -u +%Y%m%d).log"; else log="p04/validation/rtl_sim_$(date -u +%Y%m%d).log"; fi
[ $# -gt 0 ] && log="$build/stage.log"   # 한 STAGE만 돌릴 때는 기록 파일을 남기지 않는다
{
  echo "# p04 RTL simulation $(date -u +%Y-%m-%dT%H:%MZ)"
  echo "# tool: $(sim_tool_version)"
  PYTHONDONTWRITEBYTECODE=1 python3 p04/reference/p04_model.py
  for stage in $stages; do      # STAGE = 끝낸 서브젝트 수
    echo "## STAGE=$stage"
    sim_top tb_p04_top "$stage" "$build" \
      common/rtl/uart_rx.v common/rtl/uart_tx.v common/rtl/uart_core.v \
      p01/rtl/p01_reset_sync.v p01/rtl/p01_hex4_display.v \
      ch05/rtl/fixed_quantizer.v ch06/rtl/precision_compare.v \
      part03/ch02/rtl/dsp_multiplier.v part03/mini_npu/rtl/npu_dsp_mac_lane.v part03/ch04/rtl/bram_sync_buffer.v \
      part03/ch13/rtl/p3_frame64_buffer.v part03/ch14/rtl/p3_group10_core.v part03/ch17/rtl/p3_tile784_10.v \
      p04/rtl/p04_bank.v p04/rtl/p04_console.v p04/rtl/p04_view.v p04/rtl/basys3_p04_top.v \
      p04/tb/tb_p04_top.sv
  done
} 2>&1 | sed "s|$root|<repo>|g" > "$build/out.log" || true
want=$(echo $stages | wc -w)
if [ "$(grep -c '^P04_TOP_RTL_SIM_PASS' "$build/out.log")" = "$want" ] \
   && grep -q '^PYTHON_P04_SELF_TEST_PASS' "$build/out.log" \
   && ! grep -qiE 'FATAL|_FAIL|^ERROR|Traceback' "$build/out.log"; then   # 기준 모델이 죽었거나 자기 시험을 못 냈으면 실패
  echo "RTL_SIM_PASS stages=$want" >> "$build/out.log"
else
  echo "RTL_SIM_FAIL" >> "$build/out.log"
fi
[ "$log" = "$build/stage.log" ] || cp "$build/out.log" "$log"
log="$build/out.log"
if [ $# -gt 0 ]; then grep -E '^(P04_CASE_PASS|P04_TOP|RTL_SIM|FATAL)' "$log"; else grep -E '^(PYTHON_P04_(SELF|VEC|DEMO)|P04_TOP|RTL_SIM|FATAL)' "$log"; fi
grep -q '^RTL_SIM_PASS' "$log"
