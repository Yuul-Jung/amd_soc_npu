#!/usr/bin/env bash
# 3-2 코어 + 784입력 13타일 Tile Controller RTL 시뮬레이션과 Python 비트 단위 비교.
#   full : 외부 누산 41비트·Bias 40비트(INT16 계약 폭), 전체 시험·오류 주입
#   w25  : 외부 누산 25비트(INT8 최소 안전 폭) → 극값에서도 overflow 없음
#   w24  : 외부 누산 24비트(1비트 부족) → 극값에서 overflow 검출과 순환값 일치
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
part03=$(cd -- "$chapter_dir/.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/p3-17.XXXXXXXX")
trap 'rm -rf "$build_dir"' EXIT
export PYTHONDONTWRITEBYTECODE=1
python3 --version
iverilog -V 2>&1 | sed -n '1p'
for cfg in full:41:40 w25:25:24 w24:24:24; do
  IFS=: read -r name acc_w bias_w <<< "$cfg"
  suite=width; plus=""
  if [[ $name == full ]]; then suite=full; plus="+FULL"; fi
  dir="$build_dir/$name"; mkdir -p "$dir"
  echo "== config $name acc_w=$acc_w bias_w=$bias_w"
  python3 "$chapter_dir/reference/tile784_reference.py" --out "$dir" --suite "$suite" \
    --acc-w "$acc_w" --bias-w "$bias_w"
  iverilog -g2012 -Wall -s tb_p3_tile784_10 \
    -Ptb_p3_tile784_10.ACC_W="$acc_w" -Ptb_p3_tile784_10.BIAS_W="$bias_w" -o "$dir/sim" \
    "$part03/ch02/rtl/dsp_multiplier.v" "$part03/mini_npu/rtl/npu_dsp_mac_lane.v" \
    "$part03/ch13/rtl/p3_frame64_buffer.v" "$part03/ch14/rtl/p3_group10_core.v" \
    "$chapter_dir/rtl/p3_tile784_10.v" "$chapter_dir/tb/tb_p3_tile784_10.sv"
  vvp "$dir/sim" +VECTORS="$dir/vectors.txt" +ACTUAL="$dir/actual.txt" $plus
  python3 "$chapter_dir/reference/tile784_reference.py" --out "$dir" --actual "$dir/actual.txt"
done
