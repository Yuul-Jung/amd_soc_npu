#!/usr/bin/env bash
# (추가) 11장 UART 바이너리 데이터 적재·재추론 통합 시뮬레이션.
# 12장과 공유하는 동일 UART/NPU 하드웨어 TB를 재사용한다.
set -Eeuo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bash "$script_dir/../../mini_npu/scripts/run_demo.sh"
