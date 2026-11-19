#!/usr/bin/env python3
"""16장: 64→8→10 정수 MLP 기준모델·시험 명령 생성·RTL 결과 비교.

최종 점수는 host_tools의 mlp_64_8_10(x, w1, b1, w2, b2, shift), Class는 argmax_lowest.
진단용 은닉값은 같은 규칙 sat_int8(round_shift_away(max(0, dot_signed + b1), shift))을 함수 조합으로 계산해
mlp_64_8_10 출력과 일치하는지 교차 확인한다(계산 규칙 변경 없음).
명령: W L c a v / B L c v (L=0 1층, L=1 2층) / S shift / F x[64]
"""
import argparse
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from part03.host_tools.p3_integer_reference import (  # noqa: E402
    sat_int8, round_shift_away, dot_signed, argmax_lowest, mlp_64_8_10,
)

BIAS_MIN, BIAS_MAX = -(1 << 23), (1 << 23) - 1


def hidden_of(x, w1, b1, shift):
    return [sat_int8(round_shift_away(max(0, dot_signed(x, w) + b), shift)) for w, b in zip(w1, b1)]


def infer(x, w1, b1, w2, b2, shift):
    scores = mlp_64_8_10(x, w1, b1, w2, b2, shift)
    h = hidden_of(x, w1, b1, shift)
    assert scores == [dot_signed(h, w) + b for w, b in zip(w2, b2)]
    for s in scores:
        assert -(1 << 24) <= s < (1 << 24)
    return h, scores, argmax_lowest(scores)


def build_ops():
    rng = random.Random(1616)
    i8 = lambda: rng.randint(-128, 127)  # noqa: E731
    ops = []

    def load(w1f, b1f, w2f, b2f):
        for c in range(8):
            for a in range(64):
                ops.append(("W", 0, c, a, w1f(c, a)))
            ops.append(("B", 0, c, b1f(c)))
        for c in range(10):
            for a in range(8):
                ops.append(("W", 1, c, a, w2f(c, a)))
            ops.append(("B", 1, c, b2f(c)))

    def rand_x():
        return [i8() for _ in range(64)]

    # ① 무작위 모델, 여러 shift(0=포화 다수, 큰 shift=0 다수)
    load(lambda c, a: i8(), lambda c: rng.randint(-50000, 50000),
         lambda c, a: i8(), lambda c: rng.randint(-5000, 5000))
    # 첫 프레임을 같은 입력으로 2회: TB가 첫 프레임 2층 동작 중 1층 쓰기를 시도하므로
    # 차단이 실패하면 두 번째 결과가 달라진다(shift 12: 포화·0 아닌 은닉값 다수).
    x0 = rand_x()
    ops.append(("S", 12))
    ops.append(("F", x0))
    ops.append(("F", x0))
    for s in (0, 1, 4, 8, 14, 16, 20, 24, 31):
        ops.append(("S", s))
        ops.append(("F", rand_x()))
    # ② ReLU 경계: 은닉 c의 1층 점수를 Bias로 정확히 지정(-1, 0, 1, 254, 255, 256, 257, 큰 음수)
    #    W1=0이므로 점수 = Bias. shift=1: 1→1(0.5 반올림), 255→128→127 포화, 254→127
    load(lambda c, a: 0, lambda c: [-1, 0, 1, 254, 255, 256, 257, -(1 << 23)][c],
         lambda c, a: int(a == c % 8), lambda c: c)
    ops.append(("S", 1))
    ops.append(("F", rand_x()))
    ops.append(("S", 0))
    ops.append(("F", rand_x()))
    # ③ 2층 단독 최대·동점: 은닉 고정(W1=0, B1=200, shift=3 → 25), 2층 class 4·9 동점 → 4
    load(lambda c, a: 0, lambda c: 200,
         lambda c, a: 1 if c in (4, 9) else 0, lambda c: 0)
    ops.append(("S", 3))
    ops.append(("F", rand_x()))
    # ④ 전부 음수 출력: 은닉 모두 0 → 점수 = B2(전부 음수, class 6 최대)
    load(lambda c, a: -1, lambda c: -10, lambda c, a: i8(),
         lambda c: -100 + (90 if c == 6 else 0) - c)
    ops.append(("S", 0))
    ops.append(("F", [127] * 64))
    # ⑤ 무작위 모델 4개 × shift 무작위 3프레임
    for _ in range(4):
        load(lambda c, a: i8(), lambda c: rng.randint(BIAS_MIN, BIAS_MAX),
             lambda c, a: i8(), lambda c: rng.randint(BIAS_MIN, BIAS_MAX))
        for _ in range(3):
            ops.append(("S", rng.randint(6, 18)))
            ops.append(("F", rand_x()))
    return ops


def run_model(ops):
    w1 = [[None] * 64 for _ in range(8)]
    w2 = [[None] * 8 for _ in range(10)]
    b1, b2 = [0] * 8, [0] * 10
    shift, out = 0, []
    for op in ops:
        if op[0] == "W":
            _, layer, c, a, v = op
            (w1 if layer == 0 else w2)[c][a] = v
        elif op[0] == "B":
            _, layer, c, v = op
            (b1 if layer == 0 else b2)[c] = v
        elif op[0] == "S":
            shift = op[1]
        else:
            out.append(infer(op[1], w1, b1, w2, b2, shift))
    return out


def selftest():
    x = [0] * 64
    w1 = [[0] * 64 for _ in range(8)]
    b1 = [-1, 0, 1, 254, 255, 256, 257, -(1 << 23)]
    assert hidden_of(x, w1, b1, 1) == [0, 0, 1, 127, 127, 127, 127, 0]
    assert hidden_of(x, w1, [3, 5, 6, 7, 2, 1, 0, 9], 2) == [1, 1, 2, 2, 1, 0, 0, 2]
    assert hidden_of(x, w1, [200] * 8, 3) == [25] * 8


def generate(out):
    selftest()
    ops = build_ops()
    results = run_model(ops)
    with (out / "ops.txt").open("w") as f:
        for op in ops:
            if op[0] == "W":
                f.write(f"W {op[1]} {op[2]} {op[3]} {op[4]}\n")
            elif op[0] == "B":
                f.write(f"B {op[1]} {op[2]} 0 {op[3]}\n")
            elif op[0] == "S":
                f.write(f"S 0 0 0 {op[1]}\n")
            else:
                f.write("F 0 0 0 0 " + " ".join(map(str, op[1])) + "\n")
        f.write("E 0 0 0 0\n")
    with (out / "expected.txt").open("w") as f:
        for h, scores, cls in results:
            f.write("H " + " ".join(map(str, h)) + " S " + " ".join(map(str, scores)) + f" C{cls}\n")
    print(f"PYTHON_MLP_SELF_TEST_PASS ops={len(ops)} frames={len(results)} seed=1616")


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
    print(f"PYTHON_RTL_COMPARE_PASS frames={len(exp)} hidden=8 scores=10 class=1 bit_exact=1")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--actual", type=Path)
    a = p.parse_args()
    if a.actual:
        compare(a.out, a.actual)
    else:
        generate(a.out)
