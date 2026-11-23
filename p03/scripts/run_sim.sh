#!/usr/bin/env bash
# 3장 보드 Top RTL 시뮬레이션: 기준 모델 → 사례 파일 → 시뮬레이터(STAGE마다) → 판정
# 기준 모델은 MNIST 원본(data/mnist, host_tools/mnist_idx.py가 내려받고 SHA-256 확인)을 읽는다.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
build="$(mktemp -d "${TMPDIR:-/tmp}/p03.XXXXXXXX")"
trap 'rm -rf "$build"' EXIT
source tools/sim/sim_top.sh
stages="${1:-1 2 3 4}"                 # 인자 없으면 전 STAGE, 숫자를 주면 그 STAGE만 (예: run_sim.sh 2)
if [ "$(sim_kind)" = xsim ]; then log="p03/validation/xsim_rtl_$(date -u +%Y%m%d).log"; else log="p03/validation/rtl_sim_$(date -u +%Y%m%d).log"; fi
[ $# -gt 0 ] && log="$build/stage.log"   # 한 STAGE만 돌릴 때는 기록 파일을 남기지 않는다
{
  echo "# p03 RTL simulation $(date -u +%Y-%m-%dT%H:%MZ)"
  echo "# tool: $(sim_tool_version)"
  PYTHONDONTWRITEBYTECODE=1 python3 p03/reference/p03_model.py
  for stage in $stages; do      # STAGE = 끝낸 서브젝트 수
    echo "## STAGE=$stage"
    sim_top tb_p03_top "$stage" "$build" \
      common/rtl/uart_rx.v common/rtl/uart_tx.v common/rtl/uart_core.v \
      p01/rtl/p01_reset_sync.v p01/rtl/p01_hex4_display.v \
      part03/ch02/rtl/dsp_multiplier.v part03/mini_npu/rtl/npu_dsp_mac_lane.v \
      part03/ch13/rtl/p3_frame64_buffer.v part03/ch14/rtl/p3_group10_core.v \
      part03/ch16/rtl/p3_relu_requant.v part03/ch16/rtl/p3_mlp_64_8_10.v \
      p03/rtl/p03_bank.v p03/rtl/p03_console.v p03/rtl/p03_view.v p03/rtl/basys3_p03_top.v \
      p03/tb/tb_p03_top.sv
  done
} 2>&1 | sed "s|$root|<repo>|g" > "$build/out.log" || true
want=$(echo $stages | wc -w)
if [ "$(grep -c '^P03_TOP_RTL_SIM_PASS' "$build/out.log")" = "$want" ] && ! grep -qiE 'FATAL|_FAIL|^ERROR' "$build/out.log"; then
  echo "RTL_SIM_PASS stages=$want" >> "$build/out.log"
else
  echo "RTL_SIM_FAIL" >> "$build/out.log"
fi
[ "$log" = "$build/stage.log" ] || cp "$build/out.log" "$log"
log="$build/out.log"
if [ $# -gt 0 ]; then grep -E '^(P03_CASE_PASS|P03_TOP|RTL_SIM|FATAL)' "$log"; else grep -E '^(PYTHON_P03_(SELF|VEC|DEMO_HITS|MODEL)|P03_TOP|RTL_SIM|FATAL)' "$log"; fi
grep -q '^RTL_SIM_PASS' "$log"
