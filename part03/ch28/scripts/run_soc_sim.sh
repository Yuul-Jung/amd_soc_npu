#!/usr/bin/env bash
# (추가) 28장: 숫자 인식 SoC 전체 행동 시뮬레이션(xsim, 실제 MicroBlaze V + 보드용 ELF + UART 비트 단위 프레임).
# (변경) 안 A: 하드웨어는 21장 SoC 복제본(ch21/build/soc21_npu, 읽기만 하고 cp -a), ELF는 build_sw.sh 결과.
#   필요: 21장 build_soc.sh, 28장 build_sw.sh 결과(build/ws/digit_app ELF), VIVADO_SETTINGS. 시뮬레이션 약 0.2초 분량(수 시간).
#   결과: validation/soc_uart_sim.log (TB 기록 + Python 판정)
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
part03=$(cd -- "$chapter_dir/.." && pwd)
build="$chapter_dir/build"
elf=$(find "$build/ws/digit_app" -name digit_app.elf 2>/dev/null | head -1)
src_proj="$part03/ch21/build/soc21_npu"
if [[ -z "$elf" || ! -f "$src_proj/soc11_user_top.xpr" ]]; then echo "NOT_RUN SOC28_SIM: 21장 build_soc.sh·28장 build_sw.sh 먼저"; exit 2; fi
# shellcheck disable=SC1090
[[ -n "${VIVADO_SETTINGS:-}" ]] && source "$VIVADO_SETTINGS"
command -v vivado >/dev/null || { echo "NOT_RUN SOC28_SIM: vivado 없음"; exit 2; }
export PYTHONDONTWRITEBYTECODE=1
sim="$build/sim"
rm -rf "$sim"; mkdir -p "$sim"
cp -a "$src_proj" "$sim/soc28_sim"
python3 "$chapter_dir/reference/soc_sim_check.py" --make "$sim/frame.hex" "$sim/expect.json"
echo "ELF digit_app sha256=$(sha256sum "$elf" | cut -c1-16) (보드와 같은 ELF)"
(cd "$sim" && vivado -mode batch -nojournal -log "$sim/vivado_sim.log" -source "$chapter_dir/synth/soc28_uart_sim.tcl" \
  -tclargs "$sim/soc28_sim/soc11_user_top.xpr" "$chapter_dir/tb/tb_soc28_uart.sv" "$elf" "$sim/frame.hex" \
  "$sim/record.txt" > "$sim/stdout.txt" 2>&1) || true
grep -E "UART<|SOC28_SIM_END|Fatal|FATAL|^ERROR" "$sim/stdout.txt" | tr -d '\000' | sed "s#$build#build#g"
[[ -f "$sim/record.txt" ]] || { echo "SOC28_RTL_SIM_FAIL no record"; exit 1; }
tr -d '\000' < "$sim/record.txt" | grep -E "^(FND|PIN|BOOT_DONE|SEND|RESPONSE_DONE|SOC28_SIM_END)"
python3 "$chapter_dir/reference/soc_sim_check.py" --check "$sim/record.txt" "$sim/expect.json"
