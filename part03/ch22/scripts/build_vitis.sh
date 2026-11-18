#!/usr/bin/env bash
# (추가) 22장: 21장 XSA로 Vitis 플랫폼·응용(ELF)을 빌드한다. 실물 실행은 사용자와 함께 한다.
#   XSA: 21장 build/out/soc21_npu.xsa (기본), VITIS_SETTINGS: <Vitis>/settings64.sh
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
part03=$(cd -- "$chapter_dir/.." && pwd)
xsa=${XSA:-$part03/ch21/build/out/soc21_npu.xsa}
if [[ ! -f "$xsa" ]]; then echo "NOT_RUN VITIS_BUILD: XSA 없음 (21장 build_soc.sh 먼저)"; exit 2; fi
if ! command -v vitis >/dev/null 2>&1; then
  if [[ -n "${VITIS_SETTINGS:-}" ]]; then
    # shellcheck disable=SC1090
    source "$VITIS_SETTINGS"
  else
    echo "NOT_RUN VITIS_BUILD: vitis 없음 (VITIS_SETTINGS=<Vitis>/settings64.sh 지정)"; exit 2
  fi
fi
build="$chapter_dir/build"
rm -rf "$build"; mkdir -p "$build"
export PYTHONDONTWRITEBYTECODE=1
python3 "$chapter_dir/reference/gen_model.py" --out "$build/model_data.h"
(cd "$build" && vitis -s "$chapter_dir/vitis/vitis_build.py" "$build/ws" "$xsa" "$chapter_dir/sw" \
  "$build/model_data.h" > "$build/vitis.log" 2>&1) || true
grep -E "VITIS_BUILD_DONE|[Ee]rror|ERROR" "$build/vitis.log" | sed "s#$build#build#g" | head -20
grep -q VITIS_BUILD_DONE "$build/vitis.log"
elf=$(find "$build/ws/npu_app" -name "npu_app.elf" | head -1)
xpar=$(find "$build/ws/soc21_npu_plat/export" -name xparameters.h | head -1)
grep -h "XPAR_P3_NPU_0_BASEADDR\|XPAR_P3_NPU_0_HIGHADDR" "$xpar"
cat "$elf.size"
sha256sum "$elf" | sed "s#$build/##"
echo "VITIS_ELF_PASS (빌드만, 실물 실행은 사용자와 함께)"
