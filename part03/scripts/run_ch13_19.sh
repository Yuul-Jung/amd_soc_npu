#!/usr/bin/env bash
# (추가) 13~19장 신규 RTL 회귀. 구현된 장만 실행하고, 실행 스크립트가 없는 장은 NOT_IMPLEMENTED로 표시한다.
# (변경) 20장 AXI4-Lite NPU IP, 22장 C 드라이버 협동 시뮬레이션을 회귀에 포함한다(파일 이름은 기존 호출 경로 보존).
# 21장은 Vivado BD·Bitstream 빌드 장(ch21/scripts/build_soc.sh)이라 RTL 회귀에 넣지 않는다.
set -euo pipefail
part03="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
status=0
for n in 13 14 15 16 17 18 19 20 22; do
  script="$part03/ch$n/scripts/run_sim.sh"
  if [[ ! -f "$script" ]]; then
    echo "NOT_IMPLEMENTED ch$n"
    continue
  fi
  log="$part03/ch$n/validation/rtl_sim.log"
  # 로그에는 저장소 밖 절대 경로를 남기지 않는다(part03/ 기준 상대 표기).
  if bash "$script" 2>&1 | sed "s#$part03#part03#g; s#${TMPDIR:-/tmp}/p3-[0-9]*\.[A-Za-z0-9]*#<tmp>#g" > "$log" \
     && grep -q "PYTHON_RTL_COMPARE_PASS" "$log"; then
    echo "PASS ch$n ($(grep -m1 RTL_SIM_PASS "$log"))"
  else
    echo "FAIL ch$n (see $log)"
    status=1
  fi
done
exit "$status"
