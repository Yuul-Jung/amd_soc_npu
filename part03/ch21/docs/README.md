# 제21장 · MicroBlaze V + NPU SoC 통합

## 1. 구조

> (변경) 안 A(2026-11-19): 동결 주소맵, BTN GPIO, 표준 7세그먼트 IP(`ip_seg7`), INTC 입력 16개(NPU = In12), 사용자 Top `basys3_soc21_top`.
> 28~31장은 이 SoC(Bitstream·XSA)를 그대로 쓰고 ELF만 새로 만든다.

```text
Basys3 W5 100 MHz → clk_wiz_1 → rst_clk_wiz_1_100M
MicroBlaze V (microblaze_riscv_0) ─M_AXI_DP─► axi_smc (SmartConnect, MI 7)
                                                ├ M00 axi_gpio_0      0x4000_0000  [00] LED/SW
                                                ├ M05 axi_gpio_btn    0x4001_0000  [01] BTN U·D·L·R  ← 신규
                                                ├ M01 axi_uartlite_0  0x4002_0000  [02]
                                                ├ M02 axi_timer_0     0x4003_0000  [03]
                                                ├ M03 axi_intc_0      0x4004_0000  [04] 입력 16
                                                ├ M06 ip06_seg7       0x4006_0000  [06] ip_seg7 "SEG7" ← 신규
                                                └ M04 p3_npu_0 (20장 IP) 0x44A0_0000 / 4 KB
irq_concat(16) → axi_intc_0/intr: In0 Timer, In1 UART(예약), In3 BTN, In12 NPU, 나머지 0
basys3_soc21_top (핀 연결만: clk, btnC, btn[3:0], sw, led, RsRx/RsTx, seg, dp, an) → soc11_integration_wrapper
```

| 항목 | 계약 |
|---|---|
| 출발점 | 제1부 11장 성공 프로젝트 `soc11_user_top`를 `cp -a`로 `build/`에 복제. **원본은 열지 않는다**(트리 해시 전후 비교) |
| 신규 파일 | `synth/soc_npu_bd.tcl`(BD 수정·검사·빌드), `scripts/build_soc.sh`, `constraints/basys3_soc21_npu.xdc`, `rtl/basys3_soc21_top.v` |
| XDC | 원본이 쓰는 Basys3 Master XDC의 활성 42줄 + 안 A의 btn·seg·dp·an 16핀(Basys-3-Master.xdc와 같은 핀) |
| 이름 | BD `soc11_integration`, Wrapper `soc11_integration_wrapper` 그대로. Top `basys3_soc21_top`(원본 Top은 복제본에서 비활성). 셀 `p3_npu_0`·`axi_gpio_btn`·`ip06_seg7` |
| 합성 방식 | 원본과 같은 IP별 OOC(Hierarchical). 전역 합성으로 바꾸면 MicroBlaze V 코어가 black box가 되어 실패한다(실제로 확인) |
| 산출물 | `build/out/soc21_npu.xsa`(Bitstream 포함), `build/out/*.bit`, 보고서 — 저장소 제외(`.gitignore`) |

## 2. 실행

```bash
SOC11_DIR=<제1부 11장 soc11_user_top 폴더> VIVADO_SETTINGS=<Vivado>/settings64.sh JOBS=8 \
  bash part03/ch21/scripts/build_soc.sh
```

20장 `package_ip.sh`로 NPU IP를 `build/ip_repo`에 만든 뒤, 복제 프로젝트에서 BD 수정 → `validate_bd_design` → 정적 검사 → Wrapper → 합성 → 구현 → Bitstream → XSA.

## 3. 결과 (`validation/soc_summary.md`, `validation/build_soc.log`, 2026-11-19 안 A)

- `ADDR_MAP_A_PASS`(8세그먼트 표 대조), `IRQ_MAP_A_PASS`(INTC 16입력 대조), 주소 겹침 없음, 클록·Reset·외부 포트·사용자 Top CHECK_PASS
- **칩 전체 배선 후 WNS +0.374 ns / WHS +0.034 ns @100 MHz**
- 자원: 전체 LUT 5,406(26%), FF 5,285(13%), BRAM Tile 18.5(37%), DSP 4. SEG7 LUT 93·FF 179, BTN GPIO LUT 74·FF 109
- `ORIGINAL_PROJECT_UNCHANGED` — 원본 폴더 파일 트리 SHA-256 빌드 전후 동일

**미검증:** Basys3 실물 다운로드·UART 출력·7세그먼트·버튼·인터럽트 동작(사용자와 함께, `ch27/docs/BOARD_CHECKLIST.md`), Vitis 응용은 22장.
