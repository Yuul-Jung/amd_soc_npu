# 20장 AXI4-Lite NPU 제어 IP Vivado OOC 합성·배선 (실제 실행)

> Vivado 2024.2, `synth_design -mode out_of_context`, xc7a35tcpg236-1, `create_clock -period 10.000 clk`.
> 첫 표는 **합성 직후 추정치**, 배선 후 결과는 아래 별도 표. 비트스트림·실물은 하지 않았다.

| 구성 | RTL | DSP48E1 | BRAM Tile | LUT | LUTRAM | FF | WNS(ns) | TNS(ns) | 실패 끝점 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| AXI NPU INT8 | `p3_npu_axi_lite 기본(17장 Tile + 04장 x 버퍼)` | 4 | 2.5 | 2092 | 0 | 1975 | 2.517 | 0.000 | 0 |


## 임계 경로 (합성 추정)

| 구성 | 시작 | 끝 | Data Path(ns) | Logic Levels |
|---|---|---|---:|---:|
| AXI NPU INT8 | `npu/score_q_reg[2][1]/C` | `npu/a2c0_q_reg[0]/D` | 7.428 | 16 |

## OOC 배치·배선 후 (opt_design → place_design → route_design)

> 최상위 포트를 FPGA 핀에 묶지 않은 OOC 구현이다. 칩 전체 Top·I/O·비트스트림·실물은 별도.

| 구성 | DSP | BRAM Tile | LUT | FF | WNS(ns) | TNS(ns) | 실패 끝점 | 임계 경로 | Data Path(ns) |
|---|---:|---:|---:|---:|---:|---:|---:|---|---:|
| AXI NPU INT8 | 4 | 2.5 | 2076 | 1975 | 0.223 | 0.000 | 0 | `npu/score_q_reg[5][0]/C` → `npu/a2c1_q_reg[0]/D` | 9.770 |

