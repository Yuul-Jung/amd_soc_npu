#!/usr/bin/env bash
# SoC 전력 추정(Vivado report_power). vectorless + 5-4 시뮬레이션 구간별 SAIF.
#   필요: 5-2 build(배선 완료 프로젝트), 5-4 build(TB·ELF가 연결된 시뮬레이션 프로젝트)
#   결과: build/(SAIF·보고서), validation/power_summary.md (reference/power_summary.py)
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
part03=$(cd -- "$chapter_dir/.." && pwd)
p21="$part03/ch21/build/soc21_npu/soc11_user_top.xpr"
p23="$part03/ch23/build/soc23_sim"
[[ -f "$p21" && -d "$p23" ]] || { echo "NOT_RUN POWER: 5-2·5-4 build 먼저"; exit 2; }
# shellcheck disable=SC1090
[[ -n "${VIVADO_SETTINGS:-}" ]] && source "$VIVADO_SETTINGS"
command -v vivado >/dev/null || { echo "NOT_RUN POWER: vivado 없음"; exit 2; }
build="$chapter_dir/build"
rm -rf "$build"; mkdir -p "$build/out"
cp -a "$p23" "$build/soc25_sim"
(cd "$build" && vivado -mode batch -nojournal -log "$build/vivado_sim.log" -source "$chapter_dir/synth/soc_power_sim.tcl" \
  -tclargs "$build/soc25_sim/soc11_user_top.xpr" "$build/out" > "$build/sim_stdout.txt" 2>&1) || true
grep -E "SOC_BENCH|SOC_RTL_SIM_PASS|SOC_POWER_SIM_END|^ERROR" "$build/sim_stdout.txt"
ls -la "$build/out"/*.saif | awk '{print $5, $9}' | sed "s#$build/##"
(cd "$build" && vivado -mode batch -nojournal -log "$build/vivado_pwr.log" -source "$chapter_dir/synth/soc_power_report.tcl" \
  -tclargs "$p21" "$build/out" > "$build/pwr_stdout.txt" 2>&1) || true
grep -E "SOC_POWER_REPORT_DONE|^ERROR" "$build/pwr_stdout.txt"
export PYTHONDONTWRITEBYTECODE=1
python3 "$chapter_dir/reference/power_summary.py" --rpt "$build/out" --out "$chapter_dir/validation/power_summary.md"
