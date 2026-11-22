# (추가) 30장: 19장 synth_ooc.tcl 구성 파일. 모터 안전 코어(보드 파라미터)를 100 MHz로 합성부터 제약해 OOC 배치·배선.
set clk_in_synth 1
set extra_srcs [list $part03/ch30/rtl/p3_motor_safety.v]
set configs {
  motor_safety  p3_motor_safety {PWM_PERIOD=5000 DEAD_CYC=10000000 WD_CYC=50000000 RAMP_CYC=100000}
}
