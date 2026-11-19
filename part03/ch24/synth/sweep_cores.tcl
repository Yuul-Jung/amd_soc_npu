# (추가) 24장: 클록 주기 스윕용 구성(19장 synth_ooc.tcl에 전달). P3_CLK_PERIOD 환경 변수 주기로 합성부터 제약.
set clk_period $::env(P3_CLK_PERIOD)
set clk_in_synth 1
set configs {
  pe4_int8       p3_group10_core {IN_LEN=64 OUT_N=10}
  pe4_int16      p3_group10_core {IN_LEN=64 OUT_N=10 DATA_W=16 ACC_W=38 BIAS_W=24 SCORE_W=39}
  tile784_int8   p3_tile784_10   {}
}
