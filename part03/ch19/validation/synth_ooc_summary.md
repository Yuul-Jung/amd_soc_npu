# 4-4 Vivado OOC 합성 요약 (실제 실행)

> Vivado 2024.2, `synth_design -mode out_of_context`, xc7a35tcpg236-1, `create_clock -period 10.000 clk`.
> 첫 표는 **합성 직후 추정치**, 배선 후 결과는 아래 별도 표. 비트스트림·실물은 하지 않았다.

| 구성 | RTL | DSP48E1 | BRAM Tile | LUT | LUTRAM | FF | WNS(ns) | TNS(ns) | 실패 끝점 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| PE1 INT8 | `p3_group10_core #(64,1)` | 1 | 0.5 | 73 | 0 | 123 | 4.919 | 0.000 | 0 |
| PE4 INT8 | `p3_group10_core #(64,10) — 3-2 기본` | 4 | 2 | 301 | 0 | 597 | 2.758 | 0.000 | 0 |
| PE8 코어 A INT8 | `p3_group10_core #(64,6)` | 4 | 2 | 294 | 0 | 401 | 2.758 | 0.000 | 0 |
| PE8 코어 B INT8 | `p3_group10_core #(64,4)` | 4 | 2 | 283 | 0 | 302 | 2.195 | 0.000 | 0 |
| PE4 INT16 | `p3_group10_core DATA_W 16·ACC_W 38` | 4 | 2 | 459 | 0 | 779 | 2.087 | 0.000 | 0 |
| 4-2 Tile INT8 | `p3_tile784_10 기본` | 4 | 2 | 1512 | 0 | 1411 | 2.359 | 0.000 | 0 |
| 4-3 Tile INT16 | `p3_tile784_10 DATA_W 16` | 4 | 2 | 1674 | 0 | 1790 | 2.521 | 0.000 | 0 |

- PE8 = 코어 A + 코어 B (각각 따로 합성한 값의 합으로 읽는다. 공유 x 포트 배선은 포함되지 않음).
- BRAM Tile 0.5 = RAMB18 1개. 3-2 코어의 lane별 가중치 bank가 RAMB18로 추론되었다.

## 임계 경로 (합성 추정)

| 구성 | 시작 | 끝 | Data Path(ns) | Logic Levels |
|---|---|---|---:|---:|
| PE1 INT8 | `bank0_reg/CLKBWRCLK` | `lane0/acc_o_reg/B[0]` | 3.254 | 0 |
| PE4 INT8 | `s01_reg[1]/C` | `best_s_q_reg[0]/CE` | 6.956 | 12 |
| PE8 코어 A INT8 | `s01_reg[1]/C` | `best_s_q_reg[0]/CE` | 6.956 | 12 |
| PE8 코어 B INT8 | `s01_reg[0]/C` | `best_s_q_reg[0]/CE` | 7.519 | 13 |
| PE4 INT16 | `s01_reg[1]/C` | `best_s_q_reg[0]/CE` | 7.627 | 14 |
| 4-2 Tile INT8 | `score_q_reg[2][0]/C` | `a2c0_q_reg[0]/D` | 7.586 | 14 |
| 4-3 Tile INT16 | `score_q_reg[2][1]/C` | `a2c0_q_reg[0]/D` | 7.424 | 16 |

## OOC 배치·배선 후 (opt_design → place_design → route_design)

> 최상위 포트를 FPGA 핀에 묶지 않은 OOC 구현이다. 칩 전체 Top·I/O·비트스트림·실물은 별도.

| 구성 | DSP | BRAM Tile | LUT | FF | WNS(ns) | TNS(ns) | 실패 끝점 | 임계 경로 | Data Path(ns) |
|---|---:|---:|---:|---:|---:|---:|---:|---|---:|
| PE1 INT8 | 1 | 0.5 | 69 | 123 | 4.560 | 0.000 | 0 | `bank0_reg/CLKBWRCLK` → `lane0/acc_o_reg/B[12]` | 3.613 |
| PE4 INT8 | 4 | 2 | 290 | 597 | 1.096 | 0.000 | 0 | `s23_reg[3]/C` → `best_s_q_reg[17]/CE` | 8.615 |
| PE8 코어 A INT8 | 4 | 2 | 285 | 401 | 1.488 | 0.000 | 0 | `s23_reg[1]/C` → `best_s_q_reg[7]/CE` | 8.223 |
| PE8 코어 B INT8 | 4 | 2 | 276 | 302 | 0.901 | 0.000 | 0 | `s23_reg[1]/C` → `best_s_q_reg[18]/CE` | 8.810 |
| PE4 INT16 | 4 | 2 | 443 | 779 | 1.144 | 0.000 | 0 | `s01_reg[3]/C` → `best_s_q_reg[3]/CE` | 8.567 |
| 4-2 Tile INT8 | 4 | 2 | 1496 | 1411 | 0.712 | 0.000 | 0 | `score_q_reg[2][3]/C` → `a2c0_q_reg[0]/D` | 8.934 |
| 4-3 Tile INT16 | 4 | 2 | 1661 | 1790 | 0.625 | 0.000 | 0 | `score_q_reg[0][2]/C` → `a2s0_q_reg[19]/D` | 9.016 |

