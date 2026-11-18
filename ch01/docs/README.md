# P3-01 · 매개변수형 MAC 기본 연산기

INT16 기본 MAC과 INT8 비교용 독립 RTL이다. 제3부는 최신 사용자 결정에
따라 25장/7단계로 진행하며 01장은 AXI 및 MicroBlaze V 연결을 포함하지 않는다.

## 파일과 실행

| 파일 | 역할 |
|---|---|
| `../rtl/mac_core.v` | signed 곱셈·누산 Core |
| `../tb/tb_mac_core.sv` | 매 사이클 Python 기대값/SV 정수 모델/RTL 비교 |
| `../reference/mac_reference.py` | 독립 정수 모델, 자극 생성, 결과 trace 비교 |
| `../scripts/run_sim.sh` | INT16/40 및 INT8/32 자동 회귀 |
| `../validation/README.md` | 환경·기준 커밋·검증 증거·미검증 범위 |

저장소 루트에서 실행한다. Python 표준 라이브러리와 Icarus Verilog가 필요하다.

```bash
bash part03/ch01/scripts/run_sim.sh
```

스크립트는 실패 시 0이 아닌 종료 코드를 반환한다. 벡터·기대 trace·실제 trace·
시뮬레이터 실행 파일은 실행마다 생성하는 임시 디렉터리에 남긴다.
대형 trace와 Vivado 생성 파일은 소스 저장소에 포함하지 않는다.

## 입출력과 연산 계약

| 항목 | 의미 |
|---|---|
| `DATA_WIDTH` / `ACC_WIDTH` | 기본 16/40, INT8 비교 8/32 |
| 지원 폭 | `DATA_WIDTH >= 2`, `ACC_WIDTH >= 2*DATA_WIDTH` |
| `clk` | 상승 에지 동작 |
| `resetn` | 동기식 Active-Low Reset, 누산값 및 Valid를 0으로 초기화 |
| `clear_i` | 동기식 누산 초기화, Reset 다음 우선순위 |
| `valid_i` | 해당 상승 에지에서 입력 쌍 수락 |
| `a_i`, `b_i` | `DATA_WIDTH` 폭의 signed 2의 보수 정수 |
| `acc_o` | `ACC_WIDTH` 폭의 signed 누산 레지스터 |
| `valid_o` | 같은 상승 에지 직후 새 누산 결과가 유효함을 표시 |

우선순위는 `!resetn > clear_i > valid_i`이다. Reset/Clear와 겹친 입력은
수락하지 않고 `valid_o=0`이다. Valid가 없으면 누산값을 유지하며
`valid_o=0`이 된다. 연속 Valid 입력은 매 상승 에지마다 결과를 갱신한다.
입력과 출력 사이에 추가 곱 레지스터 단계는 없다. 입력은 상승 에지 전에
안정되어야 하고 결과는 그 에지의 레지스터 갱신 후 관측한다.

곱셈 결과 `2*DATA_WIDTH` 비트를 전부 보존하여 부호 확장 후 더한다.
이 장은 정수 연산이며 고정소수점 소수부, 반올림, 포화, 오버플로 플래그는 없다.
범위를 넘는 결과는 `2**ACC_WIDTH` 모듈러 연산으로 순환한다.

| 설정 | 입력 범위 | 누산 범위 |
|---|---|---|
| INT16/40 | -32768 ~ 32767 | -549755813888 ~ 549755813887 |
| INT8/32 | -128 ~ 127 | -2147483648 ~ 2147483647 |

예를 들어 INT16에서 `(-32768)*(-32768)=1073741824`를 512회 더하면
양의 누산 범위를 넘어 최솟값으로 순환한다. INT8에서 `(-128)*(-128)=16384`는
131072회째 같은 경계를 넘는다. 응용에서는 입력 개수와 값에 맞춰 누산 폭을 결정한다.

## 기존 코드와 대조

참고 저장소: [Yuul-Jung/soc](https://github.com/Yuul-Jung/soc),
기준 SHA `33e6a7da5fbbf0de7e698a556db42b8eac74abd7`.
원본 경로는 `MicroBlaze_V_SoC01_41/code/soc24/npu_mac_lab/`이다.

| 원본 | P3-01 적용 |
|---|---|
| `rtl/mac_s8_acc32_basic.v` | signed 전체 곱·부호 확장·동기식 Reset/Clear·Valid 동작을 유지하고 폭/모듈명을 일반화 |
| `rtl/mac_s8_acc32_pipelined.v` | 구조 대조만 수행. 추가 곱 레지스터와 Valid 지연은 01장에 도입하지 않음 |
| `reference/mac_reference_model.py` | 정수 순환 개념 참고. 고정 Q7 가정 대신 독립 폭 매개변수 모델 및 제어/경계 시험 작성 |

원본은 수정하지 않았다. 기존 `CURRICULUM.md`의 P3 가안(AXI 덧셈 시작)보다
사용자의 최신 INT16/INT8 MAC 결정이 우선한다. 필수 공통 문서 네 개와
실제 검색된 `soc`의 `docs/code-development-rules.md`, `docs/chapter-html-format.md`를 확인했다.
이후 `amd_soc`의 정책 커밋 `e2681842c032269ea570b5969ac47840f7b8118f`를
작업 브랜치에 반영했다. 현재 코드 개발 정책은 저장소 루트 `AGENTS.md`와
`rule_md/AGENTS.md` 및 해당 파일이 지정하는 코드·방법론·VS Code 규칙을 따른다.
정책 사본의 정본 기준은 `rule_md/SOURCE.md`의
`d1b8278d41fca8f5e3960736f3ac9d377e462fda`이다.

Vivado 프로젝트 명칭은 `npu_p3_01_mac`, 디바이스는 `xc7a35tcpg236-1`이다.
이번 작업은 소스와 RTL 검증 범위이며 로컬 XPR 및 SW 프로젝트는 생성하지 않았다.
Vivado 합성·타이밍·Basys3 실물 검증은 최신 정책에 따라 추후 일괄 수행한다.
