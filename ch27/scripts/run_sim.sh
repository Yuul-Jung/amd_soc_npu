#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export PYTHONDONTWRITEBYTECODE=1
b=$(mktemp -d /tmp/p3-27.XXXXXXXX)
iverilog -V 2>&1 | sed -n 1p; gcc --version | sed -n 1p; clang --version | sed -n 1p
python3 reference/gen_demo_header.py "$b/model_int8.h"
# ① 7세그먼트 표시기 RTL
iverilog -g2012 -Wall -s tb_fnd_class_display -o "$b/fnd" rtl/fnd_class_display.v tb/tb_fnd_class_display.sv
vvp -n "$b/fnd" | grep -E '_PASS|FATAL'
# ② 펌웨어 RV32IMC 교차 컴파일 (BSP 대역 헤더)
for f in sw/main.c sw/board_io_mbv.c ../ch22/sw/npu_drv.c ../ch22/sw/npu_hal_mbv.c; do
  clang --target=riscv32-unknown-elf -march=rv32imc -O2 -Wall -Wextra -Werror -ffreestanding \
    -Isw -I../ch22/sw -I../ch22/host/bsp_stub -I"$b" -c "$f" -o "$b/$(basename "$f" .c).o"
done
echo "RV32IMC_COMPILE_PASS files=4"
# ③ LED 워드 약속
gcc -Wall -Wextra -Werror -Isw host/test_led_word.c -o "$b/lw" && "$b/lw"
# ④ 같은 main.c를 PC에서 스위치 11번 바꿔 실행 → NPU 접근 기록 → 20장 RTL에서 재생 → 점수·클래스·LED 워드 확인
gcc -O2 -Wall -Wextra -Werror -DNPU_HOST -Isw -I../ch22/sw -I"$b" sw/main.c ../ch22/sw/npu_drv.c \
  ../ch22/host/npu_hal_trace.c host/board_io_host.c -o "$b/main_host"
NPU_TRACE="$b/trace.txt" LED_LOG="$b/led.txt" "$b/main_host" > /dev/null
iverilog -g2012 -Wall -s tb_driver_replay -o "$b/sim" \
  ../ch01/rtl/mac_core.v ../ch04/rtl/bram_sync_buffer.v ../ch07/rtl/vector_dot_core.v ../ch16/rtl/npu_argmax.v \
  ../ch19/rtl/npu_tiled_784_npe.v ../ch20/rtl/npu_axi_lite.v ../ch22/tb/tb_driver_replay.sv
vvp -n "$b/sim" +TRACE="$b/trace.txt" +ACTUAL="$b/actual.txt" | grep -E '_PASS|FATAL'
python3 reference/demo_check.py "$b/actual.txt" "$b/led.txt"
# ⑤ 최종 Top 포트 ↔ XDC
python3 tb/check_top_xdc.py
