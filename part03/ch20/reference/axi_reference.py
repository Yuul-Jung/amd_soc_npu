#!/usr/bin/env python3
"""20장: AXI4-Lite NPU 제어 IP 시험 벡터·기대값 생성과 RTL 비교(표준 라이브러리).

CPU가 레지스터로 전체 784 추론을 수행했을 때 읽은 10개 점수(SCORE_LO/HI)·CLASS·OVF가
17장 기준모델 model()과 같아야 한다. 사례: 18장 MNIST INT8 표본 3개(INT8≠Float 포함),
INT8 극값 2개(Bias ±2^39 → SCORE_HI 사용), 무작위 1개, class 0·1 동점 1개.
"""
import argparse
import json
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from part03.ch17.reference.tile784_reference import (  # noqa: E402
    N_CLASS, N_IN, build_cases, model, padding,
)
from part03.ch18.reference.precision_reference import (  # noqa: E402
    MODEL, SAMPLES, quantize_model, quantize_x,
)

ACC_W, BIAS_W = 41, 40
REG = {"CTRL": 0x00, "STATUS": 0x04, "LENGTH": 0x08, "CLASS": 0x0C, "X_INDEX": 0x10,
       "X_DATA": 0x14, "W_CLASS": 0x18, "W_INDEX": 0x1C, "W_DATA": 0x20, "BIAS_LO": 0x24,
       "BIAS_HI": 0x28, "SCORE_SEL": 0x2C, "SCORE_LO": 0x30, "SCORE_HI": 0x34, "IRQ_EN": 0x38}


def split_score(v):
    """42비트 signed 점수 → (SCORE_LO, SCORE_HI) 32비트 부호 없는 레지스터 값."""
    u = v & ((1 << 64) - 1)
    return u & 0xFFFFFFFF, u >> 32


def cases(rng):
    qm = quantize_model(json.loads(MODEL.read_text()), 8)
    picked = []
    for line in SAMPLES.read_text().splitlines():
        if line.startswith("#"):
            continue
        v = list(map(int, line.split()))
        picked.append((v[0], v[3], v[2], v[5:]))   # index, int8 예측, float 예측, pixels
    mnist = [picked[0], next(p for p in picked if p[1] != p[2]), picked[1]]
    out = [(quantize_x(px, 8), qm["w"], qm["b"]) for _, _, _, px in mnist]
    ext = build_cases("width", BIAS_W, random.Random(1717))[:2]   # 17장 극값(Bias ±2^39)
    out = [ext[0]] + out[:1] + [ext[1]] + out[1:]                 # 0: 극값(스냅샷 A), 1: MNIST(B)
    out.append(([rng.randint(-128, 127) for _ in range(N_IN)],
                [[rng.randint(-128, 127) for _ in range(N_IN)] for _ in range(N_CLASS)],
                [rng.randint(-(1 << 39), (1 << 39) - 1) for _ in range(N_CLASS)]))
    b = [-100 - c for c in range(N_CLASS)]
    b[0] = b[1] = 5
    out.append(([0] * N_IN, [[0] * N_IN for _ in range(N_CLASS)], b))
    return out


def selftest():
    assert split_score(-1) == (0xFFFFFFFF, 0xFFFFFFFF)
    assert split_score((1 << 41) - 1) == (0xFFFFFFFF, 0x1FF)
    assert split_score(-(1 << 41)) == (0, 0xFFFFFE00)
    assert sorted(REG.values()) == list(range(0, 0x3C, 4))


def generate(out):
    selftest()
    rng = random.Random(2020)
    cs = cases(rng)
    with (out / "vectors.txt").open("w") as vf, (out / "expected.txt").open("w") as ef:
        vf.write(f"{len(cs)}\n")
        for x, w, b in cs:
            pad = padding(rng, 8)
            _, scores, cls, ovf = model(x, w, b, ACC_W, BIAS_W, 8)
            vf.write(" ".join(map(str, x)) + "\n" + " ".join(map(str, pad)) + "\n")
            for row in w:
                vf.write(" ".join(map(str, row)) + "\n")
            vf.write(" ".join(map(str, b)) + "\n")
            ef.write("S " + " ".join(map(str, scores)) + f" C{cls} O{int(ovf)}\n")
    print(f"PYTHON_AXI_VECTORS_PASS inferences={len(cs)} regs={len(REG)} seed=2020")


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
    print(f"PYTHON_RTL_COMPARE_PASS inferences={len(exp)} scores_via_axi=10 class=1 overflow=1 bit_exact=1")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--actual", type=Path)
    a = p.parse_args()
    if a.actual:
        compare(a.out, a.actual)
    else:
        generate(a.out)
