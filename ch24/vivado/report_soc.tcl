# 24장: 21장 SoC 구현 결과에서 자원·타이밍·임계 경로 보고서를 같은 빌드 기준으로 뽑는다.
# 실행: 구현이 끝난 21장 프로젝트를 열고 Tcl Console에서  source <저장소>/ch24/vivado/report_soc.tcl
# 결과: <저장소>/build/ch24/*.rpt 와 build_info.txt (빌드 SHA·비트스트림 해시)
# ⚠ 미검증: Vivado에서 실행하지 않았다.
set root [file normalize [file join [file dirname [info script]] ../..]]
set out  [file join $root build ch24]
file mkdir $out

open_run impl_1
report_utilization -file [file join $out util_total.rpt]
report_utilization -hierarchical -hierarchical_depth 4 -file [file join $out util_hier.rpt]
report_timing_summary -max_paths 10 -report_unconstrained -file [file join $out timing_summary.rpt]
report_timing -max_paths 10 -nworst 1 -sort_by group -path_type summary -file [file join $out timing_paths.rpt]
report_timing -max_paths 1 -path_type full -file [file join $out critical_path.rpt]

# 같은 빌드인지 나중에 확인할 수 있게 저장소 커밋과 비트스트림 해시를 남긴다.
set fh [open [file join $out build_info.txt] w]
puts $fh "repo_commit [string trim [exec git -C $root rev-parse --short HEAD]]"
puts $fh "vivado [version -short]"
puts $fh "part [get_property PART [current_project]]"
set bit [glob -nocomplain [file join [get_property DIRECTORY [current_project]] *.runs impl_1 *.bit]]
if {[llength $bit]} { puts $fh "bitstream_sha256 [lindex [exec sha256sum [lindex $bit 0]] 0]" } else { puts $fh "bitstream_sha256 NONE" }
close $fh
puts "REPORT_SOC_DONE $out"
