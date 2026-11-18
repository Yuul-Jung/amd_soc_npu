#!/usr/bin/env python3
"""15장 기준 모델: Dense N_IN→N_OUT 점수 = 내적 + Bias, 적재 검증합 = Σ가중치 + ΣBias (mod 2^32).

64→10은 host_tools의 linear_64x10, 64→8·8→10(16장용)은 같은 dot_signed로 계산한다.
"""
from __future__ import annotations
import argparse
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "ch13" / "reference"), str(ROOT / "host_tools")]
from mnist8x8_reference import draw_digit, features   # noqa: E402
from p3_integer_reference import dot_signed, linear_64x10  # noqa: E402

CONFIGS = [(64, 10), (64, 8), (8, 10)]
BIAS_LIMIT = 1 << 24


def dense(x: list[int], w: list[list[int]], b: list[int]) -> list[int]:
    if len(x) == 64 and len(w) == 10:
        return linear_64x10(x, w, b)
    return [dot_signed(x, row) + bias for row, bias in zip(w, b)]


def model_sum(w: list[list[int]], b: list[int]) -> int:
    return (sum(map(sum, w)) + sum(b)) & 0xFFFFFFFF


def cases(n_in: int, n_out: int) -> list:
    rng = random.Random(1500 + 100 * n_in + n_out)
    out = []
    for k in range(6):
        if n_in == 64:
            x = features(draw_digit(k))
        else:  # 16장 은닉층 출력 범위 (INT8, ReLU 뒤라 0 이상이지만 부호 검사를 위해 음수도 섞음)
            x = [rng.randint(-128, 127) for _ in range(n_in)]
        w = [[rng.randint(-128, 127) for _ in range(n_in)] for _ in range(n_out)]
        b = [rng.randint(-BIAS_LIMIT, BIAS_LIMIT) for _ in range(n_out)]
        out.append((f"random_{k}", x, w, b))
    ext = 127 if n_in == 64 else -128
    out.append(("extreme", [ext] * n_in, [[-128] * n_in for _ in range(n_out)], [BIAS_LIMIT] * n_out))
    return out


def selftest() -> None:
    for n_in, n_out in CONFIGS:
        for name, x, w, b in cases(n_in, n_out):
            s = dense(x, w, b)
            assert len(s) == n_out and all(-(1 << 31) <= v < (1 << 31) for v in s), (n_in, n_out, name)
    x = [1] * 8
    assert dense(x, [[1] * 8] * 10, [0] * 10) == [8] * 10
    print(f"PYTHON_DENSE_SELF_TEST_PASS configs={'/'.join(f'{a}x{b}' for a, b in CONFIGS)} cases_each=7")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cfg", help="N_IN,N_OUT")
    ap.add_argument("--out", help="vectors.txt 파일 경로")
    ap.add_argument("--actual", help="RTL actual.txt (Python 값과 비교)")
    a = ap.parse_args()
    if not a.cfg:
        selftest()
        return
    n_in, n_out = map(int, a.cfg.split(","))
    cs = cases(n_in, n_out)
    if a.out:
        with open(a.out, "w") as f:
            for n, (name, x, w, b) in enumerate(cs):
                f.write(f"{n} {name}\n" + " ".join(map(str, x)) + "\n")
                f.writelines(" ".join(map(str, row)) + "\n" for row in w)
                f.write(" ".join(map(str, b)) + "\n")
    if a.actual:
        rows = {int(p[0]): [int(v) for v in p[1:]] for p in (ln.split() for ln in open(a.actual))}
        for n, (name, x, w, b) in enumerate(cs):
            want = dense(x, w, b) + [model_sum(w, b)]
            if rows.get(n) != want:
                raise SystemExit(f"PYTHON_RTL_COMPARE_FAIL cfg={n_in}x{n_out} case={name} rtl={rows.get(n)} python={want}")
        print(f"PYTHON_RTL_COMPARE_PASS cfg={n_in}x{n_out} cases={len(cs)} scores={n_out * len(cs)} model_sum=ok")


if __name__ == "__main__":
    main()
