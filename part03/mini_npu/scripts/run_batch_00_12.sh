#!/usr/bin/env bash
# VS Code에서 00~12장 전체 회귀. 소스 수정 없이 실제 실행 로그 저장.
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
part03="$(cd -- "$here/.." && pwd)"
logdir="$here/validation/local_runs/$(date -u +%Y%m%dT%H%M%S%N)"
mkdir -p "$logdir"
summary="$logdir/run_summary.md"
printf '# 제3부 00~12장 실제 RTL 회귀 실행\n\n| 단계 | 실제 결과 | 로그 |\n|---|---|---|\n' > "$summary"
if ! command -v iverilog >/dev/null || ! command -v vvp >/dev/null ||
   ! command -v python3 >/dev/null; then
    printf '\n필수 Icarus Verilog/Python 미설치: NOT_RUN\n' >> "$summary"
    cat "$summary";exit 2
fi
check() {
    local name="$1" match="$2";shift 2
    local log="$logdir/$name.log"
    if "$@" > "$log" 2>&1 && grep -q "$match" "$log"; then
        printf '| %s | RTL_SIM_PASS | %s |\n' "$name" "$log" >> "$summary"
        echo "PASS $name"
    else
        printf '| %s | FAIL 또는 필수 PASS 표시 누락 | %s |\n' "$name" "$log" >> "$summary"
        tail -n 28 "$log" || true
        echo "FAIL $name (see $summary)" >&2
        return 1
    fi
}
check ch00 UART_ECHO_RTL_SIM_PASS bash "$part03/ch00/scripts/run_sim.sh"
for n in 01 02 03 04 05 06 07 08 09 10; do
    check "ch$n" RTL_SIM_PASS bash "$part03/ch$n/scripts/run_sim.sh"
done
check dsp_engine NPU_ENGINE_RTL_SIM_PASS bash "$here/scripts/run_engine.sh"
marker="$logdir/start.marker";touch "$marker"
check ch11_ch12 INTEGRATED_UART_RTL_SIM_PASS bash "$here/scripts/run_demo.sh"
grep -q PC_GOLDEN_COMPARE_PASS "$logdir/ch11_ch12.log" || {
    printf 'PC GOLDEN 비교 실패\n' >> "$summary";exit 1;
}
for path in "$here/outputs/predictions.csv" "$here/outputs/demo_result.txt"; do
    if [[ ! -s "$path" || ! "$path" -nt "$marker" ]]; then
        echo "FAILED missing/stale output: $path" >&2;exit 1
    fi
done
printf '\n**실행 완료:** 원본 01~10장 독립 실험 + 신규 준비·DSP 엔진·UART 전체 회귀.\n' >> "$summary"
printf '**중요:** SYNTH_TIMING_PASS, BOARD_PASS를 뜻하지 않음.\n' >> "$summary"
cat "$summary"
