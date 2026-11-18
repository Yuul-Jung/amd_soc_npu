# 25장: 21장 SoC 구현 결과의 추정 전력을 같은 조건(100 MHz, 같은 스위칭 가정)으로 두 번 뽑는다.
#   A) 기본 벡터 없는 추정 (Vivado 기본 토글률)       → power_default.rpt
#   B) NPU 계층만 토글률을 높여 본 추정 (가정 명시)    → power_npu_active.rpt
# 실행: 구현이 끝난 21장 프로젝트를 열고  source <저장소>/ch25/vivado/report_power.tcl
# ⚠ 미검증: Vivado에서 실행하지 않았다. 둘 다 '추정'이며 실측 전력이 아니다 (Confidence Level을 함께 기록).
set root [file normalize [file join [file dirname [info script]] ../..]]
set out  [file join $root build ch25]
file mkdir $out
open_run impl_1

# 조건 기록: 클록, 주변 온도, 기판 등은 Vivado 기본값을 그대로 쓴다 (바꾸지 않음).
report_power -file [file join $out power_default.rpt]

# NPU가 연산 중일 때를 흉내 낸 가정: npu_0 안의 모든 넷 토글률 25%, 정적 확률 0.5.
# 이 숫자는 측정값이 아니라 비교용 가정이다. 바꾸면 보고서 이름도 바꾼다.
set npu_nets [get_nets -hierarchical -filter {NAME =~ "*npu_0/*"}]
set_switching_activity -toggle_rate 25 -static_probability 0.5 $npu_nets
report_power -file [file join $out power_npu_active.rpt]
reset_switching_activity -all

set fh [open [file join $out power_info.txt] w]
puts $fh "repo_commit [string trim [exec git -C $root rev-parse --short HEAD]]"
puts $fh "assumption_B npu_0_nets toggle_rate=25% static_probability=0.5 nets=[llength $npu_nets]"
close $fh
puts "REPORT_POWER_DONE $out"
