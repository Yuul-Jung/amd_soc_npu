#!/usr/bin/env bash
# 2장 보드 Top RTL 시뮬레이션: 기준 모델 → 사례 파일 → Icarus(STAGE 1~8) → 로그 (p02/validation/rtl_sim_YYYYMMDD.log)
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
build="$(mktemp -d "${TMPDIR:-/tmp}/p02.XXXXXXXX")"
trap 'rm -rf "$build"' EXIT
log="p02/validation/rtl_sim_$(date -u +%Y%m%d).log"
{
  echo "# p02 RTL simulation $(date -u +%Y-%m-%dT%H:%MZ)"
  echo "# tool: $(iverilog -V 2>&1 | sed -n 1p)"
  python3 p02/reference/p02_model.py
  for stage in 1 2 3 4 5 6 7 8; do      # 서브젝트마다 보드 확인용 빌드 (STAGE = 끝낸 서브젝트 수)
    echo "## STAGE=$stage"
    iverilog -g2012 -Wall -s tb_p02_top -P tb_p02_top.STAGE=$stage -o "$build/p02_s$stage.vvp" \
      common/rtl/uart_rx.v common/rtl/uart_tx.v common/rtl/uart_core.v \
      p01/rtl/p01_reset_sync.v p01/rtl/p01_hex4_display.v \
      ch01/rtl/mac_core.v ch04/rtl/bram_sync_buffer.v ch05/rtl/fixed_quantizer.v \
      ch07/rtl/vector_dot_core.v ch08/rtl/pe_array4.v ch09/rtl/dense_layer4.v ch10/rtl/npu_core.v \
      mini_npu/rtl/uart_npu_command_controller.v \
      ch02/rtl/dsp_multiplier.v mini_npu/rtl/npu_dsp_mac_lane.v mini_npu/rtl/npu_engine4.v \
      mini_npu/rtl/npu_display_controller.v \
      p02/rtl/p02_bank.v p02/rtl/p02_console.v p02/rtl/p02_uart_switch.v p02/rtl/p02_npu_path.v \
      p02/rtl/p02_view.v p02/rtl/basys3_p02_top.v p02/tb/tb_p02_top.sv
    vvp -n "$build/p02_s$stage.vvp"
  done
} 2>&1 | sed "s|$root|<repo>|g" > "$build/out.log" || true
if [ "$(grep -c '^P02_TOP_RTL_SIM_PASS' "$build/out.log")" = 8 ] && ! grep -qE 'FATAL|_FAIL' "$build/out.log"; then
  echo "RTL_SIM_PASS stages=8" >> "$build/out.log"
else
  echo "RTL_SIM_FAIL" >> "$build/out.log"
fi
cp "$build/out.log" "$log"
grep -E '^(PYTHON_P02_(SELF|VEC)|P02_TOP|RTL_SIM|FATAL)' "$log"
grep -q '^RTL_SIM_PASS' "$log"
