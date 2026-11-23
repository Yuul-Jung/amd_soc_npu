# 제3부 Basys3 실물 일괄 점검표 (사용자와 함께 진행)

> 이 점검표의 항목은 아직 **실행하지 않았다(NOT_RUN)**. 아래 기대값은 RTL·SoC 시뮬레이션과 Vivado/Vitis 빌드에서 얻은 값이다.
> (변경 2026-11-22) Basys3 USB 케이블 하나(J4: JTAG + USB-UART)로 진행한다. 예외는 30장이다: B19부터 JB4↔JB6(3.3 V) 점퍼 1개가 필요하고, B24(실제 모터)는 별도다.
> 점퍼는 전원을 끈 상태에서 꽂는다. JB4와 JB6 사이의 **JB5는 GND**이므로 JB6과 닿으면 3.3 V가 단락된다.

## 0. 준비

| 항목 | 내용 |
|---|---|
| 비트스트림 | `part03/ch21/build/out/basys3_soc21_top.bit` (SHA-256 fca1368c…3925, `ch21/validation/soc_summary.md`) — (변경) 안 A 동결 주소맵. **30장을 뺀 21~31장은 이 비트스트림 하나.** (변경 2026-11-22) **30장은 별도** `part03/ch30/build/out/basys3_soc30_top.bit`·`soc30_motor.xsa`(1-30절) |
| XSA | `part03/ch21/build/out/soc21_npu.xsa` (SHA-256 24abeb3a…458d) |
| ELF ① | `part03/ch22/build/ws/npu_app/build/npu_app.elf` (SHA-256 bdb8cb6e…b0ce) |
| ELF ② | `part03/ch23/build/ws/bench_board/build/bench_board.elf` (SHA-256 768c9cd9…) |
| 주의 | (추가 2026-11-22) 재빌드하면 SHA가 달라진다. 보드 점검 전에는 이 폴더에서 재빌드하지 않는다 |
| 재생성 | `LEVEL=fpga SOC11_DIR=<제1부 11장 폴더> VIVADO_SETTINGS=… VITIS_SETTINGS=… bash part03/ch27/scripts/run_all.sh` |
| 터미널 | USB-UART 115200 bps, 8N1, 흐름 제어 없음 |
| 주소(안 A) | GPIO0 LED/SW 0x4000_0000, BTN 0x4001_0000, UART 0x4002_0000, Timer 0x4003_0000, INTC 0x4004_0000, SEG7 0x4006_0000, NPU 0x44A0_0000 |
| XSDB 읽기 | Vitis의 XSDB에서 `connect; targets -set -filter {name =~ "*RISC-V*" || name =~ "*MicroBlaze*"}; mrd <주소>` (프로그램 실행 중에도 읽기만 한다) |
| 기존 성공 프로젝트 | 제1부·제2부 프로젝트와 `~/soc/hw/soc11_user_top`은 쓰지 않는다(복제본 빌드만 사용) |

## 1. 점검 항목

| # | 절차 | 기대 결과 (시뮬레이션·빌드 근거) | 판정 |
|---|---|---|---|
| B1 | Vivado Hardware Manager로 비트스트림 다운로드 | DONE LED 점등, 오류 없음 | |
| B2 | Vitis에서 `npu_app.elf` 실행(같은 XSA 플랫폼) | `P3 NPU driver test base=0x44a00000` | |
| B3 | 이어지는 UART 4줄 | `SAMPLE 0 ... npu_class=7 cpu_class=7 expect=7 scores_match=1 rc=0`<br>`SAMPLE 1 ... npu_class=2 ...`<br>`SAMPLE 2 index=92 label=9 npu_class=4 ...`<br>`SAMPLE 3 index=1640 label=9 npu_class=4 ...` | |
| B4 | 마지막 줄 | `NPU_APP_DONE samples=4 failures=0` | |
| B4a | 실행 끝난 뒤 7세그먼트·LED를 눈으로 확인 | 7세그먼트 `03 4`(왼쪽 두 자리 = 그림 번호 3, 가운데 오른쪽 꺼짐, 오른쪽 = 클래스 4), LED4만 켜짐. 각 표본 직후 `00 7`·`01 2`·`02 4` 순서 | |
| B4b | XSDB `mrd 0x4006FFF0` | `53454737`("SEG7" ID) | |
| B4c | XSDB `mrd 0x40010000`을 버튼을 누르지 않고 / btnU·btnD·btnL·btnR을 각각 누른 채로 | `0` / `8`·`4`·`2`·`1` (btn[3]=U … btn[0]=R) | |
| B5 | `bench_board.elf` 실행 | `BENCH cpu_cycles=1816547 npu_bias_cycles=3076 npu_cycles=1080161 cpu_class=7 npu_class=7 match=1 rc=0` 부근. 차이가 있으면 원인 기록 | |
| B6 | 같은 ELF 3회 반복 실행 | 사이클 값이 매번 같거나 차이를 기록(캐시 없음·같은 클록이면 같아야 함) | |
| B7 | 실행 중 btnC(Reset) 누른 뒤 다시 실행 | 처음부터 같은 출력 | |
| B8 | (선택) Vivado Hardware Manager에서 전력 확인은 Basys3에 측정 회로가 없어 **하지 않는다** | 5-6 전력 값은 Vivado 추정치로만 남긴다 | — |

## 1-28. 28장 숫자 인식 시스템 (21장 비트스트림 그대로, ELF만 다르다)

준비: (변경) 안 A: 21장 `basys3_soc21_top.bit`, ELF `part03/ch28/build/ws/digit_app/build/digit_app.elf`(SHA-256 077ca88b0cf043a9, `ch28/validation/build_sw.log`). 표시는 표준 7세그먼트 IP(이전 FND 하드웨어와 같은 모양). 호스트 도구가 시리얼 포트를 쓰므로 Vitis 터미널은 닫는다.

| # | 절차 | 기대 결과 (협동 시뮬레이션·SoC xsim 근거) | 판정 |
|---|---|---|---|
| B9 | 5장 비트스트림 다운로드, `digit_app.elf` 실행 | 7세그먼트 `F16C`(모델 ID 상위), LED 모두 꺼짐 | |
| B10 | `python3 part03/ch28/host/p3_digit_host.py --port <포트> --error-suite --csv b28.csv --log b28_uart.log` | `MODEL_ID host=f16c4f12 device=f16c4f12`, 표본 22장 `scores_match=1 display_ok=1`, `error_suite=11/11`, `DIGIT_HOST_PASS` | |
| B11 | 마지막 정상 결과 뒤 7세그먼트·LED를 눈으로 확인 | 7세그먼트 `07 _7`(img 7, Class 7), LED7·LED15 켜짐. 오류 시험 중에는 `E`+코드·LED14 | |
| B12 | (선택) `--mnist-dir <MNIST raw> --limit 200` | 장치 class = 골든 class 200/200, 정확도는 골든·장치를 따로 기록 | |
| B13 | (선택) 직접 그린 28×28 PNG `--images a.png [--invert]` | 응답·표시가 오는지 확인(정확도 주장은 하지 않음) | |
| B13a | 실행 중 btnU를 누른 채 XSDB `mrd 0x40010000` | `8` — 이 펌웨어는 버튼을 쓰지 않으므로 표시·UART에 변화 없음 | |

## 1-29. 29장 센서 감시 (21장 비트스트림 그대로, ELF만 다르다)

준비: (변경) 안 A: 21장 `basys3_soc21_top.bit`, ELF `part03/ch29/build/ws/sensor_app/build/sensor_app.elf`(`ch29/validation/build_sw.log`의 SHA-256). 센서는 연결하지 않는다(가상 센서 값을 UART로 보냄).

| # | 절차 | 기대 결과 (협동 시뮬레이션 근거) | 판정 |
|---|---|---|---|
| B14 | 5장 비트스트림 다운로드, `sensor_app.elf` 실행 | 7세그먼트 `3 _00`(UNKNOWN), LED3·LED15 켜짐 | |
| B15 | `python3 part03/ch29/host/p3_sensor_host.py --port <포트> --limit 200 --csv b29.csv --log b29_uart.log`, 안내가 나오면 btnC | `BOOT PASS`, 모든 STEP PASS, `SENSOR_HOST_PASS` | |
| B16 | 실행 중 7세그먼트·LED를 눈으로 확인 | FAULT 래치 때 자리 3의 점과 LED13, ACK 뒤 점이 꺼지고 3회 정상 뒤 `0` | |
| B17 | 호스트를 멈추고 링크 감시 시간을 스톱워치로 잰다 | `STATE src=LINK_TIMEOUT`이 주기적으로 나온다. 실측 주기(초)를 기록(폴링 10,000,000회) | |
| B17a | XSDB `mrd 0x4006FFF0`, `mrd 0x40010000`(btnL 누른 채) | `53454737`, `2` | |

## 1-30. 30장 모터 안전 (30장 비트스트림 — 모터·드라이버는 처음에는 연결하지 않는다)

> (변경) 안 A(2026-11-20): 30장 SoC = 21장 안 A SoC + 모터 GPIO `axi_gpio_motor` **0x4007_0000** + 모터 안전 코어(별도 비트스트림). 다른 주소·인터럽트는 21장과 같다(`ADDR_MAP_A_PASS`·`IRQ_MAP_A_PASS`). btnU는 BTN GPIO btn[3]이면서 비상정지 버튼이다.

준비: `part03/ch30/build/out/basys3_soc30_top.bit`(SHA-256 2fa4deada606d078), XSA `soc30_motor.xsa`(3f06b52665eb4c26), ELF `motor_app.elf`(68779b98af7fa07b) — `ch30/validation/build_soc_mapA_20261120.log`. **1단계는 가상 부하(LED)만**: JB에는 아무것도 꽂지 않는다.

| # | 절차 | 기대 결과 | 판정 |
|---|---|---|---|
| B18 | JB4 미연결 상태로 실행 | 비상정지 루프 열림 → LED9(트립) 켜짐, `python3 part03/ch30/host/p3_motor_host.py --port <포트> …`의 `clear_reset`이 trip=1로 남음(fail-safe) | |
| B19 | JB4를 3.3 V(JB6 VCC)로 점퍼(NC 루프 흉내) 후 호스트 보드 단계 | `MOTOR_HOST_PASS`(부팅 트립 → 해제 → NORMAL 80 % 운전 → WARNING 30 % → NPU FAULT 정지 → 'J' 거부), LED11·12 켜짐/밝기 변화 | |
| B20 | 운전 중 btnU 누름, 놓은 뒤 'C' 없이 프레임 계속 | LED11·12 즉시 꺼짐, LED9 켜짐, 해제 전까지 다시 켜지지 않음 | |
| B21 | 운전 중 sw[14](정방향 리밋) 올림 → 'D' 2(REV) | 정방향 즉시 정지(트립 없음), 약 100 ms 뒤 LED10(REV) | |
| B22 | sw[12](고장)·sw[11](과열) 각각 올렸다 내림 | 즉시 정지·트립 래치, 'C' 뒤에만 재가동 | |
| B23 | 호스트를 멈춤(프레임 중단) | 약 0.5 s 뒤 정지·WD 래치 | |
| B23a | 실행 중 7세그먼트를 보고, XSDB `mrd 0x4006FFF0`·`mrd 0x40070008`·`mrd 0x40010000`(btnL 누른 채) | 7세그먼트 [3] 정책 상태, [2] 구동 방향(트립이면 점), [1:0] 실제 duty 16진(램프가 끝난 뒤 B19 NORMAL FWD 80 % = `0150`, WARNING 30 % = `111E`); `53454737`; 상태 워드 [6:0] = 7세그먼트 오른쪽 두 자리 값; `2` | |
| B23b | 정지 상태에서 btnU를 누른 채 XSDB `mrd 0x40010000`·`mrd 0x40070008` | `8`(btn[3]) 그리고 상태 워드 [14] trip = 1 (같은 핀이 BTN GPIO와 비상정지에 함께 들어감), LED9 켜짐 | |
| B24 | **(별도, 사용자 판단)** 실제 드라이버·모터 연결 | 외부 전원·공통 GND·드라이버 입력 풀다운·전류 보호 확인 뒤에만. 이 점검표의 PASS로 대체하지 않는다 | |

## 1-31. 31장 보안 모델 적재 (21장 비트스트림 그대로, ELF만 다르다)

준비: (변경) 안 A: 21장 `basys3_soc21_top.bit`, `secure_app.elf`(SHA-256 624f4cedec58e289, `ch31/validation/build_sw.log`). 저장소 TEST 키로 빌드한 ELF면 호스트도 키 파일 없이, 운영 키면 `P3_KEY_FILE`로 빌드하고 호스트에 `--key-file`(둘 다 저장소 밖).

| # | 절차 | 기대 결과 | 판정 |
|---|---|---|---|
| B25 | `python3 part03/ch31/host/p3_secure_host.py --port <포트> --csv b31.csv --log b31_uart.log`, 안내가 나오면 btnC | 부팅 `key_fp` 일치, 모든 STEP PASS(모델 B 적재·추론, 거부 17종, A 재적재), `SECURE_HOST_PASS` | |
| B26 | 실행 뒤 btnC로 재부팅하고 `I` | `last_seq=0`(재부팅 뒤 Replay 가능 — 알려진 한계 확인) | |
| B26a | 모델 B 적재 뒤 7세그먼트 확인, XSDB `mrd 0x40010000`(btnD 누른 채) | 7세그먼트 `b749`(모델 B ID 상위), LED0·LED13 켜짐(`DISP fnd=000fb749 led=2001`), `4` | |

## 2. 기록할 것

- 각 항목의 UART 원문(사진 또는 터미널 로그), Vivado·Vitis 버전, 보드 리비전.
- FAIL이면 그 항목에서 멈추고 현상을 기록한다(추가 수정은 원인 확인 뒤 별도 커밋).

## 3. 이번 점검 범위 밖

- 29장 실제 센서(DS18B20·XADC·HC-SR04) 연결, 30장 실제 모터·드라이버 구동(B24는 사용자 판단으로 별도).
- 클록을 100 MHz 위로 올리는 시험(24장 Fmax는 OOC 추정).
