#!/usr/bin/env bash
# (변경) 안 A(2026-11-19): 28장은 하드웨어를 따로 만들지 않는다. 21장 SoC(Bitstream·XSA, 동결 주소맵·표준 7세그먼트 IP)
#   위에서 도는 숫자 인식 펌웨어 ELF만 만든다(이전 build_soc.sh·soc28_bd.tcl·basys3_soc28_top·axi_gpio_1은 삭제).
#   필요: 21장 build_soc.sh 결과(ch21/build/out/soc21_npu.xsa, basys3_soc21_top.bit) — 읽기만 한다.
#   결과(build/, 저장소 제외): ws/digit_app ELF.  요약은 validation/build_sw.log 로 남긴다.
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
part03=$(cd -- "$chapter_dir/.." && pwd)
xsa="$part03/ch21/build/out/soc21_npu.xsa"
bit="$part03/ch21/build/out/basys3_soc21_top.bit"
if [[ ! -f "$xsa" || ! -f "$bit" ]]; then echo "NOT_RUN DIGIT_SW_BUILD: 21장 build_soc.sh 먼저"; exit 2; fi
# shellcheck disable=SC1090
[[ -n "${VITIS_SETTINGS:-}" ]] && source "$VITIS_SETTINGS"
command -v vitis >/dev/null || { echo "NOT_RUN DIGIT_SW_BUILD: vitis 없음"; exit 2; }
build="$chapter_dir/build"
rm -rf "$build"; mkdir -p "$build"
export PYTHONDONTWRITEBYTECODE=1
echo "HW (21장 그대로) $(sha256sum "$xsa" | cut -c1-16) soc21_npu.xsa, $(sha256sum "$bit" | cut -c1-16) basys3_soc21_top.bit"
python3 "$chapter_dir/reference/digit_reference.py" --header "$build/digit_model.h"
sw22="$part03/ch22/sw"; sw="$chapter_dir/sw"
(cd "$build" && P3_PLAT_NAME=soc28_digit_plat vitis -s "$part03/ch22/vitis/vitis_build.py" "$build/ws" "$xsa" digit_app \
  "$sw22/npu_driver.h" "$sw22/npu_driver.c" "$sw22/npu_io_xil.c" "$sw22/app.h" \
  "$sw/digit_io.h" "$sw/digit_app.h" "$sw/digit_app.c" "$sw/digit_io_xil.c" "$sw/main.c" \
  "$part03/common/sw/p3_seg7.h" "$part03/common/sw/p3_stack_4k.c" "$build/digit_model.h" > "$build/vitis.log" 2>&1) || true
grep -q "VITIS_BUILD_DONE digit_app" "$build/vitis.log" || { grep -iE "error" "$build/vitis.log" | head -20; echo "VITIS_BUILD_FAIL"; exit 1; }
grep -iE "warning:" "$build/vitis.log" | grep -E "digit_app/src/" | head -10 || true
xpar=$(find "$build/ws/soc28_digit_plat/export" -name xparameters.h | head -1)
grep -hE "XPAR_(P3_NPU_0|AXI_GPIO_0|AXI_UARTLITE_0|IP06_SEG7)_BASEADDR " "$xpar"
elf=$(find "$build/ws/digit_app" -name digit_app.elf | head -1)
echo "ELF digit_app $(sed -n 2p "$elf.size" | awk '{print "text="$1, "data="$2, "bss="$3, "total="$4}') sha256=$(sha256sum "$elf" | cut -c1-16)"
bash "$part03/common/sw/elf_mem_check.sh" "$elf"
echo "DIGIT_SW_BUILD_PASS (빌드만, 실물 실행은 사용자와 함께)"
