#!/usr/bin/env python3
"""3장 8×8 MNIST 모델 학습·INT8 양자화·정수 평가 (PC, numpy).

  python3 p03/model/train_p03.py            # 학습 → p03/model/p03_models.json, 평가 줄 출력

전처리 (보드와 같음, 정수만):
  28×28 → 가운데 24×24 → 3×3 칸 평균 (합 + 4) // 9 → 0..255 → 13장 규칙 sat_int8(round_shift_away(p, 1)) → 0..127
모델 두 개 (같은 입력):
  선형 64→10        : 3-2 서브젝트 (p3_group10_core 64→10). 점수 = x·W + b
  MLP 64→8→10       : 3-4 서브젝트 (p3_mlp_64_8_10). 은닉 = sat_int8(round_shift_away(ReLU(x·W1 + b1), shift))
양자화: 가중치 대칭 INT8 (최댓값 = ±127), Bias는 누산 단위 signed 24비트로 반올림·포화.
정수 평가는 part03/host_tools/p3_integer_reference.py의 linear_64x10 · mlp_64_8_10 · argmax_lowest만 쓴다
(RTL과 비트 단위로 같은 규칙). 학습은 float32, 고정 seed.
"""
import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "host_tools"))
from mnist_idx import images, labels, SHA256                       # noqa: E402
from part03.host_tools.p3_integer_reference import (                # noqa: E402
    sat_int8, round_shift_away, linear_64x10, mlp_64_8_10, argmax_lowest)

SEED = 303
OUT = ROOT / "p03" / "model" / "p03_models.json"


def to8x8(img784):
    """28×28 화소 → 8×8 INT8 (0..127). 정수 연산만."""
    a = np.frombuffer(img784, dtype=np.uint8).reshape(28, 28)[2:26, 2:26].astype(np.int64)
    s = a.reshape(8, 3, 8, 3).sum(axis=(1, 3))
    avg = (s + 4) // 9
    return [sat_int8(round_shift_away(int(v), 1)) for v in avg.reshape(64)]


def load(split):
    xs = np.array([to8x8(im) for im in images(split)], dtype=np.int64)
    return xs, np.array(labels(split), dtype=np.int64)


def sat(v, bits):
    lo, hi = -(1 << (bits - 1)), (1 << (bits - 1)) - 1
    return max(lo, min(hi, v))


def rnd(v):
    """절반은 0에서 먼 쪽 (Python round의 짝수 반올림을 쓰지 않는다)."""
    return int(np.sign(v) * np.floor(abs(v) + 0.5))


def qweights(w):
    s = float(np.abs(w).max()) / 127.0
    return [[sat(rnd(v / s), 8) for v in row] for row in w], s


def softmax_ce(logits, y):
    z = logits - logits.max(axis=1, keepdims=True)
    p = np.exp(z)
    p /= p.sum(axis=1, keepdims=True)
    g = p.copy()
    g[np.arange(len(y)), y] -= 1
    return g / len(y)


def adam_train(params, grad_fn, x, y, epochs, lr, rng):
    m = [np.zeros_like(p) for p in params]
    v = [np.zeros_like(p) for p in params]
    t = 0
    for _ in range(epochs):
        order = rng.permutation(len(x))
        for i in range(0, len(x), 128):
            idx = order[i:i + 128]
            grads = grad_fn(params, x[idx], y[idx])
            t += 1
            for k, (p, g) in enumerate(zip(params, grads)):
                m[k] = 0.9 * m[k] + 0.1 * g
                v[k] = 0.999 * v[k] + 0.001 * g * g
                p -= lr * (m[k] / (1 - 0.9 ** t)) / (np.sqrt(v[k] / (1 - 0.999 ** t)) + 1e-8)
    return params


def main():
    rng = np.random.default_rng(SEED)
    xtr, ytr = load("train")
    xte, yte = load("test")
    ftr, fte = xtr.astype(np.float32) / 127.0, xte.astype(np.float32) / 127.0

    # ── 선형 64→10 ──
    W = rng.normal(0, 0.05, (64, 10)).astype(np.float32)
    b = np.zeros(10, np.float32)

    def g_lin(ps, x, y):
        W, b = ps
        g = softmax_ce(x @ W + b, y)
        return [x.T @ g, g.sum(axis=0)]

    W, b = adam_train([W, b], g_lin, ftr, ytr, 8, 0.01, rng)
    f_lin = float(((fte @ W + b).argmax(axis=1) == yte).mean())
    wq, sw = qweights(W.T)                                          # wq[class][i]
    bq = [sat(rnd(float(v) / ((1 / 127.0) * sw)), 24) for v in b]

    # ── MLP 64→8→10 ──
    W1 = rng.normal(0, 0.2, (64, 8)).astype(np.float32)
    b1 = np.zeros(8, np.float32)
    W2 = rng.normal(0, 0.3, (8, 10)).astype(np.float32)
    b2 = np.zeros(10, np.float32)

    def g_mlp(ps, x, y):
        W1, b1, W2, b2 = ps
        h_pre = x @ W1 + b1
        h = np.maximum(h_pre, 0)
        g = softmax_ce(h @ W2 + b2, y)
        gh = (g @ W2.T) * (h_pre > 0)
        return [x.T @ gh, gh.sum(axis=0), h.T @ g, g.sum(axis=0)]

    W1, b1, W2, b2 = adam_train([W1, b1, W2, b2], g_mlp, ftr, ytr, 15, 0.005, rng)
    h_te = np.maximum(fte @ W1 + b1, 0)
    f_mlp = float(((h_te @ W2 + b2).argmax(axis=1) == yte).mean())

    w1q, s1 = qweights(W1.T)                                        # w1q[hidden][i]
    b1q = [sat(rnd(float(v) / ((1 / 127.0) * s1)), 24) for v in b1]
    # 은닉 shift: 학습 데이터 은닉 누산의 99.9 백분위가 127 안에 들어오는 가장 작은 shift
    acc = np.maximum(xtr[:5000] @ np.array(w1q).T + np.array(b1q), 0)
    p999 = float(np.percentile(acc, 99.9))
    shift = next(s for s in range(32) if p999 / (1 << s) <= 127)
    h_unit = (1 / 127.0) * s1 * (1 << shift)                        # 은닉 정수 1의 실수 크기
    w2q, s2 = qweights(W2.T)                                        # w2q[class][hidden]
    b2q = [sat(rnd(float(v) / (h_unit * s2)), 24) for v in b2]

    # ── 정수 평가 (RTL 규칙 함수) ──
    q_lin = sum(argmax_lowest(linear_64x10(list(x), wq, bq)) == y for x, y in zip(xte.tolist(), yte))
    q_mlp = sum(argmax_lowest(mlp_64_8_10(list(x), w1q, b1q, w2q, b2q, shift)) == y
                for x, y in zip(xte.tolist(), yte))
    n = len(yte)
    res = {
        "preprocess": "28x28 -> center 24x24 -> 3x3 mean (sum+4)//9 -> sat_int8(round_shift_away(p,1)), row-major 64",
        "seed": SEED,
        "dataset_sha256": SHA256,
        "linear": {"w": wq, "b": bq, "float_test_acc": round(f_lin, 4), "int8_test_acc": round(q_lin / n, 4)},
        "mlp": {"w1": w1q, "b1": b1q, "w2": w2q, "b2": b2q, "shift": shift,
                "float_test_acc": round(f_mlp, 4), "int8_test_acc": round(q_mlp / n, 4)},
    }
    OUT.write_text(json.dumps(res, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"P03_TRAIN_LINEAR float={f_lin:.4f} int8={q_lin / n:.4f} test={n}")
    print(f"P03_TRAIN_MLP float={f_mlp:.4f} int8={q_mlp / n:.4f} shift={shift} test={n}")
    print(f"P03_MODEL_WRITTEN {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
