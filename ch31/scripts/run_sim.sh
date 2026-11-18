#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export PYTHONDONTWRITEBYTECODE=1
b=$(mktemp -d /tmp/p3-31.XXXXXXXX)
gcc --version | sed -n 1p; clang --version | sed -n 1p
# ① C 암호 함수: 공개 시험 벡터
gcc -O2 -Wall -Wextra -Werror -Isw host/test_vectors.c sw/crypto_min.c -o "$b/tv" && "$b/tv"
# ② 보드용 C를 RV32IMC로 교차 컴파일 (보드에서 돌린다는 뜻은 아님)
for f in sw/crypto_min.c sw/secure_rx.c; do
  clang --target=riscv32-unknown-elf -march=rv32imc -O2 -Wall -Wextra -Werror -ffreestanding -Isw -c "$f" -o "$b/$(basename "$f" .c).o"
done
echo "RV32IMC_COMPILE_PASS files=2"
# ③ PC(파이썬)가 만든 틀 → C 수신기 판정 → 기대와 비교
python3 host/secure_frame.py --scenario "$b/frames.bin"
gcc -O2 -Wall -Wextra -Werror -Isw host/run_frames.c sw/secure_rx.c sw/crypto_min.c -o "$b/rx"
"$b/rx" "$b/frames.bin" > "$b/got.txt"
paste -d'|' "$b/got.txt" "$b/frames.bin.expect" | awk -F'|' '{printf "FRAME %2d %-28s %s\n", NR, $1, ($1==$2?"OK":"DIFF expected " $2)}'
if cmp -s "$b/got.txt" "$b/frames.bin.expect"; then echo "SECURE_RX_HOST_PASS frames=$(wc -l < "$b/got.txt")"; else echo "SECURE_RX_HOST_FAIL"; exit 1; fi
