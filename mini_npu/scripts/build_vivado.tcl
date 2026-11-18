# (추가) 12장: 기존 성공 프로젝트를 수정하지 않는 독립 Vivado 프로젝트.
# 실행: vivado -mode batch -source mini_npu/scripts/build_vivado.tcl
set project_root [file normalize [file join [file dirname [info script]] ../..]]
set design_root [file join $project_root mini_npu]
set build_dir [file join $design_root build]
file mkdir $build_dir
create_project -force p3_uart_npu $build_dir -part xc7a35tcpg236-1
set_property target_language Verilog [current_project]
foreach file [list \
  common/rtl/uart_rx.v \
  common/rtl/uart_tx.v \
  common/rtl/uart_core.v \
  ch02/rtl/dsp_multiplier.v \
  mini_npu/rtl/npu_dsp_mac_lane.v \
  mini_npu/rtl/npu_engine4.v \
  mini_npu/rtl/uart_npu_command_controller.v \
  mini_npu/rtl/npu_display_controller.v \
  mini_npu/rtl/npu_reset_controller.v \
  mini_npu/rtl/basys3_npu_top.v \
] {
  add_files -norecurse [file join $project_root $file]
}
add_files -fileset constrs_1 -norecurse \
  [file join $design_root constraints basys3_npu.xdc]
set_property top basys3_npu_top [current_fileset]
update_compile_order -fileset sources_1
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none [get_runs synth_1]
launch_runs synth_1 -jobs 2
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "SYNTH_STATUS: $synth_status"
if {![string match "*Complete*" $synth_status]} {
    error "SYNTH_NOT_COMPLETE"
}
open_run synth_1
report_utilization -file [file join $build_dir utilization_synth.rpt]
report_timing_summary -file [file join $build_dir timing_synth.rpt]
puts "SYNTH_REPORTS_CREATED (not timing-closure or board PASS)"
if {[info exists ::env(P3_IMPLEMENT)] && $::env(P3_IMPLEMENT) eq "1"} {
    launch_runs impl_1 -to_step route_design -jobs 2
    wait_on_run impl_1
    set implementation_status [get_property STATUS [get_runs impl_1]]
    puts "IMPLEMENT_STATUS: $implementation_status"
    if {![string match "*Complete*" $implementation_status]} {
        error "IMPL_NOT_COMPLETE"
    }
    open_run impl_1
    report_utilization -file [file join $build_dir utilization_impl.rpt]
    report_timing_summary -file [file join $build_dir timing_impl.rpt]
    puts "IMPLEMENT_REPORTS_CREATED (must inspect WNS/TNS; not BOARD_PASS)"
}
close_project
