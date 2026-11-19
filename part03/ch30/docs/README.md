# 30장 NPU 기반 지능형 모터 제어 (종합 3)

센서 창 → 29장 guard·NPU·경보 정책(펌웨어) → **추천**(방향·속도) → AXI GPIO 2 명령 워드 → **독립 모터 안전 코어 RTL**(명령 승인·워치독 → 인터록 → 방향·데드타임·램프·PWM) → IN1·IN2·ENA(Pmod JB) → 모터 드라이버.

> 교육용이며 인증된 기능안전 로직이 아니다. 실제 모터는 드라이버·외부 전원·역기전력·전류 보호를 따로 두고, 사용자와 함께 연결한다.
> NPU 검증 PASS가 실물 안전 보호를 대신하지 않는다.

## 1. 결정 사항

| 항목 | 결정 |
|---|---|
| 역할 분리 | NPU·CPU는 **명령 워드만** 쓴다. IN1·IN2·ENA는 `p3_motor_safety`만 구동한다. BD에서 NPU와 모터 핀 사이 경로는 CPU의 GPIO 쓰기뿐 |
| 출발점 | 제2부 07장 `motor_controller`(L298N 계열 IN1/IN2/ENA, 조합 차단, 반전 정지 시간, 트립 래치)의 구조를 따르고, 30장에서 PWM·램프·워치독·다중 원인 래치를 더해 새로 작성(07장 파일은 수정하지 않음) |
| 최우선 정지 | E-Stop·고장·과열·워치독 만료·트립 래치는 클록을 기다리지 않는 조합 경로로 출력 0. 진행 방향 리밋은 그 방향만 차단(래치 없음, 반대 방향으로 빠져나올 수 있음) |
| 래치·해제 | 원인 {RESET, WD, OTEMP, FAULT, ESTOP}은 래치된다. 해제는 운전자 명령('C')뿐이며 **STOP 요청 중**이고 원인이 사라진 비트만 지운다 |
| 전원 복귀 | Reset 직후 RESET 래치 = 1 → 해제 전에는 NPU가 NORMAL이어도 움직이지 않는다(자동 재가동 금지) |
| 워치독 | 명령마다 kick 비트 토글. WD_CYC(보드 500 ms) 동안 새 명령이 없으면 정지·WD 래치. 센서 프레임이 끊기면 kick도 끊긴다 |
| 반전 | 방향 변경·정지 때 DEAD_CYC(보드 100 ms) 동안 IN1=IN2=0 |
| 속도 | 추천 NORMAL 80 %, WARNING 30 %, FAULT·UNKNOWN STOP. 올릴 때 RAMP_CYC(1 ms)마다 1 %, 내릴 때 즉시. PWM 20 kHz |
| 비상정지 입력 | JB4 = 외부 NC 루프(닫힘 = 3.3 V), **PULLDOWN** → 미연결·단선이면 정지(fail-safe). btnU도 비상정지. 2단 동기화 |
| 시험 입력 | 이 장에서는 sw[14] 정방향 리밋, sw[13] 역방향 리밋, sw[12] 고장, sw[11] 과열로 흉내 낸다(실제 전류·온도 회로는 사용자와 함께) |
| 표시 | LED12 ENA(PWM 밝기), LED11 IN1, LED10 IN2, LED9 트립 — 코어가 직접 구동(CPU 무관). FND [3] 정책 상태, [2] 구동 방향(점 = 트립), [1:0] 실제 duty(16진) |

## 2. 명령·상태 워드 (AXI GPIO 2, 0x4002_0000)

| 레지스터 | 비트 |
|---|---|
| 채널 1 DATA(0x0) 명령 | [6:0] duty 0..100, [9:8] dir 0 STOP·1 FWD·2 REV(3 무효), [12] clear 토글, [15] kick 토글. 무효 명령은 STOP + cmd_err |
| 채널 2 DATA(0x8) 상태 | [6:0] 실제 duty, [7] cmd_err, [9:8] 구동 방향, [11:10] 요청 방향, [12] gate, [13] dead, [14] trip, [15] wd_exp, [20:16] 래치 {RESET,WD,OTEMP,FAULT,ESTOP}, [25:21] 입력 {lim_r,lim_f,otemp,fault,estop}, [26] IN1, [27] IN2, [28] ENA |

## 3. UART 명령 (29장과 같은 프레임 형식)

| CMD | 내용 |
|---|---|
| `S` | 29장 센서 창 → 정책 → 추천 → 명령 쓰기(kick) → `MOTOR src=FRAME …` |
| `D` | 운전자 방향 1 FWD / 2 REV (속도는 계속 정책이 정한다) |
| `C` | 모터 트립 해제(STOP 쓰기 → 다음 쓰기에서 clear 토글) |
| `A` | 29장 경보 래치 ACK(모터 트립 해제와 다르다) |
| `Q` | 상태 조회(명령을 쓰지 않으므로 워치독을 갱신하지 않는다) |
| `I` | 식별 |
| `J` | **PC 협동 시뮬레이션 전용** 시험 주입(입력 비트·클록 진행). 보드 빌드는 `ERROR code=3` |

## 4. 파일

| 파일 | 내용 |
|---|---|
| `rtl/p3_motor_safety.v` | 모터 안전 코어 |
| `rtl/p3_motor_safety_bd.v`·`basys3_soc30_top.v` | BD 모듈 참조 래퍼(입력 동기화), 보드 Top |
| `reference/motor_reference.py` | 코어 클록 모델·안전 불변식·벡터(정본) |
| `tb/tb_p3_motor_safety.sv`·`tb_p3_motor_bridge.sv` | 코어 벡터 시험, 협동 시뮬레이션 브리지(NPU + 코어 + 핀 불변식 감시) |
| `sw/motor_app.c`·`motor_app.h`·`main.c` | 펌웨어(29장 `sensor_app.c`를 수정 없이 링크해 guard·특징·정책 재사용) |
| `host/p3_motor_host.py`·`motor_cosim_main.c` | 호스트(협동 시뮬레이션 시나리오·보드 자동 단계) |
| `constraints/basys3_soc30.xdc`, `synth/soc30_bd.tcl`·`synth_configs.tcl` | 28장 XDC + JB·btnU, BD 변경·구현, OOC 구성 |
| `scripts/run_sim.sh`·`run_synth.sh`·`build_soc.sh` | PC 검증, 코어 OOC, SoC Bitstream·ELF |

## 5. 결과 (실제 실행)

| 항목 | 결과 |
|---|---|
| 기준 모델 자기 시험 | `MOTOR_REFERENCE_SELFTEST_PASS` |
| 코어 단위 RTL | Python 기준 모델과 클록 단위 일치, 125,968클록 (`validation/rtl_sim.log`) |
| 코어 RTL 변이 7종 | **7/7 검출** |
| 종단간 협동 시뮬레이션 | 62/62 검사 PASS(호스트 → 펌웨어(29장 정책) → NPU RTL + 모터 안전 RTL), 핀 불변식 위반 0 / 1,403,942클록, 방향 전환 최소 간격 3,001 ≥ 데드타임 3,000 (`validation/rtl_cosim.csv`) |
| 펌웨어 변이 6종 | **6/6 검출** |
| 코어 OOC 배선 | LUT 169, FF 120, DSP 0, WNS +3.699 ns @100 MHz (`validation/synth_ooc_summary.md`) |
| SoC 비트스트림 | PASS — 2026-11-19 재빌드(11-18 23:36 시스템 종료로 첫 시도의 impl_1 중단). 배선 후 WNS +0.427 ns, WHS +0.022 ns, 출력 핀 IN1·IN2·ENA는 motor_safety_0에서만 구동, JB4 PULLDOWN, 입력 동기화기 ASYNC_REG 12셀. `basys3_soc30_top.bit` b0c00e3b07a9e2b4, XSA 1fbedd8afa770952 (`validation/build_soc_20261119.log`) |
| 펌웨어 ELF(`motor_app`) | 53,456 B, SHA-256 210ff1cff2c2ab68, `ELF_MEM_PASS`, GPIO2 0x4002_0000 |
| **Basys3 실물** | **NOT_RUN** — `ch27/docs/BOARD_CHECKLIST.md` B18~B24, 사용자와 함께 |

## 6. 알려진 한계

- 코어 단위 시험은 클록 단위로 Python과 같지만, 협동 시뮬레이션의 모터 상태는 버스 지연(브리지 TB의 GPIO 4클록 모델) 때문에 클록 단위로 예측하지 않고 단계별 술어와 핀 불변식으로 판정한다.
- 실제 과전류·온도 측정 회로, 엔코더 속도 궤환, 모터 관성(차단 뒤 바로 서지 않음)은 다루지 않는다.
- FPGA 설정 전·중에는 출력 핀이 정의되지 않으므로 드라이버 입력(IN1·IN2·ENA)에 외부 풀다운이 필요하다(사용자와 함께 확인).
