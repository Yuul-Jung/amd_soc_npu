#!/usr/bin/env python3
"""8×8·3×3 합성곱(Cross-Correlation, stride 1, padding 0)+Bias+ReLU 기준모델·시험 벡터·RTL 비교.

창마다 host_tools의 dot_signed로 9항 내적을 구한다. 출력 6×6을 행 우선으로 비교한다.
"""
import argparse
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from part03.host_tools.p3_integer_reference import dot_signed  # noqa: E402

B_MIN, B_MAX = -(1 << 23), (1 << 23) - 1


def conv3x3(img, k, b, relu):
    """img 8×8, k 3×3 → 6×6 (행 우선 36개)."""
    flat_k = [k[i][j] for i in range(3) for j in range(3)]
    out = []
    for r in range(6):
        for c in range(6):
            win = [img[r + i][c + j] for i in range(3) for j in range(3)]
            s = dot_signed(win, flat_k) + b
            out.append(max(0, s) if relu else s)
    for v in out:
        assert -(1 << 24) <= v < (1 << 24)
    return out


def cases(rng):
    spec_img = [[r * 8 + c for c in range(8)] for r in range(8)]
    spec_k = [[1, 0, -1]] * 3
    cs = [(spec_img, spec_k, 0, 0), (spec_img, spec_k, 0, 1)]
    ramp = [[(r * 8 + c) - 32 for c in range(8)] for r in range(8)]
    for pos in range(9):                                      # 창 위치 판별: one-hot 커널
        k = [[1 if 3 * i + j == pos else 0 for j in range(3)] for i in range(3)]
        cs.append((ramp, k, 0, 0))
    cs.append(([[-128] * 8] * 8, [[-128] * 3] * 3, B_MAX, 0))   # 9·16384 + 최대 Bias
    cs.append(([[-128] * 8] * 8, [[127] * 3] * 3, B_MIN, 0))    # 최소 방향
    cs.append(([[127] * 8] * 8, [[-128] * 3] * 3, 5, 1))        # 전부 음수 → ReLU 0
    for _ in range(12):
        cs.append(([[rng.randint(-128, 127) for _ in range(8)] for _ in range(8)],
                   [[rng.randint(-128, 127) for _ in range(3)] for _ in range(3)],
                   rng.randint(B_MIN, B_MAX) >> rng.randint(0, 16), rng.randint(0, 1)))
    return cs


def selftest():
    img = [[r * 8 + c for c in range(8)] for r in range(8)]
    out = conv3x3(img, [[1, 0, -1]] * 3, 0, 0)
    assert len(out) == 36 and out[0] == -6                    # 규격 예제
    assert sum(1 for _ in range(6) for _ in range(6)) * 9 == 324   # 필터 1개 324 MAC
    ident = [[0, 0, 0], [0, 1, 0], [0, 0, 0]]
    assert conv3x3(img, ident, 0, 0) == [img[r + 1][c + 1] for r in range(6) for c in range(6)]


def generate(out):
    selftest()
    cs = cases(random.Random(2626))
    with (out / "vectors.txt").open("w") as vf, (out / "expected.txt").open("w") as ef:
        vf.write(f"{len(cs)}\n")
        for img, k, b, relu in cs:
            vf.write(f"{relu} {b} " + " ".join(str(k[i][j]) for i in range(3) for j in range(3)) + " "
                     + " ".join(str(img[r][c]) for r in range(8) for c in range(8)) + "\n")
            ef.write(" ".join(map(str, conv3x3(img, k, b, relu))) + "\n")
    print(f"PYTHON_CONV_SELF_TEST_PASS frames={len(cs)} out=6x6 macs_per_frame=324 first_spec=-6 seed=2626")


def compare(out, actual):
    exp = (out / "expected.txt").read_text().splitlines()
    got = actual.read_text().splitlines()
    if exp != got:
        for i, (e, g) in enumerate(zip(exp, got)):
            if e != g:
                print(f"FAIL frame {i}:\n  expected={e}\n  got     ={g}")
                break
        print(f"frames expected={len(exp)} got={len(got)}")
        raise SystemExit("PYTHON_RTL_COMPARE_FAIL")
    print(f"PYTHON_RTL_COMPARE_PASS frames={len(exp)} outputs={36 * len(exp)} bit_exact=1")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--actual", type=Path)
    a = p.parse_args()
    if a.actual:
        compare(a.out, a.actual)
    else:
        generate(a.out)
