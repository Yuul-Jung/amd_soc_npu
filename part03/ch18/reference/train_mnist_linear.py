#!/usr/bin/env python3
"""18장: MNIST 784→10 Float32 선형 분류기 학습(PC 전용, PyTorch·NumPy 필요).

전처리: x = pixel / 255 (0..1, 평균·표준편차 정규화 없음 → 정수화 zero-point 0).
결과: 같은 폴더의 mnist_linear_f32.json (float32 가중치·Bias를 정확한 10진 표현으로 저장,
      학습 설정·데이터 파일 SHA-256·PyTorch Float32 시험 정확도 포함). 데이터셋 경로는 기록하지 않는다.
실행: python train_mnist_linear.py --mnist-dir <MNIST raw 폴더(idx 파일 4개)>
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import torch

FILES = {
    "train_x": "train-images-idx3-ubyte", "train_y": "train-labels-idx1-ubyte",
    "test_x": "t10k-images-idx3-ubyte", "test_y": "t10k-labels-idx1-ubyte",
}
SEED, EPOCHS, BATCH, LR = 1818, 10, 128, 1e-3


def read_idx(path):
    raw = path.read_bytes()
    ndim = raw[3]
    dims = [int.from_bytes(raw[4 + 4 * i:8 + 4 * i], "big") for i in range(ndim)]
    return np.frombuffer(raw, dtype=np.uint8, offset=4 + 4 * ndim).reshape(dims)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--mnist-dir", type=Path, required=True)
    p.add_argument("--out", type=Path, default=Path(__file__).with_name("mnist_linear_f32.json"))
    a = p.parse_args()
    torch.manual_seed(SEED)
    torch.use_deterministic_algorithms(True)
    torch.set_num_threads(1)
    d = {k: read_idx(a.mnist_dir / f) for k, f in FILES.items()}
    sha = {f: hashlib.sha256((a.mnist_dir / f).read_bytes()).hexdigest() for f in FILES.values()}
    xtr = torch.from_numpy(d["train_x"].reshape(-1, 784).astype(np.float32) / 255.0)
    ytr = torch.from_numpy(d["train_y"].astype(np.int64))
    xte = torch.from_numpy(d["test_x"].reshape(-1, 784).astype(np.float32) / 255.0)
    yte = torch.from_numpy(d["test_y"].astype(np.int64))
    model = torch.nn.Linear(784, 10)
    opt = torch.optim.Adam(model.parameters(), lr=LR)
    gen = torch.Generator().manual_seed(SEED)
    for epoch in range(EPOCHS):
        perm = torch.randperm(len(xtr), generator=gen)
        for i in range(0, len(xtr), BATCH):
            idx = perm[i:i + BATCH]
            opt.zero_grad()
            loss = torch.nn.functional.cross_entropy(model(xtr[idx]), ytr[idx])
            loss.backward()
            opt.step()
        with torch.no_grad():
            acc = (model(xte).argmax(1) == yte).float().mean().item()
        print(f"epoch={epoch + 1} loss={loss.item():.4f} test_acc_f32={acc:.4f}")
    with torch.no_grad():
        logits = model(xte)
        pred = logits.argmax(1)
        correct = int((pred == yte).sum())
    w = model.weight.detach().numpy().astype(np.float32)
    b = model.bias.detach().numpy().astype(np.float32)
    doc = {
        "model": "mnist_linear_784x10_f32",
        "preprocess": "x = pixel / 255 (uint8 0..255 -> float 0..1), no mean/std normalization",
        "train": {"seed": SEED, "epochs": EPOCHS, "batch": BATCH, "optimizer": "Adam", "lr": LR,
                  "loss": "cross_entropy", "torch": torch.__version__, "numpy": np.__version__},
        "dataset_sha256": sha,
        "torch_f32_test": {"correct": correct, "total": len(yte)},
        # float32 값을 Python float(정확한 binary64 확장)로 저장 → JSON 왕복 시 값이 바뀌지 않음
        "weight": [[float(v) for v in row] for row in w],
        "bias": [float(v) for v in b],
    }
    a.out.write_text(json.dumps(doc) + "\n")
    print(f"TRAIN_DONE torch_f32_test_correct={correct}/{len(yte)} out={a.out.name}")


if __name__ == "__main__":
    main()
