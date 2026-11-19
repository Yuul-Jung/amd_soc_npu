# 21장 MicroBlaze V + NPU SoC 빌드 요약 — 안 A 동결 주소맵 (Vivado 2024.2 실제 실행, 2026-11-19)

> `scripts/build_soc.sh` 실행 결과(`validation/build_soc.log`, 4분 45초). 복제 프로젝트·Bitstream·XSA는 `build/`(저장소 제외).
> 이전(원본 11장 주소 그대로) 값은 Git 이력에만 남긴다.
> **Basys3 실물 다운로드·동작은 하지 않았다(사용자와 함께 진행, `ch27/docs/BOARD_CHECKLIST.md`).**

## 주소 맵 (MicroBlaze V Data 주소 공간, Address Editor 실제 값 = 안 A 표)

| 인덱스 | 세그먼트 | 베이스 | 범위 | 비고 |
|---|---|---|---|---|
| — | dlmb_bram_if_cntlr (LMB BRAM) | 0x0000_0000 | 64 KB | 원본 |
| [00] | axi_gpio_0 LED(16)/SW(16) | 0x4000_0000 | 64 KB | 원본 |
| [01] | **axi_gpio_btn** BTN 4비트(U·D·L·R), 인터럽트 | **0x4001_0000** | 64 KB | 신규 |
| [02] | axi_uartlite_0 115200 | **0x4002_0000** | 64 KB | 0x4060_0000에서 이동 |
| [03] | axi_timer_0 | **0x4003_0000** | 64 KB | 0x41C0_0000에서 이동 |
| [04] | axi_intc_0 (입력 16) | **0x4004_0000** | 64 KB | 0x4120_0000에서 이동 |
| [05] | IIC | — | — | 넣지 않음(자리만 비움) |
| [06] | **ip06_seg7** = `ip_seg7` 1.0 (ID 0x53454737) | **0x4006_0000** | 64 KB | 신규, 모듈 참조(`part03/common/rtl/ip_std`) |
| — | p3_npu_0 (s_axi/reg0) | 0x44A0_0000 | 4 KB | 그대로 |

검사: `ADDR_MAP_A_PASS`(8줄 모두 OK, 추가 세그먼트 없음), 겹침 없음 CHECK_PASS.
`xparameters.h`(22장 플랫폼): `XPAR_AXI_GPIO_BTN_BASEADDR 0x40010000`, `XPAR_AXI_UARTLITE_0_BASEADDR 0x40020000`,
`XPAR_AXI_TIMER_0_BASEADDR 0x40030000`, `XPAR_AXI_INTC_0_BASEADDR 0x40040000`, `XPAR_IP06_SEG7_BASEADDR 0x40060000`,
`XPAR_P3_NPU_0_BASEADDR 0x44a00000`, `XPAR_AXI_INTC_0_NUM_INTR_INPUTS 0x10`.

## 인터럽트 (`irq_concat` xlconcat 16입력 → `axi_intc_0/intr`)

| INTC 입력 | 연결 |
|---|---|
| In0 | axi_timer_0/interrupt |
| In1 | axi_uartlite_0/interrupt (예약: 연결만, 펌웨어는 켜지 않음) |
| In2 | 0 (IIC 예약) |
| In3 | axi_gpio_btn/ip2intc_irpt |
| In4~In11 | 0 (C 시리즈 확장 예약) |
| **In12** | **p3_npu_0/irq_o** (이전 In1) |
| In13~In15 | 0 |

검사: `IRQ_MAP_A_PASS`(16입력 모두 OK, 예약 칸은 `irq_zero` 상수 0).
참고: NPU IP 패키지에 인터럽트 부모 정보가 없어 `XPAR_FABRIC_P3_NPU_0_INTR`은 생기지 않는다. 번호 12는 `common/sw/p3_seg7.h`의 `P3_INTC_BIT_NPU`로 둔다(지금 펌웨어는 폴링).

## 연결

| 항목 | 연결 | 검사 |
|---|---|---|
| AXI | `axi_smc` NUM_MI 4 → 7: M04 NPU, M05 BTN GPIO, M06 SEG7 | CHECK_PASS |
| 클록·Reset | 새 블록 모두 GPIO 0과 같은 넷(clk_wiz_1 100 MHz, `peripheral_aresetn`) | CHECK_PASS |
| 외부 포트 | `btn`(GPIO 인터페이스), `seg[6:0]`·`dp`·`an[3:0]` | CHECK_PASS |
| 사용자 Top | `rtl/basys3_soc21_top.v`(핀 연결만). 원본 `basys3_soc11_top`은 복제본에서 비활성 | CHECK_PASS |
| 핀 | btn[3:0] = T18·U17·W19·T17, seg = W7·W6·U8·V8·U5·V5·U7, dp V7, an = U2·U4·V4·W4 (Basys-3-Master.xdc) | XDC |
| 원본 보존 | 제1부 11장 폴더 파일 트리 SHA-256 빌드 전후 동일 | ORIGINAL_PROJECT_UNCHANGED |

## 구현 결과 (칩 전체, 배치·배선 후)

| 항목 | 값 |
|---|---|
| Timing @100 MHz | **WNS +0.374 ns, WHS +0.034 ns** (setup·hold 충족) |
| 전체 LUT / FF | 5,406 (25.99%) / 5,285 (12.70%) |
| 전체 BRAM Tile / DSP | 18.5 (37.0%) / 4 |
| p3_npu_0 | LUT 2,103, FF 1,975, RAMB18 5, DSP48E1 4 |
| microblaze_riscv_0 | LUT 1,645, FF 1,294 |
| axi_smc | LUT 651, FF 683 |
| ip06_seg7 / axi_gpio_btn | LUT 93, FF 179 / LUT 74, FF 109 |
| XSA | `soc21_npu.xsa` (-fixed -include_bit) SHA-256 24abeb3a…458d |
| Bitstream | `basys3_soc21_top.bit` SHA-256 fca1368c…3925 |
