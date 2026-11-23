#!/usr/bin/env bash
# 제3부 RTL 단독 시뮬레이션 공용 함수 (각 장 run_sim.sh가 source 해서 쓴다).
# 시뮬레이터: Vivado가 있으면(xvlog가 PATH에 있으면) Vivado 시뮬레이터(xsim), 없으면 iverilog.
#   SIM=xsim | SIM=iverilog 로 고정할 수 있다. 같은 TB·같은 plusarg·같은 Python 판정을 쓴다.
#
#   p3_sim_version                                   도구 이름·버전 한 줄
#   p3_sim_build <출력 폴더> <top> [-P 이름=값 …] -- [-I<포함 폴더>] <소스 …>   컴파일·엘라보레이션
#   p3_sim_run   <출력 폴더> [+이름=값 | +이름 …]               실행 (실패하면 0이 아닌 값)

p3_sim_kind() {
  if [ -n "${SIM:-}" ]; then echo "$SIM"; elif command -v xvlog >/dev/null 2>&1; then echo xsim; else echo iverilog; fi
}

p3_sim_version() {
  # xvlog는 현재 폴더에 xvlog.log·xvlog.pb를 남기므로 임시 폴더에서 버전만 읽는다
  if [ "$(p3_sim_kind)" = xsim ]; then (d=$(mktemp -d) && cd "$d" && xvlog --version 2>&1 | sed -n 1p; rm -rf "$d")
  else iverilog -V 2>&1 | sed -n 1p; fi
}

p3_sim_build() {
  local out="$1" top="$2"; shift 2
  local params=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do
    [ "$1" = -P ] && { params+=("$2"); shift 2; continue; }
    echo "p3_sim_build: unknown option $1" >&2; return 2
  done
  shift   # --
  local inc=() src=() s
  for s in "$@"; do case "$s" in -I*) inc+=("${s#-I}");; *) src+=("$s");; esac; done
  set -- "${src[@]}"
  mkdir -p "$out"
  echo "$top" > "$out/.p3_top"
  if [ "$(p3_sim_kind)" = xsim ]; then
    local gen=() ii=() p log="$out/xsim_build.log"
    for p in "${params[@]}"; do gen+=(-generic_top "$p"); done
    for p in "${inc[@]}"; do ii+=(-i "$p"); done
    # xsim은 작업 폴더(xsim.dir)를 현재 폴더에 만든다 → 출력 폴더 안에서 실행한다.
    if ! (cd "$out" && xvlog -sv -nolog "${ii[@]}" "$@" && xelab -nolog -timescale 1ns/1ps "${gen[@]}" "$top" -s p3_snap) > "$log" 2>&1; then
      grep -E "^(ERROR|CRITICAL)" "$log" || tail -20 "$log"; return 1
    fi
    grep -E "^(ERROR|CRITICAL)" "$log" || true
  else
    local P=() p
    for p in "${params[@]}"; do P+=(-P"$top.$p"); done
    for p in "${inc[@]}"; do P+=(-I"$p"); done
    iverilog -g2012 -Wall -s "$top" "${P[@]}" -o "$out/sim" "$@"
  fi
}

p3_sim_run() {
  local out="$1"; shift
  if [ "$(p3_sim_kind)" = xsim ]; then
    local args=() a log="$out/xsim_run.log" rc=0
    for a in "$@"; do args+=(-testplusarg "${a#+}"); done
    (cd "$out" && xsim p3_snap -nolog -R "${args[@]}") > "$log" 2>&1 || rc=$?
    grep -vE "^(INFO|Vivado Simulator|Copyright|Time resolution|source |#|run -all|exit|[[:space:]]*\*\*|[[:space:]]*$)" "$log" || true
    # $fatal·컴파일 오류는 종료 코드가 0이어도 실패로 본다
    if [ $rc -ne 0 ] || grep -qE '^(Fatal|FATAL|ERROR)|\$fatal' "$log"; then return 1; fi
  else
    vvp "$out/sim" "$@"
  fi
}
