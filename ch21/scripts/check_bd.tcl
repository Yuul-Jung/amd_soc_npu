# 21장 정적 검사 (Vivado 없이 tclsh로 실행): add_npu.tcl을 가짜 Vivado 명령으로 한 줄씩 실행해 기록하고,
#  ① 더하는 RTL 파일이 모두 있고 NPU 계층의 모듈이 빠짐없이 정의되는지
#  ② NPU 주소 범위가 기존 주변장치와 겹치지 않는지 (기존 주소는 제1부 11장 xparameters.h 확인값 + Vivado 기본값)
#  ③ 사용자 Top 포트와 XDC get_ports가 서로 같은지 (빠진 핀·남는 핀·중복 핀 없음)
# 를 확인한다. Vivado의 실제 동작(Validate Design·합성)을 대신하지 않는다.
set root [file normalize [file join [file dirname [info script]] ../..]]
set log {}
proc rec {args} { lappend ::log $args; return "" }
foreach c {update_compile_order create_bd_cell apply_bd_automation validate_bd_design save_bd_design make_wrapper
           set_property current_fileset get_bd_intf_pins get_bd_addr_spaces get_bd_addr_segs get_files} {
    proc $c {args} "rec $c {*}\$args"
}
proc add_files {args} { foreach a $args { if {[string index $a 0] ne "-" && $a ne "constrs_1"} { foreach f $a { lappend ::added $f } } }; rec add_files {*}$args }
proc assign_bd_address {args} {
    array set o {}
    for {set i 0} {$i < [llength $args]} {incr i} {
        set a [lindex $args $i]
        if {$a in {-offset -range -target_address_space}} { set o($a) [lindex $args [incr i]] }
    }
    set ::npu_off [expr {$o(-offset)}]; set ::npu_rng [expr {$o(-range)}]
    rec assign_bd_address {*}$args
}
set added {}
source [file join $root ch21 vivado add_npu.tcl]
set fail 0
proc check {ok msg} { if {$ok} { puts "  ok   $msg" } else { puts "  FAIL $msg"; incr ::fail } }

# ① 파일과 모듈 계층
set defined {}; set used {}
foreach f $added {
    check [file exists $f] "파일 있음 [string map [list $root/ {}] $f]"
    if {![file exists $f]} continue
    set fh [open $f]; set t [read $fh]; close $fh
    regsub -all {//[^\n]*} $t {} t
    foreach {m name} [regexp -all -inline {\mmodule\s+(\w+)} $t] { lappend defined $name }
    foreach {m name} [regexp -all -inline -line {^\s*(\w+)\s*(?:#\s*\([^;]*?\))?\s+\w+\s*\(\s*\.} $t] { lappend used $name }
}
set cell [lsearch -inline -index 0 $log create_bd_cell]
check [expr {[lsearch $cell npu_axi_lite] >= 0 && [lsearch $defined npu_axi_lite] >= 0}] "모듈 참조 npu_axi_lite가 더한 파일에 정의됨"
foreach u [lsort -unique $used] {
    if {$u in {soc_npu_wrapper}} continue
    check [expr {[lsearch $defined $u] >= 0}] "하위 모듈 $u 정의됨"
}

# ② 주소 겹침
set npu_end [expr {$npu_off + $npu_rng - 1}]
set periph {
    {GPIO(LED/SW) 0x40000000 0x10000 제1부11장_xparameters.h}
    {INTC         0x41200000 0x10000 제1부11장_xparameters.h}
    {UART_Lite    0x40600000 0x10000 Vivado_기본값_미검증}
    {AXI_Timer    0x41C00000 0x10000 Vivado_기본값_미검증}
}
check [expr {$npu_rng == 0x10000 && ($npu_off % $npu_rng) == 0}] [format "NPU 0x%08X 64KB, 범위 단위 정렬" $npu_off]
foreach p $periph {
    lassign $p name base rng src
    set end [expr {$base + $rng - 1}]
    check [expr {$npu_end < $base || $npu_off > $end}] [format "NPU와 %s 0x%08X 겹치지 않음 (%s)" $name $base $src]
}
check [expr {0x68 <= $npu_rng}] "레지스터 맵 0x00~0x67이 범위 안"

# ③ Top 포트 ↔ XDC
set fh [open [file join $root ch21 rtl soc_npu_top.v]]; set top [read $fh]; close $fh
set ports {}
foreach {m dir w name} [regexp -all -inline {(input|output)\s+wire\s+(\[\d+:\d+\])?\s*(\w+)} $top] {
    if {$w eq ""} { lappend ports $name } else {
        regexp {\[(\d+):(\d+)\]} $w - hi lo
        for {set i $lo} {$i <= $hi} {incr i} { lappend ports "$name\[$i\]" }
    }
}
set fh [open [file join $root ch21 constraints soc_npu.xdc]]; set x [read $fh]; close $fh
set xports {}; set pins {}
foreach {m pin p1 p2} [regexp -all -inline {PACKAGE_PIN\s+(\w+)[^\[]*\[get_ports\s+(?:\{([^\}]+)\}|(\w+))\]} $x] {
    lappend xports [string trim "$p1$p2"]; lappend pins $pin
}
set miss [lmap p $ports {expr {$p in $xports ? [continue] : $p}}]; set extra [lmap p $xports {expr {$p in $ports ? [continue] : $p}}]
if {[llength $miss] || [llength $extra]} { puts "  빠진 핀: $miss / 남는 핀: $extra" }
check [expr {[llength $miss] == 0 && [llength $extra] == 0}] "Top 포트 [llength $ports]개 = XDC 핀 배정 [llength $xports]개"
check [expr {[llength $pins] == [llength [lsort -unique $pins]]}] "XDC 핀 중복 없음"
check [string match "*create_clock*get_ports clk*" $x] "clk 100 MHz 클록 제약"

set steps [llength $log]
if {$fail} { puts "BD_STATIC_CHECK_FAIL fails=$fail"; exit 1 }
puts [format "BD_STATIC_CHECK_PASS tcl_steps=%d files=%d npu=0x%08X/64KB ports=%d" $steps [llength $added] $npu_off [llength $ports]]
