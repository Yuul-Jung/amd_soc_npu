#!/usr/bin/env bash
# 모터 안전 SoC(5-2 SoC + 모터 GPIO 0x4007_0000 + p3_motor_safety) Bitstream·XSA와 펌웨어 ELF.
#   필요: 5-2 build_soc.sh 결과(ch21/build/soc21_npu). 그 폴더는 읽기만 하고 cp -a로 복제한다(전후 해시 확인).
#   결과(build/, 저장소 제외): soc30 복제 프로젝트, out/*.bit, out/soc30_motor.xsa, ws/motor_app ELF
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
part03=$(cd -- "$chapter_dir/.." && pwd)
src_proj="$part03/ch21/build/soc21_npu"
if [[ ! -f "$src_proj/soc11_user_top.xpr" ]]; then echo "NOT_RUN SOC30_BUILD: 5-2 build_soc.sh 먼저"; exit 2; fi
# shellcheck disable=SC1090
[[ -n "${VIVADO_SETTINGS:-}" ]] && source "$VIVADO_SETTINGS"
# shellcheck disable=SC1090
[[ -n "${VITIS_SETTINGS:-}" ]] && source "$VITIS_SETTINGS"
command -v vivado >/dev/null && command -v vitis >/dev/null || { echo "NOT_RUN SOC30_BUILD: vivado/vitis 없음"; exit 2; }
build="$chapter_dir/build"
rm -rf "$build"; mkdir -p "$build"
export PYTHONDONTWRITEBYTECODE=1
tree_sum() { (cd "$1" && find . -type f -not -path "*/.Xil/*" -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-16); }
before=$(tree_sum "$src_proj")
cp -a "$src_proj" "$build/soc30"
(cd "$build" && vivado -mode batch -nojournal -log "$build/vivado.log" -source "$chapter_dir/synth/soc30_bd.tcl" \
  -tclargs "$build/soc30/soc11_user_top.xpr" "$chapter_dir" "$build/out" "${JOBS:-4}" > "$build/stdout.txt") || true
after=$(tree_sum "$src_proj")
grep -E "^(BD|ADDR|OVERLAP|IRQ_MAP_A|CHECK_PASS|CHECK_FAIL|TIMING|SOC30_BUILD_DONE)|^ERROR|^CRITICAL WARNING" "$build/stdout.txt" \
  | sed "s#$build#build#g; s#$part03#part03#g"
if [[ "$before" == "$after" ]]; then echo "CH21_PROJECT_UNCHANGED tree_sha=$before"; else echo "CH21_PROJECT_CHANGED"; exit 1; fi
grep -q "^SOC30_BUILD_DONE" "$build/stdout.txt"
xsa="$build/out/soc30_motor.xsa"
sha256sum "$xsa" "$build"/out/*.bit | sed "s#$build/##"

python3 "$part03/ch29/reference/sensor_reference.py" --header "$build/sensor_model.h"
sw22="$part03/ch22/sw"; sw29="$part03/ch29/sw"; sw="$chapter_dir/sw"
(cd "$build" && P3_PLAT_NAME=soc30_motor_plat vitis -s "$part03/ch22/vitis/vitis_build.py" "$build/ws" "$xsa" motor_app \
  "$sw22/npu_driver.h" "$sw22/npu_driver.c" "$sw22/npu_io_xil.c" "$sw22/app.h" \
  "$sw29/sensor_io.h" "$sw29/sensor_app.h" "$sw29/sensor_app.c" "$sw29/sensor_io_xil.c" \
  "$sw/motor_app.h" "$sw/motor_app.c" "$sw/main.c" "$part03/common/sw/p3_seg7.h" "$part03/common/sw/p3_stack_4k.c" "$build/sensor_model.h" \
  > "$build/vitis.log" 2>&1) || true
grep -q "VITIS_BUILD_DONE motor_app" "$build/vitis.log" || { grep -iE "error" "$build/vitis.log" | head -20; echo "VITIS_BUILD_FAIL"; exit 1; }
grep -iE "warning:" "$build/vitis.log" | grep -E "motor_app/src/" | head -10 || true
xpar=$(find "$build/ws/soc30_motor_plat/export" -name xparameters.h | head -1)
grep -hE "XPAR_(P3_NPU_0|AXI_GPIO_MOTOR|AXI_GPIO_BTN|AXI_GPIO_0|AXI_UARTLITE_0|AXI_TIMER_0|AXI_INTC_0|IP06_SEG7)_BASEADDR" "$xpar"
grep -hE "XPAR_AXI_GPIO_MOTOR_IS_DUAL" "$xpar" || true
elf=$(find "$build/ws/motor_app" -name motor_app.elf | head -1)
echo "ELF motor_app $(sed -n 2p "$elf.size" | awk '{print "text="$1, "data="$2, "bss="$3, "total="$4}') sha256=$(sha256sum "$elf" | cut -c1-16)"
bash "$part03/common/sw/elf_mem_check.sh" "$elf"
echo "SOC30_BUILD_PASS (빌드만, 실물 실행은 사용자와 함께)"
