#!/usr/bin/env python3
"""실제 MNIST 내려받기·읽기 (표준 라이브러리만). 캐시: data/mnist/ (저장소에 올리지 않음).

내려받은 파일은 SHA-256을 아래 표와 비교한다. 표의 값은 이 파일을 만들 때 내려받아 계산한 값이다.
"""
from __future__ import annotations
import gzip
import hashlib
import struct
import urllib.request
from pathlib import Path

MIRRORS = ["https://ossci-datasets.s3.amazonaws.com/mnist/", "https://storage.googleapis.com/cvdf-datasets/mnist/"]
FILES = {
    "train_images": "train-images-idx3-ubyte.gz", "train_labels": "train-labels-idx1-ubyte.gz",
    "test_images": "t10k-images-idx3-ubyte.gz", "test_labels": "t10k-labels-idx1-ubyte.gz",
}
SHA256 = {    # record_hashes() 출력 (2026-11-19 내려받기)
    "train_images": "440fcabf73cc546fa21475e81ea370265605f56be210a4024d2ca8f203523609",
    "train_labels": "3552534a0a558bbed6aed32b30c495cca23d567ec52cac8be1a0730e8010255c",
    "test_images": "8d422c7b0a1c1c79245a5bcf07fe86e33eeafee792b84584aec276f5a2dbc4e6",
    "test_labels": "f7ae60f92e00ec6debd23a6088c31dbd2371eca3ffa0defaefb259924204aec6",
}
DEFAULT_DIR = Path(__file__).resolve().parents[1] / "data" / "mnist"


def fetch(name: str, root: Path = DEFAULT_DIR) -> Path:
    root.mkdir(parents=True, exist_ok=True)
    path = root / FILES[name]
    if not path.exists():
        err = None
        for m in MIRRORS:
            try:
                urllib.request.urlretrieve(m + FILES[name], path)
                break
            except OSError as e:                      # 다음 미러 시도
                err = e
        else:
            raise SystemExit(f"MNIST_DOWNLOAD_FAIL {FILES[name]}: {err}")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if name in SHA256 and SHA256[name] != digest:
        raise SystemExit(f"MNIST_SHA256_MISMATCH {FILES[name]} {digest}")
    return path


def images(split: str, root: Path = DEFAULT_DIR) -> list[bytes]:
    """28×28 화소 784바이트(행 우선)의 목록."""
    data = gzip.decompress(fetch(f"{split}_images", root).read_bytes())
    magic, n, rows, cols = struct.unpack(">IIII", data[:16])
    assert magic == 2051 and rows == cols == 28, (magic, rows, cols)
    return [data[16 + k * 784:16 + (k + 1) * 784] for k in range(n)]


def labels(split: str, root: Path = DEFAULT_DIR) -> list[int]:
    data = gzip.decompress(fetch(f"{split}_labels", root).read_bytes())
    magic, n = struct.unpack(">II", data[:8])
    assert magic == 2049
    return list(data[8:8 + n])


def record_hashes(root: Path = DEFAULT_DIR) -> None:
    for name in FILES:
        print(f'    "{name}": "{hashlib.sha256(fetch(name, root).read_bytes()).hexdigest()}",')


if __name__ == "__main__":
    record_hashes()
