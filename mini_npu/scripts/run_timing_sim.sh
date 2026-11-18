#!/usr/bin/env bash
# 12장 배선 후 타이밍 시뮬레이션 (Vivado xsim + SDF slow corner).
# 입력: vivado_impl.tcl 이 만든 mini_npu/build/impl/basys3_npu_top_timesim.{v,sdf}
# 시험: RTL 시뮬레이션과 같은 tb_npu_uart.sv (UART 핀 파형 → 6회 분류 · Bias 변경 · ERR)
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

cd "$ts"
xvlog "$net"
xvlog tb_uart_rx_monitor.v
xvlog -sv tb_npu_uart_timesim.sv
xvlog "$XILINX_VIVADO/data/verilog/src/glbl.v"
xelab --relax -L simprims_ver -L secureip -maxdelay -transport_int_delays \
      -pulse_r 0 -pulse_int_r 0 -pulse_e 0 -pulse_int_e 0 \
      -s tb_timesim work.tb_npu_uart work.glbl
xsim tb_timesim -R -testplusarg "CSV=$ts/predictions.csv" | tee timesim.log
grep -q 'INTEGRATED_UART_RTL_SIM_PASS' timesim.log || { echo "TIMING_SIM_FAIL"; exit 1; }
python3 "$root/mini_npu/reference/check_results.py" "$ts/predictions.csv" | tee -a timesim.log
echo "TIMING_SIM_PASS ch12 basys3_npu_top post-route SDF(slow) classes=6 model_edit=1 invalid_length=1" | tee -a timesim.log
