#!/usr/bin/env bash
# CPU·NPU 벤치마크 ELF 빌드(보드용·시뮬레이션용)와 SoC 전체 행동 시뮬레이션(xsim).
#   필요: 5-2 build_soc.sh 결과(ch21/build), VIVADO_SETTINGS·VITIS_SETTINGS
#   결과: validation/soc_bench_sim.log. 보드 실측은 build/bench_board ELF로 사용자와 함께 한다.
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
part03=$(cd -- "$chapter_dir/.." && pwd)
src_proj="$part03/ch21/build/soc21_npu"
xsa="$part03/ch21/build/out/soc21_npu.xsa"
if [[ ! -f "$xsa" || ! -d "$src_proj" ]]; then echo "NOT_RUN SOC_BENCH: 21장 build_soc.sh 먼저"; exit 2; fi
# shellcheck disable=SC1090
[[ -n "${VIVADO_SETTINGS:-}" ]] && source "$VIVADO_SETTINGS"
# shellcheck disable=SC1090
[[ -n "${VITIS_SETTINGS:-}" ]] && source "$VITIS_SETTINGS"
command -v vivado >/dev/null && command -v vitis >/dev/null || { echo "NOT_RUN SOC_BENCH: vivado/vitis 없음"; exit 2; }
build="$chapter_dir/build"
rm -rf "$build"; mkdir -p "$build/cfg_board" "$build/cfg_sim"
export PYTHONDONTWRITEBYTECODE=1
python3 "$part03/ch22/reference/gen_model.py" --out "$build/model_data.h"
echo "#define BENCH_SIM 0" > "$build/cfg_board/bench_cfg.h"
echo "#define BENCH_SIM 1" > "$build/cfg_sim/bench_cfg.h"
sw22="$part03/ch22/sw"
for v in board sim; do
  (cd "$build" && vitis -s "$part03/ch22/vitis/vitis_build.py" "$build/ws" "$xsa" "bench_$v" \
    "$sw22/npu_driver.h" "$sw22/npu_driver.c" "$sw22/npu_io_xil.c" "$chapter_dir/sw/bench.c" \
    "$build/model_data.h" "$build/cfg_$v/bench_cfg.h" > "$build/vitis_$v.log" 2>&1) || true
  grep -q "VITIS_BUILD_DONE bench_$v" "$build/vitis_$v.log" || { echo "VITIS_BUILD_FAIL bench_$v"; exit 1; }
  elf=$(find "$build/ws/bench_$v" -name "bench_$v.elf" | head -1)
  echo "ELF bench_$v $(sed -n 2p "$elf.size" | awk '{print "text="$1, "data="$2, "bss="$3}') sha256=$(sha256sum "$elf" | cut -c1-16)"
done
cp -a "$src_proj" "$build/soc23_sim"
elf_sim=$(find "$build/ws/bench_sim" -name "bench_sim.elf" | head -1)
(cd "$build" && vivado -mode batch -nojournal -log "$build/vivado_sim.log" \
  -source "$chapter_dir/synth/soc_bench_sim.tcl" \
  -tclargs "$build/soc23_sim/soc11_user_top.xpr" "$chapter_dir/tb/tb_soc_bench.sv" "$elf_sim" \
  > "$build/sim_stdout.txt" 2>&1) || true
grep -E "SOC_BENCH|SOC_RTL_SIM_PASS|Fatal|FATAL|^ERROR" "$build/sim_stdout.txt" | sed "s#$build#build#g"
grep -q SOC_RTL_SIM_PASS "$build/sim_stdout.txt"
