#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export PYTHONDONTWRITEBYTECODE=1
echo "tclsh $(echo 'puts [info patchlevel]' | tclsh)"
# ① Tcl 문법(괄호·따옴표 짝) 확인
tclsh <<'TCL'
set fh [open vivado/report_soc.tcl]; set t [read $fh]; close $fh
if {![info complete $t]} { puts "TCL_SYNTAX_STATIC_CHECK_FAIL"; exit 1 }
set n [regexp -all {report_(utilization|timing_summary|timing)} $t]
puts "TCL_SYNTAX_STATIC_CHECK_PASS reports=$n"
TCL
# ② 해석기 시험: 견본 보고서 (실제 Vivado 출력 아님)
python3 reference/parse_reports.py host/fixture | sed -e 's/^REPORT_PARSE_PASS/PARSER_STATIC_CHECK_PASS fixture/' -e '/^PARSER/!s/^/[견본·실측 아님] /'
# ③ 실제 보고서가 있으면 해석 (Vivado 실행 후)
if [ -d ../build/ch24 ]; then python3 reference/parse_reports.py ../build/ch24; else echo "REAL_REPORTS NOT_RUN (Vivado 미실행)"; fi
