# (추가) 28장: 21장 SoC 복제본(MicroBlaze V + NPU)에 FND 표시 경로를 더하고 Bitstream·XSA까지 만든다.
#   AXI GPIO 1(32비트 출력, 0x4001_0000) → p3_fnd_scan(BD 모듈 참조, 같은 클록·Reset) → 외부 포트 seg/dp/an
#   사용자 Top: basys3_soc28_top(핀 연결만). 21장 build 결과와 제1부 원본은 열지 않는다(build_soc.sh가 cp -a 복제).
# 사용: vivado -mode batch -source soc28_bd.tcl -tclargs <복제 xpr> <ch28 폴더> <출력 폴더> <jobs>
set xpr [lindex $argv 0]
set ch [file normalize [lindex $argv 1]]
set out [file normalize [lindex $argv 2]]
set jobs [lindex $argv 3]
set gpio_base 0x40010000
file mkdir $out

proc check {cond msg} {
  if {[uplevel 1 [list expr $cond]]} { puts "CHECK_PASS $msg" } else { puts "CHECK_FAIL $msg"; exit 1 }
}

open_project $xpr
foreach f [get_files -quiet -of_objects [get_filesets constrs_1]] { remove_files -fileset constrs_1 $f }
add_files -fileset constrs_1 -norecurse $ch/constraints/basys3_soc28.xdc
add_files -norecurse [list $ch/rtl/p3_fnd_scan.v $ch/rtl/basys3_soc28_top.v]
# 원본 Top(basys3_soc11_top)은 새 Wrapper 포트와 맞지 않으므로 이 복제본에서만 비활성
set_property is_enabled false [get_files basys3_soc11_top.v]
update_compile_order -fileset sources_1

set bd_file [get_files -filter {FILE_TYPE == "Block Designs"}]
open_bd_design $bd_file
puts "BD [current_bd_design]"
check {[llength [get_bd_cells -quiet p3_npu_0]] == 1} "21장 NPU 포함 SoC에서 시작"

set smc [get_bd_cells axi_smc]
check {[get_property CONFIG.NUM_MI $smc] == 5} "SmartConnect NUM_MI 5 (21장)"
set_property CONFIG.NUM_MI 6 $smc
set g [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_1]
set_property -dict [list CONFIG.C_GPIO_WIDTH 32 CONFIG.C_ALL_OUTPUTS 1 CONFIG.C_DOUT_DEFAULT 0x00000000] $g
connect_bd_intf_net [get_bd_intf_pins axi_smc/M05_AXI] [get_bd_intf_pins axi_gpio_1/S_AXI]
set clk_net [get_bd_nets -of_objects [get_bd_pins axi_gpio_0/s_axi_aclk]]
set rst_net [get_bd_nets -of_objects [get_bd_pins axi_gpio_0/s_axi_aresetn]]
connect_bd_net -net $clk_net [get_bd_pins axi_gpio_1/s_axi_aclk]
connect_bd_net -net $rst_net [get_bd_pins axi_gpio_1/s_axi_aresetn]

set f [create_bd_cell -type module -reference p3_fnd_scan fnd_scan_0]
connect_bd_net -net $clk_net [get_bd_pins fnd_scan_0/clk]
connect_bd_net -net $rst_net [get_bd_pins fnd_scan_0/resetn]
connect_bd_net [get_bd_pins axi_gpio_1/gpio_io_o] [get_bd_pins fnd_scan_0/word_i]
foreach {pin port} {seg_o seg dp_o dp an_o an} {
  make_bd_pins_external -name $port [get_bd_pins fnd_scan_0/$pin]
}
assign_bd_address -target_address_space /microblaze_riscv_0/Data [get_bd_addr_segs axi_gpio_1/S_AXI/Reg] \
  -offset $gpio_base -range 64K
validate_bd_design
save_bd_design

set segs [get_bd_addr_segs -of_objects [get_bd_addr_spaces /microblaze_riscv_0/Data]]
set rows {}
foreach s $segs {
  lappend rows [list [get_property NAME $s] [get_property OFFSET $s] [get_property RANGE $s]]
  puts "ADDR [get_property NAME $s] [get_property OFFSET $s] [get_property RANGE $s]"
}
set overlap 0
foreach a $rows {
  foreach b $rows {
    if {[lindex $a 0] ne [lindex $b 0]} {
      set a0 [expr {[lindex $a 1]}]; set a1 [expr {$a0 + [lindex $a 2]}]
      set b0 [expr {[lindex $b 1]}]; set b1 [expr {$b0 + [lindex $b 2]}]
      if {$a0 < $b1 && $b0 < $a1} { set overlap 1; puts "OVERLAP [lindex $a 0] [lindex $b 0]" }
    }
  }
}
check {$overlap == 0} "data address segments do not overlap"
set gseg [get_bd_addr_segs -of_objects [get_bd_addr_spaces /microblaze_riscv_0/Data] -filter {NAME =~ "*axi_gpio_1*"}]
check {[get_property OFFSET $gseg] == $gpio_base} "FND GPIO base $gpio_base"
set nseg [get_bd_addr_segs -of_objects [get_bd_addr_spaces /microblaze_riscv_0/Data] -filter {NAME =~ "*p3_npu_0*"}]
check {[get_property OFFSET $nseg] == 0x44A00000} "NPU base unchanged 0x44A00000"
check {[get_bd_nets -of_objects [get_bd_pins fnd_scan_0/clk]] eq [get_bd_nets -of_objects [get_bd_pins axi_smc/aclk]]} "FND clock = SmartConnect clock"
check {[get_bd_nets -of_objects [get_bd_pins fnd_scan_0/resetn]] eq [get_bd_nets -of_objects [get_bd_pins rst_clk_wiz_1_100M/peripheral_aresetn]]} "FND reset = peripheral_aresetn"
foreach port {seg dp an} { check {[llength [get_bd_ports -quiet $port]] == 1} "BD port $port" }

make_wrapper -files $bd_file -top -force
generate_target all $bd_file
create_ip_run [get_files $bd_file]
export_ip_user_files -of_objects $bd_file -no_script -sync -force -quiet
set_property top basys3_soc28_top [current_fileset]
update_compile_order -fileset sources_1
check {[get_property top [current_fileset]] eq "basys3_soc28_top"} "user top basys3_soc28_top"

reset_run synth_1
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
check {[get_property PROGRESS [get_runs synth_1]] eq "100%"} "synth_1 complete"
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
check {[get_property PROGRESS [get_runs impl_1]] eq "100%"} "impl_1 + bitstream complete"
open_run impl_1
report_utilization -file $out/soc_utilization.rpt
report_utilization -hierarchical -hierarchical_depth 3 -file $out/soc_utilization_hier.rpt
report_timing_summary -max_paths 3 -file $out/soc_timing.rpt
report_io -file $out/soc_io.rpt
set wns [get_property SLACK [get_timing_paths -setup -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -hold -max_paths 1]]
puts "TIMING WNS=$wns WHS=$whs"
check {$wns >= 0 && $whs >= 0} "post-route setup/hold met"
foreach {port pin} {seg[0] W7 seg[6] U7 dp V7 an[0] U2 an[3] W4 RsRx B18 led[15] L1} {
  check {[get_property PACKAGE_PIN [get_ports $port]] eq $pin} "pin $port = $pin"
}
write_hw_platform -fixed -include_bit -force $out/soc28_digit.xsa
foreach f [glob -nocomplain [get_property DIRECTORY [get_runs impl_1]]/*.bit] { file copy -force $f $out/ }
puts "SOC28_BUILD_DONE"
