# (추가) 23장: 21장 SoC 복제 프로젝트에 TB와 벤치마크 ELF(시뮬레이션용)를 연결해 xsim 행동 시뮬레이션을 실행한다.
# 사용: vivado -mode batch -source soc_bench_sim.tcl -tclargs <복제 xpr> <tb_soc_bench.sv> <bench_sim.elf>
set xpr [lindex $argv 0]
set tb [file normalize [lindex $argv 1]]
set elf [file normalize [lindex $argv 2]]
open_project $xpr
add_files -fileset sim_1 -norecurse $tb
set_property top tb_soc_bench [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
# Associate ELF: 시뮬레이션에서 microblaze_riscv_0의 LMB BRAM 초기값으로 쓴다
add_files -fileset sim_1 -norecurse $elf
set ef [get_files -all -of_objects [get_filesets sim_1] [file tail $elf]]
set_property SCOPED_TO_REF soc11_integration $ef
set_property SCOPED_TO_CELLS {microblaze_riscv_0} $ef
set_property -name {xsim.simulate.runtime} -value {0ns} -objects [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
run all
puts "SOC_SIM_RUN_END"
close_sim
