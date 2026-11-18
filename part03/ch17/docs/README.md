# 제17장 · 784입력 13타일 분할 누산 (외부 부분합 누산)

## 1. 구조

```text
타일 t (0..12): W[c][64t .. 64t+len-1] 재적재 + x 64바이트 프레임(마지막 타일은 16 유효 + 48 패딩)
                                   │
13장 p3_frame64_buffer ─x─► [마지막 타일 주소 16~63 → 0] ─► 14장 p3_group10_core (변경 없음, 4+4+2)
                                                              │ part[t][c] (signed 25비트, 코어 Bias = 0)
                                                              ▼
                       acc[c] += part[t][c]  (signed ACC_W, 13타일 동안 유지, overflow 검출)
                                                              │ 13타일 완료 후 1회
                                                              ▼
                       score[c] = acc[c] + bias[c] (signed SCORE_W) → argmax(동점 낮은 번호)
```

| 항목 | 계약 |
|---|---|
| 신규 RTL | `rtl/p3_tile784_10.v` (Tile Controller + 클래스별 외부 누산기 + 외부 Bias) |
| 재사용 | 14장 `p3_group10_core` #(64,10) 그대로, 13장 프레임 버퍼, 12장 MAC lane, 02장 DSP 곱 |
| 타일 | 784 = 64×12 + 16 → 13타일. `tile_go_i`·`tile_id_i` 0..12 순서대로 한 번씩 |
| 가중치 | 타일마다 `W[c][64t+i]`를 코어 bank 주소 `i`에 재적재. 마지막 타일은 16주소만 써도 됨 |
| 마지막 타일 | 코어는 IN_LEN=64로 64클록을 돌지만 주소 16~63의 x를 0으로 가려 패딩·이전 타일 가중치를 누산하지 않음 |
| Bias | 14장 코어는 점수에 내부 Bias를 **자동으로 더함** → 코어 `b_wr_en_i`를 0으로 고정해 Reset 값 0 유지(코어 무변경). 실제 Bias는 외부 레지스터, 13타일 후 클래스별 **1회** |
| 폭(기본) | `ACC_W=41`, `BIAS_W=40`, `SCORE_W=42` (아래 폭 산정). `SCORE_W ≥ max(ACC_W,BIAS_W)+1` elaboration 검사 |
| overflow | 외부 누산 합이 ACC_W를 넘으면 `ovf_o` 유지(추론 시작 시 Clear), 값은 2의 보수 순환 |
| 순서 | 다음 타일 W 쓰기는 LOAD에서만, 다음 프레임은 결과 수락(`tile_done_o` + `frame_ack_o`) 뒤 버퍼가 비워져야 수신 |
| 처리 시간 | `tile_go` 수락 → `tile_done` **207클록**(코어 206 + start 레지스터 1). 이후 ACK 1클록 뒤 LOAD |
| Reset | 동기 Active-Low. 상태·외부 누산·외부 Bias·점수 초기화. 코어 가중치 bank는 유지(14장 계약) |

### 상태·명령

| 상태 | 허용 | 그 밖의 명령 |
|---|---|---|
| IDLE | `start_i`, W 쓰기, **Bias 쓰기** | `tile_go`·`abort` → `ERR_STATE` |
| LOAD | W 쓰기, `tile_go_i`, `abort_i` | Bias 쓰기 → `ERR_WRITE`, `start` → `ERR_STATE` |
| RUN·ACK·SCORE·FINISH | 없음 | 모든 쓰기 → `ERR_WRITE`, 명령 → `ERR_STATE` |

`err_code_o`: 1 `ERR_STATE`, 2 `ERR_TILE_DUP`(이미 처리한 번호), 3 `ERR_TILE_SKIP`(앞선 번호·13 이상), 4 `ERR_NO_FRAME`, 5 `ERR_WRITE`(허용 외 상태·class ≥ 10), 6 `ERR_CORE`(코어 오류 진단용, 정상 동작에서 발생하지 않음). 오류 명령은 무시하고 `error_o` 1클록.

## 2. 폭 산정

| 데이터 | 타일 부분합(64항) | 784항 누산 | + Bias |
|---|---|---|---|
| **현재 14장 코어 INT8×INT8** | max 1,048,576 → signed **22** (코어 25비트에 들어감) | max 12,845,056 → signed **25** | + Bias24 → signed **26** |
| **INT16×INT16 계약** | 2³⁶ → signed **38** | max 841,813,590,016 → signed **41** (signed40 한계 549,755,813,887 초과) | + Bias40 → 1,391,569,403,903 → signed **42** |

- 기본 폭 41/40/42는 INT16 계약을 담도록 잡았다. 18장 정밀도 비교에서 같은 외부 누산 구조를 재사용할 수 있다.
- **주의:** 14장 코어의 x·W 포트는 INT8이다. INT16 최악값은 Python 폭 산정(`width_plan`)으로만 확인했고 RTL로 실행하지 않았다.
- RTL 폭 시험: `ACC_W=25`(INT8 최소 안전 폭)은 극값에서도 overflow 없음, `ACC_W=24`는 극값 2건에서 `ovf_o=1`과 Python 순환값이 비트 단위로 일치.

## 3. 실행

```bash
bash part03/ch17/scripts/run_sim.sh
```

기대 출력(요약):

```text
== config full acc_w=41 bias_w=40
RTL_SIM_PASS TILE784 cases=22 tiles=13 tile_go_to_accept_cycles=207 acc_w=41 bias_w=40 score_w=42 errors_checked=14
PYTHON_RTL_COMPARE_PASS cases=22 tile_partials=2860 scores=10 class=1 overflow=1 bit_exact=1
== config w25 acc_w=25 bias_w=24
PYTHON_RTL_COMPARE_PASS cases=4 tile_partials=520 scores=10 class=1 overflow=1 bit_exact=1
== config w24 acc_w=24 bias_w=24
PYTHON_TILE784_SELF_TEST_PASS suite=width ... overflow_cases=2 ...
PYTHON_RTL_COMPARE_PASS cases=4 tile_partials=520 scores=10 class=1 overflow=1 bit_exact=1
```

## 4. 검증 범위

- 기준모델 `reference/tile784_reference.py`: 타일 부분합 `dot_signed`, 784 전체 `dot_tiled_64` = `dot_signed` 교차 확인, `argmax_lowest`(host_tools 함수 재사용, 신규 내적 함수 없음)
- 타일별 부분합 13×10과 최종 점수 10·Class·overflow를 RTL과 **비트 단위** 비교
- 시험 벡터: 무작위 15건, 누산 극값(±) + Bias 극값 ±2³⁹, 마지막 타일만 유효 데이터, 타일 위치 판별(class c ↔ 타일 12−c), 전 점수 음수·class 3·7 동점, x=0(점수 = Bias), 작은 Bias
- 모든 추론에서 마지막 타일 x 패딩 48개는 0이 아닌 값, 가중치 48주소는 타일 11 값이 남은 상태
- 오류·순서: IDLE의 tile_go/abort, 타일 중복(0)·누락(2)·범위 밖(13), 프레임 없는 tile_go, LOAD 중 Bias 쓰기·class 10·start, RUN 중 W(class 9·주소 63)/Bias 쓰기·start·tile_go·abort — 14건 모두 코드까지 확인, 결과 불변
- Reset: 코어 RUN 중(타일 5)·LOAD 중(타일 8) Reset 후 처음부터 재실행 결과 일치. LOAD 중 취소(타일 7) 후 프레임 해제·재실행 일치
- 상시 화이트박스: 코어 Bias 10개 항상 0, 코어 계산 중 가중치 쓰기·다음 프레임 수신 없음, 프레임 해제는 결과 수락 클록 또는 취소만, done·tile_done 1클록, 타일 처리 클록 수 일정
- 변이 시험 16종 모두 검출: 마스크 제거·경계 off-by-one, 코어 Bias 포트 연결(중복), Bias 미적용, 타일마다 Bias, start 시 누산 미Clear, 부분합 0 확장, 타일 중복·누락·프레임 검사 제거, RUN 중 W 쓰기·상시 Bias 쓰기 허용, overflow 미검출, 마지막 타일 번호 11, 조기 frame_ack, 동점 높은 번호

**미검증:** Vivado 합성(DSP·BRAM 추론, 10×42비트 가산기 타이밍)·자원, Basys3 실물, UART 경로 연결, 학습된 실제 MNIST 모델 정확도, INT16 데이터 경로의 RTL 실행.
