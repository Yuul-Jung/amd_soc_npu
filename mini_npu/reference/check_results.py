#!/usr/bin/env python3
"""12장: HDL이 기록한 실제 예측 CSV를 독립 정수 정답과 비교한다."""
import csv
import sys
from pathlib import Path


def expected_row(scenario):
    s = scenario if scenario < 4 else 0
    x = (-1 if s & 2 else 1, -1 if s & 1 else 1)
    values = []
    for lane in range(4):
        w = (-1 if lane & 2 else 1, -1 if lane & 1 else 1)
        dot = x[0] * w[0] + x[1] * w[1]
        values.append(dot + (10 if scenario == 5 and lane == 3 else 0))
    best = max(range(4), key=lambda k: (values[k], -k))
    return [scenario, best, *values]


def main():
    path = Path(sys.argv[1])
    short = "--short" in sys.argv[2:]          # 타이밍 시뮬레이션 짧은 시나리오: 0번 분류 + Bias 변경 뒤(5번)
    with path.open(newline="", encoding="utf-8") as stream:
        reader = csv.reader(stream)
        assert next(reader) == [
            "scenario", "class", "score0", "score1", "score2", "score3"
        ]
        rows = [[int(v) for v in row] for row in reader]
    expected = [expected_row(s) for s in ((0, 5) if short else range(6))]
    if rows != expected:
        for got, want in zip(rows, expected):
            if got != want:
                print(f"FAIL scenario {want[0]}: got={got} expected={want}")
        if len(rows) != len(expected):
            print(f"FAIL rows={len(rows)} expected={len(expected)}")
        raise SystemExit("GOLDEN_COMPARE_FAIL")
    print(f"PC_GOLDEN_COMPARE_PASS predictions={len(expected)} model_edit=1")


if __name__ == "__main__":
    main()
