#!/usr/bin/env bash
# (추가) 18장: MNIST t10k 전체로 Float·INT8·INT16 정확도·혼동행렬·클래스 일치 평가(PC, 표준 라이브러리).
# 사용: MNIST_DIR=<idx 파일 4개가 있는 MNIST raw 폴더> bash part03/ch18/scripts/run_eval.sh
# 결과: ch18/validation/precision_report.md, ch18/reference/mnist_rtl_samples.txt 갱신, pc_eval.log
# 모델 재학습(선택, PyTorch 필요): python ch18/reference/train_mnist_linear.py --mnist-dir "$MNIST_DIR"
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
part03=$(cd -- "$chapter_dir/.." && pwd)
if [[ -z "${MNIST_DIR:-}" || ! -f "$MNIST_DIR/t10k-images-idx3-ubyte" ]]; then
  echo "NOT_RUN PC_EVAL: MNIST_DIR (t10k-images-idx3-ubyte, t10k-labels-idx1-ubyte) 없음"
  exit 2
fi
export PYTHONDONTWRITEBYTECODE=1
{
  python3 --version
  sha256sum "$MNIST_DIR"/t10k-images-idx3-ubyte "$MNIST_DIR"/t10k-labels-idx1-ubyte | sed "s#$MNIST_DIR/##"
  sha256sum "$chapter_dir/reference/mnist_linear_f32.json" | sed "s#$part03#part03#g"
  python3 "$chapter_dir/reference/precision_reference.py" --eval --mnist-dir "$MNIST_DIR"
  sha256sum "$chapter_dir/reference/mnist_rtl_samples.txt" | sed "s#$part03#part03#g"
} 2>&1 | tee "$chapter_dir/validation/pc_eval.log"
