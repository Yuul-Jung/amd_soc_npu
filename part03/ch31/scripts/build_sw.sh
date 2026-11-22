#!/usr/bin/env bash
# (추가) 31장: 28장 SoC(Bitstream·XSA 그대로) 위의 보안 모델 적재 펌웨어 ELF. 하드웨어 변경 없음.
# (변경) 안 A(2026-11-19): 하드웨어는 21장 SoC(동결 주소맵·표준 7세그먼트 IP)의 Bitstream·XSA를 그대로 쓴다(28장 BD 폐지).
#   키: P3_KEY_FILE(저장소 밖, 16진 96자 = 암호화 16바이트 ‖ MAC 32바이트)이 있으면 그 키, 없으면 TEST 키.
#   키가 든 헤더는 build/(저장소 제외)에만 생기고, 출력에는 키 지문만 남는다.
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
part03=$(cd -- "$chapter_dir/.." && pwd)
xsa="$part03/ch21/build/out/soc21_npu.xsa"
bit="$part03/ch21/build/out/basys3_soc21_top.bit"
if [[ ! -f "$xsa" || ! -f "$bit" ]]; then echo "NOT_RUN SECURE_SW_BUILD: 21장 build_soc.sh 먼저"; exit 2; fi
# shellcheck disable=SC1090
[[ -n "${VITIS_SETTINGS:-}" ]] && source "$VITIS_SETTINGS"
command -v vitis >/dev/null || { echo "NOT_RUN SECURE_SW_BUILD: vitis 없음"; exit 2; }
build="$chapter_dir/build"
rm -rf "$build"; mkdir -p "$build"
export PYTHONDONTWRITEBYTECODE=1
echo "HW (21장 그대로) $(sha256sum "$xsa" | cut -c1-16) soc21_npu.xsa, $(sha256sum "$bit" | cut -c1-16) basys3_soc21_top.bit"
python3 "$chapter_dir/reference/secure_reference.py" --header "$build/secure_keys.h" ${P3_KEY_FILE:+--key-file "$P3_KEY_FILE"}
python3 "$part03/ch29/reference/sensor_reference.py" --header "$build/sensor_model.h" > /dev/null
sw22="$part03/ch22/sw"; sw29="$part03/ch29/sw"; sw="$chapter_dir/sw"
(cd "$build" && P3_PLAT_NAME=soc31_secure_plat vitis -s "$part03/ch22/vitis/vitis_build.py" "$build/ws" "$xsa" secure_app \
  "$sw22/npu_driver.h" "$sw22/npu_driver.c" "$sw22/npu_io_xil.c" "$sw22/app.h" \
  "$sw29/sensor_io.h" "$sw29/sensor_app.h" "$sw29/sensor_app.c" "$sw29/sensor_io_xil.c" \
  "$sw/p3_crypto.h" "$sw/p3_crypto.c" "$sw/secure_app.h" "$sw/secure_app.c" "$sw/main.c" \
  "$part03/common/sw/p3_seg7.h" "$part03/common/sw/p3_stack_4k.c" "$build/sensor_model.h" "$build/secure_keys.h" > "$build/vitis.log" 2>&1) || true
grep -q "VITIS_BUILD_DONE secure_app" "$build/vitis.log" || { grep -iE "error" "$build/vitis.log" | head -20; echo "VITIS_BUILD_FAIL"; exit 1; }
grep -iE "warning:" "$build/vitis.log" | grep -E "secure_app/src/" | head -10 || true
xpar=$(find "$build/ws/soc31_secure_plat/export" -name xparameters.h | head -1)
grep -hE "XPAR_(P3_NPU_0|AXI_GPIO_0|AXI_UARTLITE_0|IP06_SEG7)_BASEADDR " "$xpar"
elf=$(find "$build/ws/secure_app" -name secure_app.elf | head -1)
echo "ELF secure_app $(sed -n 2p "$elf.size" | awk '{print "text="$1, "data="$2, "bss="$3, "total="$4}') sha256=$(sha256sum "$elf" | cut -c1-16)"
bash "$part03/common/sw/elf_mem_check.sh" "$elf"
echo "SECURE_SW_BUILD_PASS (빌드만, 실물 실행은 사용자와 함께)"
