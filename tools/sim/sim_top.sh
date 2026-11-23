#!/usr/bin/env bash
# 장 Top 시뮬레이션 한 번 실행 (run_sim.sh가 source 해서 쓴다). 저장소 루트에서 부른다 (TB가 사례 파일을 상대 경로로 연다).
# 시뮬레이터: Vivado가 있으면(xvlog가 PATH에 있으면) Vivado 시뮬레이터를 쓰고, 없으면 iverilog를 쓴다. SIM=xsim|iverilog로 고정할 수 있다.
#   sim_top <top 모듈> <STAGE> <빌드 폴더> <소스 파일…>
sim_kind() {
  if [ -n "${SIM:-}" ]; then echo "$SIM"; elif command -v xvlog >/dev/null 2>&1; then echo xsim; else echo iverilog; fi
}
sim_tool_version() {
  # xvlog는 현재 폴더에 xvlog.log·xvlog.pb를 남기므로 임시 폴더에서 실행한다
  if [ "$(sim_kind)" = xsim ]; then (d=$(mktemp -d) && cd "$d" && xvlog --version 2>&1 | sed -n 1p; rm -rf "$d"); else iverilog -V 2>&1 | sed -n 1p; fi
}
sim_top() {
  local top="$1" stage="$2" build="$3"; shift 3
  if [ "$(sim_kind)" = xsim ]; then
    local snap="${top}_s${stage}"
    xvlog -sv -nolog "$@" | grep -E "^(ERROR|CRITICAL)" || true
    xelab -nolog -timescale 1ns/1ps -generic_top "STAGE=$stage" "$top" -s "$snap" | grep -E "^(ERROR|CRITICAL)" || true
    xsim "$snap" -nolog -R | grep -vE "^(INFO|Vivado Simulator|Copyright|Time resolution|source |## |run -all|exit|\\*\\*\\*\\*\\*\\*)" || true
  else
    iverilog -g2012 -Wall -s "$top" -P "$top.STAGE=$stage" -o "$build/${top}_s$stage.vvp" "$@"
    vvp -n "$build/${top}_s$stage.vvp"
  fi
}
