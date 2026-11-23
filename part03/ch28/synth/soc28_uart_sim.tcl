# SoC 복제 프로젝트에 TB와 보드용 digit_app.elf를 연결해 xsim 행동 시뮬레이션을 실행한다.
# 사용: vivado -mode batch -source soc28_uart_sim.tcl -tclargs <복제 xpr> <tb_soc28_uart.sv> <digit_app.elf> <frame.hex> <record.txt>
set xpr [lindex $argv 0]
set tb [file normalize [lindex $argv 1]]
set elf [file normalize [lindex $argv 2]]
set frame [file normalize [lindex $argv 3]]
set rec [file normalize [lindex $argv 4]]
open_project $xpr
add_files -fileset sim_1 -norecurse $tb
set_property top tb_soc28_uart [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
# Associate ELF: 시뮬레이션에서 microblaze_riscv_0의 LMB BRAM 초기값(보드와 같은 ELF)
add_files -fileset sim_1 -norecurse $elf
set ef [get_files -all -of_objects [get_filesets sim_1] [file tail $elf]]
set_property SCOPED_TO_REF soc11_integration $ef
set_property SCOPED_TO_CELLS {microblaze_riscv_0} $ef
set_property -name {xsim.simulate.runtime} -value {0ns} -objects [get_filesets sim_1]
set_property -name {xsim.simulate.xsim.more_options} -value "-testplusarg FRAME=$frame -testplusarg OUT=$rec" \
  -objects [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
run all
puts "SOC_SIM_RUN_END"
close_sim
