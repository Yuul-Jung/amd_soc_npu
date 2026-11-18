#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
b=$(mktemp -d /tmp/p3-30.XXXXXXXX)
iverilog -V 2>&1 | sed -n 1p
python3 reference/interlock_model.py --out "$b/v.txt"
iverilog -g2012 -Wall -s tb_motor_interlock -o "$b/sim" rtl/motor_interlock.v tb/tb_motor_interlock.sv
vvp -n "$b/sim" +VECTORS="$b/v.txt" +ACTUAL="$b/a.txt" | grep -E '_PASS|FATAL'
if cmp -s "$b/a.txt" "$b/v.txt.expect"; then
  echo "PYTHON_RTL_COMPARE_PASS cycles=$(wc -l < "$b/a.txt") outputs=en,pwm,dir,speed,block (클록 단위 동일)"
else
  diff "$b/a.txt" "$b/v.txt.expect" | head -5; echo "PYTHON_RTL_COMPARE_FAIL"; exit 1
fi
