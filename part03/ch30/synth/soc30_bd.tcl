# SoC 복제본에 모터 안전 경로를 더하고 Bitstream·XSA까지 만든다.
# 출발점은 5-2 동결 주소맵 SoC(ch21/build/soc21_npu)다.
#   5-2 주소·인터럽트는 바꾸지 않고, 빈 칸 0x4007_0000(64 KB)에 모터 GPIO(axi_gpio_motor, 듀얼:
#   채널 1 출력 = 명령 워드, 채널 2 입력 = 상태 워드)만 더한다. 모터 경로는 인터럽트를 쓰지 않는다(In4 예약 그대로 0).
#   p3_motor_safety_bd(BD 모듈 참조, GPIO와 같은 클록·peripheral_aresetn) → 외부 포트(비상정지·고장·과열·리밋 입력,
#   IN1·IN2·ENA·트립 출력). 사용자 Top: basys3_soc30_top(핀 연결만). 5-2 결과물은 build_soc.sh가 cp -a로 복제한다.
# 사용: vivado -mode batch -source soc30_bd.tcl -tclargs <복제 xpr> <ch30 폴더> <출력 폴더> <jobs>
set xpr [lindex $argv 0]
set ch [file normalize [lindex $argv 1]]
set out [file normalize [lindex $argv 2]]
set jobs [lindex $argv 3]
set gpio_base 0x40070000
file mkdir $out

proc check {cond msg} {
  if {[uplevel 1 [list expr $cond]]} { puts "CHECK_PASS $msg" } else { puts "CHECK_FAIL $msg"; exit 1 }
}

open_project $xpr
foreach f [get_files -quiet -of_objects [get_filesets constrs_1]] { remove_files -fileset constrs_1 $f }
add_files -fileset constrs_1 -norecurse $ch/constraints/basys3_soc30.xdc
add_files -norecurse [list $ch/rtl/p3_motor_safety.v $ch/rtl/p3_motor_safety_bd.v $ch/rtl/basys3_soc30_top.v]
set_property is_enabled false [get_files basys3_soc21_top.v]
update_compile_order -fileset sources_1

set bd_file [get_files -filter {FILE_TYPE == "Block Designs"}]
open_bd_design $bd_file
puts "BD [current_bd_design]"
check {[llength [get_bd_cells -quiet ip06_seg7]] == 1 && [llength [get_bd_cells -quiet p3_npu_0]] == 1 && [llength [get_bd_cells -quiet axi_gpio_btn]] == 1} "21장 안 A SoC(NPU + BTN + SEG7)에서 시작"

set smc [get_bd_cells axi_smc]
check {[get_property CONFIG.NUM_MI $smc] == 7} "SmartConnect NUM_MI 7 (21장 안 A)"
set_property CONFIG.NUM_MI 8 $smc
set g [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_motor]
set_property -dict [list CONFIG.C_IS_DUAL 1 CONFIG.C_GPIO_WIDTH 32 CONFIG.C_ALL_OUTPUTS 1 CONFIG.C_DOUT_DEFAULT 0x00000000 \
  CONFIG.C_GPIO2_WIDTH 32 CONFIG.C_ALL_INPUTS_2 1] $g
connect_bd_intf_net [get_bd_intf_pins axi_smc/M07_AXI] [get_bd_intf_pins axi_gpio_motor/S_AXI]
set clk_net [get_bd_nets -of_objects [get_bd_pins axi_gpio_0/s_axi_aclk]]
set rst_net [get_bd_nets -of_objects [get_bd_pins axi_gpio_0/s_axi_aresetn]]
connect_bd_net -net $clk_net [get_bd_pins axi_gpio_motor/s_axi_aclk]
connect_bd_net -net $rst_net [get_bd_pins axi_gpio_motor/s_axi_aresetn]

set m [create_bd_cell -type module -reference p3_motor_safety_bd motor_safety_0]
connect_bd_net -net $clk_net [get_bd_pins motor_safety_0/clk]
connect_bd_net -net $rst_net [get_bd_pins motor_safety_0/resetn]
connect_bd_net [get_bd_pins axi_gpio_motor/gpio_io_o] [get_bd_pins motor_safety_0/cmd_i]
connect_bd_net [get_bd_pins motor_safety_0/status_o] [get_bd_pins axi_gpio_motor/gpio2_io_i]
foreach {pin port} {estop_ok_i estop_ok estop_btn_i estop_btn fault_i fault otemp_i otemp lim_f_i lim_f lim_r_i lim_r
                    in1_o in1 in2_o in2 ena_o ena trip_o trip} {
  make_bd_pins_external -name $port [get_bd_pins motor_safety_0/$pin]
}
assign_bd_address -target_address_space /microblaze_riscv_0/Data [get_bd_addr_segs axi_gpio_motor/S_AXI/Reg] \
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
set gseg [get_bd_addr_segs -of_objects [get_bd_addr_spaces /microblaze_riscv_0/Data] -filter {NAME =~ "*axi_gpio_motor*"}]
check {[get_property OFFSET $gseg] == $gpio_base} "motor GPIO base $gpio_base"
# 주소맵 대조: 5-2 8줄 + 모터 1줄이 셀 이름 → 베이스·범위로 한 줄씩 같아야 한다
proc data_seg {cell} {
  return [get_bd_addr_segs -of_objects [get_bd_addr_spaces /microblaze_riscv_0/Data] -filter "NAME =~ *_${cell}_*"]
}
set map_a {dlmb_bram_if_cntlr 0x00000000 65536 axi_gpio_0 0x40000000 65536 axi_gpio_btn 0x40010000 65536
  axi_uartlite_0 0x40020000 65536 axi_timer_0 0x40030000 65536 axi_intc_0 0x40040000 65536
  ip06_seg7 0x40060000 65536 axi_gpio_motor 0x40070000 65536 p3_npu_0 0x44A00000 4096}
set addr_ok 1
foreach {cell base rng} $map_a {
  set sg [data_seg $cell]
  if {[llength $sg] != 1} { puts "ADDR_MAP_A $cell MISSING"; set addr_ok 0; continue }
  set ob [get_property OFFSET $sg]; set or [get_property RANGE $sg]
  set ok [expr {$ob == $base && $or == $rng}]
  puts "ADDR_MAP_A $cell [format 0x%08X $ob] $or expect [format 0x%08X $base] $rng [expr {$ok ? "OK" : "MISMATCH"}]"
  if {!$ok} { set addr_ok 0 }
}
if {[llength $segs] != [expr {[llength $map_a] / 3}]} { puts "ADDR_MAP_A extra segments: [llength $segs]"; set addr_ok 0 }
puts [expr {$addr_ok ? "ADDR_MAP_A_PASS" : "ADDR_MAP_A_FAIL"}]
check {$addr_ok} "address map A (21장 8줄 + 모터 1줄)"
# 인터럽트 대조: 5-2와 같아야 한다(모터는 인터럽트 없음, In4 = 0)
set irq_map_a {0 axi_timer_0/interrupt 1 axi_uartlite_0/interrupt 3 axi_gpio_btn/ip2intc_irpt 12 p3_npu_0/irq_o}
set irq_ok 1
for {set i 0} {$i < 16} {incr i} {
  if {[dict exists $irq_map_a $i]} { set exp [dict get $irq_map_a $i] } else { set exp irq_zero/dout }
  set net [get_bd_nets -quiet -of_objects [get_bd_pins irq_concat/In$i]]
  set drv [expr {$net eq "" ? "" : [get_bd_pins -quiet -of_objects $net -filter {DIR == O}]}]
  set got [string trimleft [lindex $drv 0] /]
  set ok [expr {$got eq $exp}]
  puts "IRQ_MAP_A In$i $got expect $exp [expr {$ok ? "OK" : "MISMATCH"}]"
  if {!$ok} { set irq_ok 0 }
}
if {[get_property CONFIG.NUM_PORTS [get_bd_cells irq_concat]] != 16} { set irq_ok 0 }
puts [expr {$irq_ok ? "IRQ_MAP_A_PASS" : "IRQ_MAP_A_FAIL"}]
check {$irq_ok} "irq map A (21장과 같음)"
check {[get_bd_nets -of_objects [get_bd_pins motor_safety_0/clk]] eq [get_bd_nets -of_objects [get_bd_pins axi_smc/aclk]]} "motor clock = SmartConnect clock"
check {[get_bd_nets -of_objects [get_bd_pins motor_safety_0/resetn]] eq [get_bd_nets -of_objects [get_bd_pins rst_clk_wiz_1_100M/peripheral_aresetn]]} "motor reset = peripheral_aresetn"
foreach port {estop_ok estop_btn fault otemp lim_f lim_r in1 in2 ena trip} {
  check {[llength [get_bd_ports -quiet $port]] == 1} "BD port $port"
}
foreach port {in1 in2 ena} {
  set drv [get_bd_cells -of_objects [get_bd_pins -of_objects [get_bd_nets -of_objects [get_bd_ports $port]]]]
  check {$drv eq "/motor_safety_0"} "BD port $port connects only to motor_safety_0 (not CPU/NPU)"
}
set cmd_src [get_bd_cells -of_objects [get_bd_pins -of_objects [get_bd_nets -of_objects [get_bd_pins motor_safety_0/cmd_i]]]]
check {[lsort $cmd_src] eq [lsort {/axi_gpio_motor /motor_safety_0}]} "motor cmd_i comes only from axi_gpio_motor (CPU register)"

make_wrapper -files $bd_file -top -force
generate_target all $bd_file
create_ip_run [get_files $bd_file]
export_ip_user_files -of_objects $bd_file -no_script -sync -force -quiet
set_property top basys3_soc30_top [current_fileset]
update_compile_order -fileset sources_1
check {[get_property top [current_fileset]] eq "basys3_soc30_top"} "user top basys3_soc30_top"

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
foreach {port pin} {JB[0] A14 JB[1] A16 JB[2] B15 JB4 B16 btn[3] T18 btn[0] T17 seg[0] W7 an[0] U2 RsRx B18 led[15] L1 led[12] P3} {
  check {[get_property PACKAGE_PIN [get_ports $port]] eq $pin} "pin $port = $pin"
}
check {[get_property PULLTYPE [get_ports JB4]] eq "PULLDOWN"} "JB4 estop loop PULLDOWN (open = stop)"
set ar [get_cells -hierarchical -filter {NAME =~ "*motor_safety_0*s1_reg*" || NAME =~ "*motor_safety_0*s2_reg*"}]
check {[llength $ar] > 0 && [llength [get_cells $ar -filter {ASYNC_REG == 1}]] == [llength $ar]} "input synchronizers ASYNC_REG ([llength $ar] cells)"
write_hw_platform -fixed -include_bit -force $out/soc30_motor.xsa
foreach f [glob -nocomplain [get_property DIRECTORY [get_runs impl_1]]/*.bit] { file copy -force $f $out/ }
puts "SOC30_BUILD_DONE"
