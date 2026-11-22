#!/usr/bin/env python3
"""29장: 센서 특징 8개 → 3상태(NORMAL·WARNING·FAULT) Float32 선형 분류기 학습(PC 전용, PyTorch 필요).

데이터: sensor_reference.dataset(TRAIN) — 교육용 합성 데이터(고정 seed), 실제 설비 라벨이 아니다.
입력: x = feature / 127 (특징은 0..127 정수, zero-point 0 → 18장 quantize_model 그대로 사용).
결과: 같은 폴더 sensor_model_f32.json. 정수 평가는 sensor_reference.py --eval(표준 라이브러리).
실행: <torch venv>/bin/python part03/ch29/reference/train_sensor_model.py
"""
import json
import sys
from pathlib import Path

import torch

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from part03.ch29.reference.sensor_reference import (  # noqa: E402
    MODEL_JSON, N_CLS, N_FEAT, TEST, TRAIN, dataset, features,
)

SEED, EPOCHS, LR, WD = 2929, 3000, 0.05, 1e-4


def tensors(n, seed):
    ds = dataset(n, seed)
    x = torch.tensor([[v / 127 for v in features(s)] for s in ds], dtype=torch.float32)
    y = torch.tensor([s["label"] for s in ds], dtype=torch.int64)
    return x, y


def main():
    torch.manual_seed(SEED)
    torch.use_deterministic_algorithms(True)
    torch.set_num_threads(1)
    xtr, ytr = tensors(*TRAIN)
    xte, yte = tensors(*TEST)
    m = torch.nn.Linear(N_FEAT, N_CLS)
    opt = torch.optim.Adam(m.parameters(), lr=LR, weight_decay=WD)
    for ep in range(EPOCHS):                       # 전체 배치(3000개)
        opt.zero_grad()
        loss = torch.nn.functional.cross_entropy(m(xtr), ytr)
        loss.backward()
        opt.step()
        if (ep + 1) % 500 == 0:
            with torch.no_grad():
                acc = (m(xte).argmax(1) == yte).float().mean().item()
            print(f"epoch={ep + 1} loss={loss.item():.4f} test_acc_f32={acc:.4f}")
    with torch.no_grad():
        correct = int((m(xte).argmax(1) == yte).sum())
    doc = {
        "model": "sensor_linear_8x3_f32",
        "classes": ["NORMAL", "WARNING", "FAULT"],
        "preprocess": "x = feature / 127, features per sensor_reference.features (integer 0..127)",
        "data": {"generator": "sensor_reference.gen_window (synthetic, educational)", "train": TRAIN, "test": TEST},
        "train": {"seed": SEED, "epochs": EPOCHS, "optimizer": "Adam full-batch", "lr": LR, "weight_decay": WD,
                  "loss": "cross_entropy", "torch": torch.__version__},
        "torch_f32_test": {"correct": correct, "total": len(yte)},
        "weight": [[float(v) for v in row] for row in m.weight.detach().numpy()],
        "bias": [float(v) for v in m.bias.detach().numpy()],
    }
    MODEL_JSON.write_text(json.dumps(doc) + "\n")
    print(f"TRAIN_DONE torch_f32_test_correct={correct}/{len(yte)} out={MODEL_JSON.name}")


if __name__ == "__main__":
    main()
