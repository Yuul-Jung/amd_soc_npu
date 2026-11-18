#!/usr/bin/env python3
"""18장 RTL 비교용 기준 모델: ch18/model/의 정수 모델(INT8·INT16)과 MNIST 시험 앞 20장으로 정수 점수·클래스를 계산한다.

모델 파일은 precision_pc.py --export가 실제 MNIST로 학습·양자화해 만든 것이며, RTL 시뮬레이션은 이 파일만 읽는다(내려받기 없음).
"""
from __future__ import annotations
import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "host_tools"))
from p3_integer_reference import argmax_lowest, dot_tiled_64  # noqa: E402

MODEL = ROOT / "ch18" / "model"


def load(bits):
    rows = [list(map(int, ln.split())) for ln in open(MODEL / f"model_int{bits}.txt")]
    cases = []
    for ln in open(MODEL / f"cases_int{bits}.txt"):
        p = list(map(int, ln.split()))
        cases.append((p[0], p[1], p[2:]))
    return rows[:10], rows[10], cases


def scores(x, w, b):
    return [dot_tiled_64(x, row) + bb for row, bb in zip(w, b)]


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--bits", type=int, required=True)
    ap.add_argument("--out"); ap.add_argument("--actual")
    a = ap.parse_args()
    w, b, cases = load(a.bits)
    lim = (1 << (a.bits - 1))
    assert len(w) == 10 and all(len(r) == 784 and all(-lim <= v < lim for v in r) for r in w)
    assert all(len(x) == 784 and all(0 <= v < lim for v in x) for _, _, x in cases)
    if a.out:
        with open(a.out, "w") as f:
            f.writelines(" ".join(map(str, r)) + "\n" for r in w)
            f.write(" ".join(map(str, b)) + "\n")
            for k, label, x in cases:
                f.write(f"{k} {label} " + " ".join(map(str, x)) + "\n")
        print(f"PYTHON_PRECISION_VECTORS int{a.bits} cases={len(cases)}")
    if a.actual:
        got = {}
        for ln in open(a.actual):
            try:
                p = list(map(int, ln.split()))
            except ValueError:
                raise SystemExit(f"PYTHON_RTL_COMPARE_FAIL 정수가 아닌 RTL 출력: {ln[:80]}")
            got[p[0]] = p[1:]
        right = 0
        for k, label, x in cases:
            s = scores(x, w, b)
            if got.get(k) != s + [argmax_lowest(s)]:
                raise SystemExit(f"PYTHON_RTL_COMPARE_FAIL int{a.bits} case={k} rtl={got.get(k)} py={s}")
            right += argmax_lowest(s) == label
        print(f"PYTHON_RTL_COMPARE_PASS int{a.bits} cases={len(cases)} scores={10 * len(cases)} correct={right}/{len(cases)}")


if __name__ == "__main__":
    main()
