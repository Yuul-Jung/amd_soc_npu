# 제19장 · PE 병렬도·BRAM 공급·메모리 구조 비교 (1PE·4PE·8PE)

## 1. 구성 — 14장 코어(변경 없음)만으로 만든다

```text
          ┌ PE1 : p3_group10_core #(64,1)  lane 0만 유효 → class마다 가중치 64개 재적재·10회 실행
x 타일 ───┼ PE4 : p3_group10_core #(64,10) 4+4+2 그룹 (14장 기본)
(13장     └ PE8 : 코어 A #(64,6) [class 0~3 → 8~9] ┐ 같은 클록 시작, 13장 버퍼 읽기 포트 1개 공유
 버퍼)            코어 B #(64,4) [class 4~7]       ┘ = 그룹0 8 lane, 그룹1 2 lane (8PE 출력 고정 스케줄)
```

| 항목 | 계약 |
|---|---|
| 신규 파일 | `reference/arch_reference.py`(사이클·포트 모델), `tb/tb_p3_pe_scale.sv`, `synth/synth_ooc.tcl`, `reference/synth_summary.py`, `scripts/run_sim.sh`, `scripts/run_synth.sh` |
| 신규 RTL 모듈 | 없음. 구성은 TB에서 14장 코어 인스턴스 조합으로 만든다 |
| 작업량 | 타일 1개 = 64입력 × 10출력 = **640 MAC** (PE 수와 무관), 784 추론 = 13타일 |
| 데이터 | 18장 학습 MNIST 모델 INT8 양자화본 + 고정 표본 4개 × 13타일 = 52개 타일 작업 |
| x 공급 | 출력 고정 스케줄이라 모든 lane이 같은 x를 쓴다 → 1단어/클록 방송으로 충분(PE8 두 코어 주소 일치 상시 검사) |
| 가중치 공급 | lane마다 bank 1개(1단어/클록) → PE 수 = 가중치 읽기 포트 수 |

사이클 정의: start 샘플 에지 → done 관측 에지 = `groups·(IN + 4) + 2` (그룹마다 CLEAR 1 + RUN IN + DRAIN 2 + CAPT 1, 시작·FINISH 2). 14장 206, 16장 138·38 측정값과 같은 식이다.

## 2. 결과 — RTL 시뮬레이션 측정 = 모델

| PE | 이론 하한(640 MAC) | 그룹 스케줄 발행 | lane 이용률 | **코어 사이클(타일 1개, RTL 측정)** | 784 추론 연산(13타일) | 가중치 읽기 포트 |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 640 | 640 | 100.0% | **700** (70 × 10) | 9100 | 1 |
| 4 | 160 | 192 | 83.3% | **206** | 2678 | 4 |
| 8 | 80 | 128 | 62.5% | **138** (A 138, B 70) | 1794 | 8 |

- **8PE는 4PE의 2배가 아니다:** 206 → 138 (1.49배). 출력 10개를 8 lane에 나누면 그룹 2개(8 + 2)가 되어 두 번째 그룹에서 6 lane이 논다. 그룹당 고정 지연 4클록도 그대로 남는다.
- **1PE 이론 하한 640 대비 700:** 패스마다 그룹 지연 4 + 시작·완료 2가 10번 붙는다. class마다 가중치를 다시 써야 하므로 쓰기 시간도 패스 사이에 끼어든다.
- **가중치 적재는 세 구성 모두 640단어/타일**(쓰기 포트 1개, RTL 계수). 784 추론이면 W 7,840 + x 832단어 = 8,672클록으로 연산(PE4 2,678)보다 크다 → 17장의 타일별 재적재 방식은 **적재 병목**이다. 가중치 상주(BRAM weight-store)가 다음 개선 대상이다.

가중치 읽기 포트 수에 따른 발행 클록(타일 1개, x 방송 1포트, 모델):

| PE \ 포트 | 1 | 2 | 4 | 8 |
|---:|---:|---:|---:|---:|
| 1 | 640 | 640 | 640 | 640 |
| 4 | 640 | 320 | 192 | 192 |
| 8 | 640 | 320 | 192 | 128 |

→ 포트가 4개뿐이면 8PE도 4PE와 같은 192클록. PE 수만 늘리고 BRAM 포트를 늘리지 않으면 효과가 없다.

## 3. Vivado 결과 (OOC, 100 MHz) — `validation/synth_ooc_summary.md`

argmax 수정 후 7개 구성 모두 **OOC 배치·배선 후 WNS 양수**(Vivado 2024.2, xc7a35tcpg236-1, `create_clock -period 10`).

| 구성 | DSP | BRAM Tile | LUT | FF | WNS 배선 후 (ns) | 수정 전 WNS (합성 추정) |
|---|---:|---:|---:|---:|---:|---:|
| PE1 INT8 | 1 | 0.5 | 69 | 123 | +4.560 | +4.919 |
| PE4 INT8 (14장) | 4 | 2 | 290 | 597 | +1.096 | −7.962 |
| PE8 = A + B INT8 | 4 + 4 | 2 + 2 | 285 + 276 | 401 + 302 | +1.488 / +0.901 | −2.710 / +0.503 |
| PE4 INT16 | 4 | 2 | 443 | 779 | +1.144 | −9.441 |
| 17장 Tile INT8 | 4 | 2 | 1496 | 1411 | +0.712 | −9.441 |
| 18장 Tile INT16 | 4 | 2 | 1661 | 1790 | +0.625 | −9.429 |

- DSP는 lane 수만큼 추론(INT8·INT16 모두 lane당 DSP48E1 1개). 가중치 bank는 lane당 RAMB18 1개.
- INT16 PE4는 INT8보다 LUT +53%(443 vs 290), FF +30%. DSP·BRAM 수는 같다(16비트도 DSP 25×18 한 개, bank 192×16이 RAMB18 하나).
- OOC는 최상위 포트를 FPGA 핀에 묶지 않는다. 칩 전체 Top·I/O 제약·비트스트림·실물은 별도(실물은 사용자와 함께).

### 타이밍 결함과 수정

- **발견:** 수정 전 임계 경로는 조합 argmax(`score_q_reg → class_o_reg`) — 10개 점수를 `always @*`에서 차례로 비교하는 9단 직렬 비교(PE4 INT8 37 logic level, 17.9 ns). 17·18장 Tile은 컨트롤러 42비트 argmax가 같은 구조.
- **수정(14장 코어):** CAPT에서 lane 쌍(0·1, 2·3) 승자를 레지스터에 저장, 다음 CLEAR에서 두 승자와 누적 최대값을 비교(2단), 마지막 그룹은 FINISH에서 합침.
- **수정(17장 컨트롤러):** 4단 토너먼트 트리를 두 클록으로 분할 — 마지막 ACK에서 점수 확정(종전 SCORE 작업), SCORE에서 1·2단 저장, FINISH에서 3·4단.
- **불변 확인:** class_o·done 시점·동점 규칙(낮은 번호) 그대로. 14~19장 로그의 PASS 줄·사이클·시뮬레이션 종료 시각이 수정 전과 동일. 이어서 각 비교 단 동점 시험(14장 5건, 17장 4건)을 추가해 동점 변이 10종 모두 검출.

## 4. 실행

```bash
bash part03/ch19/scripts/run_sim.sh                                   # RTL·모델 비교
VIVADO_SETTINGS=<Vivado>/settings64.sh bash part03/ch19/scripts/run_synth.sh   # OOC 합성·배선 요약 (IMPL=0이면 합성만)
```

기대 출력(요약):

```text
PYTHON_ARCH_SELF_TEST_PASS samples=4 tile_runs=52 cycles PE1=700 PE4=206 PE8=138 load_w=640
RTL_SIM_PASS PE_SCALE tile_runs=52 PE1=70x10 PE4=206 PE8=138(A 138, B 70) load_w=640
PYTHON_RTL_COMPARE_PASS tile_runs=52 configs=PE1,PE4,PE8 partials_bit_exact=1 cycles_match_model=1 mnist_samples=4 class_match_ch18_int8=1
SYNTH_OOC_SUMMARY configs=7 wns_negative=0 routed=7 route_wns_negative=0 out=synth_ooc_summary.md
```

## 5. 검증 범위

- 세 구성의 타일 부분합 52 × 10이 Python `dot_signed`와 비트 단위 일치하고, PE4 부분합 13타일 합 + Bias의 Class가 18장 INT8 평가와 일치(표본 4개)
- 구성별 start→done 사이클이 모델과 일치하고 모든 작업에서 일정, 가중치 쓰기 수 일정, PE8 공유 x 포트 주소 충돌 없음, 오류 없음
- 모델 자체 시험: 이론 하한 640/160/80, 14·16장 측정 사이클 재현, 포트 Stall 표
- 변이 시험 4종 검출: 코어 DRAIN 1클록, PE8 코어 B 1클록 늦은 시작(공유 포트 충돌), 모델 그룹 지연 3, PE8 class 매핑 교환
- 회귀: ch13~18 PASS

**미검증:** 칩 전체 Top(I/O 핀 포함) 구현·비트스트림, 공유 x 포트를 포함한 PE8 단일 Top 구현, Basys3 실물(사용자와 함께), 전력.
