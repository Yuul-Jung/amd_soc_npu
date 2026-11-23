# 5-1 AXI4-Lite NPU IP 클록 주기 스윕 구성.
set clk_period $::env(P3_CLK_PERIOD)
set clk_in_synth 1
set clk_port s_axi_aclk
set extra_srcs [list $part03/ch04/rtl/bram_sync_buffer.v $part03/ch20/rtl/p3_npu_axi_lite.v]
set configs {
  axi_npu_int8   p3_npu_axi_lite {}
}
