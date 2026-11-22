#!/usr/bin/env bash
# (추가) 20장: AXI4-Lite NPU 제어 IP Vivado OOC 합성·배치·배선(19장 synth_ooc.tcl 재사용) → validation/synth_ooc_summary.md.
# 비트스트림·실물 없음. Vivado가 PATH에 없으면 VIVADO_SETTINGS로 settings64.sh 지정.
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
part03=$(cd -- "$chapter_dir/.." && pwd)
if ! command -v vivado >/dev/null 2>&1; then
  if [[ -n "${VIVADO_SETTINGS:-}" ]]; then
    # shellcheck disable=SC1090
    source "$VIVADO_SETTINGS"
  else
    echo "NOT_RUN SYNTH_OOC: vivado 없음 (VIVADO_SETTINGS=<Vivado>/settings64.sh 지정)"
    exit 2
  fi
fi
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/p3-20s.XXXXXXXX")
trap 'rm -rf "$build_dir"' EXIT
version=$(vivado -version | sed -n '1s/^[Vv]ivado v\([0-9.]*\).*/\1/p')
echo "Vivado $version"
(cd "$build_dir" && vivado -mode batch -nojournal -log "$build_dir/vivado.log" \
  -source "$part03/ch19/synth/synth_ooc.tcl" \
  -tclargs "$part03" "$build_dir/rpt" impl "$chapter_dir/synth/synth_configs.tcl" > "$build_dir/stdout.txt")
grep -E "^Synthesis finished|^ERROR|^CRITICAL WARNING" "$build_dir/vivado.log"
python3 "$part03/ch19/reference/synth_summary.py" --rpt "$build_dir/rpt" \
  --out "$chapter_dir/validation/synth_ooc_summary.md" --version "$version" \
  --title "20장 AXI4-Lite NPU 제어 IP Vivado OOC 합성·배선 (실제 실행)" \
  --config axi_npu_int8 "AXI NPU INT8" "p3_npu_axi_lite 기본(17장 Tile + 04장 x 버퍼)"
