# 5-2 배선 완료 SoC에 대해 vectorless(기본 토글률)와 SAIF(구간별 실제 토글률) 전력을 보고한다.
# 사용: vivado -mode batch -source soc_power_report.tcl -tclargs <5-2 복제 xpr> <SAIF·출력 폴더>
set xpr [lindex $argv 0]
set out [file normalize [lindex $argv 1]]
open_project $xpr
open_run impl_1
report_power -hierarchical_depth 4 -file $out/power_vectorless.rpt
foreach mode {cpu npu} {
  reset_switching_activity -all
  read_saif -strip_path tb_soc_bench/dut $out/$mode.saif -out_file $out/${mode}_saif_match.rpt
  report_power -hierarchical_depth 4 -file $out/power_$mode.rpt
}
puts "SOC_POWER_REPORT_DONE"
