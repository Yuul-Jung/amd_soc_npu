#!/usr/bin/env bash
# 장 Top 시뮬레이션 한 번 실행 (run_sim.sh가 source 해서 쓴다). 시뮬레이터는 환경변수 SIM으로 고른다.
#   SIM=iverilog (기본) : Icarus Verilog — GitHub CI가 쓰는 자동 검사용
#   SIM=xsim            : Vivado 시뮬레이터(xvlog → xelab → xsim) — 교재 실습과 같은 도구
# 같은 TB·같은 사례 파일·같은 판정 줄을 쓴다. 저장소 루트에서 부른다 (TB가 사례 파일을 상대 경로로 연다).
#   sim_top <top 모듈> <STAGE> <빌드 폴더> <소스 파일…>
sim_tool_version() {
  if [ "${SIM:-iverilog}" = xsim ]; then xvlog --version 2>&1 | sed -n 1p; else iverilog -V 2>&1 | sed -n 1p; fi
}
sim_top() {
  local top="$1" stage="$2" build="$3"; shift 3
  if [ "${SIM:-iverilog}" = xsim ]; then
    local snap="${top}_s${stage}"
    # xvlog는 Icarus보다 엄격하다(선언 전 사용 등). 경고·정보 줄은 로그에서 걸러 판정 줄만 남긴다.
    xvlog -sv -nolog "$@" | grep -E "^(ERROR|CRITICAL)" || true
    xelab -nolog -timescale 1ns/1ps -generic_top "STAGE=$stage" "$top" -s "$snap" | grep -E "^(ERROR|CRITICAL)" || true
    xsim "$snap" -nolog -R | grep -vE "^(INFO|Vivado Simulator|Copyright|Time resolution|source |## |run -all|exit|\\*\\*\\*\\*\\*\\*)" || true
  else
    iverilog -g2012 -Wall -s "$top" -P "$top.STAGE=$stage" -o "$build/${top}_s$stage.vvp" "$@"
    vvp -n "$build/${top}_s$stage.vvp"
  fi
}
