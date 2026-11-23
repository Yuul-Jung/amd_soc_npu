#!/usr/bin/env bash
# 제1부 11장 MicroBlaze V 성공 프로젝트를 복제해 5-1 NPU IP를 통합하고 Bitstream·XSA를 만든다.
#   SOC11_DIR : 원본 프로젝트 폴더(soc11_user_top.xpr 포함). 원본은 읽기만 하고 cp -a로 build/에 복제한다.
#   결과(build/, 저장소 제외): 복제 프로젝트, NPU IP, soc21_npu.xsa, *.bit, 보고서
#   요약(저장소): validation/build_soc.log, validation/soc_summary.md
# 동결 주소맵·BTN GPIO·표준 7세그먼트 IP. ADDR_MAP_A·IRQ_MAP_A 대조 결과를 로그에 남긴다.
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
part03=$(cd -- "$chapter_dir/.." && pwd)
if [[ -z "${SOC11_DIR:-}" || ! -f "$SOC11_DIR/soc11_user_top.xpr" ]]; then
  echo "NOT_RUN SOC21_BUILD: SOC11_DIR=<제1부 11장 soc11_user_top 폴더> 필요"
  exit 2
fi
if ! command -v vivado >/dev/null 2>&1; then
  if [[ -n "${VIVADO_SETTINGS:-}" ]]; then
    # shellcheck disable=SC1090
    source "$VIVADO_SETTINGS"
  else
    echo "NOT_RUN SOC21_BUILD: vivado 없음 (VIVADO_SETTINGS=<Vivado>/settings64.sh 지정)"
    exit 2
  fi
fi
build="$chapter_dir/build"
rm -rf "$build"
mkdir -p "$build"
# 원본 보존 확인용: 복제 전·후 원본 파일 목록과 해시
orig_sum() { (cd "$SOC11_DIR" && find . -type f -not -path "*/.Xil/*" -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-16); }
before=$(orig_sum)
cp -a "$SOC11_DIR" "$build/soc21_npu"
IP_OUT="$build/ip_repo/p3_npu_axi_lite" bash "$part03/ch20/scripts/package_ip.sh"
(cd "$build" && vivado -mode batch -nojournal -log "$build/vivado.log" \
  -source "$chapter_dir/synth/soc_npu_bd.tcl" \
  -tclargs "$build/soc21_npu/soc11_user_top.xpr" "$build/ip_repo" \
  "$chapter_dir/constraints/basys3_soc21_npu.xdc" "$build/out" "${JOBS:-4}" "$part03" > "$build/stdout.txt") || true
after=$(orig_sum)
grep -E "^(BD|ADDR|OVERLAP|IRQ_MAP_A|CHECK_PASS|CHECK_FAIL|TIMING|SOC21_BUILD_DONE)|^ERROR|^CRITICAL WARNING" "$build/stdout.txt" \
  | sed "s#$build#build#g"
if [[ "$before" == "$after" ]]; then echo "ORIGINAL_PROJECT_UNCHANGED tree_sha=$before"; else echo "ORIGINAL_PROJECT_CHANGED"; exit 1; fi
grep -q "^SOC21_BUILD_DONE" "$build/stdout.txt"
sha256sum "$build/out/soc21_npu.xsa" "$build"/out/*.bit | sed "s#$build/##"
