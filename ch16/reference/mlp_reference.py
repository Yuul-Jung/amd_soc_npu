#!/usr/bin/env python3
"""16장 기준 모델: 64→8(ReLU·반올림 시프트·INT8 포화)→10, argmax(동점은 낮은 번호).

최종 점수는 host_tools의 mlp_64_8_10, 은닉값은 같은 식(sat_int8·round_shift_away)으로 따로 계산해 비교한다.
"""
from __future__ import annotations
import argparse
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "ch13" / "reference"), str(ROOT / "host_tools"), str(ROOT / "ch15" / "reference")]
from mnist8x8_reference import draw_digit, features            # noqa: E402
from p3_integer_reference import argmax_lowest, dot_signed, mlp_64_8_10, round_shift_away, sat_int8  # noqa: E402
from dense_reference import model_sum                           # noqa: E402

SHIFT = 10


def hidden(x, w1, b1, shift=SHIFT):
    return [sat_int8(round_shift_away(max(0, dot_signed(x, w) + b), shift)) for w, b in zip(w1, b1)]


def cases():
    rng = random.Random(1616)
    out = []
    for k in range(8):
        x = features(draw_digit(k))
        w1 = [[rng.randint(-32, 32) for _ in range(64)] for _ in range(8)]
        b1 = [rng.randint(-4096, 4096) for _ in range(8)]
        w2 = [[rng.randint(-128, 127) for _ in range(8)] for _ in range(10)]
        b2 = [rng.randint(-2000, 2000) for _ in range(10)]
        out.append((f"digit_{k}", x, w1, b1, w2, b2))
    x = features(draw_digit(8))
    out.append(("saturate", x, [[127] * 64] * 4 + [[-128] * 64] * 4, [0] * 8,
                [[1] * 8] * 10, list(range(10))))
    out.append(("relu_all_zero", x, [[-5] * 64] * 8, [-1] * 8, [[3] * 8] * 10, [7] * 10))
    out.append(("round_half", [1] * 64, [[8] * 64] + [[0] * 64] * 7, [0] * 8,
                [[1] + [0] * 7] * 10, [0] * 10))
    return out


def selftest():
    cs = cases()
    seen_sat = seen_zero = False
    for name, x, w1, b1, w2, b2 in cs:
        h = hidden(x, w1, b1)
        s = mlp_64_8_10(x, w1, b1, w2, b2, SHIFT)
        assert s == [dot_signed(h, w) + b for w, b in zip(w2, b2)], name
        seen_sat |= any(abs(v) >= 127 for v in h); seen_zero |= not any(h)
    assert seen_sat and seen_zero
    assert hidden([1] * 64, [[8] * 64] + [[0] * 64] * 7, [0] * 8)[0] == 1   # 512/1024 = 0.5 → 1 (0에서 먼 쪽)
    print(f"PYTHON_MLP_SELF_TEST_PASS cases={len(cs)} shift={SHIFT} saturate=1 relu_zero=1 round_half=1")
    return cs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out"); ap.add_argument("--actual")
    a = ap.parse_args()
    cs = selftest()
    if a.out and not a.actual:
        with open(Path(a.out) / "vectors.txt", "w") as f:
            for n, (name, x, w1, b1, w2, b2) in enumerate(cs):
                f.write(f"{n} {name}\n" + " ".join(map(str, x)) + "\n")
                for blk in (w1, [b1], w2, [b2]):
                    f.writelines(" ".join(map(str, r)) + "\n" for r in blk)
    if a.actual:
        rows = {int(p[0]): [int(v) for v in p[1:]] for p in (ln.split() for ln in open(a.actual))}
        for n, (name, x, w1, b1, w2, b2) in enumerate(cs):
            s = mlp_64_8_10(x, w1, b1, w2, b2, SHIFT)
            sat = int(any(round_shift_away(max(0, dot_signed(x, w) + b), SHIFT) > 127 for w, b in zip(w1, b1)))
            want = hidden(x, w1, b1) + s + [argmax_lowest(s), sat, (model_sum(w1, b1) + model_sum(w2, b2)) & 0xFFFFFFFF]
            if rows.get(n) != want:
                raise SystemExit(f"PYTHON_RTL_COMPARE_FAIL case={name}\n rtl={rows.get(n)}\n py ={want}")
        print(f"PYTHON_RTL_COMPARE_PASS cases={len(cs)} hidden={8 * len(cs)} scores={10 * len(cs)} classes={len(cs)}")


if __name__ == "__main__":
    main()
