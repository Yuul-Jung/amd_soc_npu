# 29장 센서 융합 기반 상태 감시 (종합 2)

가상 센서 창(온도·진동·거리) → UART 프레임 → MicroBlaze V → **규칙 검사(guard) 먼저** → 특징 6개 → 20장 AXI NPU → 3상태 후보 → 경보 정책 → UART 기록 + LED + FND.

> 교육용 합성 데이터로 만든 분류다. 산업 안전 성능·규격 적합성·현장 실증이 아니다.
> LED15(경보)는 표시·기록용이며 위험 장치의 정지·인터록에 연결하지 않는다. 비상정지는 NPU와 독립된 로직이 맡는다(30장).

## 1. 결정 사항

| 항목 | 결정 |
|---|---|
| 하드웨어 | **28장 Bitstream·XSA 그대로**(MicroBlaze V + 20장 NPU + AXI GPIO 0 LED + AXI GPIO 1 FND). 29장은 ELF만 새로 만든다 |
| 센서(제2부 IP 기준) | 온도 DS18B20(int16, 1/16 °C), 진동 XADC(12비트 코드), 거리 HC-SR04(cm). 창 8표본(100 ms 간격) + 센서별 age_ms |
| 입력 경로 | 이 장은 **PC가 만든 가상 센서 값**을 UART로 보낸다. 실제 센서를 Pmod에 연결하는 것은 3.3 V 변환·전원 검토 뒤 사용자와 함께 한다(HC-SR04 Echo 5 V) |
| 규칙 먼저 | 센서별 결측·지연(> 500 ms) → UNKNOWN, 범위 밖·진동 고착 → FAULT. 하나라도 걸리면 **NPU를 실행하지 않는다** |
| 특징 | 센서마다 따로 정한 심각도 눈금 0..127(0 = 정상 상한, 약 64 = WARNING/FAULT 경계, 127 = 명백한 FAULT). 단위를 한 입력에 섞지 않는다 |
| NPU 연결 | 20장 IP는 784 입력·10 class 고정 → x[0..5] = 특징, 나머지 0. w 행 3..9 = 0, Bias[3..9] = -2^38(선택 불가). 하드웨어 변경 없음 |
| 모델 | PyTorch float 선형 6→3(`train_sensor_model.py`) → 18장 `quantize_model(…, 8)`. `MODEL_ID = crc32(w[10][784] ‖ b[10]) = 18496ca4` |
| 경보 정책 | 부팅·Reset = UNKNOWN. 상향 즉시, 하향은 연속 3회 뒤(그 3개 중 가장 심각한 상태로), FAULT는 ACK 전까지 래치. 같은 정책을 Python·C·RTL로 구현해 서로 대조 |
| 링크 | 프레임 대기 시간 초과, 연속 프로토콜 오류 3회, NPU 오류, NPU≠CPU → 후보 UNKNOWN(이유 비트 8) |

## 2. 센서·판정 규칙

| 센서 | 단위·형식 | 결측(→ UNKNOWN) | 유효 범위(밖 → FAULT) | 특징 |
|---|---|---|---|---|
| 온도 | int16, 1/16 °C | 0x7FFF | -20.0..100.0 °C | f0 최고 온도 q(max t − 720, 800), f1 창 안 상승 q(t7 − t0 − 16, 160) |
| 진동 | u16, XADC 12비트 | 0xFFFF | 0..4095, 창 전체 ≤ 15 또는 ≥ 4080이면 고착 | f2 p-p q(max − min − 400, 2200), f3 MAD q(Σ\|v − v̄\|//8 − 120, 760) |
| 거리 | u16, cm | 0xFFFF(Echo 시간 초과) | 2..400 cm | f4 근접 q(125 − min d, 160), f5 접근 q(d0 − d7 − 10, 120) |

`q(n, d) = min(127, max(0, n)·127 // d)`. 지연: 센서별 age_ms > 500 → 그 센서 UNKNOWN. FAULT 비트가 하나라도 있으면 후보 FAULT(가장 보수적).

## 3. UART 규약 (115200 8N1, 28장과 같은 프레임 형식)

`'P' '3' CMD PAYLOAD CRC16`(CCITT-FALSE, 상위 바이트 먼저).

| CMD | PAYLOAD | 응답 |
|---|---|---|
| `I` | 없음 | `P3_SENSOR READY model=18496ca4 model_ok=1 feat=6 classes=3 junk=0` |
| `S` | seq u16 ‖ model_id u32 ‖ age_t·age_v·age_d u16 ‖ 8 × (t i16, v u16, d u16), 60바이트 | `STATE src=FRAME seq guard fmask umask feat npu cpu match scores cand state latch cnt junk` + `DISP` |
| `A` | 없음 | `ACK ok state latch` + `DISP` (래치가 없으면 ok=0) |
| (없음) | 링크 감시 시간 동안 프레임 없음 | `STATE src=LINK_TIMEOUT … cand=3` + `DISP` |
| 오류 | — | `ERROR seq code name detail junk bad` (+ 3회 연속이면 `STATE src=LINK_BAD`) + `DISP` |

오류 코드: 1 CRC, 2 TIMEOUT(프레임 도중), 3 CMD, 4 MODEL, 6 NPU, 7 MISMATCH. 상태 코드: 0 NORMAL, 1 WARNING, 2 FAULT, 3 UNKNOWN.

## 4. 표시

| 위치 | 의미 |
|---|---|
| FND 자리 3 | 상태 코드 0..3, **점 = FAULT 래치** |
| FND 자리 2 | 이유 비트(1 온도, 2 진동, 4 거리, 8 링크·NPU). 오류·ACK·부팅 때는 꺼짐 |
| FND 자리 1·0 | seq 하위 바이트, 오류면 `E`+코드 |
| LED0..3 | 상태 one-hot (NORMAL·WARNING·FAULT·UNKNOWN) |
| LED13 / LED14 / LED15 | 래치 / 프로토콜 오류 / 경보(상태 ≠ NORMAL, 표시 전용) |

부팅 직후: FND `3 _00`, LED3 + LED15 (UNKNOWN 경보).

## 5. 파일

| 파일 | 내용 |
|---|---|
| `reference/sensor_reference.py` | 규칙·특징·합성 데이터·양자화·골든·정책·표시·프레임·펌웨어 기대 응답 모델(정본) |
| `reference/train_sensor_model.py`·`sensor_model_f32.json` | float 학습(PyTorch, 고정 seed)과 결과 |
| `sw/sensor_app.c`·`sensor_app.h`·`sensor_io.h`·`sensor_io_xil.c`·`main.c` | MicroBlaze V 펌웨어(22장 드라이버 재사용) |
| `host/p3_sensor_host.py`·`sensor_io_host.c`·`sensor_cosim_main.c` | PC 호스트(보드 `--port`·협동 시뮬레이션 `--cosim`), PC 빌드 |
| `rtl/p3_alarm_policy.v`·`tb/tb_p3_alarm_policy.sv` | 경보 정책 RTL과 벡터 시험 |
| `synth/synth_configs.tcl` | 19장 OOC 스크립트 구성 |
| `scripts/run_sim.sh`·`run_synth.sh`·`build_sw.sh` | PC 검증, 정책 RTL OOC, ELF 빌드 |

## 6. 실행

```bash
bash part03/ch29/scripts/run_sim.sh                                     # PC 검증(수 분)
VIVADO_SETTINGS=… bash part03/ch29/scripts/run_synth.sh                  # 정책 RTL OOC
VITIS_SETTINGS=… bash part03/ch29/scripts/build_sw.sh                    # 28장 XSA로 ELF
# 보드(사용자와 함께): 28장 비트스트림 + 29장 sensor_app.elf 적재 뒤, 실행 중 btnC(Reset)를 누르라는 안내에 따른다
python3 part03/ch29/host/p3_sensor_host.py --port /dev/ttyUSB1 --limit 200 --csv b29.csv --log b29_uart.log
```

## 7. 결과 (실제 실행)

> 아래는 1차 실행(2026-11-18) 결과다. 호스트 표본 선택을 장치 연결 전으로 옮긴 뒤 전체 회귀를 다시 돌리는 중이며,
> 끝나면 `validation/rtl_sim.log`와 이 표를 갱신한다(1차에서 호스트 계산 지연 때문에 생긴 링크 감시 응답 14회는 호스트가 모델에 반영해 판정함).

| 근거 | 결과 |
|---|---|
| 기준모델 | `SENSOR_REFERENCE_SELFTEST_PASS model_id=18496ca4 frame_bytes=65` (가이드 예제 순서: 결측 → UNKNOWN, 범위 밖 → FAULT) |
| 합성 데이터 정확도 | 시험셋 1500창: float 95.67%, INT8 95.67%(float와 1500/1500 같은 판정). 혼동행렬(라벨→예측) NORMAL [500,0,0], WARNING [27,444,29], FAULT [0,9,491] — FAULT를 NORMAL로 놓친 창 0 |
| 경보 정책 RTL | `RTL_SIM_PASS ALARM_POLICY cycles=4070` (지정 31단계 + 무작위 4000클록 = Python), RTL 변이 4/4 검출(Reset 상태, 래치, 후보·ACK 동시, 하향 최대값) |
| 정책 RTL OOC 배선 | LUT 16, FF 8, WNS +6.711 ns @100 MHz (`validation/synth_ooc_summary.md`) |
| 종단간 협동 시뮬레이션 | 109/109 검사 PASS: 부팅, 식별, 정책 시나리오(전이·래치·ACK·센서 고장 주입 7종), 시험셋 60창(골든 57/60, 장치 57/60), 오류 시험 9종 (`validation/rtl_cosim.csv`) |
| 펌웨어 변이 12종 | 부팅 상태, 즉시 하향, 래치 제거, ACK 무조건, 하향 최소값, 결측·지연·고착 검사 제거, guard보다 NPU 먼저, 링크 감시 제거, 연속 오류 무시, 특징 눈금 → **12/12 검출** |
| Vitis ELF | 28장 XSA(2bffbd6f…) 그대로, `sensor_app.elf` 36,008 B, SHA-256 399faf9dd19296cc, 우리 소스 경고 0 (`validation/build_sw.log`) |
| **Basys3 실물** | **NOT_RUN** — `ch27/docs/BOARD_CHECKLIST.md` B14~B17, 사용자와 함께 |
| 실제 센서 연결 | **NOT_RUN** — 레벨 변환·전원 검토 뒤 사용자와 함께 |

## 8. 알려진 한계

- 데이터는 합성 데이터(교육용 가정)이고 라벨도 생성 규칙에서 나왔다. 실제 설비 라벨 데이터가 없으므로 정확도는 이 생성기에 대한 값일 뿐이다.
- 선형 6→3 모델은 "센서 하나라도 심하면 FAULT"를 근사한다. WARNING 두 개가 겹친 창을 FAULT로, 약한 WARNING을 NORMAL로 판정하는 오류가 남는다(혼동행렬 참조). 규칙 검사와 래치는 모델 오류를 보완하지 않는다.
- 경보 정책 RTL은 단독 검증·OOC 배선까지 했다. 28장 SoC에는 넣지 않았다(이 장의 정책은 펌웨어가 실행). 실제 센서 IP와 직접 연결하는 하드웨어 경로는 30장 독립 보호 로직에서 다룬다.
- 시간 제한은 보드에서 폴링 횟수다(바이트 간격 3,000,000회, 링크 감시 10,000,000회). 실제 시간은 보드에서 측정해 기록한다. PC 빌드는 300 ms / 1500 ms.
