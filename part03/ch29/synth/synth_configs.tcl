# 4-4 synth_ooc.tcl 구성 파일. 경보 정책 RTL을 100 MHz로 합성부터 제약해 OOC 배치·배선.
set clk_in_synth 1
set extra_srcs [list $part03/ch29/rtl/p3_alarm_policy.v]
set configs {
  alarm_policy  p3_alarm_policy {CLEAR_N=3}
}
