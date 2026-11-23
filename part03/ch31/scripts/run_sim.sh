#!/usr/bin/env bash
# 보안 모델 적재 PC 검증.
#   1) Python 기준모델: AES-128·CTR·SHA-256·HMAC 알려진 정답(NIST/RFC), cryptography 교차 확인(있으면), 거부 규칙
#   2) C 암호 구현 알려진 정답(host/crypto_selftest.c)
#   3) AES-128·SHA-256 RTL = 정답·무작위 벡터, RTL 변이 6종
#   4) 종단간 PC 시뮬레이션(호스트 → C 펌웨어 → NPU RTL): 모델 B 보안 적재·추론, 거부·전송 오류 시험, 모델 A 재적재
#   5) 펌웨어 변이 7종이 모두 FAIL이어야 한다
#   키: 저장소의 TEST 키만 쓴다. 로그에는 키 지문만 남는다.
set -euo pipefail
chapter_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
part03=$(cd -- "$chapter_dir/.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/p3-31.XXXXXXXX")
trap 'rm -rf "$build_dir"' EXIT
export PYTHONDONTWRITEBYTECODE=1
source "$chapter_dir/../common/scripts/p3_sim.sh"   # Vivado 있으면 xsim, 없으면 iverilog (SIM=로 고정)
python3 --version
gcc --version | sed -n '1p'
p3_sim_version
ref="$chapter_dir/reference/secure_reference.py"
python3 "$ref" --selftest --header "$build_dir/secure_keys.h" --rtl-vectors "$build_dir/aes.txt" "$build_dir/sha.txt"
python3 "$part03/ch29/reference/sensor_reference.py" --header "$build_dir/sensor_model.h" > /dev/null
gcc -std=c99 -O2 -Wall -Wextra -Werror -I"$chapter_dir/sw" -o "$build_dir/kat" "$chapter_dir/sw/p3_crypto.c" "$chapter_dir/host/crypto_selftest.c"
"$build_dir/kat"

# 3) RTL
rtl_run() {   # $1 = aes|sha, $2 = RTL 소스
  if [[ $1 == aes ]]; then
    p3_sim_build "$build_dir/aes" tb_p3_aes128 -- "$2" "$chapter_dir/tb/tb_p3_aes128.sv"
    p3_sim_run "$build_dir/aes" +VEC="$build_dir/aes.txt" | grep -v "finish called"
  else
    p3_sim_build "$build_dir/sha" tb_p3_sha256 -- "$2" "$chapter_dir/tb/tb_p3_sha256.sv"
    p3_sim_run "$build_dir/sha" +VEC="$build_dir/sha.txt" | grep -v "finish called"
  fi
}
rtl_run aes "$chapter_dir/rtl/p3_aes128_enc.v" | tee "$build_dir/aes.log"
rtl_run sha "$chapter_dir/rtl/p3_sha256_core.v" | tee "$build_dir/sha.log"
grep -q RTL_SIM_PASS "$build_dir/aes.log" && grep -q RTL_SIM_PASS "$build_dir/sha.log"
python3 - "$chapter_dir/rtl" "$build_dir" <<'PY'
import sys
from pathlib import Path
rtl, out = Path(sys.argv[1]), Path(sys.argv[2])
mut = {
    "aes_last_round_mix": ("p3_aes128_enc.v", "(round == 4'd10 ? ss : mix(ss))", "mix(ss)"),
    "aes_rcon_fixed": ("p3_aes128_enc.v", "rcon <= xtime(rcon);", "rcon <= rcon;"),
    "aes_no_shiftrows": ("p3_aes128_enc.v", "j = (i + 4 * (i % 4)) % 16;", "j = i;"),
    "sha_k_index": ("p3_sha256_core.v", "kc(t[5:0])", "kc(t[5:0] + 6'd1)"),
    "sha_sigma1_rot": ("p3_sha256_core.v", "rotr(e, 25)", "rotr(e, 24)"),
    "sha_chain_iv": ("p3_sha256_core.v", "a <= H[0]; b <= H[1];", "a <= 32'h6a09e667; b <= H[1];"),
}
for name, (f, a, b) in mut.items():
    src = (rtl / f).read_text()
    assert src.count(a) == 1, name
    (out / f"rtlmut_{name}.v").write_text(src.replace(a, b))
print("RTL_MUTANTS " + " ".join(mut))
PY
rk=0; rt=0
for m in "$build_dir"/rtlmut_*.v; do
  rt=$((rt + 1)); n=$(basename "$m" .v); n=${n#rtlmut_}
  if rtl_run "${n%%_*}" "$m" | grep -q RTL_SIM_PASS; then echo "RTL_MUTANT $n SURVIVED"; else rk=$((rk + 1)); echo "RTL_MUTANT $n KILLED"; fi
done
echo "RTL_MUTATION_SUMMARY killed=$rk total=$rt"
[[ $rk -eq $rt ]]

# 4) PC 시뮬레이션
p3_sim_build "$build_dir/sim" tb_p3_npu_bridge -- -I"$part03/ch20/tb" \
  "$part03/ch02/rtl/dsp_multiplier.v" "$part03/mini_npu/rtl/npu_dsp_mac_lane.v" \
  "$part03/ch04/rtl/bram_sync_buffer.v" "$part03/ch14/rtl/p3_group10_core.v" \
  "$part03/ch17/rtl/p3_tile784_10.v" "$part03/ch20/rtl/p3_npu_axi_lite.v" \
  "$part03/ch22/tb/tb_p3_npu_bridge.sv"
run_cosim() {   # $1 = 펌웨어 소스, $2 = 이름, 나머지 = 호스트 인자
  local app=$1 name=$2; shift 2
  local d="$build_dir/$name" werr=-Werror
  [[ $name == mut_* ]] && werr=-Wno-error
  mkdir -p "$d"
  gcc -std=c99 -D_DEFAULT_SOURCE -O2 -Wall -Wextra $werr -DNPU_HOST_SIM \
    -I"$part03/ch22/sw" -I"$part03/ch29/sw" -I"$chapter_dir/sw" -I"$build_dir" -o "$d/fw" \
    "$part03/ch22/sw/npu_driver.c" "$part03/ch29/sw/sensor_app.c" "$app" "$chapter_dir/sw/p3_crypto.c" \
    "$part03/ch22/host/npu_io_cosim.c" "$part03/ch29/host/sensor_io_host.c" "$chapter_dir/host/secure_cosim_main.c"
  mkfifo "$d/cmd" "$d/rsp"
  p3_sim_run "$build_dir/sim" +CMD="$d/cmd" +RSP="$d/rsp" > "$d/sim.log" 2>&1 &
  local sim_pid=$! host_rc=0 sim_rc=0
  python3 "$chapter_dir/host/p3_secure_host.py" --cosim "$d/fw $d/cmd $d/rsp" "$@" > "$d/host.log" 2>&1 || host_rc=$?
  wait "$sim_pid" || sim_rc=$?
  COSIM_HOST_RC=$host_rc
  COSIM_SIM_RC=$sim_rc
}
run_cosim "$chapter_dir/sw/secure_app.c" golden \
  --csv "$chapter_dir/validation/rtl_cosim.csv" --log "$chapter_dir/validation/rtl_cosim_uart.log"
grep -vE "^STEP .* PASS" "$build_dir/golden/host.log" || true
echo "STEPS_PASS $(grep -cE '^STEP .* PASS' "$build_dir/golden/host.log")"
grep -v "finish called" "$build_dir/golden/sim.log"
if [[ $COSIM_HOST_RC -ne 0 || $COSIM_SIM_RC -ne 0 ]] || ! grep -q RTL_SIM_PASS "$build_dir/golden/sim.log"; then
  echo "SECURE_COSIM_FAIL host_rc=$COSIM_HOST_RC sim_rc=$COSIM_SIM_RC"
  exit 1
fi
# 키 노출 검사: 로그·CSV에 TEST 키 바이트(16진)가 없어야 한다
python3 - "$chapter_dir/validation" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]).resolve().parents[2]))
from part03.ch31.reference.secure_reference import TEST_KEYS
for f in Path(sys.argv[1]).glob("rtl_cosim*"):
    t = f.read_text().lower()
    assert all(k.hex() not in t for k in TEST_KEYS), f"key material in {f.name}"
print("KEY_NOT_IN_LOGS_PASS")
PY

# 5) 펌웨어 변이
python3 - "$chapter_dir/sw/secure_app.c" "$build_dir" <<'PY'
import sys
from pathlib import Path
src, out = Path(sys.argv[1]).read_text(), Path(sys.argv[2])
mutants = {
    "skip_mac": ("    if (!ct_equal(tag, rx + HDR_LEN + len, 32)) {", "    if (0) {"),
    "no_replay": ("    if (seq <= last_seq) {", "    if (0) {"),
    "no_nonce_bind": ("    if (ivseq != seq || ivctr != 0) {", "    if (0) {"),
    "consume_seq_on_auth_fail": ("        reject(R_AUTH, seq);", "        last_seq = seq;\n        reject(R_AUTH, seq);"),
    "no_header_id_check": (" || bank[st].id != mid) {", ") {"),
    "no_blob_id_check": ("    return m->id == rd32(p + 8);", "    return 1;"),
    "no_length_bound": ("            if (len > MAX_LEN) {", "            if (len > 100000u) {"),
}
for name, (a, b) in mutants.items():
    assert src.count(a) == 1, f"mutation pattern not unique: {name}"
    (out / f"mut_{name}.c").write_text(src.replace(a, b))
print("MUTANTS " + " ".join(mutants))
PY
killed=0; total=0
for src in "$build_dir"/mut_*.c; do
  name=$(basename "$src" .c)
  total=$((total + 1))
  run_cosim "$src" "$name" --timeout 20 --csv "$build_dir/$name.csv" --log "$build_dir/$name.log"
  if [[ $COSIM_HOST_RC -ne 0 ]]; then
    killed=$((killed + 1))
    echo "MUTANT ${name#mut_} KILLED ($(grep -m1 -E '^STEP .* FAIL|SECURE_HOST_FAIL|Traceback' "$build_dir/$name/host.log" | cut -c1-110))"
  else
    echo "MUTANT ${name#mut_} SURVIVED"
  fi
done
echo "MUTATION_SUMMARY killed=$killed total=$total"
[[ $total -gt 0 && $killed -eq $total ]]
echo "PYTHON_RTL_COMPARE_PASS ch31 crypto_rtl=kat+random host->secure_frame->c_firmware(etm,replay,atomic)->npu_rtl"
