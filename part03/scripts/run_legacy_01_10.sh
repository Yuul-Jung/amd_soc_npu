#!/usr/bin/env bash
# (추가) 기존 01~10장 독립 RTL 회귀. 11~12장 통합 경로와 PASS를 혼동하지 않는다.
set -Eeuo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
if ! command -v iverilog >/dev/null || ! command -v vvp >/dev/null || ! command -v python3 >/dev/null; then
    echo "RTL_SIM_NOT_RUN: requires iverilog, vvp, python3" >&2
    exit 2
fi
for n in 01 02 03 04 05 06 07 08 09 10; do
    echo "CHECK original chapter $n"
    bash "part03/ch$n/scripts/run_sim.sh"
done
echo "ORIGINAL_01_10_REEXECUTED (check actual chapter logs and exit codes)"
