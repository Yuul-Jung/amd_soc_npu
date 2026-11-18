#!/usr/bin/env python3
"""14장 기준 모델: 64원소 × 10클래스 점수 = 내적 + Bias, 동점이면 낮은 번호 argmax.

전처리는 13장 features(), 점수·argmax는 host_tools/p3_integer_reference.py를 그대로 가져다 쓴다.
"""
from __future__ import annotations
import argparse
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "ch13" / "reference"), str(ROOT / "host_tools")]
from mnist8x8_reference import draw_digit, features          # noqa: E402  13장 입력 계약
from p3_integer_reference import argmax_lowest, linear_64x10  # noqa: E402  공통 정수 기준

BIAS_LIMIT = 1 << 24       # |Bias| 상한: 점수가 32비트 안에 남게 한다 (|내적| ≤ 64·127·128)


def template_weights(xs: list[list[int]]) -> tuple[list[list[int]], list[int]]:
    """최근접 형판 분류: |x - t|²가 가장 작은 t는 x·t - |t|²/2가 가장 크다.
    가중치 = 숫자별 특징(0~127, INT8 범위), Bias = -|t|²/2 (학습 아님, 형태 대조용)."""
    return [list(x) for x in xs], [-(sum(v * v for v in x) // 2) for x in xs]


def cases() -> list[tuple[str, list[int], list[list[int]], list[int]]]:
    xs = [features(draw_digit(d)) for d in range(10)]
    tw, tb = template_weights(xs)
    out = [(f"template_{d}", xs[d], tw, tb) for d in range(10)]
    rng = random.Random(1414)
    for k in range(10):                                   # 무작위 가중치·Bias (부호 섞임)
        w = [[rng.randint(-128, 127) for _ in range(64)] for _ in range(10)]
        b = [rng.randint(-BIAS_LIMIT, BIAS_LIMIT) for _ in range(10)]
        out.append((f"random_{k}", xs[k], w, b))
    out.append(("tie_all", xs[3], [[1] * 64] * 10, [5] * 10))            # 전부 동점 → 0
    out.append(("tie_8_9", xs[1], [[0] * 64] * 10, [0] * 8 + [9, 9]))     # 8·9 동점 → 8
    out.append(("all_negative", xs[8], [[-128] * 64] * 10, [-10 * c for c in range(10)][::-1]))
    out.append(("lane9_wins", [127] * 64, [[-1] * 64] * 9 + [[127] * 64], [0] * 10))
    return out


def selftest() -> list:
    cs = cases()
    for name, x, w, b in cs:
        s = linear_64x10(x, w, b)
        assert all(-(1 << 31) <= v < (1 << 31) for v in s), name
    got = [argmax_lowest(linear_64x10(x, w, b)) for _, x, w, b in cs[:10]]
    assert got == list(range(10)), got                     # 형태 대조로 0~9가 한 번씩 나온다
    by = {n: argmax_lowest(linear_64x10(x, w, b)) for n, x, w, b in cs}
    assert by["tie_all"] == 0 and by["tie_8_9"] == 8 and by["all_negative"] == 9 and by["lane9_wins"] == 9
    print(f"PYTHON_GROUP10_SELF_TEST_PASS cases={len(cs)} template_classes=0..9 ties=2")
    return cs


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", help="vectors.txt를 쓸 폴더")
    ap.add_argument("--actual", help="RTL 결과 actual.txt (Python 값과 비교)")
    a = ap.parse_args()
    cs = selftest()
    if a.out and not a.actual:
        with open(Path(a.out) / "vectors.txt", "w") as f:
            for n, (name, x, w, b) in enumerate(cs):
                s = linear_64x10(x, w, b)
                f.write(f"{n} {argmax_lowest(s)} {name}\n")
                f.write(" ".join(map(str, x)) + "\n")
                for row in w:
                    f.write(" ".join(map(str, row)) + "\n")
                f.write(" ".join(map(str, b)) + "\n")
    if a.actual:
        rows = {}
        for ln in open(a.actual):
            p = ln.split()
            rows[int(p[0])] = (int(p[1]), [int(v) for v in p[2:12]], int(p[12]))
        for n, (name, x, w, b) in enumerate(cs):
            s = linear_64x10(x, w, b)
            if rows.get(n, (None, None, 0))[:2] != (argmax_lowest(s), s):
                raise SystemExit(f"PYTHON_RTL_COMPARE_FAIL case={name} rtl={rows.get(n)} python={argmax_lowest(s)} {s}")
        cyc = sorted({r[2] for r in rows.values()})
        print(f"PYTHON_RTL_COMPARE_PASS cases={len(cs)} scores={10 * len(cs)} cycles_per_inference={','.join(map(str, cyc))}")


if __name__ == "__main__":
    main()
