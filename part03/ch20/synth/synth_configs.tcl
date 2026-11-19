# (추가) 20장: 19장 synth_ooc.tcl에 넘기는 구성 파일. AXI4-Lite NPU 제어 IP(INT8 기본)를 OOC 합성·배선한다.
set extra_srcs [list $part03/ch04/rtl/bram_sync_buffer.v $part03/ch20/rtl/p3_npu_axi_lite.v]
set clk_port s_axi_aclk
set configs {
  axi_npu_int8  p3_npu_axi_lite {}
}
