# P3-03 · MAC 파이프라인

[Issue #7](https://github.com/Yuul-Jung/amd_soc/issues/7)의 곱 레지스터 → 누산
레지스터 구조를 `mac_pipeline_core`로 구현한다. 기존 01·02장 원본은 유지한다.

## 인터페이스와 연산

| 항목 | 계약 |
|---|---|
| `DATA_WIDTH`, `ACC_WIDTH` | 기본 16/40, 비교 구성 8/32 |
| 지원 조건 | DATA_WIDTH >= 2, ACC_WIDTH >= 2*DATA_WIDTH |
| `a_i`, `b_i` | DATA_WIDTH 폭의 signed 정수 |
| `product_q` | 2*DATA_WIDTH 폭의 전체 signed 곱 레지스터 |
| `product_valid_q` | 해당 곱과 함께 저장한 입력 Valid |
| `acc_o` | ACC_WIDTH 폭의 signed 누산 레지스터 |
| `valid_o` | 이번 에지에서 이전 곱이 누산되었음을 표시 |
| `resetn` | 동기식 Active-Low Reset |
| `clear_i` | 동기식 누산·파이프라인 초기화 |
| `valid_i` | 현재 상승 에지에서 새 입력 수락 |

입력을 상승 에지 k에서 수락하면 k 직후 `product_q`와 `product_valid_q`가
갱신되고, k+1 직후 누산 결과와 `valid_o`가 갱신된다. 비차단 대입으로
누산 단계는 현재 `valid_i`가 아닌 **이전 에지의 `product_valid_q`**를 사용한다.

`!resetn > clear_i > 파이프라인 진행` 순서다. Reset/Clear는 현재 입력을
수락하지 않고, 계류 곱·계류 Valid·누산·출력 Valid를 모두 0으로 초기화한다.
버블(`valid_i=0`)에서는 계류 곱을 정상 누산할 수 있다. 버블은 취소 명령이 아니다.
버블일 때 `product_q`는 값을 유지하지만 `product_valid_q=0`이므로 다시 누산하지 않는다.

곱은 부호 확장 후 누산한다. 01장처럼 상위 초과 비트를 버리는 2의 보수
순환 연산이며 포화·반올림·고정소수점 스케일 변환을 추가하지 않았다.

## 에지별 대조표

아래 값은 `validation/rtl_sim.log`의 첫 지정 시험과 일치한다.
모든 레지스터 값은 해당 상승 에지 **직후** 값이다. `—`는 수락/출력이 없음을 뜻한다.

| 관측 에지 | 입력 수락 에지·입력 | product_q / product_valid_q | 누산 대상 입력 에지 | 출력 에지 | acc_o / valid_o |
|---:|---|---|---:|---:|---|
| 1 | — (Reset) | 0 / 0 | — | — | 0 / 0 |
| 2 | 2: 3×4 | 12 / 1 | — | — | 0 / 0 |
| 3 | 3: 3×(-4) | -12 / 1 | 2 | 3 | 12 / 1 |
| 4 | 4: (-3)×(-4) | 12 / 1 | 3 | 4 | 0 / 1 |
| 5 | — (버블) | 12 / 0 | 4 | 5 | 12 / 1 |
| 6 | — (버블) | 12 / 0 | — | — | 12 / 0 |
| 14 | 14: 7×9 | 63 / 1 | — | — | 0 / 0 |
| 15 | — (Clear+Valid) | 0 / 0 | — (14 취소) | — | 0 / 0 |
| 16·17 | — (버블) | 0 / 0 | — | — | 0 / 0 |
| 18 | 18: (-2)×3 | -6 / 1 | — | — | 0 / 0 |
| 19 | — (버블) | -6 / 0 | 18 | 19 | -6 / 1 |
| 20 | — (버블) | -6 / 0 | — | — | -6 / 0 |
| 21 | 21: 6×7 | 42 / 1 | — | — | -6 / 0 |
| 22 | — (Reset+Clear+Valid) | 0 / 0 | — (21 취소) | — | 0 / 0 |

01장에서는 k 입력의 결과가 k 직후에 나온다. 03장은 이보다 상승 에지
간격 하나만큼 지연된다. 2·3·4에 연속 수락한 입력은 3·4·5에 연속 출력되어,
채워진 파이프라인에서 에지당 입력/출력 한 쌍의 기능상 처리량을 확인할 수 있다.
실제 MHz·WNS·자원·전력 개선은 이번 시뮬레이션으로 판단하지 않는다.

## 파일 및 재현

- `rtl/mac_pipeline_core.v`: 전체 곱·Valid 저장 및 다음 에지 누산.
- `reference/mac_pipeline_reference.py`: `(곱, 수락 에지)` 대기 큐 모델.
- `tb/tb_mac_pipeline_core.sv`: 이전 곱·Valid를 사용하는 SV 모델과 Python 기대값 대조.
- `scripts/run_sim.sh`: 두 설정의 컴파일·RTL 실행·Python trace 비교·에지별 표 출력.
- `validation/`: 실제 로그, 회귀 로그, 소스 해시, 검증 한계.

```bash
bash part03/ch03/scripts/run_sim.sh
bash part03/ch01/scripts/run_sim.sh
bash part03/ch02/scripts/run_sim.sh
```

Python 표준 라이브러리와 Icarus Verilog/vvp를 사용한다. 01장의 `wrap`과
`compare` 함수만 읽기 전용으로 재사용한다. 01장의 같은 에지 정답 함수를
파이프라인 정답으로 사용하지 않는다. Python은 큐에서 **이전 입력 배출 후 현재 입력 삽입**
순서로 동작하며 취소 시 큐를 비운다. SV는 이전 에지 상태를 별도로 저장한다.
모든 사이클에서 누산·출력 Valid 및 내부 곱·계류 Valid를 비교한다.

참고 원형은 `Yuul-Jung/soc`의 기준 커밋
`33e6a7da5fbbf0de7e698a556db42b8eac74abd7`에 있는
`MicroBlaze_V_SoC01_41/code/soc24/npu_mac_lab/rtl/mac_s8_acc32_pipelined.v`다.
정상 원형의 두 단계 제어 구조를 폭 매개변수로 일반화하고 한글 주석을 작성했다.
원본의 Q7 해석은 이 장의 정수 연산 계약에 도입하지 않았다.

검증 결과와 한계는 [검증 기록](../validation/README.md)을 참조한다.
보드/AXI Top을 추가하지 않았으며 합성·타이밍·실물 검증은 후반 일괄 수행 대상이다.
