# 00~10장 단위 모듈 Out-of-Context(OOC) 합성·배치·배선·타이밍 확인.
# 실행 (저장소 루트):
#   vivado -mode batch -nojournal -source tools/vivado/ooc_timing.tcl            ;# 전체
#   vivado -mode batch -nojournal -source tools/vivado/ooc_timing.tcl -tclargs ch01 ch04
# 결과: build/vivado/chNN/{synth_util,route_util,timing_route}.rpt
#       build/vivado/ooc_summary.txt (장별 1줄 판정)
# 판정: 배선 후 setup WNS >= 0 이고 hold WHS >= 0 (clk 100 MHz, 10.000 ns).
#       OOC는 입출력 핀 지연을 포함하지 않으므로 보드 Top 타이밍(12장)을 대신하지 않는다.

set root   [file normalize [file join [file dirname [info script]] ../..]]
set part   xc7a35tcpg236-1
set period 10.000
set outdir [file join $root build vivado]
file mkdir $outdir

# {장  Top 모듈  RTL 파일(저장소 루트 기준)}
set designs {
    {ch00 basys3_uart_echo_top {common/rtl/uart_rx.v common/rtl/uart_tx.v common/rtl/uart_core.v common/rtl/uart_echo_controller.v ch00/rtl/basys3_uart_echo_top.v}}
    {ch01 mac_core            {ch01/rtl/mac_core.v}}
    {ch02 dsp_multiplier      {ch02/rtl/dsp_multiplier.v}}
    {ch03 mac_pipeline_core   {ch03/rtl/mac_pipeline_core.v}}
    {ch04 bram_sync_buffer    {ch04/rtl/bram_sync_buffer.v}}
    {ch05 fixed_quantizer     {ch05/rtl/fixed_quantizer.v}}
    {ch06 precision_compare   {ch05/rtl/fixed_quantizer.v ch06/rtl/precision_compare.v}}
    {ch07 vector_dot_core     {ch01/rtl/mac_core.v ch07/rtl/vector_dot_core.v}}
    {ch08 pe_array4           {ch01/rtl/mac_core.v ch07/rtl/vector_dot_core.v ch08/rtl/pe_array4.v}}
    {ch09 dense_layer4        {ch01/rtl/mac_core.v ch05/rtl/fixed_quantizer.v ch07/rtl/vector_dot_core.v ch08/rtl/pe_array4.v ch09/rtl/dense_layer4.v}}
    {ch10 npu_core            {ch01/rtl/mac_core.v ch04/rtl/bram_sync_buffer.v ch05/rtl/fixed_quantizer.v ch07/rtl/vector_dot_core.v ch08/rtl/pe_array4.v ch09/rtl/dense_layer4.v ch10/rtl/npu_core.v}}
    {ch13 npu10_input_loader  {ch04/rtl/bram_sync_buffer.v ch13/rtl/npu10_input_loader.v}}
    {ch14 npu10_group_scheduler {ch01/rtl/mac_core.v ch04/rtl/bram_sync_buffer.v ch07/rtl/vector_dot_core.v ch08/rtl/pe_array4.v ch13/rtl/npu10_input_loader.v ch14/rtl/npu10_group_scheduler.v}}
    {ch15 npu_dense {ch01/rtl/mac_core.v ch04/rtl/bram_sync_buffer.v ch07/rtl/vector_dot_core.v ch08/rtl/pe_array4.v ch15/rtl/npu_dense_core.v ch15/rtl/npu_dense_store.v ch15/rtl/npu_dense.v}}
}

proc worst_slack {kind} {
    set p [get_timing_paths -quiet -$kind -max_paths 1 -nworst 1]
    if {[llength $p] == 0} { return NA }
    return [format %.3f [get_property SLACK $p]]
}
proc count_ref {pattern} {
    return [llength [get_cells -quiet -hierarchical -filter "IS_PRIMITIVE && REF_NAME =~ $pattern"]]
}

set selected $argv
set summary [file join $outdir ooc_summary.txt]
set fh [open $summary w]
puts $fh "# OOC ${period}ns · $part · [clock format [clock seconds] -format {%Y-%m-%d %H:%M}] · [version -short]"
set fail 0

foreach d $designs {
    lassign $d ch top files
    if {[llength $selected] > 0 && [lsearch -exact $selected $ch] < 0} { continue }
    set cdir [file join $outdir $ch]
    file mkdir $cdir
    set rc [catch {
        create_project -in_memory -part $part
        foreach f $files { read_verilog [file join $root $f] }
        set xdc [file join $cdir ooc.xdc]
        set x [open $xdc w]
        puts $x "create_clock -name clk -period $period \[get_ports clk\]"
        close $x
        read_xdc $xdc
        synth_design -top $top -part $part -mode out_of_context
        report_utilization -file [file join $cdir synth_util.rpt]
        opt_design
        place_design
        route_design
        report_utilization -file [file join $cdir route_util.rpt]
        report_timing_summary -max_paths 10 -file [file join $cdir timing_route.rpt]
        set wns [worst_slack setup]
        set whs [worst_slack hold]
        set res "LUT=[count_ref LUT*] FF=[count_ref FD*] DSP48E1=[count_ref DSP48E1] RAMB=[count_ref RAMB*]"
        set ok [expr {($wns eq "NA" || $wns >= 0) && ($whs eq "NA" || $whs >= 0)}]
        set tag [expr {$ok ? "SYNTH_TIMING_PASS" : "SYNTH_TIMING_FAIL"}]
        set line "$tag $ch $top WNS=$wns WHS=$whs $res"
        close_project
    } err]
    if {$rc} {
        set line "SYNTH_TIMING_FAIL $ch $top ERROR=[string map {\n { }} $err]"
        catch {close_project}
    }
    if {[string match SYNTH_TIMING_FAIL* $line]} { incr fail }
    puts $line
    puts $fh $line
    flush $fh
}
close $fh
puts "OOC_SUMMARY: $summary"
if {$fail > 0} { error "OOC_TIMING_FAILED count=$fail" }
