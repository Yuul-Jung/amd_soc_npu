#!/usr/bin/env bash
# 제3부 RTL 회귀: 3-1~3-4·4-2~4-4·5-1(AXI4-Lite NPU IP)·5-3(C 드라이버 PC 시뮬레이션)·6-2(합성곱 RTL)와
# 6-1·6-3·6-4·6-5의 PC 검증(장치 RTL·펌웨어↔NPU RTL PC 시뮬레이션·변이)을 차례로 돌린다.
# 실행 스크립트가 없는 장은 NOT_IMPLEMENTED로 표시한다. 파일 이름은 기존 호출 경로를 지키려고 그대로 둔다.
# 5-2(BD·비트스트림), 5-4~5-6(SoC xsim·Vivado 분석)은 도구 실행 장이라 넣지 않는다.
# 시뮬레이터는 각 장 run_sim.sh가 고른다(common/scripts/p3_sim.sh: Vivado 있으면 xsim, 없으면 iverilog).
set -euo pipefail
part03="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
status=0
for n in 13 14 15 16 17 18 19 20 22 26 28 29 30 31; do
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
