#!/usr/bin/env python3
"""13~19/28장 호스트 정수 기준모델의 독립 unittest. FPGA 검증과 별개."""
import random
import unittest

from part03.host_tools.p3_integer_reference import (
    sat_int8, round_shift_away, dot_signed, dot_tiled_64,
    argmax_lowest, linear_64x10, mlp_64_8_10,
)


class TestP3IntegerReference(unittest.TestCase):
    def test_rounding_ties_away_from_zero(self):
        values = [-7, -5, -3, -1, 0, 1, 3, 5, 7]
        expect = [-4, -3, -2, -1, 0, 1, 2, 3, 4]
        self.assertEqual([round_shift_away(x, 1) for x in values], expect)
        self.assertEqual(round_shift_away(-13, 0), -13)
        with self.assertRaises(ValueError):
            round_shift_away(1, -1)

    def test_int8_saturation(self):
        self.assertEqual([sat_int8(x) for x in (-129, -128, 0, 127, 128)],
                         [-128, -128, 0, 127, 127])

    def test_argmax_signed_tie_and_empty(self):
        self.assertEqual(argmax_lowest([-4, -1, -1, -9]), 1)
        self.assertEqual(argmax_lowest([-3, -2, -5, -1, -4, -7, -1, -8, -6, -9]), 3)
        with self.assertRaises(ValueError):
            argmax_lowest([])

    def test_tiled_dot_including_remainder(self):
        rng = random.Random(20261117)
        for n in (0, 1, 63, 64, 65, 127, 128, 784):
            x = [rng.randint(-128, 127) for _ in range(n)]
            w = [rng.randint(-128, 127) for _ in range(n)]
            self.assertEqual(dot_tiled_64(x, w), dot_signed(x, w))
        with self.assertRaises(ValueError):
            dot_tiled_64([1], [1, 2])

    def test_linear_64x10_exact_scores(self):
        x = [i - 32 for i in range(64)]
        w = [[int(j == i) for j in range(64)] for i in range(10)]
        b = list(range(10))
        self.assertEqual(
            linear_64x10(x, w, b),
            [-32 + 2 * i for i in range(10)]
        )

    def test_linear_shape_rejected(self):
        with self.assertRaises(ValueError):
            linear_64x10([0] * 63, [[0] * 64 for _ in range(10)], [0] * 10)
        with self.assertRaises(ValueError):
            linear_64x10([0] * 64, [[0] * 63 for _ in range(10)], [0] * 10)

    def test_mlp_two_layers_relu_and_bias(self):
        x = [-20, 4] + [0] * 62
        w1 = [[int(j == i) for j in range(64)] for i in range(8)]
        w2 = [[int(j == (i % 8)) for j in range(8)] for i in range(10)]
        y = mlp_64_8_10(x, w1, [0] * 8, w2, [0] * 10, 0)
        self.assertEqual(y, [0, 4, 0, 0, 0, 0, 0, 0, 0, 4])

    def test_mlp_invalid_shape_rejected(self):
        x = [0] * 64
        w1 = [[0] * 64 for _ in range(8)]
        w2 = [[0] * 8 for _ in range(10)]
        with self.assertRaises(ValueError):
            mlp_64_8_10(x, w1, [0] * 8, w2[:-1], [0] * 10, 0)


if __name__ == "__main__":
    unittest.main()
