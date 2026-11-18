# 28장 숫자 인식 SoC 빌드 요약 (Vivado·Vitis 2024.2 실제 실행)

> `scripts/build_soc.sh` 실행 결과(`validation/build_soc.log`). 복제 프로젝트·Bitstream·XSA·ELF는 `build/`(저장소 제외).
> **Basys3 실물 다운로드·동작은 하지 않았다(사용자와 함께 진행).**

## 21장 대비 변경 (복제본에서만)

| 항목 | 내용 | 검사 |
|---|---|---|
| 출발점 | `ch21/build/soc21_npu`를 `cp -a`로 복제. 21장 폴더 트리 SHA-256 빌드 전후 동일 | CH21_PROJECT_UNCHANGED |
| AXI | `axi_smc` NUM_MI 5 → 6, `M05_AXI` → `axi_gpio_1`(32비트, 모두 출력, 초기값 0) | CHECK_PASS |
| 주소 | `axi_gpio_1` 0x4001_0000 / 64 KB, NPU 0x44A0_0000 그대로, 세그먼트 7개 겹침 없음 | CHECK_PASS |
| FND | `fnd_scan_0` = `p3_fnd_scan`(BD 모듈 참조) — GPIO와 같은 클록(clk_wiz_1 100 MHz)·`peripheral_aresetn` | CHECK_PASS |
| 외부 포트 | BD 포트 `seg[6:0]`·`dp`·`an[3:0]` → 새 Top `basys3_soc28_top`(핀 연결만). 원본 Top 파일은 복제본에서 비활성 | CHECK_PASS |
| 핀 | seg[0]=W7, seg[6]=U7, dp=V7, an[0]=U2, an[3]=W4 (Basys-3-Master.xdc), RsRx=B18, led[15]=L1 | CHECK_PASS |

## 구현 결과 (칩 전체, 배치·배선 후)

| 항목 | 28장 | (21장) |
|---|---|---|
| Timing @100 MHz | **WNS +0.420 ns, WHS +0.020 ns** | +0.219 / +0.021 |
| 전체 LUT / FF | 5,170 (24.86%) / 4,935 (11.86%) | 4,985 / 4,692 |
| BRAM Tile / DSP | 18.5 / 4 | 18.5 / 4 |
| axi_gpio_1 | LUT 63, FF 158 | — |
| fnd_scan_0 | LUT 16, FF 31 | — |
| XSA | `soc28_digit.xsa` SHA-256 2bffbd6f…b8de | |
| Bitstream | `basys3_soc28_top.bit` SHA-256 0bce5489…772c | |
| ELF | `digit_app.elf` text 27,456 + data 204 + bss 5,252 = 32,912 B (LMB 64 KB), SHA-256 9179c509c9e7dbaa | |

CRITICAL WARNING 4건: `Constraints 18-1055/1056`(sys_clk_pin이 clk_wiz 입력 클록 정의를 대체)은 21장과 같은 2건이다.
`filemgmt 20-742`(원본 Top 비활성 직후 자동 Top 선택)는 스크립트가 곧바로 `basys3_soc28_top`을 지정하고 검사한다.
`Synth 8-6895`(원본의 증분 합성 체크포인트가 맞지 않아 일반 합성으로 진행)는 결과에 영향이 없다.
