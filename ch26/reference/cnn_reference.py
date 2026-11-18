#!/usr/bin/env python3
"""26장 기준 모델: 8×8 → 3×3 합성곱 4필터(ReLU·반올림 시프트·INT8 포화) → 2×2 최대 풀링 → Dense 36(64)→10 → argmax."""
from __future__ import annotations
import argparse
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "ch13" / "reference"), str(ROOT / "host_tools")]
from mnist8x8_reference import draw_digit, features            # noqa: E402
from p3_integer_reference import argmax_lowest, dot_signed, round_shift_away, sat_int8  # noqa: E402

SHIFT = 6


def conv(x, k, kb):
    out = []
    for f in range(4):
        for oy in range(6):
            for ox in range(6):
                win = [x[(oy + ky) * 8 + ox + kx] for ky in range(3) for kx in range(3)]
                out.append(sat_int8(round_shift_away(max(0, dot_signed(win, k[f]) + kb[f]), SHIFT)))
    return out


def pool(c):
    return [max(c[f * 36 + (2 * py + dy) * 6 + 2 * px + dx] for dy in (0, 1) for dx in (0, 1))
            for f in range(4) for py in range(3) for px in range(3)]


def infer(x, k, kb, w, b):
    p = pool(conv(x, k, kb))
    s = [dot_signed(p + [0] * 28, row) + bb for row, bb in zip(w, b)]
    return p, s, argmax_lowest(s)


def cases():
    rng = random.Random(2626)
    edges = [[-1, 0, 1, -2, 0, 2, -1, 0, 1], [-1, -2, -1, 0, 0, 0, 1, 2, 1],
             [0, 1, 0, 1, -4, 1, 0, 1, 0], [1, 1, 1, 1, 1, 1, 1, 1, 1]]    # 세로·가로 경계, 라플라시안, 평균
    out = []
    for d in range(10):
        x = features(draw_digit(d))
        k = edges if d < 5 else [[rng.randint(-20, 20) for _ in range(9)] for _ in range(4)]
        kb = [rng.randint(-200, 200) for _ in range(4)]
        w = [[rng.randint(-128, 127) for _ in range(64)] for _ in range(10)]   # 36~63번 가중치는 입력이 0이라 점수에 영향 없음
        b = [rng.randint(-5000, 5000) for _ in range(10)]
        out.append((f"digit_{d}", x, k, kb, w, b))
    x = features(draw_digit(8))
    out.append(("relu_zero", x, [[-10] * 9] * 4, [-1] * 4, [[1] * 64] * 10, list(range(10))))
    out.append(("saturate", [127] * 64, [[127] * 9] * 4, [0] * 4, [[1] * 64] * 10, [0] * 10))
    return out


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--out"); ap.add_argument("--actual")
    a = ap.parse_args()
    cs = cases()
    seen = {n: infer(x, k, kb, w, b) for n, x, k, kb, w, b in cs}
    assert not any(seen["relu_zero"][0]) and all(v == 127 for v in seen["saturate"][0])
    print(f"PYTHON_CNN_SELF_TEST_PASS cases={len(cs)} conv=6x6x4 pool=3x3x4 shift={SHIFT}")
    if a.out and not a.actual:
        with open(Path(a.out) / "vectors.txt", "w") as f:
            for n, (name, x, k, kb, w, b) in enumerate(cs):
                f.write(f"{n} {name}\n")
                for blk in ([x], k, [kb], w, [b]):
                    f.writelines(" ".join(map(str, r)) + "\n" for r in blk)
    if a.actual:
        got = {}
        for ln in open(a.actual):
            try:
                p = list(map(int, ln.split()))
            except ValueError:
                raise SystemExit(f"PYTHON_RTL_COMPARE_FAIL 정수가 아닌 RTL 출력: {ln[:60]}")
            got[p[0]] = p[1:]
        for n, (name, x, k, kb, w, b) in enumerate(cs):
            p, s, c = infer(x, k, kb, w, b)
            if got.get(n) != p + s + [c]:
                raise SystemExit(f"PYTHON_RTL_COMPARE_FAIL case={name}\n rtl={got.get(n)}\n py ={p + s + [c]}")
        print(f"PYTHON_RTL_COMPARE_PASS cases={len(cs)} pooled={36 * len(cs)} scores={10 * len(cs)}")


if __name__ == "__main__":
    main()
