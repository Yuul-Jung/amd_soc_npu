#!/usr/bin/env bash
# 4장 보드 Top RTL 시뮬레이션: 기준 모델 → 사례 파일 → Icarus(STAGE 1~4) → 로그 (p04/validation/rtl_sim_YYYYMMDD.log)
# 시연 그림은 part03/ch18/reference/mnist_rtl_samples.txt (MNIST 원본 불필요).
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
build="$(mktemp -d "${TMPDIR:-/tmp}/p04.XXXXXXXX")"
trap 'rm -rf "$build"' EXIT
log="p04/validation/rtl_sim_$(date -u +%Y%m%d).log"
{
  echo "# p04 RTL simulation $(date -u +%Y-%m-%dT%H:%MZ)"
  echo "# tool: $(iverilog -V 2>&1 | sed -n 1p)"
  PYTHONDONTWRITEBYTECODE=1 python3 p04/reference/p04_model.py
  for stage in 1 2 3 4; do      # 서브젝트마다 보드 확인용 빌드 (STAGE = 끝낸 서브젝트 수)
    echo "## STAGE=$stage"
    iverilog -g2012 -Wall -s tb_p04_top -P tb_p04_top.STAGE=$stage -o "$build/p04_s$stage.vvp" \
      common/rtl/uart_rx.v common/rtl/uart_tx.v common/rtl/uart_core.v \
      p01/rtl/p01_reset_sync.v p01/rtl/p01_hex4_display.v \
      ch05/rtl/fixed_quantizer.v ch06/rtl/precision_compare.v \
      part03/ch02/rtl/dsp_multiplier.v part03/mini_npu/rtl/npu_dsp_mac_lane.v part03/ch04/rtl/bram_sync_buffer.v \
      part03/ch13/rtl/p3_frame64_buffer.v part03/ch14/rtl/p3_group10_core.v part03/ch17/rtl/p3_tile784_10.v \
      p04/rtl/p04_bank.v p04/rtl/p04_console.v p04/rtl/p04_view.v p04/rtl/basys3_p04_top.v \
      p04/tb/tb_p04_top.sv
    vvp -n "$build/p04_s$stage.vvp"
  done
} 2>&1 | sed "s|$root|<repo>|g" > "$build/out.log" || true
if [ "$(grep -c '^P04_TOP_RTL_SIM_PASS' "$build/out.log")" = 4 ] && ! grep -qE 'FATAL|_FAIL' "$build/out.log"; then
  echo "RTL_SIM_PASS stages=4" >> "$build/out.log"
else
  echo "RTL_SIM_FAIL" >> "$build/out.log"
fi
cp "$build/out.log" "$log"
grep -E '^(PYTHON_P04_(SELF|VEC|DEMO)|P04_TOP|RTL_SIM|FATAL)' "$log"
grep -q '^RTL_SIM_PASS' "$log"
