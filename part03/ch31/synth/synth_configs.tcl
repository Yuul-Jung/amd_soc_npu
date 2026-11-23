# 4-4 synth_ooc.tcl 구성 파일. AES-128·SHA-256 코어를 100 MHz로 합성부터 제약해 OOC 배치·배선.
set clk_in_synth 1
set extra_srcs [list $part03/ch31/rtl/p3_aes128_enc.v $part03/ch31/rtl/p3_sha256_core.v]
set configs {
  aes128   p3_aes128_enc  {}
  sha256   p3_sha256_core {}
}
