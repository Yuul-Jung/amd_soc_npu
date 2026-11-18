#!/usr/bin/env python3
"""17장: 784입력 13타일 외부 부분합 누산 기준모델·시험 벡터 생성·RTL 결과 비교.

타일 부분합은 host_tools의 dot_signed, 784 전체는 dot_tiled_64·dot_signed로 계산해 교차 확인한다.
Bias는 13타일 누산을 마친 뒤 클래스별로 1회만 더한다. 외부 누산 폭(acc_w)이 부족하면
RTL과 같은 2의 보수 순환값과 overflow 플래그를 기대값으로 만든다(폭 검증용).
"""
import argparse
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from part03.host_tools.p3_integer_reference import (  # noqa: E402
    argmax_lowest, dot_signed, dot_tiled_64,
)

N_IN, TILE, N_CLASS = 784, 64, 10
N_TILE = (N_IN + TILE - 1) // TILE          # 13
LAST_LEN = N_IN - TILE * (N_TILE - 1)       # 16
CORE_BIAS_W = 24                            # 14장 코어 Bias 폭(17장에서는 0으로 고정)


def core_part_w(data_w):
    """14장 코어 점수(부분합) 폭: INT8은 기존 25비트, 그 밖은 lane 누산 2N+6비트 + 1."""
    core_acc = 24 if data_w == 8 else 2 * data_w + 6
    return max(core_acc, CORE_BIAS_W) + 1


def tile_ranges():
    """(시작 주소, 유효 길이) 13개: 64×12 + 16."""
    return [(t * TILE, min(TILE, N_IN - t * TILE)) for t in range(N_TILE)]


def signed_bits(lo, hi):
    """lo..hi를 담는 최소 signed 비트 수."""
    n = 1
    while not (-(1 << (n - 1)) <= lo and hi <= (1 << (n - 1)) - 1):
        n += 1
    return n


def width_plan(data_w, bias_w):
    """signed data_w 입력·가중치, signed bias_w Bias일 때 필요한 폭."""
    lo, hi = -(1 << (data_w - 1)), (1 << (data_w - 1)) - 1
    p_max, p_min = lo * lo, lo * hi                  # 최대 양의 곱, 최소 음의 곱
    b_lo, b_hi = -(1 << (bias_w - 1)), (1 << (bias_w - 1)) - 1
    return {
        "tile": signed_bits(TILE * p_min, TILE * p_max),
        "acc": signed_bits(N_IN * p_min, N_IN * p_max),
        "score": signed_bits(N_IN * p_min + b_lo, N_IN * p_max + b_hi),
        "acc_max": N_IN * p_max,
        "score_max": N_IN * p_max + b_hi,
    }


def fits(v, w):
    return -(1 << (w - 1)) <= v <= (1 << (w - 1)) - 1


def wrap(v, w):
    v &= (1 << w) - 1
    return v - (1 << w) if v >> (w - 1) else v


def model(x, w, b, acc_w, bias_w, data_w=8):
    """반환: 타일별 부분합[13][10], 최종 점수[10], class, overflow."""
    assert len(x) == N_IN and len(w) == N_CLASS and len(b) == N_CLASS
    for v in x + [e for row in w for e in row]:
        if not fits(v, data_w):
            raise ValueError(f"x/w must be signed {data_w}-bit (14장 코어 DATA_W 계약)")
    for v in b:
        if not fits(v, bias_w):
            raise ValueError(f"bias must be signed {bias_w}-bit")
    parts = [[dot_signed(x[s:s + n], w[c][s:s + n]) for c in range(N_CLASS)]
             for s, n in tile_ranges()]
    for row in parts:
        for p in row:
            assert fits(p, width_plan(data_w, CORE_BIAS_W)["tile"]) and fits(p, core_part_w(data_w))
    acc, ovf = [0] * N_CLASS, False
    for row in parts:
        for c in range(N_CLASS):
            v = acc[c] + row[c]
            ovf |= not fits(v, acc_w)
            acc[c] = wrap(v, acc_w)
    full = [dot_tiled_64(x, w[c]) for c in range(N_CLASS)]
    assert full == [dot_signed(x, w[c]) for c in range(N_CLASS)]
    if not ovf:
        assert acc == full
    scores = [a + bias for a, bias in zip(acc, b)]   # Bias는 누산 완료 후 1회
    return parts, scores, argmax_lowest(scores), ovf


def build_cases(suite, bias_w, rng, data_w=8):
    b_lo, b_hi = -(1 << (bias_w - 1)), (1 << (bias_w - 1)) - 1
    lo, hi = -(1 << (data_w - 1)), (1 << (data_w - 1)) - 1

    def rand_case():
        return ([rng.randint(lo, hi) for _ in range(N_IN)],
                [[rng.randint(lo, hi) for _ in range(N_IN)] for _ in range(N_CLASS)],
                [rng.randint(b_lo, b_hi) for _ in range(N_CLASS)])

    # 짝수 class = 최대 양수 방향, 홀수 class = 최대 음수 방향 누산
    w_ext = [[lo] * N_IN if c % 2 == 0 else [hi] * N_IN for c in range(N_CLASS)]
    b_ext = [b_hi, b_lo, 0, 0, b_hi, b_lo, -1, 1, b_hi, b_lo]
    extremes = [([lo] * N_IN, w_ext, b_ext), ([hi] * N_IN, w_ext, b_ext)]
    if suite == "width":
        return extremes + [rand_case() for _ in range(2)]

    cases = [rand_case() for _ in range(3)]          # 0: 오류 주입, 1: Reset, 2: 취소
    cases += extremes                                # 3·4: 누산 극값 + Bias 극값
    # 5: 마지막 타일만 유효 데이터(앞 768개 x=0). 패딩·이전 타일 가중치가 섞이면 틀린다.
    x = [0] * 768 + [rng.choice([lo, hi, rng.randint(lo, hi)]) for _ in range(LAST_LEN)]
    cases.append((x, rand_case()[1], [0] * N_CLASS))
    # 6: 타일 위치 판별: class c는 타일 12-c에만 가중치 1, x = 타일번호+1
    x = [i // TILE + 1 for i in range(N_IN)]
    w = [[int(i // TILE == 12 - c) for i in range(N_IN)] for c in range(N_CLASS)]
    cases.append((x, w, [0] * N_CLASS))
    # 7: 전 점수 음수·타일 경계 class 동점(3·7 → 3)
    cases.append(([1] * N_IN, [[-1] * N_IN for _ in range(N_CLASS)],
                  [-9, -8, -7, -1, -6, -5, -4, -1, -3, -2]))
    # 8: x=0 → 점수 = Bias 그대로(13번 중복 적용이면 즉시 드러남)
    cases.append(([0] * N_IN, [[rng.randint(lo, hi) for _ in range(N_IN)]
                               for _ in range(N_CLASS)], b_ext))
    # 9: 작은 Bias 1000*(c+1): 타일마다 중복 적용되면 점수가 12000*(c+1)만큼 달라진다
    x = [rng.randint(-2, 2) for _ in range(N_IN)]
    w = [[rng.randint(-2, 2) for _ in range(N_IN)] for _ in range(N_CLASS)]
    cases.append((x, w, [1000 * (c + 1) for c in range(N_CLASS)]))
    cases += [rand_case() for _ in range(12)]
    # (추가) 19장 argmax 트리: 1단 쌍(0·1, 2·3)·2단(1 vs 2, 5 vs 6) 동점 → 낮은 번호. x=0이라 점수 = Bias
    z = [[0] * N_IN for _ in range(N_CLASS)]
    for tie in ((0, 1), (2, 3), (1, 2), (5, 6)):
        b = [-100 - c for c in range(N_CLASS)]
        b[tie[0]] = b[tie[1]] = 77
        cases.append(([0] * N_IN, z, b))
    return cases


def padding(rng, data_w=8):
    """마지막 타일 주소 16~63에 보내는 쓰레기 값(0이 아니어야 누락 검출 가능)."""
    lo, hi = -(1 << (data_w - 1)), (1 << (data_w - 1)) - 1
    return [rng.choice([lo, hi, 55, -77]) for _ in range(TILE - LAST_LEN)]


def selftest():
    assert [n for _, n in tile_ranges()] == [64] * 12 + [16]
    assert sum(n for _, n in tile_ranges()) == N_IN
    p8, p16 = width_plan(8, 24), width_plan(16, 40)
    assert (p8["tile"], p8["acc"], p8["score"]) == (22, 25, 26)
    assert p8["acc_max"] == 12_845_056
    assert (p16["tile"], p16["acc"], p16["score"]) == (38, 41, 42)
    assert p16["acc_max"] == 841_813_590_016 and p16["score_max"] == 1_391_569_403_903
    assert not fits(p16["acc_max"], 40)              # 40비트 누산은 INT16 784항에 부족
    assert wrap(1 << 23, 24) == -(1 << 23) and wrap(-1, 24) == -1
    # 24비트 외부 누산은 INT8 최악값에서 넘친다, 25비트는 넘치지 않는다
    x, w = [-128] * N_IN, [[-128] * N_IN] * N_CLASS
    assert model(x, w, [0] * N_CLASS, 24, 24)[3] is True
    _, s, _, o = model(x, w, [0] * N_CLASS, 25, 24)
    assert o is False and s[0] == 12_845_056
    # 위치 판별 case: score[c] = 타일(12-c) 길이 × (13-c)
    x = [i // TILE + 1 for i in range(N_IN)]
    w = [[int(i // TILE == 12 - c) for i in range(N_IN)] for c in range(N_CLASS)]
    assert model(x, w, [0] * N_CLASS, 41, 40)[1] == [16 * 13] + [64 * (13 - c) for c in range(1, 10)]
    return p8, p16


def write_vectors(out, cases, pads, acc_w, bias_w, data_w=8):
    """TB 입력(vectors.txt)과 기대값(expected.txt)을 쓴다. 반환: overflow 사례 수."""
    n_ovf = 0
    with (out / "vectors.txt").open("w") as vf, (out / "expected.txt").open("w") as ef:
        vf.write(f"{len(cases)}\n")
        for (x, w, b), pad in zip(cases, pads):
            parts, scores, cls, ovf = model(x, w, b, acc_w, bias_w, data_w)
            n_ovf += ovf
            vf.write(" ".join(map(str, x)) + "\n" + " ".join(map(str, pad)) + "\n")
            for row in w:
                vf.write(" ".join(map(str, row)) + "\n")
            vf.write(" ".join(map(str, b)) + "\n")
            for t, row in enumerate(parts):
                ef.write(f"T{t} " + " ".join(map(str, row)) + "\n")
            ef.write("S " + " ".join(map(str, scores)) + f" C{cls} O{int(ovf)}\n")
    return n_ovf


def generate(out, suite, acc_w, bias_w, data_w=8):
    p8, p16 = selftest()
    rng = random.Random(1717)
    cases = build_cases(suite, bias_w, rng, data_w)
    pads = [padding(rng, data_w) for _ in cases]
    n_ovf = write_vectors(out, cases, pads, acc_w, bias_w, data_w)
    dw = "" if data_w == 8 else f" data_w={data_w}"
    print(f"PYTHON_TILE784_SELF_TEST_PASS suite={suite} cases={len(cases)} tiles=13 "
          f"last_len={LAST_LEN} acc_w={acc_w} bias_w={bias_w} overflow_cases={n_ovf} seed=1717{dw}")
    print(f"WIDTH_PLAN INT8: tile={p8['tile']} acc={p8['acc']} score(+bias24)={p8['score']} | "
          f"INT16: tile={p16['tile']} acc={p16['acc']} score(+bias40)={p16['score']}")


def compare(out, actual):
    exp = (out / "expected.txt").read_text().splitlines()
    got = actual.read_text().splitlines()
    if exp != got:
        for i, (e, g) in enumerate(zip(exp, got)):
            if e != g:
                print(f"FAIL line {i}:\n  expected={e}\n  got     ={g}")
                break
        print(f"lines expected={len(exp)} got={len(got)}")
        raise SystemExit("PYTHON_RTL_COMPARE_FAIL")
    n_case = sum(line.startswith("S ") for line in exp)
    print(f"PYTHON_RTL_COMPARE_PASS cases={n_case} tile_partials={n_case * N_TILE * N_CLASS} "
          f"scores=10 class=1 overflow=1 bit_exact=1")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--actual", type=Path)
    p.add_argument("--suite", choices=["full", "width"], default="full")
    p.add_argument("--acc-w", type=int, default=41)
    p.add_argument("--bias-w", type=int, default=40)
    p.add_argument("--data-w", type=int, default=8, choices=[8, 16])
    a = p.parse_args()
    if a.actual:
        compare(a.out, a.actual)
    else:
        generate(a.out, a.suite, a.acc_w, a.bias_w, a.data_w)
