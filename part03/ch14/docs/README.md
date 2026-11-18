# 제14장 · 4PE 3그룹(4+4+2) 10분류 코어

## 1. 구조

```text
13장 p3_frame64_buffer ──x[i] (읽기 1클록 지연)──┐
                                                 ▼
가중치 bank0~3 ──w[l]──► npu_dsp_mac_lane × 4 (12장 재사용, DATA 8 / ACC 24)
                                                 │ group 0: class 0~3
                                                 │ group 1: class 4~7
                                                 │ group 2: class 8~9 (lane 2·3 무효: valid 차단)
                                                 ▼
                           score[c] = acc + bias[c] (signed 25비트) → argmax(동점 낮은 번호)
```

| 항목 | 계약 |
|---|---|
| 매핑 | `class = 4*group + lane`, 유효 class 0~9만 점수 저장 |
| 가중치 bank | `bank l` = class l, l+4, l+8. 주소 `group*64 + index` → 매 클록 4개 병렬 읽기 |
| 형식 | x·W signed INT8, Bias signed 24비트, Score signed 25비트 |
| 처리 시간 | start → done **206클록** = 3그룹 × (CLEAR 1 + RUN 64 + DRAIN 2 + CAPT 1) + 2 |
| Busy | 처리 중 가중치·Bias 쓰기와 start는 무시하고 `error_o` 1클록 |
| 오류 | 프레임 없는 start, class ≥ 10 쓰기 → `error_o` |
| Reset | 동기 Active-Low. Bias·점수·상태 초기화, 가중치 bank는 유지 |

- RTL: `rtl/p3_group10_core.v` + 재사용 `ch02/rtl/dsp_multiplier.v`, `mini_npu/rtl/npu_dsp_mac_lane.v`, `ch13/rtl/p3_frame64_buffer.v`
- 기준모델: `reference/group10_reference.py` → `linear_64x10`, `argmax_lowest` (기존 규칙 변경 없음)
- (변경) 19장: 조합 argmax(9단 직렬 비교, 100 MHz 타이밍 실패)를 누적형으로 변경 — CAPT에서 lane 쌍 승자 저장, CLEAR/FINISH에서 2단 비교. class_o·done 시점·동점 규칙 불변(14~19장 로그 동일)
- (변경) 18장: `DATA_W`·`ACC_W`·`BIAS_W`·`SCORE_W` 파라미터 추가. 기본값 8/24/24/25가 이 장의 동작이며 위 기대 출력은 그대로다.
- 10개 점수를 4PE끼리 합산하지 않는다. 그룹이 바뀔 때 입력이 아니라 해당 class 가중치 bank 주소가 바뀐다.

## 2. 실행

```bash
bash part03/ch14/scripts/run_sim.sh
```

기대 출력:

```text
PYTHON_GROUP10_SELF_TEST_PASS cases=41 groups=4+4+2 seed=1414
RTL_SIM_PASS GROUP10 cases=41 start_to_done_cycles=206 errors_checked=4
PYTHON_RTL_COMPARE_PASS cases=41 scores=10 class=1 bit_exact=1
```

## 3. 검증 범위

- class 매핑(one-hot 가중치), 전 점수 음수(무효 차선 오염 검출), 그룹 경계 동점(3·7·8 → 3), class 9 단독 최대
- 누산 극값 ±(128·128·64), Bias 극값 ±2²³, 무작위 30건 — 10개 점수와 Class를 Python과 **비트 단위** 비교
- 프레임 없는 start, 범위 밖 class, Busy 중 쓰기·start 거부(결과 불변), Busy 중 Reset 후 재실행
- done 1클록, load_ready = !busy, 처리 클록 수 일정, x 읽기는 프레임 보관 중에만
- (추가) 19장 argmax 수정 후: 각 비교 단 동점 5건(class 0·1, 2·3, 4·5, 6·7, 8·9 → 낮은 번호) 추가, 동점 변이 5종(lane 쌍 2·그룹·누적·초기화) 검출
- 변이 시험 7종(동점 우선순위, DRAIN 누락, bank 매핑, Bias 색인, class 9 누락, Busy 쓰기 허용, group 2 lane 마스크) 모두 검출

**미검증:** Vivado 합성(DSP·BRAM 실제 추론)·Timing, Basys3 실물, 학습된 실제 MNIST 가중치 정확도.
