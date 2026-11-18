#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export PYTHONDONTWRITEBYTECODE=1
build_dir=$(mktemp -d /tmp/p3-18.XXXXXXXX)
iverilog -V 2>&1 | sed -n 1p
for cfg in 8,32 16,48; do
  dw=${cfg%,*}; aw=${cfg#*,}
  python3 reference/precision_rtl.py --bits "$dw" --out "$build_dir/v$dw.txt"
  iverilog -g2012 -Wall -s tb_npu_precision -P tb_npu_precision.DW="$dw" -P tb_npu_precision.AW="$aw" -o "$build_dir/sim$dw" \
    ../ch01/rtl/mac_core.v ../ch04/rtl/bram_sync_buffer.v ../ch07/rtl/vector_dot_core.v ../ch08/rtl/pe_array4.v \
    ../ch15/rtl/npu_dense_core.v ../ch16/rtl/npu_argmax.v ../ch17/rtl/npu_tiled_784.v \
    rtl/npu_tiled_784_p.v tb/tb_npu_precision.sv
  vvp -n "$build_dir/sim$dw" +VECTORS="$build_dir/v$dw.txt" +ACTUAL="$build_dir/a$dw.txt"
  python3 reference/precision_rtl.py --bits "$dw" --actual "$build_dir/a$dw.txt"
done
# 폭 부족 확인: INT16을 32비트 누산으로 돌리면 점수가 넘쳐 Python과 달라야 한다 (실패가 정상).
iverilog -g2012 -s tb_npu_precision -P tb_npu_precision.DW=16 -P tb_npu_precision.AW=32 -o "$build_dir/sim16n" \
  ../ch01/rtl/mac_core.v ../ch04/rtl/bram_sync_buffer.v ../ch07/rtl/vector_dot_core.v ../ch08/rtl/pe_array4.v \
  ../ch15/rtl/npu_dense_core.v ../ch16/rtl/npu_argmax.v ../ch17/rtl/npu_tiled_784.v \
  rtl/npu_tiled_784_p.v tb/tb_npu_precision.sv
vvp -n "$build_dir/sim16n" +VECTORS="$build_dir/v16.txt" +ACTUAL="$build_dir/a16n.txt" > /dev/null
if python3 reference/precision_rtl.py --bits 16 --actual "$build_dir/a16n.txt" > "$build_dir/n.txt" 2>&1; then
  echo "ACC_WIDTH_CHECK_FAIL INT16을 32비트로 돌렸는데 넘침이 드러나지 않음"; exit 1
fi
echo "ACC_WIDTH_CHECK_PASS int16_acc32_mismatch=$(grep -o 'case=[0-9]*' "$build_dir/n.txt" | head -1)"
