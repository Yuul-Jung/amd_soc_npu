# 복제된 제1부 11장 MicroBlaze V 프로젝트에 5-1 NPU AXI4-Lite IP를 추가하고 Bitstream·XSA까지 만든다.
# 원본 프로젝트는 열지 않는다(build_soc.sh가 cp -a로 복제한 사본만 연다). BD 이름·사용자 Top·Wrapper 이름은 그대로.
# 동결 주소맵(UART 0x4002·Timer 0x4003·INTC 0x4004·BTN GPIO 0x4001·SEG7 0x4006, NPU 0x44A0 그대로),
#   표준 7세그먼트 IP ip_seg7(모듈 참조, part03/common/rtl/ip_std), BTN GPIO(인터럽트), xlconcat 16입력(NPU = In12).
#   사용자 Top은 basys3_soc21_top(핀 연결만). 원본 Top basys3_soc11_top은 이 복제본에서만 비활성.
# 사용: vivado -mode batch -source soc_npu_bd.tcl -tclargs <복제 xpr> <IP repo> <XDC> <출력 폴더> <jobs> <part03 폴더>
set xpr [lindex $argv 0]
set ip_repo [file normalize [lindex $argv 1]]
set xdc [file normalize [lindex $argv 2]]
set out [file normalize [lindex $argv 3]]
set jobs [lindex $argv 4]
set part03 [file normalize [lindex $argv 5]]
set npu_base 0x44A00000
set npu_range 4K
file mkdir $out

proc check {cond msg} {
  if {[uplevel 1 [list expr $cond]]} { puts "CHECK_PASS $msg" } else { puts "CHECK_FAIL $msg"; exit 1 }
}

open_project $xpr
# 원본의 상대 경로 XDC($PPRDIR/../../Basys-3-Master.xdc)는 사본 위치에서 맞지 않으므로 같은 활성 줄의 5-2 XDC로 바꾼다
foreach f [get_files -quiet -of_objects [get_filesets constrs_1]] { remove_files -fileset constrs_1 $f }
add_files -fileset constrs_1 -norecurse $xdc
set_property ip_repo_paths [list $ip_repo] [current_project]
update_ip_catalog -rebuild
# 표준 IP 소스(모듈 참조)와 5-2 사용자 Top
add_files -norecurse [list $part03/common/rtl/ip_std/ip_seg7.v $part03/common/rtl/ip_std/axil_slave.v \
  $part03/common/rtl/ip_std/ip_std.v $part03/ch21/rtl/basys3_soc21_top.v]
set_property is_enabled false [get_files basys3_soc11_top.v]
update_compile_order -fileset sources_1

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

# BTN GPIO(4비트 입력, 인터럽트)와 표준 7세그먼트 IP(ip06_seg7). SmartConnect M05·M06
set_property CONFIG.NUM_MI 7 $smc
set gb [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_btn]
set_property -dict [list CONFIG.C_GPIO_WIDTH 4 CONFIG.C_ALL_INPUTS 1 CONFIG.C_INTERRUPT_PRESENT 1] $gb
connect_bd_intf_net [get_bd_intf_pins axi_smc/M05_AXI] [get_bd_intf_pins axi_gpio_btn/S_AXI]
connect_bd_net -net $clk_net [get_bd_pins axi_gpio_btn/s_axi_aclk]
connect_bd_net -net $rst_net [get_bd_pins axi_gpio_btn/s_axi_aresetn]
make_bd_intf_pins_external -name btn [get_bd_intf_pins axi_gpio_btn/GPIO]
set sg [create_bd_cell -type module -reference ip_seg7 ip06_seg7]
connect_bd_intf_net [get_bd_intf_pins axi_smc/M06_AXI] [get_bd_intf_pins ip06_seg7/s_axi]
connect_bd_net -net $clk_net [get_bd_pins ip06_seg7/s_axi_aclk]
connect_bd_net -net $rst_net [get_bd_pins ip06_seg7/s_axi_aresetn]
foreach port {seg dp an} { make_bd_pins_external -name $port [get_bd_pins ip06_seg7/$port] }

# 인터럽트: xlconcat 16입력. In0 Timer, In1 UART(예약, 펌웨어는 켜지 않음), In3 BTN, In12 NPU, 나머지 상수 0
set tmr_net [get_bd_nets -of_objects [get_bd_pins axi_timer_0/interrupt]]
delete_bd_objs $tmr_net
set cat [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 irq_concat]
set_property CONFIG.NUM_PORTS 16 $cat
set zero [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 irq_zero]
set_property -dict [list CONFIG.CONST_WIDTH 1 CONFIG.CONST_VAL 0] $zero
set irq_map_a {0 axi_timer_0/interrupt 1 axi_uartlite_0/interrupt 3 axi_gpio_btn/ip2intc_irpt 12 p3_npu_0/irq_o}
for {set i 0} {$i < 16} {incr i} {
  if {[dict exists $irq_map_a $i]} { set src [dict get $irq_map_a $i] } else { set src irq_zero/dout }
  connect_bd_net [get_bd_pins $src] [get_bd_pins irq_concat/In$i]
}
connect_bd_net [get_bd_pins irq_concat/dout] [get_bd_pins axi_intc_0/intr]

# 주소: 사용자 IP 기본 영역 0x44A0_0000, 4 KB
assign_bd_address -target_address_space /microblaze_riscv_0/Data [get_bd_addr_segs p3_npu_0/s_axi/reg0] \
  -offset $npu_base -range $npu_range
# 동결 주소맵: 기존 세그먼트를 옮기고(겹침 없는 순서) 새 블록을 배치한다
proc data_seg {cell} {
  return [get_bd_addr_segs -of_objects [get_bd_addr_spaces /microblaze_riscv_0/Data] -filter "NAME =~ *_${cell}_*"]
}
foreach {cell base} {axi_uartlite_0 0x40020000 axi_timer_0 0x40030000 axi_intc_0 0x40040000} {
  set_property OFFSET $base [data_seg $cell]
}
assign_bd_address -target_address_space /microblaze_riscv_0/Data [get_bd_addr_segs axi_gpio_btn/S_AXI/Reg] \
  -offset 0x40010000 -range 64K
assign_bd_address -target_address_space /microblaze_riscv_0/Data [get_bd_addr_segs ip06_seg7/s_axi/*] \
  -offset 0x40060000 -range 64K
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
# 주소맵 대조: 셀 이름 → 베이스·범위가 지시문 2절 표와 한 줄씩 같아야 한다
set map_a {dlmb_bram_if_cntlr 0x00000000 65536 axi_gpio_0 0x40000000 65536 axi_gpio_btn 0x40010000 65536
  axi_uartlite_0 0x40020000 65536 axi_timer_0 0x40030000 65536 axi_intc_0 0x40040000 65536
  ip06_seg7 0x40060000 65536 p3_npu_0 0x44A00000 4096}
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
check {$addr_ok} "address map A"
# 인터럽트 대조: concat 입력 번호마다 구동원을 확인한다(예약 칸은 irq_zero)
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
check {$irq_ok} "irq map A"
foreach port {seg dp an} { check {[llength [get_bd_ports -quiet $port]] == 1} "BD port $port" }
check {[llength [get_bd_intf_ports -quiet btn]] == 1} "BD interface port btn"
check {[get_bd_nets -of_objects [get_bd_pins p3_npu_0/s_axi_aclk]] eq [get_bd_nets -of_objects [get_bd_pins axi_smc/aclk]]} "NPU clock = SmartConnect clock"
check {[get_bd_nets -of_objects [get_bd_pins p3_npu_0/s_axi_aresetn]] eq [get_bd_nets -of_objects [get_bd_pins rst_clk_wiz_1_100M/peripheral_aresetn]]} "NPU reset = peripheral_aresetn"
check {[get_bd_nets -of_objects [get_bd_pins irq_concat/dout]] eq [get_bd_nets -of_objects [get_bd_pins axi_intc_0/intr]]} "irq_concat -> axi_intc intr"
# 원본과 같은 IP별 OOC 합성(Hierarchical)을 유지한다. MicroBlaze V 코어는 전역 합성에서 black box가 된다.
make_wrapper -files $bd_file -top -force
generate_target all $bd_file
create_ip_run [get_files $bd_file]
export_ip_user_files -of_objects $bd_file -no_script -sync -force -quiet

# 사용자 Top은 basys3_soc21_top(핀 연결만)
set_property top basys3_soc21_top [current_fileset]
update_compile_order -fileset sources_1
check {[get_property top [current_fileset]] eq "basys3_soc21_top"} "user top basys3_soc21_top"

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
