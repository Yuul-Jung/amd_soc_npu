# 21장 MicroBlaze V + NPU SoC 빌드 요약 (Vivado 2024.2 실제 실행)

> `scripts/build_soc.sh` 실행 결과(`validation/build_soc.log`). 복제 프로젝트·Bitstream·XSA는 `build/`(저장소 제외).
> **Basys3 실물 다운로드·동작은 하지 않았다(사용자와 함께 진행).**

## 주소 맵 (MicroBlaze V Data 주소 공간, Address Editor 실제 값)

| 세그먼트 | 베이스 | 범위 | 비고 |
|---|---|---|---|
| dlmb_bram_if_cntlr (LMB BRAM) | 0x0000_0000 | 64 KB | 원본 |
| axi_gpio_0 | 0x4000_0000 | 64 KB | 원본 |
| axi_uartlite_0 | 0x4060_0000 | 64 KB | 원본 |
| axi_intc_0 | 0x4120_0000 | 64 KB | 원본 |
| axi_timer_0 | 0x41C0_0000 | 64 KB | 원본 |
| **p3_npu_0 (s_axi/reg0)** | **0x44A0_0000** | **4 KB** | 신규. 레지스터 64바이트가 4 KB 안에서 반복 |

## 연결

| 항목 | 연결 | 검사 |
|---|---|---|
| AXI | `axi_smc` NUM_MI 4 → 5, `M04_AXI` → `p3_npu_0/s_axi` | CHECK_PASS |
| 클록 | `p3_npu_0/s_axi_aclk` = SmartConnect·GPIO와 같은 넷(clk_wiz_1, 100 MHz) | CHECK_PASS |
| Reset | `p3_npu_0/s_axi_aresetn` = `rst_clk_wiz_1_100M/peripheral_aresetn` | CHECK_PASS |
| 인터럽트 | `irq_concat`(xlconcat 2) → `axi_intc_0/intr`: In0 = axi_timer_0, **In1 = p3_npu_0/irq_o** | CHECK_PASS |
| 주소 | 데이터 세그먼트 6개 겹침 없음 | CHECK_PASS |
| 사용자 Top | `basys3_soc11_top` 그대로(보드 핀·Wrapper 연결만), BD 이름 `soc11_integration` 유지 | CHECK_PASS |
| 원본 보존 | 원본 폴더 파일 트리 SHA-256 빌드 전후 동일 | ORIGINAL_PROJECT_UNCHANGED |

## 구현 결과 (칩 전체, 배치·배선 후)

| 항목 | 값 |
|---|---|
| Timing @100 MHz | **WNS +0.219 ns, WHS +0.021 ns** (setup·hold 충족) |
| 전체 LUT / FF | 4,985 (23.97%) / 4,692 (11.28%) |
| 전체 BRAM Tile / DSP | 18.5 (37.0%) / 4 |
| p3_npu_0 | LUT 2,109, FF 1,975, RAMB18 5 (가중치 bank 4 + x 버퍼 1), DSP48E1 4 |
| microblaze_riscv_0 | LUT 1,645, FF 1,294 |
| axi_smc | LUT 540, FF 533 |
| XSA | `soc21_npu.xsa` (-fixed -include_bit) SHA-256 da4edc61…a1fb |
| Bitstream | `basys3_soc11_top.bit` SHA-256 881216da…cbe0 |

- 경고 `[Constraints 18-1055/1056] sys_clk_pin overrides clk`는 원본 제1부 11장 프로젝트의 합성·구현 로그에도 같은 내용이 있다(이번 변경으로 생긴 것이 아님).
- 같은 RTL·같은 도구라도 배치·배선 결과의 SHA는 Vivado 버전·옵션에 따라 달라질 수 있다.
