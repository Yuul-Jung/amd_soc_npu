#!/usr/bin/env bash
# 12장: 실제 UART RX/TX 비트파형을 TB가 검증하고 CSV를 생성.
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
root="$(cd -- "$here/.." && pwd)"
cd "$root/.."
out="$root/outputs"
mkdir -p "$out"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/p3-uart-npu.XXXXXXXX")"
trap 'rm -rf "$tmp"' EXIT
iverilog -g2012 -Wall -s tb_npu_uart -o "$tmp/npu.vvp" \
  "$root/../common/rtl/uart_rx.v" \
  "$root/../common/rtl/uart_tx.v" \
  "$root/../common/rtl/uart_core.v" \
  "$root/../ch02/rtl/dsp_multiplier.v" \
  "$root/rtl/npu_dsp_mac_lane.v" \
  "$root/rtl/npu_engine4.v" \
  "$root/rtl/uart_npu_command_controller.v" \
  "$root/rtl/npu_display_controller.v" \
  "$root/rtl/npu_reset_controller.v" \
  "$root/rtl/basys3_npu_top.v" \
  "$root/tb/tb_npu_uart.sv"
vvp "$tmp/npu.vvp" +CSV="$out/predictions.csv" | tee "$out/demo_result.txt"
python3 "$root/reference/check_results.py" "$out/predictions.csv"
