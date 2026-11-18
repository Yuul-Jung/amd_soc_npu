#!/usr/bin/env bash
# (추가) 20장: AXI4-Lite NPU IP 패키징(Vivado ipx). 출력 IP 폴더는 빌드 산출물(기본: 임시 폴더, IP_OUT로 지정).
# 인터페이스(s_axi AXI4-Lite, clock, reset, interrupt)와 주소 블록을 확인해 validation/package_ip.log에 남긴다.
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
part03=$(cd -- "$chapter_dir/.." && pwd)
if ! command -v vivado >/dev/null 2>&1; then
  if [[ -n "${VIVADO_SETTINGS:-}" ]]; then
    # shellcheck disable=SC1090
    source "$VIVADO_SETTINGS"
  else
    echo "NOT_RUN IP_PACKAGE: vivado 없음 (VIVADO_SETTINGS=<Vivado>/settings64.sh 지정)"
    exit 2
  fi
fi
work=$(mktemp -d "${TMPDIR:-/tmp}/p3-20p.XXXXXXXX")
trap 'rm -rf "$work"' EXIT
ip_out=${IP_OUT:-$work/ip}
(cd "$work" && vivado -mode batch -nojournal -log "$work/vivado.log" \
  -source "$chapter_dir/synth/package_ip.tcl" -tclargs "$part03" "$work/proj" "$ip_out" > "$work/out.txt")
grep -E "^(BUSIF|ADDRBLOCK|IP_PACKAGE_DONE)|^ERROR|^CRITICAL WARNING" "$work/out.txt"
grep -q "^IP_PACKAGE_DONE" "$work/out.txt"
