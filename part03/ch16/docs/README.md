# 제16장 · 64→8→10 정수 MLP

## 1. 구조

```text
13장 p3_frame64_buffer ─x[64]─► 1층 p3_group10_core #(64,8)   (14장 코어 재사용, 138클록)
                                     │ score1[8] (signed 25비트)
                                     ▼
                         p3_relu_requant × 8: sat_int8(round_shift_away(max(0, s), shift))
                                     │ hidden[8] INT8 레지스터 (1클록 지연 읽기)
                                     ▼
                         2층 p3_group10_core #(8,10)   (14장 코어 재사용, 38클록)
                                     │ score2[10], argmax(동점 낮은 번호)
```

| 항목 | 계약 |
|---|---|
| 신규 RTL | `rtl/p3_relu_requant.v`(조합 재양자화), `rtl/p3_mlp_64_8_10.v`(두 계층 순서 제어·은닉 레지스터) |
| 재사용 | 14장 `p3_group10_core`(15장 파라미터), 13장 프레임 버퍼, 12장 MAC lane, 02장 DSP 곱 |
| 쓰기 | `wr_layer_i` 0=1층(class 0~7), 1=2층(class 0~9). MLP 동작 중 두 계층 모두 쓰기 차단 + `error_o` |
| shift | `shift_i`(0~31)를 start 시점에 래치. 동작 중 변경은 결과에 영향 없음 |
| 처리 시간 | start → done **180클록** = 1 + 138 + 1(은닉 저장) + 1(2층 start) + 38 + 1 |
| 출력 | `scores_o`(10×25비트), `class_o`, 진단용 `hidden_o`(8×INT8) |
| 오류 | 프레임 없는 start, 동작 중 start·쓰기, 1층 class ≥ 8, 2층 class ≥ 10 |

- 기준모델: `reference/mlp_reference.py` → `mlp_64_8_10`, `argmax_lowest`. 은닉값은 같은 함수 조합으로 계산해 교차 확인(규칙 변경 없음).
- ReLU 이후 값은 0 이상이므로 RTL 반올림은 `(v + 2^(shift-1)) >> shift`, 상한 127 포화.

## 2. 실행

```bash
bash part03/ch16/scripts/run_sim.sh
```

기대 출력:

```text
PYTHON_MLP_SELF_TEST_PASS ops=4933 frames=27 seed=1616
RTL_SIM_PASS MLP64_8_10 frames=27 start_to_done_cycles=180 errors_checked=5
PYTHON_RTL_COMPARE_PASS frames=27 hidden=8 scores=10 class=1 bit_exact=1
```

## 3. 검증 범위

- shift 0·1·4·8·12·14·16·20·24·31 및 무작위 6~18, 무작위 모델 5개 — 은닉 8·점수 10·Class 비트 단위 비교
- 재양자화 기본 경계: 1층 점수 -1·0·1·254·255·256·257·-2²³ (shift 1·0) → ReLU, 0.5 반올림, 127 포화
- 2층 동점(class 4·9 → 4), 은닉 전부 0·출력 전부 음수
- 2층 동작 중 1층 쓰기 차단(가중치·Bias 화이트박스 확인), shift 래치, 동작 중 start 거부, 프레임 없는 start, 1층 class 8 거부
- 변이 시험 9종(반올림 누락, 포화 경계 128, ReLU 누락, shift 비래치, 1층 가중치·Bias 쓰기 차단 누락, 은닉 주소, 계층 선택 반전) 모두 검출

**18장으로 남김:** INT8/INT16 정밀도 비교, 음수 반올림·포화 하한 등 정밀도 경계 체계 검증.
**미검증:** Vivado 합성·Timing·자원, Basys3 실물, 학습된 MNIST 모델 정확도.
