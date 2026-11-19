#!/usr/bin/env bash
# (추가) 29장: 28장 SoC(Bitstream·XSA 그대로) 위에서 도는 센서 감시 펌웨어 ELF를 만든다. 하드웨어 변경 없음.
#   필요: 28장 build_soc.sh 결과(ch28/build/out/soc28_digit.xsa, basys3_soc28_top.bit) — 읽기만 한다.
#   결과(build/, 저장소 제외): ws/sensor_app ELF.
# (변경) 31장: 스택 1 KB → 4 KB(part03/common/sw/p3_stack_4k.c, -O0 최대 호출 깊이 약 960 B 측정)와 ELF 메모리 검사.  요약은 validation/build_sw.log 로 남긴다.
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
part03=$(cd -- "$chapter_dir/.." && pwd)
xsa="$part03/ch28/build/out/soc28_digit.xsa"
bit="$part03/ch28/build/out/basys3_soc28_top.bit"
if [[ ! -f "$xsa" || ! -f "$bit" ]]; then echo "NOT_RUN SENSOR_SW_BUILD: 28장 build_soc.sh 먼저"; exit 2; fi
# shellcheck disable=SC1090
[[ -n "${VITIS_SETTINGS:-}" ]] && source "$VITIS_SETTINGS"
command -v vitis >/dev/null || { echo "NOT_RUN SENSOR_SW_BUILD: vitis 없음"; exit 2; }
build="$chapter_dir/build"
rm -rf "$build"; mkdir -p "$build"
export PYTHONDONTWRITEBYTECODE=1
echo "HW (28장 그대로) $(sha256sum "$xsa" | cut -c1-16) soc28_digit.xsa, $(sha256sum "$bit" | cut -c1-16) basys3_soc28_top.bit"
python3 "$chapter_dir/reference/sensor_reference.py" --header "$build/sensor_model.h"
sw22="$part03/ch22/sw"; sw="$chapter_dir/sw"
(cd "$build" && P3_PLAT_NAME=soc29_sensor_plat vitis -s "$part03/ch22/vitis/vitis_build.py" "$build/ws" "$xsa" sensor_app \
  "$sw22/npu_driver.h" "$sw22/npu_driver.c" "$sw22/npu_io_xil.c" "$sw22/app.h" \
  "$sw/sensor_io.h" "$sw/sensor_app.h" "$sw/sensor_app.c" "$sw/sensor_io_xil.c" "$sw/main.c" \
  "$part03/common/sw/p3_stack_4k.c" "$build/sensor_model.h" > "$build/vitis.log" 2>&1) || true
grep -q "VITIS_BUILD_DONE sensor_app" "$build/vitis.log" || { grep -iE "error" "$build/vitis.log" | head -20; echo "VITIS_BUILD_FAIL"; exit 1; }
grep -iE "warning:" "$build/vitis.log" | grep -E "sensor_app/src/" | head -10 || true
xpar=$(find "$build/ws/soc29_sensor_plat/export" -name xparameters.h | head -1)
grep -hE "XPAR_(P3_NPU_0|AXI_GPIO_1|AXI_GPIO_0|AXI_UARTLITE_0)_BASEADDR" "$xpar"
elf=$(find "$build/ws/sensor_app" -name sensor_app.elf | head -1)
echo "ELF sensor_app $(sed -n 2p "$elf.size" | awk '{print "text="$1, "data="$2, "bss="$3, "total="$4}') sha256=$(sha256sum "$elf" | cut -c1-16)"
bash "$part03/common/sw/elf_mem_check.sh" "$elf"
echo "SENSOR_SW_BUILD_PASS (빌드만, 실물 실행은 사용자와 함께)"
