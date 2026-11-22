# 1장 보드 Top (UART 계산기): STAGE 1~4 각각 합성 → 구현 → 타이밍 판정 → 비트스트림.
# STAGE = 끝낸 서브젝트 수 (1 = 1-1 에코 … 4 = 1-4 파이프라인). 서브젝트마다 보드에서 확인할 비트스트림을 만든다.
# 실행 (저장소 루트): vivado -mode batch -nojournal -source p01/vivado/build_p01.tcl
#   한 단계만: vivado -mode batch -nojournal -source p01/vivado/build_p01.tcl -tclargs 2
# 결과: build/vivado/p01_s<STAGE>/ (timing_route.rpt, util_route.rpt, drc_route.rpt, basys3_p01_top.bit)
#       p01/validation/vivado_impl_YYYYMMDD.txt (증거, 커밋 대상. 한 줄씩: SYNTH_TIMING_PASS|FAIL p01 basys3_p01_top STAGE=n WNS=… …)
# 판정: 배선 후 setup WNS >= 0, hold WHS >= 0, DRC Error 0

set root  [file normalize [file join [file dirname [info script]] ../..]]
set part  xc7a35tcpg236-1
set top   basys3_p01_top
set base  [file join $root build vivado]
file mkdir $base
set stages [expr {[llength $argv] ? $argv : {1 2 3 4}}]

set rtl {
    common/rtl/uart_rx.v
    common/rtl/uart_tx.v
    common/rtl/uart_core.v
    ch01/rtl/mac_core.v
    ch02/rtl/dsp_multiplier.v
    ch03/rtl/mac_pipeline_core.v
    p01/rtl/p01_reset_sync.v
    p01/rtl/p01_mac_bank.v
    p01/rtl/p01_calc_controller.v
    p01/rtl/p01_hex4_display.v
    p01/rtl/basys3_p01_top.v
}

proc worst_slack {kind} {
    set p [get_timing_paths -quiet -$kind -max_paths 1 -nworst 1]
    if {[llength $p] == 0} { return NA }
    return [format %.3f [get_property SLACK $p]]
}
proc count_ref {pattern} {
    return [llength [get_cells -quiet -hierarchical -filter "IS_PRIMITIVE && REF_NAME =~ $pattern"]]
}

set day [clock format [clock seconds] -format %Y%m%d]
set fh [open [file join $root p01 validation vivado_impl_$day.txt] w]
puts $fh "# [clock format [clock seconds] -format {%Y-%m-%d %H:%M}] · [version -short] · $part"
set all_ok 1
foreach s $stages {
    set out [file join $base p01_s$s]
    file mkdir $out
    close_project -quiet
    create_project -in_memory -part $part
    foreach f $rtl { read_verilog [file join $root $f] }
    read_xdc [file join $root p01 constraints basys3_p01.xdc]

    synth_design -top $top -part $part -generic STAGE=$s
    opt_design
    place_design
    phys_opt_design
    route_design
    report_utilization    -file [file join $out util_route.rpt]
    report_timing_summary -max_paths 10 -report_unconstrained -file [file join $out timing_route.rpt]
    report_drc -name drc_route -file [file join $out drc_route.rpt]

    set wns  [worst_slack setup]
    set whs  [worst_slack hold]
    set derr [llength [get_drc_violations -quiet -name drc_route -filter {SEVERITY == "Error"}]]
    set res  "LUT=[count_ref LUT*] FF=[count_ref FD*] DSP48E1=[count_ref DSP48E1]"
    set ok   [expr {$wns ne "NA" && $wns >= 0 && $whs ne "NA" && $whs >= 0 && $derr == 0}]

    set_property CFGBVS VCCO [current_design]
    set_property CONFIG_VOLTAGE 3.3 [current_design]
    write_bitstream -force [file join $out ${top}.bit]

    set tag  [expr {$ok ? "SYNTH_TIMING_PASS" : "SYNTH_TIMING_FAIL"}]
    set line "$tag p01 $top STAGE=$s WNS=$wns WHS=$whs DRC_ERRORS=$derr $res"
    puts $fh $line
    puts $line
    if {!$ok} { set all_ok 0 }
}
close $fh
if {!$all_ok} { error "P01_IMPL_TIMING_FAILED" }
