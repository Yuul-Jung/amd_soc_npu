# 31장 AES-128·SHA-256 코어 Vivado OOC 합성·배선 (실제 실행)

> Vivado 2024.2, `synth_design -mode out_of_context`, xc7a35tcpg236-1, `create_clock -period 10.000 clk`.
> 첫 표는 **합성 직후 추정치**, 배선 후 결과는 아래 별도 표. 비트스트림·실물은 하지 않았다.

| 구성 | RTL | DSP48E1 | BRAM Tile | LUT | LUTRAM | FF | WNS(ns) | TNS(ns) | 실패 끝점 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| AES128 | `p3_aes128_enc (1 라운드/클록, 11클록/블록)` | 0 | 5 | 560 | 0 | 270 | 3.521 | 0.000 | 0 |
| SHA256 | `p3_sha256_core (1 라운드/클록, 66클록/블록)` | 0 | 0 | 1417 | 0 | 1044 | 0.219 | 0.000 | 0 |


## 임계 경로 (합성 추정)

| 구성 | 시작 | 끝 | Data Path(ns) | Logic Levels |
|---|---|---|---:|---:|
| AES128 | `sel/CLKBWRCLK` | `sel__0/ADDRARDADDR[4]` | 5.829 | 3 |
| SHA256 | `t_reg[0]/C` | `a_reg[31]/D` | 9.726 | 15 |

## OOC 배치·배선 후 (opt_design → place_design → route_design)

> 최상위 포트를 FPGA 핀에 묶지 않은 OOC 구현이다. 칩 전체 Top·I/O·비트스트림·실물은 별도.

| 구성 | DSP | BRAM Tile | LUT | FF | WNS(ns) | TNS(ns) | 실패 끝점 | 임계 경로 | Data Path(ns) |
|---|---:|---:|---:|---:|---:|---:|---:|---|---:|
| AES128 | 0 | 5 | 554 | 270 | 1.829 | 0.000 | 0 | `sel/CLKBWRCLK` → `st_reg_rep/ADDRARDADDR[8]` | 7.521 |
| SHA256 | 0 | 0 | 1394 | 1044 | 0.117 | 0.000 | 0 | `t_reg[4]/C` → `a_reg[29]/D` | 9.831 |

