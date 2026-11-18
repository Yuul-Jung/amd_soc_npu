#!/usr/bin/env python3
"""27장: 실제 MNIST 시험 집합에서 숫자마다 첫 그림 1장씩(10장)을 골라 INT8 입력(13·18장 계약)으로 ch27/model/에 쓴다.
한 번 실행해 저장소에 넣은 파일을 시뮬레이션·펌웨어가 쓴다 (CI는 내려받지 않음)."""
from __future__ import annotations
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "host_tools"))
from mnist_idx import images, labels    # noqa: E402

imgs, labs = images("test"), labels("test")
out = ROOT / "ch27" / "model" / "demo_cases_int8.txt"
with open(out, "w") as f:
    for d in range(10):
        k = labs.index(d)
        x = [min(127, (p + 1) >> 1) for p in imgs[k]]
        f.write(f"{k} {d} " + " ".join(map(str, x)) + "\n")
print(f"DEMO_CASES_OK images=10 test_indices={[labs.index(d) for d in range(10)]}")
