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

## 남은 것

- Basys3 점검표 B1~B26 (사용자와 함께). B24 실제 모터는 사용자 판단으로 따로.
- 보드 실측과 sim 비교: 23장 클록, 28장 손글씨 결과 = PC.
