#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export PYTHONDONTWRITEBYTECODE=1
b=$(mktemp -d /tmp/p3-28.XXXXXXXX)
iverilog -V 2>&1 | sed -n 1p; gcc --version | sed -n 1p; clang --version | sed -n 1p
python3 ../ch27/reference/gen_demo_header.py "$b/model_int8.h" > /dev/null
# ① 펌웨어 RV32IMC 교차 컴파일
for f in sw/main.c sw/proto.c sw/uart_io_mbv.c; do
  clang --target=riscv32-unknown-elf -march=rv32imc -O2 -Wall -Wextra -Werror -ffreestanding \
    -Isw -I../ch22/sw -I../ch27/sw -I../ch22/host/bsp_stub -I"$b" -c "$f" -o "$b/$(basename "$f" .c).o"
done
echo "RV32IMC_COMPILE_PASS files=3"
# ② PC: 손글씨 PGM 3장(흰 바탕, 위치·크기 다름) 전처리 → 틀 7개(정상 3, 검사합 틀림, 범위 밖, 잡음 뒤 정상)
python3 host/digit_client.py host/samples/*.pgm --frames "$b/frames.bin"
# ③ 같은 main.c를 PC에서 실행 (UART = 표준 입출력) → NPU 접근 기록
gcc -O2 -Wall -Wextra -Werror -Isw -I../ch22/sw -I../ch27/sw -I"$b" sw/main.c sw/proto.c host/uart_io_host.c \
  host/board_io_null.c ../ch22/sw/npu_drv.c ../ch22/host/npu_hal_trace.c -o "$b/fw"
NPU_TRACE="$b/trace.txt" "$b/fw" < "$b/frames.bin" > "$b/host_out.txt"
# ④ 기록을 20장 RTL에서 재생 → 보드 응답을 만들어 PC 기대와 비교
iverilog -g2012 -Wall -s tb_driver_replay -o "$b/sim" \
  ../ch01/rtl/mac_core.v ../ch04/rtl/bram_sync_buffer.v ../ch07/rtl/vector_dot_core.v ../ch16/rtl/npu_argmax.v \
  ../ch19/rtl/npu_tiled_784_npe.v ../ch20/rtl/npu_axi_lite.v ../ch22/tb/tb_driver_replay.sv
vvp -n "$b/sim" +TRACE="$b/trace.txt" +ACTUAL="$b/actual.txt" | grep -E '_PASS|FATAL'
python3 reference/check_replay.py "$b/actual.txt" "$b/host_out.txt" "$b/frames.bin.expect"
