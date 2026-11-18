#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export PYTHONDONTWRITEBYTECODE=1
build_dir=$(mktemp -d /tmp/p3-15.XXXXXXXX)
iverilog -V 2>&1 | sed -n 1p
python3 reference/dense_reference.py
for cfg in 64,10 64,8 8,10; do
  n_in=${cfg%,*}; n_out=${cfg#*,}
  python3 reference/dense_reference.py --cfg "$cfg" --out "$build_dir/v_$n_in.$n_out.txt"
  iverilog -g2012 -Wall -s tb_npu_dense -P tb_npu_dense.N_IN="$n_in" -P tb_npu_dense.N_OUT="$n_out" \
    -o "$build_dir/sim_$n_in.$n_out" \
    ../ch01/rtl/mac_core.v ../ch04/rtl/bram_sync_buffer.v ../ch07/rtl/vector_dot_core.v ../ch08/rtl/pe_array4.v \
    rtl/npu_dense_core.v rtl/npu_dense_store.v rtl/npu_dense.v tb/tb_npu_dense.sv
  vvp -n "$build_dir/sim_$n_in.$n_out" +VECTORS="$build_dir/v_$n_in.$n_out.txt" +ACTUAL="$build_dir/a_$n_in.$n_out.txt"
  python3 reference/dense_reference.py --cfg "$cfg" --actual "$build_dir/a_$n_in.$n_out.txt"
done
