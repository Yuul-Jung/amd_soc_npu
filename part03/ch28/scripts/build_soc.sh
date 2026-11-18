#!/usr/bin/env bash
# (추가) 28장: 숫자 인식 SoC(21장 MicroBlaze V + NPU + 28장 FND) Bitstream·XSA와 펌웨어 ELF를 만든다.
#   필요: 21장 build_soc.sh 결과(ch21/build/soc21_npu). 그 폴더는 읽기만 하고 cp -a로 복제한다(전후 해시 확인).
#   결과(build/, 저장소 제외): soc28 복제 프로젝트, out/*.bit, out/soc28_digit.xsa, ws/digit_app ELF
#   요약(저장소): validation/build_soc.log 와 validation/soc_summary.md 는 이 출력으로 만든다.
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
part03=$(cd -- "$chapter_dir/.." && pwd)
src_proj="$part03/ch21/build/soc21_npu"
if [[ ! -f "$src_proj/soc11_user_top.xpr" ]]; then echo "NOT_RUN SOC28_BUILD: 21장 build_soc.sh 먼저"; exit 2; fi
# shellcheck disable=SC1090
[[ -n "${VIVADO_SETTINGS:-}" ]] && source "$VIVADO_SETTINGS"
# shellcheck disable=SC1090
[[ -n "${VITIS_SETTINGS:-}" ]] && source "$VITIS_SETTINGS"
command -v vivado >/dev/null && command -v vitis >/dev/null || { echo "NOT_RUN SOC28_BUILD: vivado/vitis 없음"; exit 2; }
build="$chapter_dir/build"
rm -rf "$build"; mkdir -p "$build"
export PYTHONDONTWRITEBYTECODE=1
tree_sum() { (cd "$1" && find . -type f -not -path "*/.Xil/*" -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-16); }
before=$(tree_sum "$src_proj")
cp -a "$src_proj" "$build/soc28"
(cd "$build" && vivado -mode batch -nojournal -log "$build/vivado.log" -source "$chapter_dir/synth/soc28_bd.tcl" \
  -tclargs "$build/soc28/soc11_user_top.xpr" "$chapter_dir" "$build/out" "${JOBS:-4}" > "$build/stdout.txt") || true
after=$(tree_sum "$src_proj")
grep -E "^(BD|ADDR|OVERLAP|CHECK_PASS|CHECK_FAIL|TIMING|SOC28_BUILD_DONE)|^ERROR|^CRITICAL WARNING" "$build/stdout.txt" \
  | sed "s#$build#build#g; s#$part03#part03#g"
if [[ "$before" == "$after" ]]; then echo "CH21_PROJECT_UNCHANGED tree_sha=$before"; else echo "CH21_PROJECT_CHANGED"; exit 1; fi
grep -q "^SOC28_BUILD_DONE" "$build/stdout.txt"
xsa="$build/out/soc28_digit.xsa"
sha256sum "$xsa" "$build"/out/*.bit | sed "s#$build/##"

# 펌웨어: 22장 드라이버 + 28장 응용. 플랫폼은 28장 XSA(AXI GPIO 1 포함)
python3 "$chapter_dir/reference/digit_reference.py" --header "$build/digit_model.h"
sw22="$part03/ch22/sw"; sw="$chapter_dir/sw"
(cd "$build" && P3_PLAT_NAME=soc28_digit_plat vitis -s "$part03/ch22/vitis/vitis_build.py" "$build/ws" "$xsa" digit_app \
  "$sw22/npu_driver.h" "$sw22/npu_driver.c" "$sw22/npu_io_xil.c" "$sw22/app.h" \
  "$sw/digit_io.h" "$sw/digit_app.h" "$sw/digit_app.c" "$sw/digit_io_xil.c" "$sw/main.c" \
  "$build/digit_model.h" > "$build/vitis.log" 2>&1) || true
grep -q "VITIS_BUILD_DONE digit_app" "$build/vitis.log" || { grep -iE "error" "$build/vitis.log" | head -20; echo "VITIS_BUILD_FAIL"; exit 1; }
xpar=$(find "$build/ws/soc28_digit_plat/export" -name xparameters.h | head -1)
grep -hE "XPAR_(P3_NPU_0|AXI_GPIO_1|AXI_GPIO_0|AXI_UARTLITE_0)_BASEADDR" "$xpar"
elf=$(find "$build/ws/digit_app" -name digit_app.elf | head -1)
echo "ELF digit_app $(sed -n 2p "$elf.size" | awk '{print "text="$1, "data="$2, "bss="$3, "total="$4}') sha256=$(sha256sum "$elf" | cut -c1-16)"
echo "SOC28_BUILD_PASS (빌드만, 실물 실행은 사용자와 함께)"
