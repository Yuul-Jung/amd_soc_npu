# (추가) 21장: 복제된 제1부 11장 MicroBlaze V 프로젝트에 20장 NPU AXI4-Lite IP를 추가하고 Bitstream·XSA까지 만든다.
# 원본 프로젝트는 열지 않는다(build_soc.sh가 cp -a로 복제한 사본만 연다). BD 이름·사용자 Top·Wrapper 이름은 그대로.
# 사용: vivado -mode batch -source soc_npu_bd.tcl -tclargs <복제 xpr> <IP repo> <XDC> <출력 폴더> <jobs>
set xpr [lindex $argv 0]
set ip_repo [file normalize [lindex $argv 1]]
set xdc [file normalize [lindex $argv 2]]
set out [file normalize [lindex $argv 3]]
set jobs [lindex $argv 4]
set npu_base 0x44A00000
set npu_range 4K
file mkdir $out

proc check {cond msg} {
  if {[uplevel 1 [list expr $cond]]} { puts "CHECK_PASS $msg" } else { puts "CHECK_FAIL $msg"; exit 1 }
}

open_project $xpr
# 원본의 상대 경로 XDC($PPRDIR/../../Basys-3-Master.xdc)는 사본 위치에서 맞지 않으므로 같은 활성 줄의 21장 XDC로 바꾼다
foreach f [get_files -quiet -of_objects [get_filesets constrs_1]] { remove_files -fileset constrs_1 $f }
add_files -fileset constrs_1 -norecurse $xdc
set_property ip_repo_paths [list $ip_repo] [current_project]
update_ip_catalog -rebuild

set bd_file [get_files -filter {FILE_TYPE == "Block Designs"}]
open_bd_design $bd_file
set bd [current_bd_design]
puts "BD $bd"

# NPU IP 추가, SmartConnect 마스터 포트 1개 추가(M04)
set npu [create_bd_cell -type ip -vlnv user.org:p3:p3_npu_axi_lite:1.0 p3_npu_0]
set smc [get_bd_cells axi_smc]
set nmi [get_property CONFIG.NUM_MI $smc]
check {$nmi == 4} "SmartConnect NUM_MI 4 in original"
set_property CONFIG.NUM_MI 5 $smc
connect_bd_intf_net [get_bd_intf_pins axi_smc/M04_AXI] [get_bd_intf_pins p3_npu_0/s_axi]

# 클록·Reset: 기존 AXI 주변장치(GPIO)와 같은 넷에 연결
set clk_net [get_bd_nets -of_objects [get_bd_pins axi_gpio_0/s_axi_aclk]]
set rst_net [get_bd_nets -of_objects [get_bd_pins axi_gpio_0/s_axi_aresetn]]
connect_bd_net -net $clk_net [get_bd_pins p3_npu_0/s_axi_aclk]
connect_bd_net -net $rst_net [get_bd_pins p3_npu_0/s_axi_aresetn]

# 인터럽트: intr[0] = 기존 Timer, intr[1] = NPU
set tmr_net [get_bd_nets -of_objects [get_bd_pins axi_timer_0/interrupt]]
delete_bd_objs $tmr_net
set cat [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 irq_concat]
set_property CONFIG.NUM_PORTS 2 $cat
connect_bd_net [get_bd_pins axi_timer_0/interrupt] [get_bd_pins irq_concat/In0]
connect_bd_net [get_bd_pins p3_npu_0/irq_o] [get_bd_pins irq_concat/In1]
connect_bd_net [get_bd_pins irq_concat/dout] [get_bd_pins axi_intc_0/intr]

# 주소: 사용자 IP 기본 영역 0x44A0_0000, 4 KB
assign_bd_address -target_address_space /microblaze_riscv_0/Data [get_bd_addr_segs p3_npu_0/s_axi/reg0] \
  -offset $npu_base -range $npu_range
validate_bd_design
save_bd_design

# ---- 정적 검사: 주소 겹침·클록·Reset·인터럽트 ----
set segs [get_bd_addr_segs -of_objects [get_bd_addr_spaces /microblaze_riscv_0/Data]]
set rows {}
foreach s $segs {
  set off [get_property OFFSET $s]; set rng [get_property RANGE $s]
  lappend rows [list [get_property NAME $s] $off $rng]
  puts "ADDR [get_property NAME $s] $off $rng"
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
set nseg [get_bd_addr_segs -of_objects [get_bd_addr_spaces /microblaze_riscv_0/Data] -filter {NAME =~ "*p3_npu_0*"}]
check {[get_property OFFSET $nseg] == $npu_base} "NPU base $npu_base"
check {[get_bd_nets -of_objects [get_bd_pins p3_npu_0/s_axi_aclk]] eq [get_bd_nets -of_objects [get_bd_pins axi_smc/aclk]]} "NPU clock = SmartConnect clock"
check {[get_bd_nets -of_objects [get_bd_pins p3_npu_0/s_axi_aresetn]] eq [get_bd_nets -of_objects [get_bd_pins rst_clk_wiz_1_100M/peripheral_aresetn]]} "NPU reset = peripheral_aresetn"
check {[get_bd_nets -of_objects [get_bd_pins irq_concat/dout]] eq [get_bd_nets -of_objects [get_bd_pins axi_intc_0/intr]]} "irq_concat -> axi_intc intr"
# 원본과 같은 IP별 OOC 합성(Hierarchical)을 유지한다. MicroBlaze V 코어는 전역 합성에서 black box가 된다.
make_wrapper -files $bd_file -top -force
generate_target all $bd_file
create_ip_run [get_files $bd_file]
export_ip_user_files -of_objects $bd_file -no_script -sync -force -quiet

# 사용자 Top은 원본 그대로(기능 논리 없음): basys3_soc11_top
check {[get_property top [current_fileset]] eq "basys3_soc11_top"} "user top basys3_soc11_top kept"

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
set wns [get_property SLACK [get_timing_paths -setup -max_paths 1]]
set whs [get_property SLACK [get_timing_paths -hold -max_paths 1]]
puts "TIMING WNS=$wns WHS=$whs"
check {$wns >= 0 && $whs >= 0} "post-route setup/hold met"
write_hw_platform -fixed -include_bit -force $out/soc21_npu.xsa
foreach f [glob -nocomplain [get_property DIRECTORY [get_runs impl_1]]/*.bit] { file copy -force $f $out/ }
puts "SOC21_BUILD_DONE"
