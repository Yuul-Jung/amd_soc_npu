# P3-02 · DSP48E1 곱셈 RTL 후보

[Issue #5](https://github.com/Yuul-Jung/amd_soc/issues/5)에 따라 signed 곱의
폭과 DSP48E1 연산 범위를 확인한다. 기존 P3-01 MAC을 복제하지 않고,
입력 폭이 서로 다른 독립 곱셈기 `dsp_multiplier`를 작성했다.
누산은 TB에서 기존 `ch01/rtl/mac_core.v`를 그대로 인스턴스화하여 대조한다.
AXI·MicroBlaze V·보드 핀 연결은 포함하지 않는다.

## 연산 폭과 DSP48E1 대응

![INT16 곱·누산과 DSP48E1의 개념적 폭 대응](dsp_width_mapping.svg)

DSP48E1은 25×18 signed 곱셈과 48비트 누산/ALU 경로를 제공한다.
이는 RTL을 배치한 결과가 아니라 하드웨어의 연산 가능 범위이다.
근거: [AMD UG479, 7 Series DSP48E1 Slice User Guide](https://docs.amd.com/api/khub/documents/gu4oRPFEh_Pm2uaAlfY6Kg/content),
Chapter 1, Figure 1-1 및 Chapter 2.

| 논리 연산 | 폭 대응 |
|---|---|
| INT16 입력 `a_i`, `b_i` | signed 16비트 각각을 `a_dsp_w` 25비트, `b_dsp_w` 18비트로 부호 확장 |
| `product_full_w` | 25×18의 전체 signed 결과 43비트 |
| INT16 `product_o` | 원래 두 입력 폭의 합인 32비트. 상위 11비트는 부호 확장이므로 유효 정보 손실 없음 |
| P3-01 `acc_o` | 32비트 곱을 40비트로 부호 확장하여 순환 누산 |
| DSP48E1의 48비트 연산 경로 | 40비트 누산 표현을 담을 수 있지만 P3-01의 40비트 순환 정책과 하드웨어의 48비트 순환은 같지 않음 |
| INT8 비교 | 8×8 → 전체 결과 16비트 → P3-01 32비트 순환 누산 |
| native 입력 경계 시험 | 25×18 → 43비트 결과 전체 보존 |

DSP48E1 primitive의 A 포트 전체 폭은 30비트이며 위 25비트는 **곱셈에
사용되는 입력 경로**의 폭이다. 이 RTL은 primitive를 직접 인스턴스화하지 않는다.
Pre-adder, cascade, OPMODE 및 내부 파이프라인 레지스터는 이번 모델의 대상이 아니다.

INT16 min×min = `1073741824`, min×max = `-1073709056`이며 둘 다 32비트에
들어간다. 누산 범위를 넘을 때 포화·반올림 없이 40비트로 순환하는 정의는
01장과 동일하다. `use_dsp="yes"`는 합성 의도만 표시한다.

## RTL 인터페이스와 타이밍

| 포트/매개변수 | 계약 |
|---|---|
| `A_WIDTH`, `B_WIDTH` | 기본 16/16; 지원 범위 A=2~25, B=2~18 |
| `a_i`, `b_i` | 각 매개변수 폭의 signed 입력 |
| `product_o` | signed `A_WIDTH+B_WIDTH`비트 레지스터 |
| `clk` | 상승 에지에서 입력을 수락하고 결과를 갱신 |
| `resetn` | 동기식 Active-Low Reset; 곱과 Valid를 0으로 초기화 |
| `clear_i` | 동기 초기화; Reset 다음 우선순위 |
| `valid_i`, `valid_o` | 수락한 상승 에지 직후 새 곱과 Valid가 함께 출력 |

`!resetn > clear_i > valid_i` 순서이다. Valid가 없으면 곱은 유지하고
`valid_o=0`이다. Reset/Clear와 겹친 입력은 버린다. 추가 입력 레지스터나
대기 단계 없이 매 상승 에지마다 입력 한 쌍을 처리하는 기능 모델이다.
이 기술은 달성 가능한 물리 클록 주파수를 의미하지 않는다.

TB는 곱셈기와 기존 MAC에 같은 원본 입력을 **병렬로** 구동한다.
`product_o`를 MAC의 곱 입력으로 재연결하는 직렬 파이프라인은 아니다.
Python과 SV 정수 모델이 곱과 누산을 각각 검사하므로 곱의 부호 확장과
MAC 결과 정의를 동시에 대조한다.

native25×18 시험에서 MAC의 대칭 입력 폭은 25, 누산 폭은 56이다.
이는 기존 MAC의 `ACC_WIDTH>=2*DATA_WIDTH` 조건을 지키기 위한 **TB 비교 설정**이며,
DSP48E1에 56비트 누산기가 있다는 의미가 아니다. 이 실습은 native 구성에서도
곱셈의 기능 정합성만 확인한다.

## 재현

저장소 루트에서 실행한다. Python 표준 라이브러리, Icarus Verilog, vvp만 사용한다.

```bash
bash part03/ch02/scripts/run_sim.sh
bash part03/ch01/scripts/run_sim.sh
```

자동 실행 설정: 16/16/40, 8/8/32, 25/18/56 (A/B/ACC).
Python은 01장의 `step`, `stimulus`, `compare`, `self_test`를 읽기 전용으로 재사용한다.
시뮬레이터 실행 파일과 벡터·전체 trace는 임시 디렉터리에 생성한다.
실행 스크립트는 실패 시 0이 아닌 종료 코드를 반환한다.

소스·로그 목록과 실제 판정은 [검증 기록](../validation/README.md)을 참조한다.

## Basys3 계획 예산

DSP48E1 **90개**, BRAM **1,800 Kbit**를 향후 자원 예산 상한으로 사용한다.
근거: [Digilent Basys 3 제품 설명](https://digilent.com/shop/basys-3-artix-7-fpga-trainer-board-recommended-for-introductory-users/).
현재 코드의 실제 DSP/LUT/FF/BRAM 사용량은 측정하지 않았다.
INT8이 INT16보다 DSP를 적게 쓴다거나 자동으로 여러 곱을 한 DSP에 패킹한다는
가정은 하지 않는다. 합성·타이밍·Basys3 검증은 추후 일괄 수행한다.
