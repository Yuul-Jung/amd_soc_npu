# 제3부 Basys3 실물 일괄 점검표 (사용자와 함께 진행)

> 이 점검표의 항목은 아직 **실행하지 않았다(NOT_RUN)**. 아래 기대값은 RTL·SoC 시뮬레이션과 Vivado/Vitis 빌드에서 얻은 값이다.
> 외부 회로 연결 없이 Basys3 USB 케이블 하나(J4: JTAG + USB-UART)만 사용한다.

## 0. 준비

| 항목 | 내용 |
|---|---|
| 비트스트림 | `part03/ch21/build/out/basys3_soc11_top.bit` (SHA-256 881216da…cbe0, `ch21/validation/soc_summary.md`) |
| XSA | `part03/ch21/build/out/soc21_npu.xsa` (SHA-256 da4edc61…a1fb) |
| ELF ① | `part03/ch22/build/ws/npu_app/build/npu_app.elf` (SHA-256 8805a761…efb9) |
| ELF ② | `part03/ch23/build/ws/bench_board/build/bench_board.elf` (SHA-256 201d9d84…) |
| 재생성 | `LEVEL=fpga SOC11_DIR=<제1부 11장 폴더> VIVADO_SETTINGS=… VITIS_SETTINGS=… bash part03/ch27/scripts/run_all.sh` |
| 터미널 | USB-UART 115200 bps, 8N1, 흐름 제어 없음 |
| 기존 성공 프로젝트 | 제1부·제2부 프로젝트와 `~/soc/hw/soc11_user_top`은 쓰지 않는다(복제본 빌드만 사용) |

## 1. 점검 항목

| # | 절차 | 기대 결과 (시뮬레이션·빌드 근거) | 판정 |
|---|---|---|---|
| B1 | Vivado Hardware Manager로 비트스트림 다운로드 | DONE LED 점등, 오류 없음 | |
| B2 | Vitis에서 `npu_app.elf` 실행(같은 XSA 플랫폼) | `P3 NPU driver test base=0x44a00000` | |
| B3 | 이어지는 UART 4줄 | `SAMPLE 0 ... npu_class=7 cpu_class=7 expect=7 scores_match=1 rc=0`<br>`SAMPLE 1 ... npu_class=2 ...`<br>`SAMPLE 2 index=92 label=9 npu_class=4 ...`<br>`SAMPLE 3 index=1640 label=9 npu_class=4 ...` (22장 협동 시뮬레이션과 같은 줄) | |
| B4 | 마지막 줄 | `NPU_APP_DONE samples=4 failures=0` | |
| B5 | `bench_board.elf` 실행 | `BENCH cpu_cycles=1816547 npu_bias_cycles=3076 npu_cycles=1080161 cpu_class=7 npu_class=7 match=1 rc=0` 부근(23장 SoC xsim 값). 차이가 있으면 원인 기록 | |
| B6 | 같은 ELF 3회 반복 실행 | 사이클 값이 매번 같거나 차이를 기록(캐시 없음·같은 클록이면 같아야 함) | |
| B7 | 실행 중 btnC(Reset) 누른 뒤 다시 실행 | 처음부터 같은 출력 | |
| B8 | (선택) Vivado Hardware Manager에서 전력 확인은 Basys3에 측정 회로가 없어 **하지 않는다** | 25장 값은 Vivado 추정치로만 남긴다 | — |

## 1-28. 28장 숫자 인식 시스템 (같은 USB 케이블, 비트스트림이 다르다)

준비: `part03/ch28/build/out/basys3_soc28_top.bit`(SHA-256 0bce5489…772c), `soc28_digit.xsa`, ELF `part03/ch28/build/ws/digit_app/build/digit_app.elf`(SHA-256 9179c509c9e7dbaa). 호스트 도구가 시리얼 포트를 쓰므로 Vitis 터미널은 닫는다.

| # | 절차 | 기대 결과 (협동 시뮬레이션·SoC xsim 근거) | 판정 |
|---|---|---|---|
| B9 | 28장 비트스트림 다운로드, `digit_app.elf` 실행 | FND `F16C`(모델 ID 상위), LED 모두 꺼짐 | |
| B10 | `python3 part03/ch28/host/p3_digit_host.py --port <포트> --error-suite --csv b28.csv --log b28_uart.log` | `MODEL_ID host=f16c4f12 device=f16c4f12`, 22장 `scores_match=1 display_ok=1`, `error_suite=11/11`, `DIGIT_HOST_PASS` (`ch28/validation/rtl_cosim.csv`와 같은 class) | |
| B11 | 마지막 정상 결과 뒤 FND·LED를 눈으로 확인 | FND `07 _7`(img 7, Class 7), LED7·LED15 켜짐. 오류 시험 중에는 `E`+코드·LED14 | |
| B12 | (선택) `--mnist-dir <MNIST raw> --limit 200` | 장치 class = 골든 class 200/200, 정확도는 골든·장치를 따로 기록 | |
| B13 | (선택) 직접 그린 28×28 PNG `--images a.png [--invert]` | 응답·표시가 오는지 확인(정확도 주장은 하지 않음) | |

## 1-29. 29장 센서 감시 (28장 비트스트림 그대로, ELF만 다르다)

준비: 28장 `basys3_soc28_top.bit`, ELF `part03/ch29/build/ws/sensor_app/build/sensor_app.elf`(`ch29/validation/build_sw.log`의 SHA-256). 센서는 연결하지 않는다(가상 센서 값을 UART로 보냄).

| # | 절차 | 기대 결과 (협동 시뮬레이션 근거) | 판정 |
|---|---|---|---|
| B14 | 28장 비트스트림 다운로드, `sensor_app.elf` 실행 | FND `3 _00`(UNKNOWN), LED3·LED15 켜짐 | |
| B15 | `python3 part03/ch29/host/p3_sensor_host.py --port <포트> --limit 200 --csv b29.csv --log b29_uart.log`, 안내가 나오면 btnC | `BOOT PASS`, 모든 STEP PASS, `SENSOR_HOST_PASS` (`ch29/validation/rtl_cosim.csv`와 같은 판정) | |
| B16 | 실행 중 FND·LED를 눈으로 확인 | FAULT 래치 때 자리 3의 점과 LED13, ACK 뒤 점이 꺼지고 3회 정상 뒤 `0` | |
| B17 | 호스트를 멈추고 링크 감시 시간을 스톱워치로 잰다 | `STATE src=LINK_TIMEOUT`이 주기적으로 나온다. 실측 주기(초)를 기록(폴링 10,000,000회) | |

## 2. 기록할 것

- 각 항목의 UART 원문(사진 또는 터미널 로그), Vivado·Vitis 버전, 보드 리비전.
- FAIL이면 그 항목에서 멈추고 현상을 기록한다(추가 수정은 원인 확인 뒤 별도 커밋).

## 3. 이번 점검 범위 밖

- 29장 실제 센서(DS18B20·XADC·HC-SR04) 연결, 30·31장 모터·보안 UART 실물 검증.
- 클록을 100 MHz 위로 올리는 시험(24장 Fmax는 OOC 추정).
