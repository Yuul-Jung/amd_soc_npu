# 제18장 · INT8·INT16 양자화·정밀도 비교 (MNIST 784→10)

## 1. 구조

```text
PC  MNIST train 60000 ─► train_mnist_linear.py (PyTorch Float32 784→10, seed 1818) ─► mnist_linear_f32.json
                                                                          │ 같은 가중치
                                       ┌──────────────────────────────────┼────────────────────────────┐
                                       ▼                                  ▼                            ▼
                              Float (pixel/255)              INT8 양자화(Q=127)              INT16 양자화(Q=32767)
                                       │                                  │                            │
PC  MNIST t10k 10000 (같은 전처리) ─► precision_reference.py --eval: Accuracy·혼동행렬·클래스 일치·Logit 오차
                                                                          │ 고정 표본 16개
RTL                                     17장 p3_tile784_10 #(DATA_W=8)   │   #(DATA_W=16)
                                        14장 p3_group10_core #(DATA_W=8) │   #(DATA_W=16, ACC_W=38)
                                        → 타일 부분합·Logit·Class를 Python 정수 모델과 비트 단위 비교
```

| 항목 | 계약 |
|---|---|
| 신규 파일 | `reference/train_mnist_linear.py`(PC 학습), `reference/precision_reference.py`(양자화·평가·RTL 벡터), `scripts/run_sim.sh`, `scripts/run_eval.sh` |
| 재사용 | 17장 Tile Controller·TB·기준모델(`model`, `write_vectors`, `padding`, `compare`), 14장 코어, 13장 8비트 프레임 버퍼, 04장 `bram_sync_buffer`(INT16 x 타일), host_tools `dot_tiled_64`·`argmax_lowest`·`sat_int8` |
| 파라미터 확장 | 14장 코어 `DATA_W/ACC_W/BIAS_W/SCORE_W`, 17장 `DATA_W/CORE_ACC_W/PART_W`, 17장 TB·기준모델 `DATA_W`. **기본값 = 기존 INT8 동작**(ch14~17 로그의 PASS 줄·사이클·종료 시각 동일) |
| 신규 RTL 모듈 | 없음 |

## 2. 양자화 계약 (PC에서 1회, RTL은 정수 누산만)

N = 8 또는 16, Q = 2^(N−1) − 1, 모든 zero-point = 0(대칭).

| 대상 | 정수 변환 | Scale | 반올림 | 포화 |
|---|---|---|---|---|
| 입력 x | `x_q = round_half_away(pixel·Q/255)` (정수 연산) | s_x = 1/Q | 절반은 0에서 먼 쪽 | 0..Q (발생 안 함) |
| 가중치 W | `w_q = sat_N(round_half_away(W/s_w))` | s_w = max\|W\|/Q | 절반은 0에서 먼 쪽 | −Q..Q (최대값이 정확히 ±Q) |
| Bias b | `b_q = sat_40(round_half_away(b/(s_x·s_w)))` | 누산 단위 | 절반은 0에서 먼 쪽 | signed 40 |
| Logit | `z_q = Σ x_q·w_q + b_q` (17장 13타일) | z ≈ z_q·s_x·s_w | 없음 | 없음(ACC 41 / 점수 42, `ovf_o`=0 확인) |

- 출력층 ReLU·16비트 포화 없이 wide signed Logit에서 argmax(동점 낮은 번호). s_x·s_w > 0이므로 순위가 보존된다.
- Python `round()`는 짝수 반올림이므로 사용하지 않는다(기준모델 자체 시험으로 차이 확인). FPGA는 이미 변환된 정수를 읽는다.

## 3. PC 결과 (실제 실행, `validation/precision_report.md`)

| 모델 | 정답/10000 | Accuracy | Float 대비 클래스 일치 | 최대 역양자화 Logit 오차 |
|---|---:|---:|---:|---:|
| Float (float32 가중치) | 9260 | 92.60% | — | — |
| INT8 | 9256 | 92.56% | 9976 (99.76%) | 0.154 |
| INT16 | 9260 | 92.60% | 10000 (100.00%) | 0.00065 |

- PyTorch Float32 시험 정답 9260 = 표준 라이브러리 Float 계산 9260. 재학습 시 가중치 파일 SHA-256 동일(결정적 학습).
- 학습: Adam lr 1e-3, batch 128, 10 epoch 고정(시험셋으로 모델 선택하지 않음). 전처리 `pixel/255`만.
- 혼동행렬 3종과 세 모델 예측이 다른 시험 표본 목록은 보고서에 있다.

## 4. 실행

```bash
bash part03/ch18/scripts/run_sim.sh                       # RTL (데이터셋 불필요)
MNIST_DIR=<MNIST raw 폴더> bash part03/ch18/scripts/run_eval.sh   # PC 전체 평가
python3 part03/ch18/reference/train_mnist_linear.py --mnist-dir <MNIST raw 폴더>  # 선택: 재학습(PyTorch)
```

기대 출력(요약):

```text
== config i16_full data_w=16 acc_w=41 bias_w=40
RTL_SIM_PASS TILE784 cases=26 ... errors_checked=14 data_w=16 part_w=39
PYTHON_RTL_COMPARE_PASS cases=26 tile_partials=3380 scores=10 class=1 overflow=1 bit_exact=1
== config i16_w40 ... overflow_cases=2 ...  → PYTHON_RTL_COMPARE_PASS
== config mnist8  → PYTHON_PRECISION_VECTORS_PASS data_w=8 samples=16 class_differs_from_float=4 / PYTHON_RTL_COMPARE_PASS cases=16
== config mnist16 → PYTHON_PRECISION_VECTORS_PASS data_w=16 samples=16 class_differs_from_float=0 / PYTHON_RTL_COMPARE_PASS cases=16
PC_EVAL_PASS samples=10000 float=9260 int8=9256 int16=9260 torch_f32=9260 agree_int8_float=9976 agree_int16_float=10000
```

## 5. 검증 범위

- **INT16 RTL**(17장 미검증 항목 해소): 17장 전체 시험(무작위·극값·마지막 타일·Bias·오류 14건·Reset·취소)을 DATA_W=16으로 실행, 3,380개 부분합 비트 단위 일치. INT16 극값 784·(−32768)² = 841,813,590,016: 외부 누산 41비트 무넘침, 40비트 넘침 검출·순환값 일치
- **MNIST 실제 모델 RTL**: 고정 표본 16개(앞 8개, INT8≠Float 4개, Float 오답 4개; INT16≠Float 표본은 시험셋에 없음)를 INT8·INT16 RTL로 추론 → 타일 부분합·Logit·Class가 Python과 일치하고, Class가 시험셋 평가 결과와 일치(INT8 경로는 Float와 다른 4건 재현)
- 기준모델 자체 시험: 절반값 ±0.5·±1.5·±2.5 반올림 대칭, Python `round()`와의 차이, 정수 나눗셈 반올림, `sat_signed(·,8)` = host `sat_int8`, INT16 포화 경계, 0/255 입력 경계
- 회귀: ch13~17 PASS, ch14~17 로그는 경고 줄 번호 외 동일
- 변이 시험 6종 검출: 코어 lane DATA_WIDTH 8 고정, bank 8비트, Bias 합 24비트 절단, 코어 누산 24비트(INT16), 마지막 타일 마스크 제거, 기준모델 짝수 반올림. 17장 변이 16종도 파라미터화 후 재검출

**미검증:** Vivado 합성·자원(INT8 vs INT16의 DSP·BRAM·LUT·FF)·Timing — 19장/후반 일괄. Basys3 실물, UART 적재 경로, 784→8→10 MLP의 정밀도 비교(이번 모델은 단층 784→10).

> 데이터 출처: MNIST (Y. LeCun, C. Cortes, C. J. C. Burges). 데이터셋 파일은 커밋하지 않고 `run_eval.sh` 로그에 SHA-256만 기록한다. RTL 표본 16개만 `reference/mnist_rtl_samples.txt`에 포함.
