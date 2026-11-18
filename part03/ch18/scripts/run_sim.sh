#!/usr/bin/env bash
# (추가) 18장: INT8·INT16 정밀도 RTL 시뮬레이션. 17장 Tile Controller·TB를 DATA_W 파라미터로 재사용한다.
#   i16_full : INT16 무작위·극값·마지막 타일·Bias·오류 주입·Reset·취소 (외부 누산 41 / Bias 40)
#   i16_w41  : INT16 극값, 외부 누산 41비트 → overflow 없음
#   i16_w40  : INT16 극값, 외부 누산 40비트 → overflow 검출과 순환값 일치
#   mnist8 / mnist16 : 학습된 MNIST 784→10 모델의 INT8·INT16 양자화본으로 고정 표본 16개 추론
# 데이터셋은 필요 없다(커밋된 표본 reference/mnist_rtl_samples.txt 사용). 시험셋 전체 정확도는 run_eval.sh.
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
part03=$(cd -- "$chapter_dir/.." && pwd)
ch17="$part03/ch17"
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/p3-18.XXXXXXXX")
trap 'rm -rf "$build_dir"' EXIT
export PYTHONDONTWRITEBYTECODE=1
python3 --version
iverilog -V 2>&1 | sed -n '1p'
sha256sum "$chapter_dir/reference/mnist_linear_f32.json" "$chapter_dir/reference/mnist_rtl_samples.txt" \
  | sed "s#$part03#part03#g"

sim() {  # name data_w acc_w bias_w plusargs
  local dir="$build_dir/$1"
  iverilog -g2012 -Wall -s tb_p3_tile784_10 -Ptb_p3_tile784_10.DATA_W="$2" \
    -Ptb_p3_tile784_10.ACC_W="$3" -Ptb_p3_tile784_10.BIAS_W="$4" -o "$dir/sim" \
    "$part03/ch02/rtl/dsp_multiplier.v" "$part03/mini_npu/rtl/npu_dsp_mac_lane.v" \
    "$part03/ch13/rtl/p3_frame64_buffer.v" "$part03/ch04/rtl/bram_sync_buffer.v" \
    "$part03/ch14/rtl/p3_group10_core.v" "$ch17/rtl/p3_tile784_10.v" "$ch17/tb/tb_p3_tile784_10.sv"
  vvp "$dir/sim" +VECTORS="$dir/vectors.txt" +ACTUAL="$dir/actual.txt" $5
}

for cfg in i16_full:full:41:40 i16_w41:width:41:40 i16_w40:width:40:40; do
  IFS=: read -r name suite acc_w bias_w <<< "$cfg"
  dir="$build_dir/$name"; mkdir -p "$dir"
  echo "== config $name data_w=16 acc_w=$acc_w bias_w=$bias_w"
  python3 "$ch17/reference/tile784_reference.py" --out "$dir" --suite "$suite" \
    --acc-w "$acc_w" --bias-w "$bias_w" --data-w 16
  plus=""; [[ $suite == full ]] && plus="+FULL"
  sim "$name" 16 "$acc_w" "$bias_w" "$plus"
  python3 "$ch17/reference/tile784_reference.py" --out "$dir" --actual "$dir/actual.txt"
done

for bits in 8 16; do
  name="mnist$bits"; dir="$build_dir/$name"; mkdir -p "$dir"
  echo "== config $name data_w=$bits acc_w=41 bias_w=40"
  python3 "$chapter_dir/reference/precision_reference.py" --rtl-vectors --data-w "$bits" --out "$dir"
  sim "$name" "$bits" 41 40 ""
  python3 "$chapter_dir/reference/precision_reference.py" --out "$dir" --actual "$dir/actual.txt"
done
