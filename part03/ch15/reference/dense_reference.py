#!/usr/bin/env python3
"""15장: 정수 Dense 계층(64→10, 64→8, 8→10) 기준모델·시험 명령 생성·RTL 결과 비교.

점수 = dot_signed(x, W[c]) + bias[c], Class = argmax_lowest (host_tools 규칙 그대로).
64→10은 linear_64x10 결과와 동일함을 함께 확인한다.
명령: W c a v (가중치 쓰기) / B c v (Bias 쓰기) / F x... (프레임 입력 후 추론)
모델은 명령 사이에 유지된다(부분 갱신·다중 프레임 검증).
"""
import argparse
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from part03.host_tools.p3_integer_reference import (  # noqa: E402
    dot_signed, linear_64x10, argmax_lowest,
)

BIAS_MIN, BIAS_MAX = -(1 << 23), (1 << 23) - 1


def dense(x, w, b):
    scores = [dot_signed(x, row) + bias for row, bias in zip(w, b)]
    if len(x) == 64 and len(w) == 10:
        assert scores == linear_64x10(x, w, b)
    for s in scores:
        assert -(1 << 24) <= s < (1 << 24), "score exceeds 25-bit contract"
    return scores


def build_ops(n_in, n_out, seed):
    rng = random.Random(seed)
    i8 = lambda: rng.randint(-128, 127)  # noqa: E731
    ops = []

    def full_model(wfun, bfun):
        for c in range(n_out):
            for a in range(n_in):
                ops.append(("W", c, a, wfun(c, a)))
        for c in range(n_out):
            ops.append(("B", c, bfun(c)))

    def frame(xs=None):
        ops.append(("F", xs if xs is not None else [i8() for _ in range(n_in)]))

    # ① 무작위 모델 1회 적재 후 4프레임(모델 유지)
    full_model(lambda c, a: i8(), lambda c: rng.randint(BIAS_MIN, BIAS_MAX))
    for _ in range(4):
        frame()
    # ② 부분 갱신: 가중치 5개 + Bias 1개, 같은 주소 2회 쓰기(마지막 값 유효)
    for _ in range(5):
        ops.append(("W", rng.randrange(n_out), rng.randrange(n_in), i8()))
    ops.append(("W", n_out - 1, n_in - 1, 77))
    ops.append(("W", n_out - 1, n_in - 1, -77))
    ops.append(("B", rng.randrange(n_out), rng.randint(BIAS_MIN, BIAS_MAX)))
    frame()
    frame()
    # ③ Bias만 전부 갱신
    for c in range(n_out):
        ops.append(("B", c, rng.randint(-1000, 1000)))
    frame()
    # ④ 극값: W=-128, x=-128 / x=127, Bias 극값 교대
    full_model(lambda c, a: -128, lambda c: BIAS_MAX if c % 2 else BIAS_MIN)
    frame([-128] * n_in)
    frame([127] * n_in)
    # ⑤ 부호 혼합 누산: 짝수 class W=+127, 홀수 class W=-128, x 부호 교대
    full_model(lambda c, a: 127 if c % 2 == 0 else -128, lambda c: 0)
    frame([127 if a % 2 == 0 else -128 for a in range(n_in)])
    # ⑥ 새 무작위 모델 5개 × 2프레임
    for _ in range(5):
        full_model(lambda c, a: i8(), lambda c: rng.randint(BIAS_MIN, BIAS_MAX))
        frame()
        frame()
    return ops


def run_model(ops, n_in, n_out):
    w = [[None] * n_in for _ in range(n_out)]
    b = [0] * n_out  # RTL Bias는 Reset 시 0
    out = []
    for op in ops:
        if op[0] == "W":
            _, c, a, v = op
            w[c][a] = v
        elif op[0] == "B":
            _, c, v = op
            b[c] = v
        else:
            assert all(v is not None for row in w for v in row), "weights not fully loaded"
            scores = dense(op[1], w, b)
            out.append((scores, argmax_lowest(scores)))
    return out


def selftest():
    assert dense([1, -2], [[3, 4], [-1, -1]], [10, -10]) == [5, -9]
    x = [i - 32 for i in range(64)]
    w = [[int(j == i) for j in range(64)] for i in range(10)]
    assert dense(x, w, [0] * 10) == [-32 + i for i in range(10)]
    ops = [("W", 0, 0, 2), ("W", 1, 0, 3), ("F", [5]), ("W", 1, 0, -3), ("B", 0, 1), ("F", [5])]
    assert run_model(ops, 1, 2) == [([10, 15], 1), ([11, -15], 0)]


def generate(out, n_in, n_out):
    selftest()
    ops = build_ops(n_in, n_out, seed=1500 + n_in * 16 + n_out)
    results = run_model(ops, n_in, n_out)
    with (out / "ops.txt").open("w") as f:
        for op in ops:
            if op[0] == "W":
                f.write(f"W {op[1]} {op[2]} {op[3]}\n")
            elif op[0] == "B":
                f.write(f"B {op[1]} 0 {op[2]}\n")
            else:
                padded = op[1] + [0] * (64 - n_in)  # 13장 프레임은 항상 64원소
                f.write("F 0 0 0 " + " ".join(map(str, padded)) + "\n")
        f.write("E 0 0 0\n")
    with (out / "expected.txt").open("w") as f:
        for scores, cls in results:
            f.write(" ".join(map(str, scores)) + f" C{cls}\n")
    print(f"PYTHON_DENSE_SELF_TEST_PASS shape={n_in}x{n_out} ops={len(ops)} frames={len(results)}")


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
    print(f"PYTHON_RTL_COMPARE_PASS frames={len(exp)} bit_exact=1")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--in-len", type=int, default=64)
    p.add_argument("--out-n", type=int, default=10)
    p.add_argument("--actual", type=Path)
    a = p.parse_args()
    if a.actual:
        compare(a.out, a.actual)
    else:
        generate(a.out, a.in_len, a.out_n)
