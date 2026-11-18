#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export PYTHONDONTWRITEBYTECODE=1
b=$(mktemp -d /tmp/p3-26.XXXXXXXX)
iverilog -V 2>&1 | sed -n 1p
python3 reference/cnn_reference.py --out "$b"
iverilog -g2012 -Wall -s tb_npu_cnn3x3 -o "$b/sim" \
  ../ch01/rtl/mac_core.v ../ch04/rtl/bram_sync_buffer.v ../ch05/rtl/fixed_quantizer.v ../ch07/rtl/vector_dot_core.v \
  ../ch08/rtl/pe_array4.v ../ch15/rtl/npu_dense_core.v ../ch15/rtl/npu_dense_store.v ../ch15/rtl/npu_dense.v \
  ../ch16/rtl/npu_argmax.v rtl/npu_cnn3x3.v tb/tb_npu_cnn3x3.sv
vvp -n "$b/sim" +VECTORS="$b/vectors.txt" +ACTUAL="$b/actual.txt"
python3 reference/cnn_reference.py --actual "$b/actual.txt"
# 기존 NPU 회귀: 이 장이 재사용하는 15·16장과, 20장 AXI 경로가 그대로 통과하는지
for ch in ch15 ch16 ch20; do
  line=$(bash "../$ch/scripts/run_sim.sh" 2>&1 | grep -E '_PASS|_FAIL' | tail -1)
  echo "REGRESSION $ch: $line"
  [[ "$line" == *_PASS* ]] || exit 1
done
echo "REGRESSION_PASS chapters=3"
