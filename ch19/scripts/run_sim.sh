#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export PYTHONDONTWRITEBYTECODE=1
build_dir=$(mktemp -d /tmp/p3-19.XXXXXXXX)
iverilog -V 2>&1 | sed -n 1p
python3 reference/pe_compare.py --out "$build_dir/v.txt"
meas=()
for npe in 1 2 4 8; do
  iverilog -g2012 -Wall -s tb_npu_npe -P tb_npu_npe.NPE="$npe" -o "$build_dir/sim$npe" \
    ../ch01/rtl/mac_core.v ../ch04/rtl/bram_sync_buffer.v ../ch07/rtl/vector_dot_core.v ../ch08/rtl/pe_array4.v \
    ../ch16/rtl/npu_argmax.v ../ch18/rtl/npu_tiled_784_p.v rtl/npu_tiled_784_npe.v tb/tb_npu_npe.sv
  line=$(vvp -n "$build_dir/sim$npe" +VECTORS="$build_dir/v.txt" +ACTUAL="$build_dir/a$npe.txt" | grep -E 'RTL_SIM|CH18_DW8|FATAL|Error' || true)
  echo "$line"
  [[ "$line" == *RTL_SIM_PASS* ]] || exit 1
  python3 reference/pe_compare.py --npe "$npe" --actual "$build_dir/a$npe.txt"
  meas+=("$npe=${line##*cycles=}")
done
python3 reference/pe_compare.py --cycles "${meas[@]}"
