# VS Code 보고 — 지시문 안 A (`docs/plan/VSCODE_DIRECTIVE_A.md`) 1~10 수행 결과 (2026-11-20)

> 브랜치: `vscode/part03-ch13-31` (part03 작업), `restructure/projects` (p01~p04 Vivado 증거만).
> 실물 Basys3는 하나도 실행하지 않았다 — 점검표 B1~B26 모두 `NOT_RUN` (사용자와 함께).
> 전력은 Vivado `report_power` 추정값이다.

## 7절 보고 표

| 항목 | 결과 | 증거 파일 | 값 |
|---|---|---|---|
| 미커밋 정리 | PASS | 4ddba1c·9203bfa·6ca0015·a1c8904·943f864·18d7b06 | 장 단위 원자 커밋 |
| SEG7 TB | PASS | f89e668 (`common/rtl/ip_std`, Icarus) | ID 0xFFF0 = 0x53454737 |
| ADDR_MAP_A / IRQ_MAP_A | PASS / PASS | `ch21/validation/build_soc.log` | 8줄 OK·추가 세그먼트 없음 / 16입력 OK, NPU = In12 |
| 21장 비트스트림 | PASS | `ch21/validation/soc_summary.md` | WNS +0.374 · WHS +0.034 ns, LUT 5,406 · FF 5,285, NPU RAMB18 5 · DSP 4, bit fca1368c…3925, XSA 24abeb3a…458d |
| 22~31장 ELF | PASS | 각 장 `validation/build_*.log` | 22 npu_app 30,952 B (bdb8cb6e, `VITIS_ELF_PASS`) · 28 digit 36,276 B (077ca88b) · 29 sensor 39,372 B (9afada1f) · 30 motor 53,748 B (68779b98) · 31 secure 61,556 B (624f4ced, 스택 끝 61,560) — 28~31장 `ELF_MEM_PASS`, LMB 65,536 |
| 23장 클록 | PASS (xsim) | `ch23/validation/soc_bench_sim.log` (749eb5a) | CPU 1,816,547 · NPU 1,080,161 클록 (안 A 이전과 같음) |
| 25장 전력 (안 A 재실행, 8-2) | PASS (추정) | `ch25/validation/power_summary.md` (c32d094) | CPU 4.596 · NPU 2.765 mJ/추론 (1.66배) |
| 27장 run_all | PASS | `ch27/validation/run_all_summary.md` (67a1a09 sim, 68fd5b6 fpga) | `LEVEL=sim` PASS, `LEVEL=fpga` 16/16 PASS (별도 worktree 처음부터 재빌드: WNS·ELF 크기 기록과 같음, SHA는 빌드 시각·경로로 다름) |
| 1장 Top STAGE 1~4 | PASS | `p01/validation/vivado_impl_20261119.txt` | WNS 최소 +3.211 · WHS 최소 +0.024, LUT 427 · DSP 3 (STAGE 4) |
| 2장 Top STAGE 1~8 | PASS | `p02/validation/vivado_impl_20261119.txt` (7eb69ed) | STAGE 8 재실행(8-1) WNS +0.484 · WHS +0.021 (수정 전 −1.952), LUT 4,307 · DSP 17 · RAMB18 15 |
| 3장 Top STAGE 1~4 | PASS | `p03/validation/vivado_impl_20261119.txt` | WNS 최소 +0.710, LUT 4,331 · DSP 20 (STAGE 4) |
| 4장 Top STAGE 1~4 | PASS | `p04/validation/vivado_impl_20261119.txt` | WNS 최소 +0.224, LUT 7,400 · DSP 21 (STAGE 4) |
| 28장 안 A SoC xsim (10) | **PASS** | `ch28/validation/soc_sim_mapA_20261120.log` | `SOC28_RTL_SIM_PASS checks=15/15`, NPU 7 = CPU 7, 점수 = 기준 모델, SEG7·LED 핀 대조 |
| 30장 안 A SoC (10) | PASS (빌드) | `ch30/validation/build_soc_mapA_20261120.log` (336d1b2) | 모터 GPIO `axi_gpio_motor` 0x4007_0000, ADDR_MAP_A 9줄·IRQ_MAP_A PASS, WNS +0.357 · WHS +0.030, bit 2fa4deada606d078 · XSA 3f06b52665eb4c26 |
| 판단 필요 | — | — | 아래 |

## 판단 결과 (내가 정한 것 — 바꾸려면 지시)

| 항목 | 정한 것 | 이유 |
|---|---|---|
| 30장 모터 연결 | AXI GPIO(듀얼) `axi_gpio_motor`를 0x4007_0000에 두고 `p3_motor_safety_bd`를 그 뒤에 연결 | 모터 코어는 AXI 슬레이브가 아니라 명령·상태 워드 포트다. 기존 검증(협동 sim·변이 시험)을 그대로 유지 |
| 30장 인터럽트 | 쓰지 않음 (In4 = 0 그대로) | 펌웨어가 폴링, 워치독은 코어 안 |
| btnU | 21장처럼 btn[3](BTN GPIO)이면서 비상정지 입력에도 연결 (Top 배선만) | 21장 핀·주소를 바꾸지 않기 위해. 점검표 B23b로 확인 |
| 28장 `p3_fnd_scan` | RTL 시험용으로만 남김, BD에서는 표준 SEG7 | a41a118 |

## 4절 — 웹이 가져간 파일 변경

`part03/ch13~19`·`ch04/rtl/bram_sync_buffer.v`·`host_tools`·`ch02/rtl/dsp_multiplier.v`·`mini_npu/rtl/npu_dsp_mac_lane.v`: 9203bfa 이후 **변경 없음**.

## 추가 — VSCODE_HANDOFF 2절 00~12장 Vivado 게이트 (`restructure/projects`)

| 항목 | 결과 | 증거 | 값 |
|---|---|---|---|
| OOC 합성·타이밍 (`run_vivado_all.sh ooc`) | **19 PASS · 2 FAIL · 3 미검사** (정정 2026-11-22, 이전 기재 22/24 PASS는 잘못) | `chNN/validation/vivado_ooc_20261120.txt` (200eedc) | 00·03·05~10·13~20·30장 PASS (19장 NPE 1·4·8). 01·02·04장은 WNS·WHS=NA, 검사된 경로가 없어 PASS가 아니다 (`VSCODE_TO_WEB_20261122.md` 2절). **코드 판 구분(정정 2026-11-23): 19 PASS 중 00~10장이 8건이고, 13~20·30장 11건은 채택하지 않은 웹 판 RTL의 결과다.** 채택한 VS Code 판의 타이밍 근거는 아래 표 |
| 도구 수정 | — | `tools/vivado/ooc_timing.tcl` (200eedc) | `worst_slack`: SLACK이 비면 NA (첫 실행에서 01·02·04장이 Tcl 오류로 FAIL로 찍혔던 원인). 정정 2026-11-22: 이 수정으로 NA가 PASS로 집계됐고, VS Code 작업 경계 밖 수정이었다 |
| 웹 판 ch26 `npu_cnn3x3` | **FAIL** | `ch26/validation/vivado_ooc_20261120.txt` | WNS −0.468 ns — VS Code 판 `part03/ch26`은 OOC PASS (68fd5b6). 억지로 고치지 않음 |
| 웹 판 ch29 `sensor_guard_ai` | **FAIL** | `ch29/validation/vivado_ooc_20261120.txt` | WNS −2.811 ns — VS Code 판 `part03/ch29`은 OOC PASS (68fd5b6). 억지로 고치지 않음 |
| 12장 구현 | PASS | `ch12/validation/vivado_impl_timesim_20261122.txt` (a5d89dc) | WNS +1.193 · WHS +0.064, LUT 1,656 · DSP 4 · RAMB 5 |
| 12장 배선 후 SDF 타이밍 시뮬레이션 | **PASS** (2026-11-22, 전체 시나리오) | `ch12/validation/vivado_impl_timesim_20261122.txt` (`restructure/projects` a5d89dc) | 분류 6/6 = 기준 모델, Bias 변경·ERR 확인, 위반 경고 0(음성 대조로 검출 확인). 이전에 적은 RSTRAMB setup 경고 2건은 11-20 실행의 기록이며 이번 실행에는 없음. 동작 중 btnC 리셋은 미검증 |
| 12장 동기 리셋 판 (지시 12·13) | **PASS** (2026-11-23, 구현 + SDF 전체 시나리오) | `ch12/validation/vivado_impl_timesim_20261123.txt` (`fix/sync-reset` 1b99bd2) | WNS +1.993 · WHS +0.024, 분류 6/6, 위반 경고 0. 동작 중 btnC는 별도 시험에서 RAMB18 위반 69 → 0건(위반 검출만) |

## 채택한 VS Code 판 13~31장 RTL의 타이밍 근거 (2026-11-23 파일 단위 대조)

| RTL | 근거 (100 MHz, 배선 후) |
|---|---|
| 13·14·16장 | p03 Top STAGE 1~4 PASS (15장은 자체 RTL 없음) |
| 14·17장, 18장 INT16 구성 | p04 Top STAGE 1~4, `ch19/validation/synth_ooc_summary.md` PASS |
| 20·26·29·30·31장 코어 | 각 장 `validation/synth_ooc_summary.md` PASS |
| 21·30장 SoC Top | 각 장 빌드 로그 PASS |
| `ch28/rtl/p3_fnd_scan.v` | 없음 (RTL 시험 전용, BD에서 쓰지 않음) |

## 남은 것

- Basys3 점검표 B1~B26 (사용자와 함께). B24 실제 모터는 사용자 판단으로 따로.
- 보드 실측과 sim 비교: 23장 클록, 28장 손글씨 결과 = PC.
- REQP-1840: `fix/sync-reset` 1b99bd2에서 21개 빌드 0건, 지시 13 합격 기준 충족 (`VSCODE_TO_WEB_20261122.md` 11절). **main에는 병합 전까지 남아 있다.** 남은 것은 웹의 HTML 재생성·CI 확인·병합이다.
- 보드 점검에는 12장·p01~p04의 2026-11-23 동기 리셋 비트스트림을 쓴다. 이전 비트스트림은 쓰지 않는다.
