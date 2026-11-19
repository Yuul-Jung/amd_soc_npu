# 제20장 · AXI4-Lite NPU 제어 IP

## 1. 구조

```text
MicroBlaze V ─AXI4-Lite─► p3_npu_axi_lite (신규 어댑터)
                            ├─ AW 보관 ┐
                            ├─ W  보관 ┴─ 둘 다 있으면 실행 → B 응답(BREADY까지 유지)
                            ├─ AR → R 응답(RREADY까지 유지)
                            ├─ 레지스터 뱅크 / SCORE 스냅샷 / IRQ
                            ├─ 04장 bram_sync_buffer (x 타일 64×INT8)
                            └─ 17장 p3_tile784_10 → 14장 p3_group10_core (변경 없음)
```

| 항목 | 계약 |
|---|---|
| 신규 RTL | `rtl/p3_npu_axi_lite.v` (AXI4-Lite Slave + 레지스터 + x 타일 버퍼 연결) |
| 재사용 | 17장 Tile Controller(784·10분류, 외부 누산 41 / Bias 40 / 점수 42비트), 14장 코어, 04장 동기 버퍼 |
| 버스 | AXI4-Lite 32비트 데이터, 주소 6비트(64바이트, 4 KB 주소 블록 안에서 반복), 한 채널당 미완료 1건 |
| 클록·Reset | `s_axi_aclk` 하나, `s_axi_aresetn` 동기 Active-Low(NPU와 공유) |
| 인터럽트 | `irq_o` = IRQ_EN[0] && STATUS.DONE (레벨, 높음 활성) |

Vivado 템플릿(Create and Package New IP)의 S00_AXI는 AW와 W가 모두 와야 둘 다 받는다. 이 장은 규격 요구(AW/W 독립 도착·응답 역압력·SLVERR)를 시험 가능한 형태로 직접 구현하고, 패키징만 `ipx` Tcl로 한다.

## 2. 레지스터 맵 (교육용 신규 계약, 실제 베이스 주소는 21장 Address Editor 값 사용)

| 오프셋 | 이름 | 접근 | 내용 |
|---|---|---|---|
| 0x00 | CTRL | W | bit0 START, bit1 TILE_GO(bits[11:8] = 타일 번호), bit2 ABORT — 한 번에 하나, WSTRB 4'hF 필수 |
| 0x04 | STATUS | R / W1C | bit0 BUSY, bit1 DONE(유지), bit2 ERROR(유지), bit3 OVF, bit4 LOAD_READY, bit5 X_HELD, [11:8] TILE, [15:12] ERR_CODE. bit1·bit2에 1을 쓰면 지움 |
| 0x08 | LENGTH | R/W | 입력 길이. 784만 허용(START 시 다르면 ERROR 8). Reset 784 |
| 0x0C | CLASS | R | 최종 Class 0~9 |
| 0x10 | X_INDEX | R/W | 0~63, X_DATA 쓰기마다 +1 |
| 0x14 | X_DATA | W | signed INT8(32비트 부호 확장 필수). 프레임 잠금(X_HELD) 중에는 SLVERR |
| 0x18 | W_CLASS | R/W | 0~9 (W_DATA·BIAS 대상 class) |
| 0x1C | W_INDEX | R/W | 0~63, W_DATA 쓰기마다 +1 |
| 0x20 | W_DATA | W | signed INT8 가중치 → 현재 타일 코어 bank |
| 0x24 | BIAS_LO | R/W | Bias 하위 32비트(대기) |
| 0x28 | BIAS_HI | W | Bias [39:32](bit 7 부호 확장 필수). 쓰는 순간 {HI, LO}를 W_CLASS의 Bias로 확정 |
| 0x2C | SCORE_SEL | R/W | 0~9 |
| 0x30 | SCORE_LO | R | 선택 점수 [31:0]. **읽는 순간 42비트 전체를 래치** |
| 0x34 | SCORE_HI | R | 마지막 SCORE_LO 읽기 때의 상위 [41:32] 부호 확장 32비트 |
| 0x38 | IRQ_EN | R/W | bit0 DONE 인터럽트 허용 |
| 0x3C | — | — | 미할당: 쓰기·읽기 SLVERR |

**응답 규칙:** 버스 수준 거부는 SLVERR이며 아무 효과도 없다 — 미할당 주소, 읽기 전용 레지스터 쓰기, 동작 레지스터(CTRL·X_DATA·W_DATA·BIAS_HI)의 부분 WSTRB, 범위 밖 값(X_INDEX·W_INDEX > 63, W_CLASS·SCORE_SEL > 9, 부호 확장 아님, CTRL 명령 2개 이상), 프레임 잠금 중 X_DATA. 설정 레지스터는 WSTRB 바이트만 바꾼 값으로 검사·저장한다. 쓰기 전용 레지스터는 0으로 읽힌다.

**ERR_CODE:** 1 상태 위반(IDLE의 TILE_GO, BUSY 중 START 등), 2 타일 중복, 3 타일 누락, 4 x 미완성 TILE_GO, 5 허용 외 쓰기(추론 중 Bias 등), 6 코어 오류(진단), 8 LENGTH ≠ 784, 9 가중치 미적재 TILE_GO(현재 타일 W 쓰기 < 10 × 유효 길이).

**DONE 정책:** 완료 시 1로 유지, STATUS W1C 또는 START 수락으로 0.

## 3. CPU 실행 순서 (784 추론)

```text
for c in 0..9: W_CLASS=c; BIAS_LO=b[31:0]; BIAS_HI=b[39:32]       (IDLE에서만)
CTRL=START
for t in 0..12 (len = 64, 마지막 16):
    for c in 0..9: W_CLASS=c; W_INDEX=0; W_DATA × len
    X_INDEX=0; X_DATA × 64                                          (마지막 타일 48개는 무시됨)
    CTRL=TILE_GO | t<<8
    STATUS 폴링: X_HELD=0 → LOAD_READY=1 (마지막 타일은 DONE=1)
CLASS 읽기; for c: SCORE_SEL=c; SCORE_LO → SCORE_HI   (LO 먼저)
STATUS=0x2 (DONE W1C, IRQ 해제)
```

## 4. 실행

```bash
bash part03/ch20/scripts/run_sim.sh                                     # BFM RTL 시뮬레이션
VIVADO_SETTINGS=<Vivado>/settings64.sh bash part03/ch20/scripts/run_synth.sh   # OOC 합성·배치·배선
VIVADO_SETTINGS=<Vivado>/settings64.sh bash part03/ch20/scripts/package_ip.sh  # IP 패키징(IP_OUT=<폴더>)
```

기대 출력:

```text
PYTHON_AXI_VECTORS_PASS inferences=7 regs=15 seed=2020
RTL_SIM_PASS AXI_NPU inferences=7 axi_writes=67451 axi_reads=7012 slverr=16
PYTHON_RTL_COMPARE_PASS inferences=7 scores_via_axi=10 class=1 overflow=1 bit_exact=1
SYNTH_OOC_SUMMARY configs=1 wns_negative=0 routed=1 route_wns_negative=0 out=synth_ooc_summary.md
BUSIF s_axi xilinx.com:interface:aximm:1.0 ... BUSIF irq_o xilinx.com:signal:interrupt:1.0 / IP_PACKAGE_DONE
```

## 5. 검증 결과

- **RTL(BFM):** 레지스터만으로 784 추론 7회 — 18장 MNIST INT8 표본 3개(INT8≠Float 1개 포함), INT8 극값 2개(Bias ±2³⁹ → SCORE_HI 사용), 무작위 1개, class 0·1 동점 1개. 10개 점수(LO/HI)·CLASS·OVF가 17장 기준모델과 비트 단위 일치
- **프로토콜:** AW·W 동시/AW 먼저/W 먼저, BREADY 4·7클록·RREADY 5클록 지연 중 응답 유지(상시 검사), B 대기 중 새 쓰기 차단, WSTRB 병합(바이트별), SLVERR 16건(효과 없음 확인)
- **동작:** LENGTH 528 START → 8, IDLE TILE_GO → 1, x 10개만 쓴 TILE_GO → 4, W 없는 TILE_GO → 9, BUSY 중 START → 1, 추론 중 Bias → 5, 계산 중 X_DATA → SLVERR, ERROR·DONE W1C, START가 남은 DONE을 지움, IRQ_EN 0/1 전환
- **스냅샷:** 추론 A 뒤 SCORE_LO를 읽어 두고 추론 B를 끝낸 뒤 SCORE_HI → A의 상위 비트
- **Reset:** AW만 받은 미완료 쓰기 중 Reset → 보관 삭제(W만으로는 실행 안 됨), 타일 5 계산 중 Reset → 처음부터 다시 추론 일치
- **변이 시험 16종 검출:** B 대기 중 AW 수락, B·R 유지 안 함, HI 실시간(스냅샷 없음), 잠금 중 X_DATA 허용, 읽기 전용 쓰기 OKAY, W 미적재·x 미완성·LENGTH 검사 제거, WSTRB 병합 없음, BIAS_HI 부호 검사 제거, ERROR W1C 고장, IRQ_EN 무시, 동작 레지스터 부분 WSTRB 허용, CTRL 명령 2개 허용, START 시 DONE 미해제
- **Vivado 2024.2 OOC(100 MHz, `validation/synth_ooc_summary.md`):** DSP 4, BRAM Tile 2.5, LUT 2076, FF 1975, **배선 후 WNS +0.223 ns**(임계: 컨트롤러 argmax 1·2단). 합성 경고는 미사용 AWPROT/ARPROT·주소 하위 2비트, OOC 클록 소스 안내뿐
- **IP 패키징:** `s_axi`(aximm), `s_axi_aclk`, `s_axi_aresetn`, `irq_o`(interrupt, LEVEL_HIGH), 주소 블록 4 KB. IP 폴더는 Vivado가 RTL을 `src/`로 복사하므로 저장소에 두지 않는 빌드 산출물(정본은 각 장 `rtl/`)

**미검증:** MicroBlaze V BD 연결·주소 할당·XSA(21장), Vitis 드라이버(22장), 칩 전체 Top 구현·비트스트림, Basys3 실물(사용자와 함께). 배선 후 여유가 0.223 ns로 작아 BD 통합 시 다시 확인한다.
