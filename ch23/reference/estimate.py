#!/usr/bin/env python3
"""23장 추정: cpu_infer.c를 RV32IMC -O2로 컴파일해 안쪽 반복의 명령 수를 세고, CPU 클록을 CPI 가정별로 추정한다.
NPU 쪽은 19·22장 시뮬레이션 값(코어 7,185클록)과 AXI 쓰기 횟수(입력 784번)를 쓴다.
보드에서 bench.c로 잰 값이 나오기 전까지 모든 CPU 숫자는 '추정'이다."""
from __future__ import annotations
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]


def inner_loop_len(obj):
    dis = subprocess.run(["llvm-objdump", "-d", "--no-show-raw-insn", obj], capture_output=True, text=True, check=True).stdout
    lines = [ln for ln in dis.splitlines() if re.match(r"\s+[0-9a-f]+:\s", ln)]
    addr = [int(ln.split(":")[0], 16) for ln in lines]
    best = None
    for k, ln in enumerate(lines):                       # 뒤로 가는 분기 = 반복의 끝, 가장 짧은 반복 = 안쪽 반복
        m = re.search(r"\s(b\w+)\s.*?0x([0-9a-f]+)\s*<", ln)
        if m:
            tgt = int(m.group(2), 16)
            if tgt < addr[k]:
                body = [x for x in lines if tgt <= int(x.split(":")[0], 16) <= addr[k]]
                if best is None or len(body) < len(best):
                    best = body
    return best


def main():
    with tempfile.TemporaryDirectory() as d:
        obj = f"{d}/cpu_infer.elf"         # 분기 목적지를 풀기 위해 링크까지 한다 (진입점 = cpu_infer)
        subprocess.run(["clang", "--target=riscv32-unknown-elf", "-march=rv32imc", "-O2", "-nostdlib", "-fuse-ld=lld",
                        "-Wl,--entry=cpu_infer", str(HERE / "sw" / "cpu_infer.c"), "-I", str(HERE / "sw"), "-o", obj], check=True)
        body = inner_loop_len(obj)
    n = len(body)
    ops = ", ".join(re.split(r"\s+", b.split(":", 1)[1].strip())[0] for b in body)
    macs = 784 * 10
    print(f"CPU_INNER_LOOP instructions={n} ({ops})")
    for cpi in (1.0, 1.5, 2.0):
        print(f"ESTIMATE cpu_clk cpi={cpi} ≈ {int(macs * n * cpi):,} (= 7,840 MAC × {n}명령 × CPI, 바깥 반복 제외)")
    print("MEASURED_SIM npu_core_clk=7185 (19장 NPE=4) · npu_load = AXI 쓰기 784번 + 제어 (버스 클록은 보드 측정)")
    print(f"ESTIMATE speedup_core_only cpi=1 ≈ {macs * n / 7185:.1f}x (입력 적재 시간 제외)")
    print("CPU_ESTIMATE_DONE (보드 측정 전 추정)")


if __name__ == "__main__":
    main()
