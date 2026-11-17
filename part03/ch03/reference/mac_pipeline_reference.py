#!/usr/bin/env python3
"""P3-03 대기 큐 모델: 입력 수락 에지와 출력 에지를 분리한다."""
import argparse
import csv
import random
import sys
from collections import deque
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "ch01" / "reference"))
from mac_reference import compare, wrap


class PipelineReference:
    def __init__(self, acc_width):
        self.acc_width = acc_width
        self.pending = deque()
        self.product = 0
        self.acc = 0
        self.edge = 0

    def tick(self, resetn, clear, valid, a, b):
        self.edge += 1
        source_edge = 0
        out_valid = 0
        if not resetn or clear:
            self.pending.clear()
            self.product = 0
            self.acc = 0
        else:
            # 먼저 이전 입력을 배출한 다음 현재 입력을 큐에 넣는다.
            if self.pending:
                product, source_edge = self.pending.popleft()
                if source_edge != self.edge - 1:
                    raise AssertionError("Pipeline latency must be one edge")
                self.acc = wrap(self.acc + product, self.acc_width)
                out_valid = 1
            if valid:
                self.product = a * b
                self.pending.append((self.product, self.edge))
        return self.product, int(bool(self.pending)), self.acc, out_valid, source_edge


def self_test():
    for aw in (32, 40):
        m = PipelineReference(aw)
        assert m.tick(0, 0, 1, 3, 4) == (0, 0, 0, 0, 0)
        assert m.tick(1, 0, 1, 3, 4) == (12, 1, 0, 0, 0)
        assert m.tick(1, 0, 1, 3, -4) == (-12, 1, 12, 1, 2)
        assert m.tick(1, 0, 0, 9, 9) == (-12, 0, 0, 1, 3)
        assert m.tick(1, 0, 0, 9, 9) == (-12, 0, 0, 0, 0)
        assert m.tick(1, 0, 1, -3, -4) == (12, 1, 0, 0, 0)
        assert m.tick(1, 1, 1, 9, 9) == (0, 0, 0, 0, 0)
        assert m.tick(1, 0, 0, 9, 9) == (0, 0, 0, 0, 0)
        m.tick(1, 0, 1, 9, 9)
        assert m.tick(0, 1, 1, 9, 9) == (0, 0, 0, 0, 0)
        assert m.tick(1, 0, 0, 9, 9) == (0, 0, 0, 0, 0)
    print("PYTHON_PIPELINE_SELF_TEST_PASS ACC=32,40")


def stimulus(dw, aw):
    lo, hi = -(1 << (dw - 1)), (1 << (dw - 1)) - 1
    yield (0, 0, 0, 0, 0)
    for a, b in ((3, 4), (3, -4), (-3, -4)):
        yield (1, 0, 1, a, b)
    yield (1, 0, 0, hi, hi)
    yield (1, 0, 0, lo, lo)
    for a, b in ((0, lo), (lo, lo), (lo, hi), (hi, lo), (hi, hi)):
        yield (1, 0, 1, a, b)
    yield (1, 0, 0, 0, 0)
    yield (1, 1, 0, 0, 0)
    yield (1, 0, 1, 7, 9)
    yield (1, 1, 1, hi, hi)  # 계류 곱과 동시 입력을 모두 취소
    yield (1, 0, 0, 1, 1)
    yield (1, 0, 0, 1, 1)
    yield (1, 0, 1, -2, 3)   # Clear 직후 정상 회복과 단발 Valid
    yield (1, 0, 0, 1, 1)
    yield (1, 0, 0, 1, 1)
    yield (1, 0, 1, 6, 7)
    yield (0, 1, 1, hi, hi)  # Reset > Clear > Valid 및 계류 곱 취소
    yield (1, 0, 0, 1, 1)
    yield (1, 0, 1, 6, 7)
    yield (0, 0, 1, hi, hi)  # Reset 단독으로도 파이프라인 취소
    yield (1, 0, 0, 1, 1)
    yield (1, 0, 0, 1, 1)
    yield (1, 1, 0, 0, 0)
    # 실제 입력을 누적해 양의 오버플로로 min 도달 후 min-1=max를 시험한다.
    for _ in range(1 << (aw - 2 * dw + 1)):
        yield (1, 0, 1, lo, lo)
    yield (1, 0, 0, 0, 0)  # 마지막 곱 배출 → 누산 min
    yield (1, 0, 1, -1, 1)
    yield (1, 0, 0, 0, 0)  # min-1 배출 → max
    yield (1, 0, 0, 0, 0)
    rng = random.Random(30300 + dw)
    for _ in range(2000):
        yield (int(rng.randrange(43) != 0), int(rng.randrange(29) == 0),
               int(rng.randrange(4) != 0), rng.randint(lo, hi), rng.randint(lo, hi))
    yield (1, 0, 0, 0, 0)
    yield (1, 0, 0, 0, 0)


def generate(dw, aw, vector_path, expected_path, timing_path):
    model = PipelineReference(aw)
    counts = dict(clear_pending=0, reset_pending=0, bubble_drain=0,
                  positive_wrap=0, negative_wrap=0)
    with vector_path.open("w") as vf, expected_path.open("w") as ef, timing_path.open("w") as tf:
        timing = csv.writer(tf, lineterminator="\n")
        timing.writerow(("edge", "resetn", "clear_i", "valid_i", "accepted_edge", "a_i", "b_i", "product_q",
                         "product_valid_q", "output_source_edge", "output_edge", "acc_o", "valid_o"))
        for edge, row in enumerate(stimulus(dw, aw), 1):
            rn, clear, valid, a, b = row
            if model.pending:
                if not rn:
                    counts["reset_pending"] += 1
                elif clear:
                    counts["clear_pending"] += 1
                else:
                    raw = model.acc + model.pending[0][0]
                    counts["positive_wrap"] += int(raw >= (1 << (aw-1)))
                    counts["negative_wrap"] += int(raw < -(1 << (aw-1)))
                    counts["bubble_drain"] += int(not valid)
            pq, pv, acc, out_valid, source = model.tick(*row)
            vf.write(" ".join(map(str, (*row, pq, pv, acc, out_valid))) + "\n")
            ef.write(f"{edge} {pq} {pv} {acc} {out_valid}\n")
            if edge <= 28:
                timing.writerow((edge, rn, clear, valid, edge if rn and not clear and valid else "-", a, b,
                                 pq, pv, source or "-", edge if out_valid else "-", acc, out_valid))
    if model.pending or not all(counts.values()):
        raise AssertionError(f"Missing directed coverage or final drain: {counts}")
    print(f"PYTHON_VECTORS INT{dw}/{aw} cycles={edge} seed={30300+dw}")
    print("SCENARIO_COUNTS " + " ".join(f"{key}={value}" for key, value in counts.items()))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-width", type=int, default=16)
    parser.add_argument("--acc-width", type=int, default=40)
    parser.add_argument("--vectors", type=Path)
    parser.add_argument("--expected", type=Path, required=True)
    parser.add_argument("--actual", type=Path)
    parser.add_argument("--timing", type=Path)
    args = parser.parse_args()
    if (args.data_width, args.acc_width) not in ((16, 40), (8, 32)):
        parser.error("This test generator supports 16/40 and 8/32")
    if bool(args.vectors) == bool(args.actual) or (args.vectors and not args.timing):
        parser.error("Use --actual or --vectors with --timing")
    self_test()
    if args.actual:
        compare(args.expected, args.actual)
    else:
        generate(args.data_width, args.acc_width, args.vectors, args.expected, args.timing)
