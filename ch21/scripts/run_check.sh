#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
echo "tclsh $(echo 'puts [info patchlevel]' | tclsh)"
tclsh scripts/check_bd.tcl | sed "s#$(cd .. && pwd)#<repo>#g"
