#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export PYTHONDONTWRITEBYTECODE=1
b=$(mktemp -d /tmp/p3-22.XXXXXXXX)
iverilog -V 2>&1 | sed -n 1p; gcc --version | sed -n 1p; clang --version | sed -n 1p
python3 reference/gen_model_header.py --n 5 --out "$b/model_int8.h"
# ① 보드용 소스를 RV32IMC로 교차 컴파일 (BSP 대역 헤더, 경고도 오류로)
for f in sw/npu_drv.c sw/npu_hal_mbv.c sw/main.c; do
  clang --target=riscv32-unknown-elf -march=rv32imc -O2 -Wall -Wextra -Werror -ffreestanding \
    -Isw -Ihost/bsp_stub -I"$b" -c "$f" -o "$b/$(basename "$f" .c).o"
done
echo "RV32IMC_COMPILE_PASS files=3"
# ② 오류 경로 PC 시험 (가짜 NPU)
gcc -O2 -Wall -Wextra -Werror -Isw host/test_driver.c sw/npu_drv.c host/npu_hal_fake.c -o "$b/test_driver"
"$b/test_driver"
# ③ 같은 main.c를 PC에서 돌려 레지스터 접근 기록 → 20장 RTL에서 재생 → Python 비교
gcc -O2 -Wall -Wextra -Werror -DNPU_HOST -Isw -I"$b" sw/main.c sw/npu_drv.c host/npu_hal_trace.c -o "$b/main_host"
NPU_TRACE="$b/trace.txt" "$b/main_host" > /dev/null
echo "DRIVER_TRACE ops=$(wc -l < "$b/trace.txt") writes=$(grep -c '^W' "$b/trace.txt") polls=$(grep -c '^P' "$b/trace.txt")"
iverilog -g2012 -Wall -s tb_driver_replay -o "$b/sim" \
  ../ch01/rtl/mac_core.v ../ch04/rtl/bram_sync_buffer.v ../ch07/rtl/vector_dot_core.v ../ch16/rtl/npu_argmax.v \
  ../ch19/rtl/npu_tiled_784_npe.v ../ch20/rtl/npu_axi_lite.v tb/tb_driver_replay.sv
vvp -n "$b/sim" +TRACE="$b/trace.txt" +ACTUAL="$b/actual.txt"
python3 reference/trace_check.py "$b/actual.txt" 5
