#!/usr/bin/env bash
# (추가) 13~19장 신규 RTL 회귀. 구현된 장만 실행하고, 실행 스크립트가 없는 장은 NOT_IMPLEMENTED로 표시한다.
set -euo pipefail
part03="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
status=0
for n in 13 14 15 16 17 18 19; do
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
