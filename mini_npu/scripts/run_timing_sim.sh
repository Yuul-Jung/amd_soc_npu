#!/usr/bin/env bash
# 12장 배선 후 타이밍 시뮬레이션 (Vivado xsim + SDF slow corner).
# 입력: vivado_impl.tcl 이 만든 mini_npu/build/impl/basys3_npu_top_timesim.{v,sdf}
# 시험: RTL 시뮬레이션과 같은 tb_npu_uart.sv (UART 핀 파형).
#   기본 = RTL과 같은 전체 시나리오: 분류 6 · Bias 변경 · ERR (시뮬 시간 약 29.2 ms) → TIMING_SIM_PASS
#   TIMESIM_SHORT=1 = 짧은 smoke 시험: 분류 1 · Bias 변경 뒤 재분류 1 · ERR 1 (약 10.8 ms) → TIMING_SIM_SMOKE_PASS
#     smoke는 클래스 1·2를 만들지 않아 LED1·2 고장 같은 결함을 놓친다. 게이트 증거로 쓰지 않는다.
#   시간은 대부분 115200 bps UART 송신(응답 1줄 52바이트 ≈ 4.5 ms)이다.
# 판정: INTEGRATED_UART_RTL_SIM_PASS + PC_GOLDEN_COMPARE_PASS → TIMING_SIM_PASS
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
for t in xvlog xelab xsim; do
    command -v "$t" >/dev/null 2>&1 || { echo "TIMING_SIM_NOT_RUN: $t not found (source Vivado settings64.sh)" >&2; exit 2; }
done
: "${XILINX_VIVADO:?TIMING_SIM_NOT_RUN: XILINX_VIVADO not set}"
impl="$root/mini_npu/build/impl"
net="$impl/basys3_npu_top_timesim.v"
[ -f "$net" ] && [ -f "$impl/basys3_npu_top_timesim.sdf" ] || {
    echo "TIMING_SIM_NOT_RUN: run vivado_impl.tcl first" >&2; exit 2; }

ts="$root/mini_npu/build/timesim"
rm -rf "$ts"; mkdir -p "$ts"
# 타이밍 넷리스트에도 uart_rx 모듈이 있으므로 TB 쪽 UART 수신 모니터만 이름을 바꾼 사본을 쓴다.
sed 's/^module uart_rx\([ #(]\)/module tb_uart_rx_monitor\1/' common/rtl/uart_rx.v > "$ts/tb_uart_rx_monitor.v"
sed 's/^\([[:space:]]*\)uart_rx tx_monitor/\1tb_uart_rx_monitor tx_monitor/' mini_npu/tb/tb_npu_uart.sv > "$ts/tb_npu_uart_timesim.sv"
grep -q '^module tb_uart_rx_monitor' "$ts/tb_uart_rx_monitor.v"
grep -q 'tb_uart_rx_monitor tx_monitor' "$ts/tb_npu_uart_timesim.sv"
# 진행 표시(1 ms마다 응답 수). 타이밍 시뮬레이션은 수 시간이 걸려 멈춤과 느림을 구분해야 한다.
sed -i 's/^\([[:space:]]*\)integer scenario,exp_cls;/\1always #1000000 $display("TIMESIM_PROGRESS t=%0d ms results=%0d ack=%0d err=%0d",$time\/1000000,c_count,ack_count,err_count);\n&/' "$ts/tb_npu_uart_timesim.sv"
grep -q 'TIMESIM_PROGRESS' "$ts/tb_npu_uart_timesim.sv"
# xsim은 SDF INTERCONNECT 대상 이름의 대괄호 이스케이프(reg\[0\])를 조용히 무시한다 → 클록 배선 지연이
# 일부 FF에만 걸려 가짜 hold 경합(UART 수신 valid 소실)이 생긴다. 이름만 같은 규칙으로 바꾼 사본을 쓴다.
python3 "$root/mini_npu/scripts/timesim_sanitize.py" "$net" "$impl/basys3_npu_top_timesim.sdf" \
    "$ts/basys3_npu_top_timesim.v" "$ts/basys3_npu_top_timesim.sdf"
net="$ts/basys3_npu_top_timesim.v"

cd "$ts"
xvlog "$net"
xvlog tb_uart_rx_monitor.v
xvlog -sv tb_npu_uart_timesim.sv
xvlog "$XILINX_VIVADO/data/verilog/src/glbl.v"
xelab --relax -L simprims_ver -L secureip -maxdelay -transport_int_delays \
      -pulse_r 0 -pulse_int_r 0 -pulse_e 0 -pulse_int_e 0 \
      -s tb_timesim work.tb_npu_uart work.glbl
if [ "${TIMESIM_SHORT:-0}" = 1 ]; then mode=short; tag=TIMING_SIM_SMOKE_PASS; plus=(-testplusarg SHORT); chk=(--short); n=2; else mode=full; tag=TIMING_SIM_PASS; plus=(); chk=(); n=6; fi
echo "TIMESIM_MODE $mode"
xsim tb_timesim -R -testplusarg "CSV=$ts/predictions.csv" "${plus[@]}" | tee timesim.log
grep -q 'INTEGRATED_UART_RTL_SIM_PASS' timesim.log || { echo "TIMING_SIM_FAIL"; exit 1; }
python3 "$root/mini_npu/reference/check_results.py" "$ts/predictions.csv" "${chk[@]}" | tee -a timesim.log
# xsim 타이밍 검사 경고("Timing violation" 줄) 수를 판정 줄에 함께 남긴다. 0이 아니면 증거를 볼 때 원인을 확인해야 한다
# (경고 문구 형식은 Vivado xsim 실제 로그로 확인할 것 — 웹에서는 xsim을 돌리지 못했다).
viol=$(grep -ci "timing violation" timesim.log || true)
echo "$tag ch12 basys3_npu_top post-route SDF(slow) classes=$n model_edit=1 invalid_length=1 timing_violations=$viol scenario=$mode" | tee -a timesim.log
