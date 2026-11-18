#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export PYTHONDONTWRITEBYTECODE=1
b=$(mktemp -d /tmp/p3-23.XXXXXXXX)
gcc --version | sed -n 1p; clang --version | sed -n 1p
python3 ../ch22/reference/gen_model_header.py --n 20 --out "$b/model_int8.h"
# ① 보드용 소스 교차 컴파일 (BSP 대역 헤더)
for f in sw/cpu_infer.c sw/bench.c; do
  clang --target=riscv32-unknown-elf -march=rv32imc -O2 -Wall -Wextra -Werror -ffreestanding \
    -Isw -I../ch22/sw -I../ch22/host/bsp_stub -I"$b" -c "$f" -o "$b/$(basename "$f" .c).o"
done
echo "RV32IMC_COMPILE_PASS files=2"
# ② cpu_infer를 PC에서 20장 실행 → 18장 기준 모델과 비교 (형식이 19장 비교와 같다)
gcc -O2 -Wall -Wextra -Werror -Isw -I"$b" host/test_cpu_infer.c sw/cpu_infer.c -o "$b/t"
"$b/t" > "$b/cpu.txt"
python3 - "$b/cpu.txt" <<'PY'
import sys
sys.path.insert(0, "../ch18/reference")
from precision_rtl import load, scores
from p3_integer_reference import argmax_lowest
w, b, cases = load(8)
rows = [list(map(int, l.split())) for l in open(sys.argv[1])]
for (k, label, x), r in zip(cases, rows):
    s = scores(x, w, b)
    assert r == [k] + s + [argmax_lowest(s)], k
print(f"CPU_REF_PASS images={len(rows)} scores={10 * len(rows)} (C cpu_infer = Python 정수 기준)")
PY
# ③ CPU 클록 추정 (보드 측정 전)
python3 reference/estimate.py
