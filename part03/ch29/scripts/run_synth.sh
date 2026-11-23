#!/usr/bin/env bash
# 경보 정책 RTL Vivado OOC 합성·배치·배선(4-4 synth_ooc.tcl 재사용) → validation/synth_ooc_summary.md
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
part03=$(cd -- "$chapter_dir/.." && pwd)
# shellcheck disable=SC1090
[[ -n "${VIVADO_SETTINGS:-}" ]] && source "$VIVADO_SETTINGS"
command -v vivado >/dev/null || { echo "NOT_RUN SYNTH_OOC: vivado 없음"; exit 2; }
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/p3-29s.XXXXXXXX")
trap 'rm -rf "$build_dir"' EXIT
version=$(vivado -version | sed -n '1s/^[Vv]ivado v\([0-9.]*\).*/\1/p')
echo "Vivado $version"
(cd "$build_dir" && vivado -mode batch -nojournal -log "$build_dir/vivado.log" \
  -source "$part03/ch19/synth/synth_ooc.tcl" \
  -tclargs "$part03" "$build_dir/rpt" impl "$chapter_dir/synth/synth_configs.tcl" > "$build_dir/stdout.txt")
grep -E "^Synthesis finished|^ERROR|^CRITICAL WARNING" "$build_dir/vivado.log" || true
python3 "$part03/ch19/reference/synth_summary.py" --rpt "$build_dir/rpt" \
  --out "$chapter_dir/validation/synth_ooc_summary.md" --version "$version" \
  --title "6-3 경보 정책 RTL Vivado OOC 합성·배선 (실제 실행)" \
  --config alarm_policy "ALARM_POLICY" "p3_alarm_policy (CLEAR_N=3)"
