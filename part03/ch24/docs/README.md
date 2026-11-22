# 제24장 · FPGA 자원·타이밍 분석 (Vivado 실제 보고서)

## 1. 무엇을 측정했나

| 대상 | 방법 | 근거 파일 |
|---|---|---|
| 14장 코어 PE1/4/8, INT8/INT16, 17장 Tile | OOC 합성·배치·배선 @100 MHz | `ch19/validation/synth_ooc_summary.md` |
| 20장 AXI NPU IP | OOC 합성·배치·배선 @100 MHz | `ch20/validation/synth_ooc_summary.md` |
| 21장 MicroBlaze V + NPU SoC | 칩 전체 구현·Bitstream (I/O 포함) | `ch21/validation/soc_summary.md` |
| 주요 4개 구성 Fmax | 합성부터 10/8/7/6 ns로 제약해 OOC 배치·배선 반복 | `validation/timing_sweep.md` (이 장) |

신규 파일: `synth/sweep_cores.tcl`, `synth/sweep_axi.tcl`, `scripts/run_sweep.sh`, `reference/sweep_summary.py`. 19장 `synth_ooc.tcl`에 `clk_period`·`clk_in_synth` 옵션만 추가(기본값은 19·20장 결과 재현).

## 2. 자원 (배치·배선 후)

| 구성 | DSP48E1 | BRAM Tile | LUT | FF |
|---|---:|---:|---:|---:|
| PE1 INT8 코어 | 1 | 0.5 | 69 | 123 |
| PE4 INT8 코어(14장) | 4 | 2 | 290 | 597 |
| PE8 INT8(코어 2개 합) | 8 | 4 | 561 | 703 |
| PE4 INT16 코어 | 4 | 2 | 443 | 779 |
| 17장 Tile INT8 | 4 | 2 | 1,496 | 1,411 |
| 20장 AXI NPU IP | 4 | 2.5 | 2,076 | 1,975 |
| **21장 SoC 전체** | **4** | **18.5 (37%)** | **4,985 (24%)** | **4,692 (11%)** |
| └ SoC 안의 NPU | 4 | 2.5 | 2,109 | 1,975 |

- DSP = lane 수(INT8·INT16 모두 lane당 DSP48E1 1개). 가중치 bank = lane당 RAMB18 1개, x 버퍼 RAMB18 1개.
- Tile 컨트롤러가 코어보다 LUT 5배: 10개 × 41비트 외부 누산·넘침 검출, 42비트 Bias 합·점수, 42비트 argmax 트리.
- Basys3 XC7A35T 예산(DSP 90, BRAM 50 Tile) 대비 NPU는 DSP 4%, BRAM 5%. 가중치 상주 BRAM(784×10 INT8 = 62.7 kbit ≈ 2 RAMB36)도 들어간다.

## 3. 타이밍

### 100 MHz 결함과 수정 (19장 발견 → 14·17장 수정, 커밋 2e45bf1)

| 구성 | 수정 전 WNS(합성 추정) | 수정 후 WNS(배선 후) |
|---|---:|---:|
| PE4 INT8 코어 | −7.962 | +1.096 |
| PE4 INT16 코어 | −9.441 | +1.144 |
| 17장 Tile INT8 | −9.441 | +0.712 |
| 20장 AXI NPU IP | — | +0.223 ~ +0.476 |
| 21장 SoC 전체 (안 A 이전 기록, 현재는 +0.374 · WHS +0.034) | — | **+0.219 (WHS +0.021)** |

원인은 10개 점수를 한 클록에 직렬 비교하던 조합 argmax(9단). 동작·사이클 계약을 바꾸지 않고 레지스터로 나눴다.

### Fmax 스윕 (`validation/timing_sweep.md`)

| 구성 | 통과한 가장 짧은 주기 | WNS | Fmax 추정 |
|---|---:|---:|---:|
| PE4 INT8 코어 | 7.000 ns | +0.155 | 146.1 MHz |
| PE4 INT16 코어 | 8.000 ns | +0.091 | 126.4 MHz |
| 17장 Tile INT8 | 10.000 ns | +0.103 | 101.0 MHz |
| 20장 AXI NPU IP | 10.000 ns | +0.476 | 105.0 MHz |

- **전체 Fmax를 정하는 경로는 17장 컨트롤러 argmax 1·2단**(`score_q → a2s0_q`, 42비트 비교 2단). 코어(146 MHz)보다 훨씬 낮다.
- INT16 코어는 lane 쌍 비교 폭(39비트)이 커져 INT8보다 약 20 MHz 낮다.
- 같은 RTL도 실행마다 배치가 달라 WNS가 0.1~0.6 ns 흔들린다(예: Tile INT8 @10 ns +0.712 / +0.103). 100 MHz 여유는 작다.

### 개선 방향 (미적용)

- 컨트롤러 argmax를 클록당 비교 1단으로 나누면(SCORE·ARG1·ARG2·FINISH) done이 2클록 늦어지는 대신 Tile·AXI IP가 코어 수준(약 130 MHz 이상) 여유를 가질 것으로 보인다. 17·20·23장 측정값 재기록이 필요해 이번에는 적용하지 않았다. 21장 SoC는 100 MHz에서 setup·hold를 충족한다.

## 4. 실행

```bash
VIVADO_SETTINGS=<Vivado>/settings64.sh bash part03/ch24/scripts/run_sweep.sh   # 8회 Vivado, 약 40분
```

기대 출력: `SWEEP_SUMMARY pe4_int8=146.1MHz pe4_int16=126.4MHz tile784_int8=101.0MHz axi_npu_int8=105.0MHz`

**경계:** 모든 수치는 Vivado 2024.2 보고서 기준이다. OOC 수치는 칩 I/O를 포함하지 않으며, 실물 동작 주파수 검증은 아니다(실물은 사용자와 함께).
