#!/usr/bin/env bash
# VS Code(Vivado 설치 PC)에서 00~12장 합성·타이밍·타이밍 시뮬레이션을 한 번에 실행하고
# 각 장 validation/ 에 증거 로그를 남긴다. 보드 확인(BOARD_PASS)과는 별개다.
#   source /tools/Xilinx/Vivado/<버전>/settings64.sh
#   bash tools/run_vivado_all.sh            # 전체
#   bash tools/run_vivado_all.sh ooc        # 00~10장 OOC만
#   bash tools/run_vivado_all.sh impl       # 12장 구현 + 타이밍 시뮬레이션만
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
command -v vivado >/dev/null 2>&1 || { echo "VIVADO_NOT_RUN: vivado not found (source settings64.sh)" >&2; exit 2; }
what="${1:-all}"
day="$(date +%Y%m%d)"
logs="$root/build/vivado/logs"; mkdir -p "$logs"
clean() { sed -e "s#$root#<repo>#g" -e "s#$HOME#~#g" "$1"; }
status=0

if [ "$what" = all ] || [ "$what" = ooc ]; then
    vivado -mode batch -nojournal -log "$logs/ooc.log" -source tools/vivado/ooc_timing.tcl || status=1
    while read -r tag ch rest; do
        case "$tag" in SYNTH_TIMING_*) ;; *) continue ;; esac
        { head -1 build/vivado/ooc_summary.txt; echo "$tag $ch $rest"; echo;
          sed -n '/Design Timing Summary/,/^$/p;/WNS(ns)/,+3p' "build/vivado/$ch/timing_route.rpt" 2>/dev/null || true; } \
          | clean /dev/stdin > "$ch/validation/vivado_ooc_$day.txt"
    done < build/vivado/ooc_summary.txt
    cat build/vivado/ooc_summary.txt
fi

if [ "$what" = all ] || [ "$what" = impl ]; then
    if vivado -mode batch -nojournal -log "$logs/impl.log" -source mini_npu/scripts/vivado_impl.tcl; then
        bash mini_npu/scripts/run_timing_sim.sh > "$logs/timesim.log" 2>&1 || status=1
    else
        status=1
    fi
    { cat mini_npu/build/impl/impl_summary.txt 2>/dev/null || true; echo;
      sed -n '/WNS(ns)/,+3p' mini_npu/build/impl/timing_route.rpt 2>/dev/null || true; echo;
      if [ -f mini_npu/build/impl/basys3_npu_top.bit ]; then sha256sum mini_npu/build/impl/basys3_npu_top.bit; fi;
      echo; echo "## run_timing_sim.sh"; grep -E '_PASS|_FAIL|NOT_RUN|Error|FATAL' "$logs/timesim.log" 2>/dev/null || true; } \
      | clean /dev/stdin > ch12/validation/vivado_impl_timesim_$day.txt
    cat ch12/validation/vivado_impl_timesim_$day.txt
fi

[ $status -eq 0 ] && echo "VIVADO_ALL_PASS ($what)" || echo "VIVADO_ALL_FAIL ($what) — build/vivado/logs 확인"
exit $status
