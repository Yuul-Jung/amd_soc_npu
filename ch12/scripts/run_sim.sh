#!/usr/bin/env bash
# (추가) 제3부 준비~12장 독립 원본 및 통합 기능 전체 회귀.
set -Eeuo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bash "$script_dir/../../mini_npu/scripts/run_batch_00_12.sh"
