#!/usr/bin/env python3
"""13장 기준 모델: 28×28 화소 → 8×8 평균 풀링 → INT8 64원소 (표준 라이브러리만 사용).

시험 영상은 5×7 글꼴로 그린 숫자 0~9 합성 영상이다(실제 MNIST 아님).
실제 MNIST 확인은 --mnist 옵션 (torch·torchvision 설치와 내려받기 필요, 선택).
"""
from __future__ import annotations
import argparse
from pathlib import Path

SIZE, OUT = 28, 8
FONT = {  # 5×7 글꼴, 1 = 획
    0: ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    1: ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    2: ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    3: ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    4: ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    5: ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    6: ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    7: ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    8: ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    9: ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
}


def draw_digit(d: int) -> list[list[int]]:
    """글꼴 1칸을 가로 4 × 세로 3 화소로 키워 28×28 가운데(왼쪽 4, 위 3)에 그린다. 획 255, 바탕 0."""
    img = [[0] * SIZE for _ in range(SIZE)]
    for r, row in enumerate(FONT[d]):
        for c, bit in enumerate(row):
            if bit == "1":
                for y in range(3 + 3 * r, 6 + 3 * r):
                    for x in range(4 + 4 * c, 8 + 4 * c):
                        img[y][x] = 255
    return img


def window(i: int) -> range:
    """PyTorch adaptive_avg_pool2d와 같은 창: [floor(i·28/8), ceil((i+1)·28/8))."""
    return range((i * SIZE) // OUT, -(-((i + 1) * SIZE) // OUT))


def pool_8x8(img: list[list[int]]) -> list[list[int]]:
    """창 평균을 정수 반올림(0.5 올림)한 0~255 값."""
    out = []
    for i in range(OUT):
        row = []
        for j in range(OUT):
            vals = [img[y][x] for y in window(i) for x in window(j)]
            row.append((sum(vals) + len(vals) // 2) // len(vals))
        out.append(row)
    return out


def to_int8(pooled: list[list[int]]) -> list[int]:
    """행 우선 64원소, 값 = round(평균/2) 상한 127 → 부호 비트가 항상 0인 INT8."""
    return [min(127, (p + 1) >> 1) for row in pooled for p in row]


def features(img: list[list[int]]) -> list[int]:
    return to_int8(pool_8x8(img))


def show(x: list[int]) -> str:
    shade = " .:-=+*#%@"
    return "\n".join("".join(shade[min(9, v * 10 // 128)] * 2 for v in x[r * 8:r * 8 + 8]) for r in range(8))


def selftest() -> list[tuple[int, list[int]]]:
    wins = [list(window(i)) for i in range(OUT)]
    assert all(len(w) == 4 for w in wins), wins                  # 28/8 = 3.5 → 창 4화소, 일부 겹침
    assert sorted({p for w in wins for p in w}) == list(range(SIZE))
    assert features([[0] * SIZE for _ in range(SIZE)]) == [0] * 64
    assert features([[255] * SIZE for _ in range(SIZE)]) == [127] * 64
    samples = [(d, features(draw_digit(d))) for d in range(10)]
    for d, x in samples:
        assert len(x) == 64 and all(0 <= v <= 127 for v in x) and any(x), d
    assert len({tuple(x) for _, x in samples}) == 10              # 숫자마다 다른 벡터
    print(f"PYTHON_MNIST8X8_SELF_TEST_PASS samples=10 elements=64 range=0..{max(max(x) for _, x in samples)}")
    return samples


def mnist_check(root: str, count: int) -> None:
    """선택: 실제 MNIST 시험 집합으로 shape·라벨·범위와 adaptive_avg_pool2d 일치를 확인한다."""
    import torch
    from torchvision.datasets import MNIST
    data = MNIST(root, train=False, download=True)
    worst = 0
    for k in range(count):
        image, label = data[k]
        img = [[image.getpixel((x, y)) for x in range(SIZE)] for y in range(SIZE)]
        ours = pool_8x8(img)
        ref = torch.nn.functional.adaptive_avg_pool2d(torch.tensor(img, dtype=torch.float32)[None, None], (8, 8))[0, 0]
        worst = max(worst, max(abs(ours[i][j] - float(ref[i][j])) for i in range(8) for j in range(8)))
        assert 0 <= int(label) <= 9
    assert worst <= 0.5, worst
    print(f"MNIST_POOL_MATCH_PASS samples={count} max_round_error={worst:.3f}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", help="vectors.txt를 쓸 폴더")
    ap.add_argument("--actual", help="RTL이 읽어 낸 actual.txt (Python 값과 비교)")
    ap.add_argument("--show", type=int, help="숫자 하나의 8×8 특징을 글자 그림으로 출력")
    ap.add_argument("--mnist", help="선택: MNIST 저장 폴더 (torch·torchvision 필요)")
    a = ap.parse_args()
    if a.mnist:
        mnist_check(a.mnist, 100)
        return
    samples = selftest()
    if a.show is not None:
        print(show(samples[a.show][1]))
    if a.out and not a.actual:
        with open(Path(a.out) / "vectors.txt", "w") as f:
            for d, x in samples:
                f.write(f"{d} " + " ".join(f"{v:02x}" for v in x) + "\n")
    if a.actual:
        got = {}
        for ln in open(a.actual):
            p = ln.split()
            got[int(p[0])] = [int(v, 16) for v in p[1:]]
        for d, x in samples:
            if got.get(d) != x:
                raise SystemExit(f"PYTHON_RTL_COMPARE_FAIL label={d}")
        print(f"PYTHON_RTL_COMPARE_PASS samples={len(samples)} values={64 * len(samples)}")


if __name__ == "__main__":
    main()
