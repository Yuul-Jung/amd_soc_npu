#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export PYTHONDONTWRITEBYTECODE=1
echo "tclsh $(echo 'puts [info patchlevel]' | tclsh)"
tclsh <<'TCL'
set fh [open vivado/report_power.tcl]; set t [read $fh]; close $fh
if {![info complete $t]} { puts "TCL_SYNTAX_STATIC_CHECK_FAIL"; exit 1 }
puts "TCL_SYNTAX_STATIC_CHECK_PASS power_reports=[regexp -all {report_power -file} $t] activity_reset=[regexp -all {reset_switching_activity} $t]"
TCL
python3 reference/energy.py host/fixture host/fixture/bench.csv | sed -e 's/^POWER_PARSE_PASS/ENERGY_PARSER_STATIC_CHECK_PASS fixture/' -e '/^ENERGY_PARSER/!s/^/[견본·실측 아님] /'
if [ -d ../build/ch25 ]; then python3 reference/energy.py ../build/ch25 "$(ls ../ch23/validation/board_bench_*.csv 2>/dev/null | tail -1)"; else echo "REAL_POWER NOT_RUN (Vivado 미실행)"; fi
