#!/usr/bin/env bash
# (추가) UART FIFO 단위 경계 시험 + 11·12장 통합 적대적 UART 시험. 기존 소스 수정 없음.
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
common="$here/../common/rtl"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/p3-adv.XXXXXXXX")"
trap 'rm -rf "$tmp"' EXIT
iverilog -g2012 -Wall -s tb_uart_core_fifo -o "$tmp/fifo.vvp" \
  "$common/uart_rx.v" "$common/uart_tx.v" "$common/uart_core.v" \
  "$here/tb/tb_uart_core_fifo.sv"
vvp "$tmp/fifo.vvp"
iverilog -g2012 -Wall -s tb_npu_uart_adversarial -o "$tmp/adv.vvp" \
  "$common/uart_rx.v" "$common/uart_tx.v" "$common/uart_core.v" \
  "$here/../ch02/rtl/dsp_multiplier.v" \
  "$here/rtl/npu_dsp_mac_lane.v" "$here/rtl/npu_engine4.v" \
  "$here/rtl/uart_npu_command_controller.v" "$here/rtl/npu_display_controller.v" \
  "$here/rtl/npu_reset_controller.v" "$here/rtl/basys3_npu_top.v" \
  "$here/tb/tb_npu_uart_adversarial.sv"
vvp "$tmp/adv.vvp"
