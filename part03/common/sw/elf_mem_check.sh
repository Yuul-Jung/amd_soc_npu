#!/usr/bin/env bash
# 6-5: MicroBlaze V ELF 메모리 배치 검사. .stack ≥ 4096(p3_stack_4k.c 적용)이고 스택 끝이 LMB 64 KB 안이어야 PASS.
# 사용: elf_mem_check.sh <elf>   (Vitis settings를 source한 셸에서)
set -euo pipefail
elf=$1
size=$(command -v riscv32-xilinx-elf-size || find "${XILINX_VITIS:-/tools/Xilinx/Vitis/2024.2}/gnu/riscv" -name riscv32-xilinx-elf-size | head -1)
read -r stack addr < <("$size" -A "$elf" | awk '$1==".stack"{print $2, $3}')
heap=$("$size" -A "$elf" | awk '$1==".heap"{print $2}')
end=$((addr + stack))
echo "ELF_MEM stack=$stack heap=$heap stack_end=$end lmb=65536"
[[ $stack -ge 4096 && $end -le 65536 ]] && echo "ELF_MEM_PASS" || { echo "ELF_MEM_FAIL"; exit 1; }
