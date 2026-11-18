#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export PYTHONDONTWRITEBYTECODE=1
build_dir=$(mktemp -d /tmp/p3-04.XXXXXXXX)
for config in 16:8 8:3; do
  w=${config%:*}; a=${config#*:}
  python3 reference/bram_reference.py --width "$w" --addr "$a" --out "$build_dir"
  iverilog -g2012 -Wall -s tb_bram_sync_buffer -Ptb_bram_sync_buffer.W="$w" -Ptb_bram_sync_buffer.A="$a" \
    -o "$build_dir/sim" rtl/bram_sync_buffer.v tb/tb_bram_sync_buffer.sv
  vvp "$build_dir/sim" +VECTORS="$build_dir/vectors.txt" +ACTUAL="$build_dir/actual.txt"
  python3 reference/bram_reference.py --out "$build_dir" --actual "$build_dir/actual.txt"
  for bad in COLLISION UNINITIALIZED; do
    if vvp "$build_dir/sim" +"${bad}_TEST" > "$build_dir/reject.log" 2>&1; then
      printf 'FAIL missing rejection\n'; exit 1
    fi
    rg -q "$bad" "$build_dir/reject.log"
    printf 'EXPECTED_REJECTION %s\n' "$bad"
  done
done
