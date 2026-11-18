# 19장 Vivado OOC 합성 요약 (실제 실행)

> Vivado 2024.2, `synth_design -mode out_of_context`, xc7a35tcpg236-1, `create_clock -period 10.000 clk`.
> **합성 직후 추정치**다. 배치·배선·Timing closure·비트스트림·실물은 하지 않았다(24장·후반 일괄).

| 구성 | RTL | DSP48E1 | BRAM Tile | LUT | LUTRAM | FF | WNS(ns) | TNS(ns) | 실패 끝점 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| PE1 INT8 | `p3_group10_core #(64,1)` | 1 | 0.5 | 51 | 0 | 66 | 4.919 | 0.000 | 0 |
| PE4 INT8 | `p3_group10_core #(64,10) — 14장 기본` | 4 | 2 | 558 | 0 | 512 | -7.962 | -31.848 | 4 |
| PE8 코어 A INT8 | `p3_group10_core #(64,6)` | 4 | 2 | 319 | 0 | 315 | -2.710 | -6.984 | 3 |
| PE8 코어 B INT8 | `p3_group10_core #(64,4)` | 4 | 2 | 229 | 0 | 215 | 0.503 | 0.000 | 0 |
| PE4 INT16 | `p3_group10_core DATA_W 16·ACC_W 38` | 4 | 2 | 822 | 0 | 652 | -9.441 | -37.764 | 4 |
| 17장 Tile INT8 | `p3_tile784_10 기본` | 4 | 2 | 1650 | 0 | 1289 | -9.441 | -37.764 | 4 |
| 18장 Tile INT16 | `p3_tile784_10 DATA_W 16` | 4 | 2 | 1821 | 0 | 1659 | -9.429 | -37.708 | 4 |

- PE8 = 코어 A + 코어 B (각각 따로 합성한 값의 합으로 읽는다. 공유 x 포트 배선은 포함되지 않음).
- BRAM Tile 0.5 = RAMB18 1개. 14장 코어의 lane별 가중치 bank가 RAMB18로 추론되었다.

## 임계 경로 (합성 추정)

| 구성 | 시작 | 끝 | Data Path(ns) | Logic Levels |
|---|---|---|---:|---:|
| PE1 INT8 | `bank0_reg/CLKBWRCLK` | `lane0/acc_o_reg/B[0]` | 3.254 | 0 |
| PE4 INT8 | `score_q_reg[0][1]/C` | `class_o_reg[0]/D` | 17.907 | 37 |
| PE8 코어 A INT8 | `score_q_reg[0][0]/C` | `class_o_reg[0]/D` | 12.655 | 25 |
| PE8 코어 B INT8 | `score_q_reg[0][0]/C` | `class_o_reg[0]/D` | 9.442 | 18 |
| PE4 INT16 | `score_q_reg[0][1]/C` | `class_o_reg[0]/D` | 19.386 | 43 |
| 17장 Tile INT8 | `score_q_reg[0][1]/C` | `class_o_reg[0]/D` | 19.386 | 43 |
| 18장 Tile INT16 | `score_q_reg[0][1]/C` | `class_o_reg[0]/D` | 19.374 | 49 |

