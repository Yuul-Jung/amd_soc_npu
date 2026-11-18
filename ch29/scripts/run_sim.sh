#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export PYTHONDONTWRITEBYTECODE=1
b=$(mktemp -d /tmp/p3-29.XXXXXXXX)
iverilog -V 2>&1 | sed -n 1p
python3 reference/sensor_model.py --out "$b/v.txt"
iverilog -g2012 -Wall -s tb_sensor_guard_ai -o "$b/sim" \
  ../ch01/rtl/mac_core.v ../ch04/rtl/bram_sync_buffer.v ../ch07/rtl/vector_dot_core.v ../ch08/rtl/pe_array4.v \
  ../ch15/rtl/npu_dense_core.v ../ch15/rtl/npu_dense_store.v ../ch15/rtl/npu_dense.v rtl/sensor_guard_ai.v tb/tb_sensor_guard_ai.sv
vvp -n "$b/sim" +VECTORS="$b/v.txt" +ACTUAL="$b/a.txt"
python3 reference/sensor_model.py --actual "$b/a.txt"
