#!/usr/bin/env python3
"""제3부 13~19/28장: PC 정수 기준모델. RTL 동작 검증 결과와 별개."""
from __future__ import annotations


def sat_int8(value: int) -> int:
    """부호 있는 INT8 범위 [-128, 127]로 포화한다."""
    return max(-128, min(127, value))


def round_shift_away(value: int, shift: int) -> int:
    """2**shift로 나눈 뒤 절반은 0에서 먼 쪽으로 반올림한다."""
    if shift < 0:
        raise ValueError("shift must be >= 0")
    if shift == 0:
        return value
    magnitude = (abs(value) + (1 << (shift - 1))) >> shift
    return -magnitude if value < 0 else magnitude


def dot_signed(x: list[int], w: list[int]) -> int:
    if len(x) != len(w):
        raise ValueError("vector lengths must match")
    return sum(a * b for a, b in zip(x, w))


def dot_tiled_64(x: list[int], w: list[int]) -> int:
    """최대 64원소씩 처리해 부분 누산을 결합한다."""
    if len(x) != len(w):
        raise ValueError("vector lengths must match")
    return sum(dot_signed(x[i:i + 64], w[i:i + 64])
               for i in range(0, len(x), 64))


def argmax_lowest(scores: list[int]) -> int:
    if not scores:
        raise ValueError("scores must not be empty")
    return max(range(len(scores)), key=lambda i: (scores[i], -i))


def linear_64x10(x: list[int], w: list[list[int]], b: list[int]) -> list[int]:
    if len(x) != 64 or len(w) != 10 or len(b) != 10:
        raise ValueError("require 64 inputs, 10 neurons, 10 biases")
    if any(len(row) != 64 for row in w):
        raise ValueError("each weight row must contain 64 values")
    return [dot_signed(x, row) + bias for row, bias in zip(w, b)]


def mlp_64_8_10(x: list[int], w1: list[list[int]], b1: list[int],
                w2: list[list[int]], b2: list[int], shift: int) -> list[int]:
    if len(x) != 64 or len(w1) != 8 or len(b1) != 8:
        raise ValueError("first layer shape must be 64 -> 8")
    if any(len(row) != 64 for row in w1):
        raise ValueError("first layer weight width must be 64")
    if len(w2) != 10 or len(b2) != 10 or any(len(row) != 8 for row in w2):
        raise ValueError("second layer shape must be 8 -> 10")
    hidden = [sat_int8(round_shift_away(max(0, dot_signed(x, w) + b), shift))
              for w, b in zip(w1, b1)]
    return [dot_signed(hidden, w) + b for w, b in zip(w2, b2)]


def selftest() -> None:
    assert [round_shift_away(x, 1) for x in (-5, -3, -1, 0, 1, 3, 5)] == \
           [-3, -2, -1, 0, 1, 2, 3]
    assert sat_int8(999) == 127 and sat_int8(-999) == -128
    assert argmax_lowest([-3, 2, 2, -1]) == 1
    x = [((i * 7) % 255) - 127 for i in range(784)]
    w = [((i * 11) % 255) - 127 for i in range(784)]
    assert dot_tiled_64(x, w) == dot_signed(x, w)
    assert len([x[i:i + 64] for i in range(0, len(x), 64)]) == 13
    x64 = [1] * 64
    w64 = [[1 if j == i else 0 for j in range(64)] for i in range(10)]
    assert linear_64x10(x64, w64, [0] * 10) == [1] * 10
    w1 = [[1 if j == i else 0 for j in range(64)] for i in range(8)]
    w2 = [[1 if j == (i % 8) else 0 for j in range(8)] for i in range(10)]
    assert mlp_64_8_10(x64, w1, [0] * 8, w2, [0] * 10, 0) == [1] * 10
    try:
        linear_64x10(x64, [[0] * 63] * 10, [0] * 10)
    except ValueError:
        pass
    else:
        raise AssertionError("shape validation missing")
    print("P3_INTEGER_REFERENCE_HOST_PASS cases=9")


if __name__ == "__main__":
    selftest()
