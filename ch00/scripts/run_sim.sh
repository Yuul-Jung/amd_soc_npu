#!/usr/bin/env bash
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
root="$(cd -- "$here/.." && pwd)"
build="$(mktemp -d "${TMPDIR:-/tmp}/p3-echo.XXXXXXXX")"
trap 'rm -rf "$build"' EXIT
iverilog -g2012 -Wall -s tb_uart_echo -o "$build/echo.vvp" \
  "$root/common/rtl/uart_rx.v" "$root/common/rtl/uart_tx.v" \
  "$root/common/rtl/uart_core.v" "$root/common/rtl/uart_echo_controller.v" \
  "$here/rtl/basys3_uart_echo_top.v" "$here/tb/tb_uart_echo.sv"
vvp "$build/echo.vvp"
