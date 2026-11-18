#!/usr/bin/env bash
# (추가) 실제 Vivado가 설치된 VS Code에서 00~12장 통합 NPU를 별도 합성.
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
if ! command -v vivado >/dev/null 2>&1; then
    echo "SYNTH_NOT_RUN: Vivado command not found" >&2
    exit 2
fi
vivado -mode batch -source mini_npu/scripts/build_vivado.tcl
echo "SYNTH_EXECUTED: inspect utilization_synth.rpt and timing_synth.rpt"
