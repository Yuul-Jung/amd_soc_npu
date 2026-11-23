#!/usr/bin/env python3
"""4PE 3그룹(4+4+2) 10분류 코어 기준모델·시험 벡터 생성·RTL 결과 비교.

점수와 Class는 host_tools/p3_integer_reference.py의 linear_64x10, argmax_lowest로 계산한다.
그룹 스케줄(class = 4*group + lane, group 2는 lane 0·1만 유효)은 group_schedule()로 별도 확인한다.
"""
import argparse
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from part03.host_tools.p3_integer_reference import linear_64x10, argmax_lowest  # noqa: E402

BIAS_MIN, BIAS_MAX = -(1 << 23), (1 << 23) - 1


def group_schedule():
    """(group, lane, class) 목록. 유효 차선만 포함한다."""
    return [(g, l, 4 * g + l) for g in range(3) for l in range(4) if 4 * g + l < 10]


def expected(x, w, b):
    for v in x + [e for row in w for e in row]:
        if not -128 <= v <= 127:
            raise ValueError("x/w must be INT8")
    for v in b:
        if not BIAS_MIN <= v <= BIAS_MAX:
            raise ValueError("bias must be signed 24-bit")
    scores = linear_64x10(x, w, b)
    for s in scores:
        assert -(1 << 24) <= s < (1 << 24), "score exceeds 25-bit contract"
    return scores, argmax_lowest(scores)


def onehot(c, i):
    return int(c == i)


def build_cases():
    rng = random.Random(1414)
    ramp = [i - 32 for i in range(64)]
    cases = []
    # ① class 매핑: W[c][c]=1 → score[c] = x[c] = c-32 (+bias c*1000)
    cases.append((ramp, [[onehot(c, i) for i in range(64)] for c in range(10)],
                  [c * 1000 for c in range(10)]))
    # ② 모든 점수 음수: 무효 차선(점수 0)이 섞이면 class가 틀어진다
    cases.append(([1] * 64, [[-1 - c] * 64 for c in range(10)], [0] * 10))
    # ③ 그룹 경계 동점: class 3과 7, 8이 같은 최대값 → 3
    w = [[0] * 64 for _ in range(10)]
    b = [-5, -4, -3, 50, -9, 0, 1, 50, 50, -50]
    cases.append(([0] * 64, w, b))
    # ④ 마지막 유효 차선(class 9)만 최대
    b = [-(1 << 23)] * 9 + [-(1 << 23) + 1]
    cases.append(([0] * 64, [[0] * 64 for _ in range(10)], b))
    # ⑤ 누산 극값: (-128)*(-128)*64 = 1048576, (-128)*127*64 = -1040384, Bias 극값
    w = [[-128] * 64 if c % 2 == 0 else [127] * 64 for c in range(10)]
    b = [BIAS_MAX, BIAS_MIN, 0, 0, BIAS_MAX, BIAS_MIN, -1, 1, BIAS_MAX, BIAS_MIN]
    cases.append(([-128] * 64, w, b))
    cases.append(([127] * 64, w, b))
    # ⑥ 무작위 30개
    for _ in range(30):
        x = [rng.randint(-128, 127) for _ in range(64)]
        w = [[rng.randint(-128, 127) for _ in range(64)] for _ in range(10)]
        b = [rng.randint(BIAS_MIN, BIAS_MAX) for _ in range(10)]
        cases.append((x, w, b))
    # 4-4 argmax 트리: 각 비교 단의 동점(lane 쌍 0·1, 2·3, 그룹 1의 4·5, 6·7, 그룹 2의 8·9) → 낮은 번호
    z = [[0] * 64 for _ in range(10)]
    for pair in ((0, 1), (2, 3), (4, 5), (6, 7), (8, 9)):
        b = [-100 - c for c in range(10)]
        b[pair[0]] = b[pair[1]] = 77
        cases.append(([0] * 64, z, b))
    return cases


def selftest():
    sched = group_schedule()
    assert [c for _, _, c in sched] == list(range(10))
    assert [len([s for s in sched if s[0] == g]) for g in range(3)] == [4, 4, 2]
    s, c = expected([1] * 64, [[-1 - k] * 64 for k in range(10)], [0] * 10)
    assert c == 0 and max(s) < 0
    s, c = expected([0] * 64, [[0] * 64] * 10, [-5, -4, -3, 50, -9, 0, 1, 50, 50, -50])
    assert c == 3
    try:
        expected([0] * 64, [[0] * 64] * 10, [1 << 23] + [0] * 9)
    except ValueError:
        pass
    else:
        raise AssertionError("bias range check missing")


def generate(out):
    selftest()
    cases = build_cases()
    with (out / "vectors.txt").open("w") as vf, (out / "expected.txt").open("w") as ef:
        vf.write(f"{len(cases)}\n")
        for x, w, b in cases:
            scores, cls = expected(x, w, b)
            vf.write(" ".join(map(str, x)) + "\n")
            for row in w:
                vf.write(" ".join(map(str, row)) + "\n")
            vf.write(" ".join(map(str, b)) + "\n")
            ef.write(" ".join(map(str, scores)) + f" C{cls}\n")
    print(f"PYTHON_GROUP10_SELF_TEST_PASS cases={len(cases)} groups=4+4+2 seed=1414")


def compare(out, actual):
    exp = (out / "expected.txt").read_text().splitlines()
    got = actual.read_text().splitlines()
    if exp != got:
        for i, (e, g) in enumerate(zip(exp, got)):
            if e != g:
                print(f"FAIL case {i}:\n  expected={e}\n  got     ={g}")
                break
        print(f"cases expected={len(exp)} got={len(got)}")
        raise SystemExit("PYTHON_RTL_COMPARE_FAIL")
    print(f"PYTHON_RTL_COMPARE_PASS cases={len(exp)} scores=10 class=1 bit_exact=1")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--actual", type=Path)
    a = p.parse_args()
    if a.actual:
        compare(a.out, a.actual)
    else:
        generate(a.out)
