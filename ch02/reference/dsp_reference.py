#!/usr/bin/env python3
"""P3-02 signed 곱 기준 모델. P3-01의 누산/제어 모델과 trace 비교를 재사용한다."""
import argparse
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "ch01" / "reference"))
from mac_reference import compare, self_test, step, stimulus


def vectors(a_width, b_width, acc_width):
    # 대칭 INT16/INT8은 기존 누산 오버플로 자극도 그대로 사용한다.
    if a_width == b_width:
        yield from stimulus(a_width, acc_width)
    else:
        yield (0, 1, 1, 1, -1)
        yield (1, 0, 0, 0, 0)
    amin, amax = -(1 << (a_width - 1)), (1 << (a_width - 1)) - 1
    bmin, bmax = -(1 << (b_width - 1)), (1 << (b_width - 1)) - 1
    yield (1, 1, 1, amax, bmax)
    for a in (amin, amin + 1, -1, 0, 1, amax - 1, amax):
        for b in (bmin, bmin + 1, -1, 0, 1, bmax - 1, bmax):
            yield (1, 0, 1, a, b)
    # INT8의 65536개 입력 쌍은 전수 대조한다(제어 상태 전수 검증은 아님).
    if (a_width, b_width) == (8, 8):
        for a in range(amin, amax + 1):
            for b in range(bmin, bmax + 1):
                yield (1, 0, 1, a, b)
    rng = random.Random(a_width * 1000 + b_width)
    for _ in range(2000):
        yield (int(rng.randrange(43) != 0), int(rng.randrange(31) == 0),
               int(rng.randrange(4) != 0), rng.randint(amin, amax), rng.randint(bmin, bmax))
    yield (0, 0, 1, amin, bmax)
    yield (0, 1, 1, amin, bmin)
    yield (1, 0, 1, amax, bmin)
    yield (1, 0, 0, amin, bmax)
    yield (1, 1, 0, 1, 1)
    yield (1, 0, 0, 0, 0)


def generate(a_width, b_width, acc_width, vector_path, expected_path):
    product, acc = 0, 0
    count = 0
    with vector_path.open("w") as vf, expected_path.open("w") as ef:
        for count, row in enumerate(vectors(a_width, b_width, acc_width), 1):
            rn, clear, valid, a, b = row
            if not rn or clear:
                product = 0
            elif valid:
                product = a * b  # Python의 무제한 정수 곱, RTL 폭 변환에 의존하지 않는다.
            acc, out_valid = step(acc, *row, acc_width)
            if not -(1 << (a_width+b_width-1)) <= product < (1 << (a_width+b_width-1)):
                raise AssertionError("Product outside full signed result width")
            vf.write(" ".join(map(str, (*row, product, acc, out_valid))) + "\n")
            ef.write(f"{count} {product} {acc} {out_valid}\n")
    print(f"PYTHON_VECTORS A={a_width} B={b_width} ACC={acc_width} cycles={count}")


def product_self_test():
    assert (-32768) * (-32768) == 1073741824
    assert (-32768) * 32767 == -1073709056
    assert (-128) * (-128) == 16384
    assert (-16777216) * (-131072) == 2199023255552
    assert 16777215 * (-131072) == -2199023124480
    print("PYTHON_PRODUCT_SELF_TEST_PASS INT16,INT8,native25x18")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--a-width", type=int, default=16)
    parser.add_argument("--b-width", type=int, default=16)
    parser.add_argument("--acc-width", type=int, default=40)
    parser.add_argument("--vectors", type=Path)
    parser.add_argument("--expected", type=Path, required=True)
    parser.add_argument("--actual", type=Path)
    args = parser.parse_args()
    # TB는 P3-01 MAC 입력 폭을 두 입력 중 큰 폭으로 맞춰 비교한다.
    if not (2 <= args.a_width <= 25 and 2 <= args.b_width <= 18
            and 2 * max(args.a_width, args.b_width) <= args.acc_width <= 56):
        parser.error("Unsupported DSP input or TB accumulator width")
    if bool(args.vectors) == bool(args.actual):
        parser.error("Select exactly one of --vectors and --actual")
    product_self_test()
    self_test()
    if args.actual:
        compare(args.expected, args.actual)
    else:
        generate(args.a_width, args.b_width, args.acc_width, args.vectors, args.expected)
