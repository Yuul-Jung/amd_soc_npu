#!/usr/bin/env bash
# 독립 DSP/BRAM/4PE RTL 데이터패스 테스트 (UART 제외).
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/p3-engine.XXXXXXXX")"
trap 'rm -rf "$tmp"' EXIT
iverilog -g2012 -Wall -s tb_npu_engine4 -o "$tmp/engine.vvp" \
  "$here/../ch02/rtl/dsp_multiplier.v" \
  "$here/rtl/npu_dsp_mac_lane.v" "$here/rtl/npu_engine4.v" \
  "$here/tb/tb_npu_engine4.sv"
vvp "$tmp/engine.vvp"
