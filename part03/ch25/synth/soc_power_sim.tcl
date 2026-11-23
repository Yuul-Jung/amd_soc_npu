# 5-4 SoC 시뮬레이션 프로젝트에서 CPU 추론 구간과 NPU 추론 구간의 SAIF(토글률)를 따로 기록한다.
# 시뮬레이션은 결정적이라 5-4 결과로 구간 시각을 정한다: CPU 1~18 ms, NPU 19~28.9 ms(경계 여유).
# 사용: vivado -mode batch -source soc_power_sim.tcl -tclargs <5-4 복제 xpr> <출력 폴더>
set xpr [lindex $argv 0]
set out [file normalize [lindex $argv 1]]
file mkdir $out
open_project $xpr
launch_simulation -simset sim_1 -mode behavioral
run 1ms
open_saif $out/cpu.saif
log_saif [get_objects -r /tb_soc_bench/dut/*]
run 17ms
close_saif
run 1ms
open_saif $out/npu.saif
log_saif [get_objects -r /tb_soc_bench/dut/*]
run 9900us
close_saif
run all
puts "SOC_POWER_SIM_END"
close_sim
