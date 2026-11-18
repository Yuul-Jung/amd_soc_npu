#!/usr/bin/env python3
"""P3-01 독립 정수 모델, 재현 가능한 자극 생성 및 RTL 전 사이클 대조."""
import argparse
import random
from pathlib import Path


def wrap(value, width):
    """Python 무제한 정수를 signed 2의 보수 범위로 변환한다."""
    modulus = 1 << width
    return (value + modulus // 2) % modulus - modulus // 2


def step(acc, resetn, clear, valid, a, b, acc_width):
    if not resetn or clear:
        return 0, 0
    return (wrap(acc + a * b, acc_width), 1) if valid else (acc, 0)


def self_test():
    # 별도의 상수 정답으로 산술/제어 및 각 설정의 양·음 오버플로를 검증한다.
    for dw, aw in ((8, 32), (16, 40)):
        maximum = (1 << (aw - 1)) - 1
        minimum = -(1 << (aw - 1))
        assert step(0, 1, 0, 1, 3, 4, aw) == (12, 1)
        assert step(0, 1, 0, 1, 3, -4, aw) == (-12, 1)
        assert step(0, 1, 0, 1, -3, -4, aw) == (12, 1)
        assert step(maximum, 1, 0, 1, 1, 1, aw) == (minimum, 1)
        assert step(minimum, 1, 0, 1, 1, -1, aw) == (maximum, 1)
        assert step(7, 1, 0, 0, 3, 4, aw) == (7, 0)
        assert step(7, 1, 1, 1, 3, 4, aw) == (0, 0)
        assert step(7, 0, 1, 1, 3, 4, aw) == (0, 0)
        assert wrap((-(1 << (dw - 1))) ** 2, aw) == 1 << (2 * dw - 2)
    print("PYTHON_SELF_TEST_PASS configurations=INT8/32,INT16/40")


def stimulus(dw, aw):
    lo, hi = -(1 << (dw - 1)), (1 << (dw - 1)) - 1
    yield (0, 0, 1, hi, lo)
    yield (0, 1, 1, lo, lo)
    yield (1, 0, 0, 0, 0)
    # 부호 조합, 0, 입력 경계, 연속 valid 및 idle.
    for a, b in ((3, 4), (3, -4), (-3, -4), (hi, hi),
                 (lo, lo), (lo, hi), (hi, lo), (0, lo), (-1, -1)):
        yield (1, 0, 1, a, b)
    for _ in range(4):
        yield (1, 0, 0, hi, hi)
    yield (1, 1, 1, hi, hi)
    yield (1, 1, 0, lo, lo)
    # 내부 레지스터 force 없이 실제 포트로 최댓값에 도달한다.
    target = (1 << (aw - 1)) - 1
    count, remainder = divmod(target, lo * lo)
    for _ in range(count):
        yield (1, 0, 1, lo, lo)
    count, remainder = divmod(remainder, hi)
    for _ in range(count):
        yield (1, 0, 1, hi, 1)
    if remainder:
        yield (1, 0, 1, remainder, 1)
    yield (1, 0, 0, hi, hi)  # 최댓값 유지
    yield (1, 0, 1, 1, 1)    # max + 1 -> min
    yield (1, 0, 0, hi, hi)  # 최솟값 유지
    yield (1, 0, 1, -1, 1)   # min - 1 -> max
    yield (0, 1, 1, lo, hi)  # Reset/Clear/Valid 동시 입력
    rng = random.Random(301 + dw)
    for _ in range(2000):
        yield (int(rng.randrange(53) != 0), int(rng.randrange(29) == 0),
               int(rng.randrange(4) != 0), rng.randint(lo, hi), rng.randint(lo, hi))
    yield (1, 0, 0, 0, 0)


def generate(dw, aw, vectors, expected):
    acc = 0
    count = 0
    with vectors.open("w") as vf, expected.open("w") as ef:
        for count, row in enumerate(stimulus(dw, aw), 1):
            acc, valid = step(acc, *row, aw)
            vf.write(" ".join(map(str, (*row, acc, valid))) + "\n")
            ef.write(f"{count} {acc} {valid}\n")
    print(f"PYTHON_VECTORS INT{dw}/{aw} cycles={count} seed={301 + dw}")


def compare(expected, actual):
    # 길이도 비교하여 조기 종료/누락 행이 PASS가 되지 않게 한다.
    from itertools import zip_longest
    count = 0
    with expected.open() as ef, actual.open() as af:
        for count, (e, a) in enumerate(zip_longest(ef, af), 1):
            if e is None or a is None or e.split() != a.split():
                raise AssertionError(f"cycle={count}: expected={e!r}, actual={a!r}")
    if count == 0:
        raise AssertionError("Empty comparison")
    print(f"PYTHON_RTL_COMPARE_PASS cycles={count}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-width", type=int, default=16)
    parser.add_argument("--acc-width", type=int, default=40)
    parser.add_argument("--vectors", type=Path)
    parser.add_argument("--expected", type=Path)
    parser.add_argument("--actual", type=Path)
    args = parser.parse_args()
    if args.data_width < 2 or args.acc_width < 2 * args.data_width:
        parser.error("Require DATA_WIDTH>=2 and ACC_WIDTH>=2*DATA_WIDTH")
    self_test()
    if args.actual:
        compare(args.expected, args.actual)
    elif args.vectors:
        generate(args.data_width, args.acc_width, args.vectors, args.expected)
