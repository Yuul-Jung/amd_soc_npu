# 제15장 · 64→10 정수 Dense 분류기

## 1. 재사용 구조 (새 연산 RTL 없음)

| 모듈 | 출처 | 15장 역할 |
|---|---|---|
| `p3_frame64_buffer` | 13장 | 입력 x 64원소 프레임 보관·1클록 지연 읽기 |
| `p3_group10_core #(IN_LEN, OUT_N)` | 14장 (파라미터만 추가) | 4PE 그룹 스케줄·signed 누산·Bias·Argmax |
| `npu_dsp_mac_lane` / `dsp_multiplier` | 12장 / 02장 | DSP 등록 곱 + 누산 |

14장 코어에 `IN_LEN`(1~64), `OUT_N`(1~12) 파라미터만 추가했다. 기본값 64→10은 14장과 동일하며 14장 회귀(206클록, 36건 비트 일치)로 확인했다.

| 형태 | 용도 | 그룹 | start→done |
|---|---|---|---|
| 64→10 | 15장 분류기 | 4+4+2 | 206클록 |
| 64→8 | 16장 1층(은닉) | 4+4 | 138클록 |
| 8→10 | 16장 2층(출력) | 4+4+2 | 38클록 |

처리 클록 = `그룹 수 × (IN_LEN + 4) + 2`.

- 8→10은 13장 64원소 프레임 중 앞 8개만 읽는다(TB가 `read beyond IN_LEN`을 매 클록 검사).
- 점수 = `dot_signed(x, W[c]) + bias[c]` (signed 25비트), Class = `argmax_lowest`. 64→10은 `linear_64x10`과 동일함을 함께 확인.

## 2. 실행

```bash
bash part03/ch15/scripts/run_sim.sh
```

기대 출력(형태별 3회):

```text
RTL_SIM_PASS DENSE 64x10 frames=20 w_writes=5127 b_writes=91 cycles=206
PYTHON_RTL_COMPARE_PASS frames=20 bit_exact=1
RTL_SIM_PASS DENSE 64x8 frames=20 w_writes=4103 b_writes=73 cycles=138
PYTHON_RTL_COMPARE_PASS frames=20 bit_exact=1
RTL_SIM_PASS DENSE 8x10 frames=20 w_writes=647 b_writes=91 cycles=38
PYTHON_RTL_COMPARE_PASS frames=20 bit_exact=1
```

## 3. 검증 범위 (14장에서 시험하지 않은 항목 포함)

- **모델 유지:** 1회 적재 후 4프레임 연속 추론
- **부분 갱신:** 가중치 5개·Bias 1개 변경, 같은 주소 2회 쓰기(마지막 값 유효), Bias 전체만 갱신
- **signed 누산 극값:** W=-128·x=-128/127, 부호 교대 W·x, Bias ±2²³
- 무작위 모델 5개 × 2프레임, 형태별 20프레임
- 변이 시험: 길이 고정(63), 마지막 그룹 고정(2), start 시 Bias 소거, 누산 부호확장 누락 → 모두 검출. `lane_mask <10` 변이는 OUT_N≤10에서 동치라 검출 대상 아님

**미검증:** Vivado 합성·Timing·자원, Basys3 실물, 학습된 MNIST 가중치의 분류 정확도.
