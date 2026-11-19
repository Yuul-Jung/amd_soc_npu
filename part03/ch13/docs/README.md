# 제13장 · 8×8 숫자 입력 프레임과 데이터 계약

## 1. 데이터 계약

| 항목 | 계약 |
|---|---|
| 입력 크기 | 8×8 = **64원소** (MNIST 원본 28×28=784와 구분, 784는 17장) |
| 원소 형식 | signed INT8 (2의 보수, -128..127) |
| 저장 순서 | 행 우선: `addr = row*8 + col` (0행0열=0, 7행7열=63) |
| 픽셀 양자화(호스트) | `sat_int8(round_shift_away(pixel_u8, 1))` → 0..255가 0..127 (255는 포화로 127) |
| 스트림 | `s_data_i/s_valid_i/s_ready_o/s_last_i`, `valid && ready`일 때만 수락 |
| 프레임 판정 | **64번째 바이트에만 last**. 더 짧으면 `err_short_o`, 64번째에 last가 없으면 `err_long_o` 후 다음 last까지 버리고 재동기화 |
| Busy | 유효 프레임은 `frame_valid_o=1`로 `frame_ack_i`까지 유지, 그동안 `s_ready_o=0` |
| 읽기 | `rd_en_i/rd_addr_i` → 다음 클록 `rd_data_o`, `rd_valid_o`(프레임 보관 중에만 1) |
| Reset | 동기 Active-Low. 수신 중·DROP·보관 중 프레임 폐기. 저장 배열 내용은 지우지 않음 |

- RTL: `rtl/p3_frame64_buffer.v` (Top이 아닌 기능 모듈)
- 기준모델: `reference/frame64_reference.py` — `host_tools/p3_integer_reference.py`의 `sat_int8`, `round_shift_away`만 조합
- 0~9 시험 숫자는 **합성 8×8 비트맵**이며 실제 MNIST 다운샘플이 아니다.

## 2. 실행

```bash
bash part03/ch13/scripts/run_sim.sh
```

기대 출력:

```text
PYTHON_FRAME64_SELF_TEST_PASS items=2664 frames=36 short=2 long=3 seed=1313
RTL_SIM_PASS FRAME64 frames=36 short=2 long=3
PYTHON_RTL_COMPARE_PASS frames=36 bit_exact=1
```

## 3. 검증 범위

- 합성 숫자 0~9, 행 우선 순서(값=주소-32), 부호 경계(-128/127/0/-1), 무작위 프레임
- 짧은 프레임(63·1바이트), 긴 프레임(65·70바이트, 64바이트 last 없음) 후 재동기화
- 수신 중 Reset, DROP 중 Reset, 보관(FULL) 중 Reset 시 프레임 미출력
- 무작위 valid 간격, Busy 중 ready=0, stall 중 데이터 유지, 읽기 1클록 지연, 비보관 중 읽기 rd_valid=0
- 변이 시험 5종(길이 경계, Busy 해제, DROP 누락, 쓰기 주소 어긋남, rd_valid 조건) 모두 검출

**미검증:** Vivado 합성(메모리 추론 형태)·Timing, Basys3 실물. 실제 MNIST 데이터셋 전처리 정확도.
