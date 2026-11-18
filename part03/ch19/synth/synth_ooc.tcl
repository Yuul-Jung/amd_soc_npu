# (추가) 19장: 14장 코어·17장 Tile Controller 구성별 Out-of-Context 합성(Basys3 XC7A35T, 100 MHz 제약).
# 합성(synth_design)만 수행한다. 배치·배선·Timing closure·비트스트림은 하지 않는다.
# 사용: vivado -mode batch -source synth_ooc.tcl -tclargs <part03 경로> <출력 폴더>
set part03 [lindex $argv 0]
set out [lindex $argv 1]
file mkdir $out
set part xc7a35tcpg236-1
set srcs [list \
  $part03/ch02/rtl/dsp_multiplier.v \
  $part03/mini_npu/rtl/npu_dsp_mac_lane.v \
  $part03/ch14/rtl/p3_group10_core.v \
  $part03/ch17/rtl/p3_tile784_10.v]

# 이름 top generic
set configs {
  pe1_int8        p3_group10_core {IN_LEN=64 OUT_N=1}
  pe4_int8        p3_group10_core {IN_LEN=64 OUT_N=10}
  pe8a_int8       p3_group10_core {IN_LEN=64 OUT_N=6}
  pe8b_int8       p3_group10_core {IN_LEN=64 OUT_N=4}
  pe4_int16       p3_group10_core {IN_LEN=64 OUT_N=10 DATA_W=16 ACC_W=38 BIAS_W=24 SCORE_W=39}
  tile784_int8    p3_tile784_10   {}
  tile784_int16   p3_tile784_10   {DATA_W=16 CORE_ACC_W=38 PART_W=39}
}
foreach {name top generics} $configs {
  read_verilog $srcs
  set g {}
  foreach kv $generics { lappend g -generic $kv }
  synth_design -top $top -part $part -mode out_of_context {*}$g
  create_clock -name clk -period 10.000 [get_ports clk]
  report_utilization -file $out/${name}_utilization.rpt
  report_utilization -hierarchical -file $out/${name}_utilization_hier.rpt
  report_timing_summary -max_paths 1 -file $out/${name}_timing.rpt
  close_design
}
