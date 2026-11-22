#!/usr/bin/env bash
# 1장 보드 Top RTL 시뮬레이션: 기준 모델 → 사례 파일 → Icarus(STAGE 1~4) → 로그 (p01/validation/rtl_sim_YYYYMMDD.log)
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
build="$(mktemp -d "${TMPDIR:-/tmp}/p01.XXXXXXXX")"
trap 'rm -rf "$build"' EXIT
log="p01/validation/rtl_sim_$(date -u +%Y%m%d).log"
{
  echo "# p01 RTL simulation $(date -u +%Y-%m-%dT%H:%MZ)"
  echo "# tool: $(iverilog -V 2>&1 | sed -n 1p)"
  python3 p01/reference/p01_model.py
  for stage in 1 2 3 4; do      # 서브젝트마다 보드 확인용 빌드 (STAGE = 끝낸 서브젝트 수)
    echo "## STAGE=$stage"
    iverilog -g2012 -Wall -s tb_p01_top -P tb_p01_top.STAGE=$stage -o "$build/p01_s$stage.vvp" \
      common/rtl/uart_rx.v common/rtl/uart_tx.v common/rtl/uart_core.v \
      ch01/rtl/mac_core.v ch02/rtl/dsp_multiplier.v ch03/rtl/mac_pipeline_core.v \
      p01/rtl/p01_reset_sync.v p01/rtl/p01_mac_bank.v p01/rtl/p01_calc_controller.v \
      p01/rtl/p01_hex4_display.v p01/rtl/basys3_p01_top.v p01/tb/tb_p01_top.sv
    vvp -n "$build/p01_s$stage.vvp"
  done
} 2>&1 | sed "s|$root|<repo>|g" > "$build/out.log" || true
if [ "$(grep -c '^P01_TOP_RTL_SIM_PASS' "$build/out.log")" = 4 ] && ! grep -qE 'FATAL|_FAIL' "$build/out.log"; then
  echo "RTL_SIM_PASS stages=4" >> "$build/out.log"
else
  echo "RTL_SIM_FAIL" >> "$build/out.log"
fi
cp "$build/out.log" "$log"
grep -E '^(PYTHON_P01_(SELF|VEC)|P01_TOP|RTL_SIM|FATAL)' "$log"
grep -q '^RTL_SIM_PASS' "$log"
