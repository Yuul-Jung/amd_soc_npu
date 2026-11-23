#!/usr/bin/env bash
# Vivado Out-of-Context 합성(7개 구성) → validation/synth_ooc_summary.md.
# 기본으로 OOC 배치·배선까지 수행한다(IMPL=0이면 합성만). 비트스트림·실물 없음.
# Vivado가 PATH에 없으면 VIVADO_SETTINGS로 settings64.sh 지정.
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
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/p3-19s.XXXXXXXX")
trap 'rm -rf "$build_dir"' EXIT
version=$(vivado -version | sed -n '1s/^[Vv]ivado v\([0-9.]*\).*/\1/p')
echo "Vivado $version"
(cd "$build_dir" && vivado -mode batch -nojournal -log "$build_dir/vivado.log" \
  -source "$chapter_dir/synth/synth_ooc.tcl" -tclargs "$part03" "$build_dir/rpt" "$([[ ${IMPL:-1} == 1 ]] && echo impl || echo synth)" > "$build_dir/stdout.txt")
grep -E "^Synthesis finished|^ERROR|^CRITICAL WARNING" "$build_dir/vivado.log"
python3 "$chapter_dir/reference/synth_summary.py" --rpt "$build_dir/rpt" \
  --out "$chapter_dir/validation/synth_ooc_summary.md" --version "$version"
