# 30장 모터 안전 코어 Vivado OOC 합성·배선 (실제 실행)

> Vivado 2024.2, `synth_design -mode out_of_context`, xc7a35tcpg236-1, `create_clock -period 10.000 clk`.
> 첫 표는 **합성 직후 추정치**, 배선 후 결과는 아래 별도 표. 비트스트림·실물은 하지 않았다.

| 구성 | RTL | DSP48E1 | BRAM Tile | LUT | LUTRAM | FF | WNS(ns) | TNS(ns) | 실패 끝점 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| MOTOR_SAFETY | `p3_motor_safety (20 kHz PWM, DEAD 100 ms, WD 500 ms)` | 0 | 0 | 174 | 0 | 120 | 4.730 | 0.000 | 0 |


## 임계 경로 (합성 추정)

| 구성 | 시작 | 끝 | Data Path(ns) | Logic Levels |
|---|---|---|---:|---:|
| MOTOR_SAFETY | `wd_cnt_reg[4]/C` | `ramp_cnt_reg[0]/R` | 4.662 | 4 |

## OOC 배치·배선 후 (opt_design → place_design → route_design)

> 최상위 포트를 FPGA 핀에 묶지 않은 OOC 구현이다. 칩 전체 Top·I/O·비트스트림·실물은 별도.

| 구성 | DSP | BRAM Tile | LUT | FF | WNS(ns) | TNS(ns) | 실패 끝점 | 임계 경로 | Data Path(ns) |
|---|---:|---:|---:|---:|---:|---:|---:|---|---:|
| MOTOR_SAFETY | 0 | 0 | 169 | 120 | 3.699 | 0.000 | 0 | `wd_cnt_reg[28]/C` → `duty_cur_reg[0]/R` | 5.788 |

