#!/usr/bin/env python3
"""19장 기준 모델: 18장 INT8 실제 MNIST 모델로 1·2·4·8PE 결과가 같은지 보고, 측정 사이클을 식으로 설명한다.

사이클 식 (파형에서 읽은 구조): 원소 1개 = READ·WAIT_READ·SEND 3클록, 타일·그룹 1회 = 3·len + A, 마무리 = B
  cycles(NPE) = G · Σ_t (3·len_t + A) + B,  G = ceil(10 / NPE),  len = 64 × 12 + 16
A·B는 4PE·8PE 측정값 두 개로 구하고, 1PE·2PE 측정값을 예측해 맞는지 확인한다.
"""
from __future__ import annotations
import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "ch18" / "reference"))
from precision_rtl import load, scores                   # noqa: E402
from p3_integer_reference import argmax_lowest            # noqa: E402

CASES = 5
LENS = [64] * 12 + [16]


def groups(npe):
    return -(-10 // npe)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out"); ap.add_argument("--npe", type=int); ap.add_argument("--actual")
    ap.add_argument("--cycles", nargs="*", help="NPE=cycles 목록 (사이클 식 확인)")
    a = ap.parse_args()
    w, b, cases = load(8)
    cases = cases[:CASES]
    if a.out:
        with open(a.out, "w") as f:
            f.writelines(" ".join(map(str, r)) + "\n" for r in w)
            f.write(" ".join(map(str, b)) + "\n")
            for k, label, x in cases:
                f.write(f"{k} {label} " + " ".join(map(str, x)) + "\n")
    if a.actual:
        seen = 0
        for ln in open(a.actual):
            try:
                p = list(map(int, ln.split()))
            except ValueError:
                raise SystemExit(f"PYTHON_RTL_COMPARE_FAIL 정수가 아닌 RTL 출력: {ln[:80]}")
            k = p[0]; s = scores(cases[k][2], w, b)
            if p[1:] != s + [argmax_lowest(s)]:
                raise SystemExit(f"PYTHON_RTL_COMPARE_FAIL npe={a.npe} case={k}")
            seen += 1
        if seen == 0:
            raise SystemExit("PYTHON_RTL_COMPARE_FAIL RTL 결과 없음")
        print(f"PYTHON_RTL_COMPARE_PASS npe={a.npe} cases={seen} scores={10 * seen}")
    if a.cycles:
        meas = {int(k): int(v) for k, v in (c.split("=") for c in a.cycles)}
        base = sum(3 * n for n in LENS)                   # 그룹 1회의 원소 클록 합
        # 4PE·8PE로 A·B 구하기: c = G·(base + 13·A) + B
        g4, g8 = groups(4), groups(8)
        a13 = (meas[4] - meas[8]) // (g4 - g8) - base     # 13·A
        A, B = a13 // 13, meas[4] - g4 * (base + a13)
        assert a13 % 13 == 0, a13
        for npe, c in sorted(meas.items()):
            pred = groups(npe) * (base + 13 * A) + B
            print(f"CYCLES npe={npe} groups={groups(npe)} measured={c} formula={pred} speedup_vs_1pe={meas[1] / c:.2f}")
            if pred != c:
                raise SystemExit(f"CYCLE_MODEL_FAIL npe={npe}")
        print(f"CYCLE_MODEL_PASS A={A} B={B} element=3clk")


if __name__ == "__main__":
    main()
