# 6-3 경보 정책 RTL Vivado OOC 합성·배선 (실제 실행)

> Vivado 2024.2, `synth_design -mode out_of_context`, xc7a35tcpg236-1, `create_clock -period 10.000 clk`.
> 첫 표는 **합성 직후 추정치**, 배선 후 결과는 아래 별도 표. 비트스트림·실물은 하지 않았다.

| 구성 | RTL | DSP48E1 | BRAM Tile | LUT | LUTRAM | FF | WNS(ns) | TNS(ns) | 실패 끝점 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| ALARM_POLICY | `p3_alarm_policy (CLEAR_N=3)` | 0 | 0 | 18 | 0 | 8 | 7.338 | 0.000 | 0 |


## 임계 경로 (합성 추정)

| 구성 | 시작 | 끝 | Data Path(ns) | Logic Levels |
|---|---|---|---:|---:|
| ALARM_POLICY | `hold_reg[1]/C` | `state_reg[0]/D` | 2.607 | 2 |

## OOC 배치·배선 후 (opt_design → place_design → route_design)

> 최상위 포트를 FPGA 핀에 묶지 않은 OOC 구현이다. 칩 전체 Top·I/O·비트스트림·실물은 별도.

| 구성 | DSP | BRAM Tile | LUT | FF | WNS(ns) | TNS(ns) | 실패 끝점 | 임계 경로 | Data Path(ns) |
|---|---:|---:|---:|---:|---:|---:|---:|---|---:|
| ALARM_POLICY | 0 | 0 | 16 | 8 | 6.711 | 0.000 | 0 | `latch_reg/C` → `cnt_reg[1]/D` | 3.282 |

