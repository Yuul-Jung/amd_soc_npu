# 제21장 · MicroBlaze V + NPU SoC 통합

## 1. 구조

```text
Basys3 W5 100 MHz → clk_wiz_1 → rst_clk_wiz_1_100M
MicroBlaze V (microblaze_riscv_0) ─M_AXI_DP─► axi_smc (SmartConnect, MI 5)
                                                ├ M00 axi_gpio_0      0x4000_0000
                                                ├ M01 axi_uartlite_0  0x4060_0000
                                                ├ M02 axi_timer_0     0x41C0_0000
                                                ├ M03 axi_intc_0      0x4120_0000
                                                └ M04 p3_npu_0 (20장 IP) 0x44A0_0000 / 4 KB   ← 신규
axi_timer_0/interrupt ─In0┐
p3_npu_0/irq_o       ─In1┴ irq_concat → axi_intc_0/intr → MicroBlaze V INTERRUPT
basys3_soc11_top (제1부 11장 사용자 Top, 변경 없음) → soc11_integration_wrapper
```

| 항목 | 계약 |
|---|---|
| 출발점 | 제1부 11장 성공 프로젝트 `soc11_user_top`를 `cp -a`로 `build/`에 복제. **원본은 열지 않는다**(트리 해시 전후 비교) |
| 신규 파일 | `synth/soc_npu_bd.tcl`(BD 수정·검사·빌드), `scripts/build_soc.sh`, `constraints/basys3_soc21_npu.xdc` |
| XDC | 원본이 쓰는 Basys3 Master XDC의 활성 42줄을 그대로 옮김(원본 XDC는 상대 경로라 복제 위치에서 맞지 않음) |
| 이름 | BD `soc11_integration`, Wrapper `soc11_integration_wrapper`, Top `basys3_soc11_top` 그대로. NPU 셀 `p3_npu_0` |
| 합성 방식 | 원본과 같은 IP별 OOC(Hierarchical). 전역 합성으로 바꾸면 MicroBlaze V 코어가 black box가 되어 실패한다(실제로 확인) |
| 산출물 | `build/out/soc21_npu.xsa`(Bitstream 포함), `build/out/*.bit`, 보고서 — 저장소 제외(`.gitignore`) |

## 2. 실행

```bash
SOC11_DIR=<제1부 11장 soc11_user_top 폴더> VIVADO_SETTINGS=<Vivado>/settings64.sh JOBS=8 \
  bash part03/ch21/scripts/build_soc.sh
```

20장 `package_ip.sh`로 NPU IP를 `build/ip_repo`에 만든 뒤, 복제 프로젝트에서 BD 수정 → `validate_bd_design` → 정적 검사 → Wrapper → 합성 → 구현 → Bitstream → XSA.

## 3. 결과 (`validation/soc_summary.md`, `validation/build_soc.log`)

- CHECK 9개 모두 PASS: 원본 NUM_MI 4, 주소 겹침 없음, NPU 베이스 0x44A0_0000, NPU 클록 = SmartConnect 클록, NPU Reset = peripheral_aresetn, irq_concat → INTC, 사용자 Top 유지, 합성·구현·Bitstream 완료, 배선 후 setup·hold 충족
- **칩 전체 배선 후 WNS +0.219 ns / WHS +0.021 ns @100 MHz**
- 자원: 전체 LUT 4,985(24%), FF 4,692(11%), BRAM Tile 18.5(37%), DSP 4. NPU는 LUT 2,109·FF 1,975·RAMB18 5·DSP 4
- `ORIGINAL_PROJECT_UNCHANGED` — 원본 폴더 파일 트리 SHA-256 빌드 전후 동일

**미검증:** Basys3 실물 다운로드·UART 출력·인터럽트 동작(사용자와 함께), Vitis 응용은 22장.
