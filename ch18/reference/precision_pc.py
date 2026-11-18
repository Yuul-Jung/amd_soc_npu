#!/usr/bin/env python3
"""18장 PC 정밀도 비교: 같은 784→10 선형 모델을 Float32, INT8, INT16으로 실제 MNIST 시험 집합 10,000장에서 평가한다.

학습: 소프트맥스 회귀(1층), 미니배치 SGD, 시드 고정. 학습한 Float32 가중치를 정수로 양자화한다.
  INT8 : 입력 x = min(127, (p+1)>>1) (13·17장 계약), 가중치 = round(w / s8),  s8  = max|w| / 127
  INT16: 입력 x = p × 128 (0~32640),               가중치 = round(w / s16), s16 = max|w| / 32767
  Bias : 정수 점수 단위로 바꿔 반올림 (INT16은 40비트 이상 필요할 수 있음 → 실제 비트 수를 출력)
결과: 정확도, 혼동행렬, 정수 경로와 Float32의 클래스 일치율, 최악 누산 비트 수.
--export: 정수 모델과 RTL 시험용 앞 20장을 ch18/model/에 쓴다 (RTL 시뮬레이션은 이 파일만 읽음).
"""
from __future__ import annotations
import argparse
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "host_tools"))
from mnist_idx import images, labels          # noqa: E402

MODEL = ROOT / "ch18" / "model"
RTL_CASES = 20


def load(split):
    x = np.frombuffer(b"".join(images(split)), dtype=np.uint8).reshape(-1, 784)
    return x, np.array(labels(split), dtype=np.int64)


def train(p, y, epochs=8, lr=0.5, batch=128, seed=18):
    rng = np.random.default_rng(seed)
    x = p.astype(np.float32) / 255.0
    w = np.zeros((784, 10), np.float32); b = np.zeros(10, np.float32)
    onehot = np.eye(10, dtype=np.float32)[y]
    for _ in range(epochs):
        order = rng.permutation(len(x))
        for s in range(0, len(x), batch):
            i = order[s:s + batch]
            z = x[i] @ w + b
            z -= z.max(1, keepdims=True)
            pr = np.exp(z); pr /= pr.sum(1, keepdims=True)
            g = (pr - onehot[i]) / len(i)
            w -= lr * x[i].T @ g; b -= lr * g.sum(0)
    return w, b


def quantize(w, b, bits):
    qmax = (1 << (bits - 1)) - 1
    s_w = float(np.abs(w).max()) / qmax
    if bits == 8:
        s_x = 2.0 / 255.0                       # x8 ≈ p/2 → p/255 = x8 · 2/255
    else:
        s_x = 1.0 / (255.0 * 128.0)             # x16 = p·128 → p/255 = x16 / (255·128)
    wq = np.clip(np.rint(w / s_w), -qmax - 1, qmax).astype(np.int64)
    bq = np.rint(b / (s_x * s_w)).astype(np.int64)
    return wq.T, bq                              # (10, 784), (10,)


def to_x(p, bits):
    p = p.astype(np.int64)
    return np.minimum(127, (p + 1) >> 1) if bits == 8 else p * 128


def argmax_lowest(s):
    return np.argmax(s, axis=1)                  # numpy argmax는 동점이면 앞 번호 → argmax_lowest와 같음


def confusion(y, pred):
    m = np.zeros((10, 10), np.int64)
    np.add.at(m, (y, pred), 1)
    return m


def bits_needed(v):
    return int(abs(int(v))).bit_length() + 1    # 부호 포함


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--export", action="store_true")
    a = ap.parse_args()
    ptr, ytr = load("train"); pte, yte = load("test")
    w, b = train(ptr, ytr)
    pred = {"float32": argmax_lowest((pte.astype(np.float32) / 255.0) @ w + b)}
    q = {}
    for bits in (8, 16):
        wq, bq = quantize(w, b, bits)
        s = to_x(pte, bits) @ wq.T + bq
        q[bits] = (wq, bq, s)
        pred[f"int{bits}"] = argmax_lowest(s)
    print(f"MNIST test={len(yte)} train={len(ytr)} model=softmax_784x10 epochs=8 seed=18")
    for k, pr in pred.items():
        acc = (pr == yte).mean()
        print(f"ACCURACY {k} {acc * 100:.2f}% ({int((pr == yte).sum())}/{len(yte)})")
    for bits in (8, 16):
        print(f"AGREE int{bits}_vs_float32 {(pred[f'int{bits}'] == pred['float32']).mean() * 100:.2f}%")
    for k, pr in pred.items():
        print(f"CONFUSION {k} (행 = 정답 0~9, 열 = 예측 0~9)")
        for r, row in enumerate(confusion(yte, pr)):
            print(f"  {r}: " + " ".join(f"{v:4d}" for v in row))
    for bits in (8, 16):
        wq, bq, s = q[bits]
        xmax = 127 if bits == 8 else 255 * 128
        worst_dot = 784 * xmax * (1 << (bits - 1))
        print(f"RANGE int{bits} max|w|={int(np.abs(wq).max())} bias_bits={bits_needed(np.abs(bq).max())} "
              f"worst_dot_bits={bits_needed(worst_dot)} worst_total_bits={bits_needed(worst_dot + int(np.abs(bq).max()))} "
              f"observed_score_bits={bits_needed(np.abs(s).max())}")
    if a.export:
        MODEL.mkdir(exist_ok=True)
        for bits in (8, 16):
            wq, bq, s = q[bits]
            with open(MODEL / f"model_int{bits}.txt", "w") as f:
                f.writelines(" ".join(map(str, row)) + "\n" for row in wq)
                f.write(" ".join(map(str, bq)) + "\n")
            with open(MODEL / f"cases_int{bits}.txt", "w") as f:
                for k in range(RTL_CASES):
                    f.write(f"{k} {yte[k]} " + " ".join(map(str, to_x(pte[k:k + 1], bits)[0])) + "\n")
        print(f"EXPORT model_int8 model_int16 cases={RTL_CASES}")
    ok = (pred["int8"] == yte).mean() > 0.85 and (pred["int16"] == pred["float32"]).mean() > 0.99
    print("PC_PRECISION_PASS" if ok else "PC_PRECISION_FAIL")


if __name__ == "__main__":
    main()
