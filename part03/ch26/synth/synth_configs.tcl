# (추가) 26장: 19장 synth_ooc.tcl 구성 파일. 3×3 합성곱 코어를 100 MHz로 합성부터 제약해 OOC 배치·배선.
set clk_in_synth 1
set extra_srcs [list $part03/ch26/rtl/p3_conv3x3_8x8.v]
set configs {
  conv3x3_int8  p3_conv3x3_8x8 {}
}
