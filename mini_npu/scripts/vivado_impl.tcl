# 통합 NPU Top (2-8): 합성 → 구현 → 타이밍 판정 → 비트스트림 → 타이밍 시뮬레이션용 넷리스트.
# 실행 (저장소 루트): vivado -mode batch -nojournal -source mini_npu/scripts/vivado_impl.tcl
# 결과: mini_npu/build/impl/
#   post_synth.dcp, post_route.dcp           (GUI 확인: File → Checkpoint → Open)
#   timing_synth.rpt, timing_route.rpt, util_route.rpt, drc_route.rpt
#   basys3_npu_top.bit
#   basys3_npu_top_timesim.v, basys3_npu_top_timesim.sdf   (run_timing_sim.sh 입력)
# 판정: 배선 후 setup WNS >= 0, hold WHS >= 0, DRC Error 0 → SYNTH_TIMING_PASS

set root   [file normalize [file join [file dirname [info script]] ../..]]
set part   xc7a35tcpg236-1
set top    basys3_npu_top
set out    [file join $root mini_npu build impl]
file mkdir $out

set rtl {
    common/rtl/uart_rx.v
    common/rtl/uart_tx.v
    common/rtl/uart_core.v
    ch02/rtl/dsp_multiplier.v
    mini_npu/rtl/npu_dsp_mac_lane.v
    mini_npu/rtl/npu_engine4.v
    mini_npu/rtl/uart_npu_command_controller.v
    mini_npu/rtl/npu_display_controller.v
    mini_npu/rtl/npu_reset_controller.v
    mini_npu/rtl/basys3_npu_top.v
}
foreach f $rtl { read_verilog [file join $root $f] }
read_xdc [file join $root mini_npu constraints basys3_npu.xdc]

synth_design -top $top -part $part
write_checkpoint -force [file join $out post_synth.dcp]
report_utilization    -file [file join $out util_synth.rpt]
report_timing_summary -file [file join $out timing_synth.rpt]

opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force [file join $out post_route.dcp]
report_utilization    -file [file join $out util_route.rpt]
report_timing_summary -max_paths 10 -report_unconstrained -file [file join $out timing_route.rpt]
report_drc -name drc_route -file [file join $out drc_route.rpt]

proc worst_slack {kind} {
    set p [get_timing_paths -quiet -$kind -max_paths 1 -nworst 1]
    if {[llength $p] == 0} { return NA }
    return [format %.3f [get_property SLACK $p]]
}
proc count_ref {pattern} {
    return [llength [get_cells -quiet -hierarchical -filter "IS_PRIMITIVE && REF_NAME =~ $pattern"]]
}
set wns  [worst_slack setup]
set whs  [worst_slack hold]
set derr [llength [get_drc_violations -quiet -name drc_route -filter {SEVERITY == "Error"}]]
set res  "LUT=[count_ref LUT*] FF=[count_ref FD*] DSP48E1=[count_ref DSP48E1] RAMB=[count_ref RAMB*]"
set ok   [expr {$wns ne "NA" && $wns >= 0 && $whs ne "NA" && $whs >= 0 && $derr == 0}]

# Basys3 구성 전압 (XDC 원본 해시를 바꾸지 않도록 여기서 지정)
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
write_bitstream -force [file join $out ${top}.bit]

# 배선 후 타이밍 시뮬레이션용 넷리스트·SDF (slow corner)
set sdf [file join $out ${top}_timesim.sdf]
write_verilog -force -mode timesim -nolib -sdf_anno true -sdf_file $sdf [file join $out ${top}_timesim.v]
write_sdf     -force -mode timesim -process_corner slow $sdf

set tag [expr {$ok ? "SYNTH_TIMING_PASS" : "SYNTH_TIMING_FAIL"}]
set line "$tag ch12 $top WNS=$wns WHS=$whs DRC_ERRORS=$derr $res"
set fh [open [file join $out impl_summary.txt] w]
puts $fh "# [clock format [clock seconds] -format {%Y-%m-%d %H:%M}] · [version -short] · $part"
puts $fh $line
close $fh
puts $line
if {!$ok} { error "IMPL_TIMING_FAILED" }
