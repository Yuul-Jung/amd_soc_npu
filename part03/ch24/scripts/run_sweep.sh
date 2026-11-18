#!/usr/bin/env bash
# (추가) 24장: 주요 구성의 OOC 합성·배치·배선을 클록 주기 10/8/7/6 ns로 반복해 실제 Fmax를 찾는다.
# 결과 보고서는 build/(저장소 제외), 요약은 validation/timing_sweep.md (reference/sweep_summary.py).
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
part03=$(cd -- "$chapter_dir/.." && pwd)
# shellcheck disable=SC1090
[[ -n "${VIVADO_SETTINGS:-}" ]] && source "$VIVADO_SETTINGS"
command -v vivado >/dev/null || { echo "NOT_RUN SWEEP: vivado 없음"; exit 2; }
build="$chapter_dir/build"
rm -rf "$build"; mkdir -p "$build"
periods=${PERIODS:-"10.000 8.000 7.000 6.000"}
run() {  # period cfg
  local d="$build/p$1_$2"; mkdir -p "$d"
  (cd "$d" && P3_CLK_PERIOD=$1 vivado -mode batch -nojournal -log "$d/vivado.log" \
    -source "$part03/ch19/synth/synth_ooc.tcl" -tclargs "$part03" "$d/rpt" impl \
    "$chapter_dir/synth/sweep_$2.tcl" > "$d/stdout.txt" 2>&1)
  grep -c "^ERROR" "$d/vivado.log" | sed "s/^/p$1_$2 errors=/"
}
for p in $periods; do
  run "$p" cores &
  run "$p" axi &
  wait
done
export PYTHONDONTWRITEBYTECODE=1
python3 "$chapter_dir/reference/sweep_summary.py" --build "$build" --out "$chapter_dir/validation/timing_sweep.md"
