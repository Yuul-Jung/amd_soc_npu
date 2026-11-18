#!/usr/bin/env python3
"""28장 PC 전처리: 손글씨 영상(PGM 또는 28×28 숫자 표) → MNIST와 같은 모양(20×20 상자에 맞추고 무게중심을 28×28 가운데로)
→ 784 INT8(13·18장 계약) 또는 8×8 64 INT8(13장). 표준 라이브러리만 쓴다.

검사(--selftest): 실제 MNIST 시험 그림을 일부러 옮기고 키운 뒤(바깥 64×64 캔버스) 전처리로 되돌려
18장 INT8 모델 정확도가 원래 그림과 얼마나 같은지 본다."""
from __future__ import annotations
import argparse
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "host_tools"), str(ROOT / "ch13" / "reference"), str(ROOT / "ch18" / "reference")]


def read_pgm(path):
    data = Path(path).read_bytes()
    tok, i = [], 0
    while len(tok) < 4:                                  # P2/P5, 너비, 높이, 최대값 (주석 # 무시)
        while data[i:i + 1].isspace(): i += 1
        if data[i:i + 1] == b"#":
            while data[i:i + 1] not in (b"\n", b""): i += 1
            continue
        j = i
        while not data[j:j + 1].isspace(): j += 1
        tok.append(data[i:j].decode()); i = j
    kind, w, h, mx = tok[0], int(tok[1]), int(tok[2]), int(tok[3])
    vals = list(data[i + 1:i + 1 + w * h]) if kind == "P5" else list(map(int, data[i:].split()))[:w * h]
    img = [[vals[r * w + c] * 255 // mx for c in range(w)] for r in range(h)]
    if sum(map(sum, img)) > 127 * w * h:                 # 흰 바탕에 검은 글씨면 뒤집는다 (MNIST는 검은 바탕·흰 글씨)
        img = [[255 - v for v in row] for row in img]
    return img


def resize(img, nw, nh):
    """면적 평균 축소·확대 (정수 좌표, 단순 박스 필터)."""
    h, w = len(img), len(img[0])
    out = []
    for r in range(nh):
        y0, y1 = r * h // nh, max(r * h // nh + 1, (r + 1) * h // nh)
        row = []
        for c in range(nw):
            x0, x1 = c * w // nw, max(c * w // nw + 1, (c + 1) * w // nw)
            vals = [img[y][x] for y in range(y0, y1) for x in range(x0, x1)]
            row.append(sum(vals) // len(vals))
        out.append(row)
    return out


def mnist_like(img):
    """글씨 상자를 잘라 긴 변 20화소로 맞추고, 무게중심이 28×28 가운데(14,14)에 오게 놓는다."""
    ys = [y for y, row in enumerate(img) if any(v > 30 for v in row)]
    xs = [x for x in range(len(img[0])) if any(img[y][x] > 30 for y in range(len(img)))]
    if not ys:
        return [[0] * 28 for _ in range(28)]
    crop = [row[xs[0]:xs[-1] + 1] for row in img[ys[0]:ys[-1] + 1]]
    h, w = len(crop), len(crop[0])
    s = 20 / max(h, w)
    nh, nw = max(1, round(h * s)), max(1, round(w * s))
    small = resize(crop, nw, nh)
    tot = sum(map(sum, small)) or 1
    cy = sum(y * v for y, row in enumerate(small) for v in row) / tot
    cx = sum(x * v for row in small for x, v in enumerate(row)) / tot
    oy, ox = round(14 - cy - 0.5), round(14 - cx - 0.5)
    out = [[0] * 28 for _ in range(28)]
    for y, row in enumerate(small):
        for x, v in enumerate(row):
            if 0 <= y + oy < 28 and 0 <= x + ox < 28:
                out[y + oy][x + ox] = v
    return out


def to_x784(img28):
    return [min(127, (p + 1) >> 1) for row in img28 for p in row]


def selftest(n):
    from mnist_idx import images, labels
    from precision_rtl import load, scores
    from p3_integer_reference import argmax_lowest
    w, b, _ = load(8)
    imgs, labs = images("test"), labels("test")
    rng = random.Random(28)
    base = moved = 0
    for k in range(n):
        img = [list(imgs[k][r * 28:(r + 1) * 28]) for r in range(28)]
        base += argmax_lowest(scores(to_x784(img), w, b)) == labs[k]
        big = resize(img, 28 * 2, 28 * 2)                # 두 배로 키워
        canvas = [[0] * 64 for _ in range(64)]
        oy, ox = rng.randint(0, 8), rng.randint(0, 8)    # 아무 데나 놓는다
        for y in range(56):
            for x in range(56):
                canvas[y + oy][x + ox] = big[y][x]
        moved += argmax_lowest(scores(to_x784(mnist_like(canvas)), w, b)) == labs[k]
    print(f"PREPROCESS_CHECK original={100 * base / n:.1f}% moved_scaled_then_preprocessed={100 * moved / n:.1f}% images={n}")
    ok = moved >= base * 0.9
    print("PREPROCESS_HOST_PASS" if ok else "PREPROCESS_HOST_FAIL")
    return ok


if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("--selftest", type=int); ap.add_argument("pgm", nargs="?")
    a = ap.parse_args()
    if a.selftest:
        sys.exit(0 if selftest(a.selftest) else 1)
    x = to_x784(mnist_like(read_pgm(a.pgm)))
    print(" ".join(map(str, x)))
