#!/usr/bin/env python3
"""17장 기준 모델: 784원소(28×28) × 10클래스를 64원소 타일 13개로 나눠 누산, Bias는 끝에 한 번.

입력 스케일은 13장과 같다: 화소 p(0~255) → min(127, (p+1)>>1).
점수는 host_tools의 dot_tiled_64, 타일 누계(부분합)는 같은 타일 경계로 따로 계산해 RTL 타일 순서를 확인한다.
"""
from __future__ import annotations
import argparse
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "ch13" / "reference"), str(ROOT / "host_tools")]
from mnist8x8_reference import draw_digit               # noqa: E402
from p3_integer_reference import argmax_lowest, dot_signed, dot_tiled_64  # noqa: E402

N, TILE = 784, 64
TILE_LENS = [TILE] * 12 + [N - TILE * 12]               # 64 × 12 + 16


def x784(img):
    return [min(127, (p + 1) >> 1) for row in img for p in row]


def scores(x, w, b):
    return [dot_tiled_64(x, row) + bias for row, bias in zip(w, b)]


def tile_prefix(x, w):
    """타일 t까지의 누계 (Bias 없음), t = 0~12."""
    out, acc, start = [], [0] * len(w), 0
    for ln in TILE_LENS:
        acc = [a + dot_signed(x[start:start + ln], row[start:start + ln]) for a, row in zip(acc, w)]
        out.append(acc)
        start += ln
    return out


def cases():
    tmpl = [x784(draw_digit(d)) for d in range(10)]
    tw, tb = tmpl, [-(sum(v * v for v in t) // 2) for t in tmpl]       # 최근접 형판 (학습 아님)
    out = [(f"template_{d}", tmpl[d], tw, tb) for d in (0, 4, 9)]
    rng = random.Random(1717)
    for k in range(2):
        w = [[rng.randint(-128, 127) for _ in range(N)] for _ in range(10)]
        out.append((f"random_{k}", tmpl[k + 2], w, [rng.randint(-(1 << 20), 1 << 20) for _ in range(10)]))
    # 마지막 타일(768~783) 16원소만 0이 아니고, 그 구간 가중치만 클래스 6을 고르게 한다
    x = [0] * 768 + [100] * 16
    w = [[0] * N for _ in range(10)]
    for c in range(10):
        for i in range(768, N):
            w[c][i] = 5 if c == 6 else -3
    out.append(("last_tile_only", x, w, [0] * 10))
    return out


def selftest():
    cs = cases()
    assert sum(TILE_LENS) == N and len(TILE_LENS) == 13
    for name, x, w, b in cs:
        s = scores(x, w, b)
        assert s == [dot_signed(x, row) + bb for row, bb in zip(w, b)], name
        assert tile_prefix(x, w)[-1] == [v - bb for v, bb in zip(s, b)], name
        assert all(-(1 << 31) <= v < (1 << 31) for v in s), name
    cls = {n: argmax_lowest(scores(x, w, b)) for n, x, w, b in cs}
    assert cls["template_0"] == 0 and cls["template_4"] == 4 and cls["template_9"] == 9 and cls["last_tile_only"] == 6
    print(f"PYTHON_TILED784_SELF_TEST_PASS cases={len(cs)} tiles=13 lens=64x12+16")
    return cs


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--out"); ap.add_argument("--actual")
    a = ap.parse_args()
    cs = selftest()
    if a.out and not a.actual:
        with open(Path(a.out) / "vectors.txt", "w") as f:
            for n, (name, x, w, b) in enumerate(cs):
                f.write(f"{n} {name}\n" + " ".join(map(str, x)) + "\n")
                f.writelines(" ".join(map(str, r)) + "\n" for r in w)
                f.write(" ".join(map(str, b)) + "\n")
    if a.actual:
        got = {}
        for ln in open(a.actual):
            p = ln.split()
            try:
                got.setdefault(int(p[0]), {})[p[1]] = [int(v) for v in p[2:]]
            except ValueError:                                  # RTL이 x·z(정의되지 않은 값)를 냈음
                raise SystemExit(f"PYTHON_RTL_COMPARE_FAIL 정수가 아닌 RTL 출력: {ln.strip()[:80]}")
        for n, (name, x, w, b) in enumerate(cs):
            g = got.get(n, {})
            s = scores(x, w, b)
            for t, acc in enumerate(tile_prefix(x, w)):
                if g.get(f"T{t}") != [t] + acc:
                    raise SystemExit(f"PYTHON_RTL_COMPARE_FAIL case={name} tile={t} rtl={g.get(f'T{t}')}")
            if g.get("S") != s + [argmax_lowest(s)]:
                raise SystemExit(f"PYTHON_RTL_COMPARE_FAIL case={name} scores rtl={g.get('S')}")
        print(f"PYTHON_RTL_COMPARE_PASS cases={len(cs)} tile_prefix={13 * 10 * len(cs)} scores={10 * len(cs)}")


if __name__ == "__main__":
    main()
