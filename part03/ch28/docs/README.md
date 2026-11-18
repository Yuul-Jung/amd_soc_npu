# 28장 손글씨 숫자 인식 NPU 시스템 (종합 1)

PC의 손글씨 이미지 → Python 전처리 → UART 프레임 → MicroBlaze V → 20장 AXI NPU(784 입력·13타일·10분류) → 10개 점수·Class → UART 결과 줄 + LED + FND.

## 1. 결정 사항

| 항목 | 결정 |
|---|---|
| 실습 모드 | **28×28·784 타일링**(17장 하드웨어, 18장 INT8 학습 모델). 8×8·64 모드는 이 장에서 쓰지 않는다 |
| 모델 연결 | 18장 `mnist_linear_f32.json` → INT8 양자화 → `MODEL_ID = zlib.crc32(w ‖ b(int64 LE)) = f16c4f12`. 펌웨어가 부팅 때 같은 CRC32를 계산해 ROM 모델을 확인하고, 모든 추론 프레임이 MODEL_ID를 실어 보낸다 |
| 전처리 | 28×28 8비트 회색조, MNIST 극성(흰 글씨·검은 바탕). `x_q = round_half_away(pixel·127/255)` ∈ 0..127 (18장과 같은 규칙). 다른 크기는 거부(임의 축소 없음), `--invert`로 극성만 뒤집을 수 있음 |
| 역할 분담 | MicroBlaze V: 프레임 수신·검사, NPU 레지스터 적재·완료 확인, 결과 전송·표시. NPU RTL: 10개 점수의 MAC 전부. CPU 정수 추론은 대조용으로만 실행 |
| 표시 규칙 | Class는 NPU DONE·rc=0·MODEL_ID 일치·NPU 점수=CPU 점수일 때만 표시. 아니면 오류 표시 |
| FND 하드웨어 | 21장 SoC 복제본에 AXI GPIO 1(32비트) + `p3_fnd_scan`(BD 모듈 참조) 추가. 21장 결과물·제1부 원본은 그대로 |

## 2. UART 규약 (115200 8N1)

PC → 보드 프레임: `'P' '3' CMD PAYLOAD CRC16` — CRC16/CCITT-FALSE(0x1021, 초기 0xFFFF)를 `CMD‖PAYLOAD`에 계산해 **상위 바이트 먼저** 붙인다(수신 쪽은 CRC 포함 잔여값 0으로 판정).

| CMD | PAYLOAD | 응답 |
|---|---|---|
| `I` | 없음 | `P3_DIGIT READY model=f16c4f12 model_ok=1 mode=784x8 tiles=13 junk=0` |
| `X` | img_id u16 LE ‖ model_id u32 LE ‖ x[784] int8 (790바이트, 프레임 795바이트) | `RESULT img=… model=… npu_class=… cpu_class=… match=1 rc=0 status=… junk=… scores=s0,…,s9` + `DISP …` |
| `T` | 없음 | 가중치 미적재 자체 시험 `SELFTEST w_missing err_code=9 recovered=1 …` + `DISP …` |
| 오류 | — | `ERROR img=<id 또는 -1> code=<n> name=<이름> detail=<n> junk=<n>` + `DISP …` |

오류 코드(FND 마지막 자리): 1 CRC, 2 TIMEOUT(프레임 도중 바이트 간격 초과), 3 CMD, 4 MODEL(ID 불일치 또는 부팅 모델 검사 실패), 5 RANGE(화소 > 127), 6 NPU(HW 오류·시간 초과·넘침), 7 MISMATCH(NPU ≠ CPU).
동기 `P3` 앞의 바이트는 버리고 `junk`로 센다. 부팅 시 `P3_DIGIT READY … bias_rc=0`과 `DISP`를 한 번 보낸다.

## 3. 표시

| 상태 | FND (왼쪽 → 오른쪽) | LED |
|---|---|---|
| 부팅 | MODEL_ID 상위 16비트 `F16C` | 모두 꺼짐 |
| 결과 | img_id 하위 바이트 16진 2자리, 빈칸, Class | LED[Class] + LED15(유효) |
| 오류 | img_id 2자리(모르면 꺼짐), `E`, 오류 코드 | LED14 |
| 자체 시험 통과 | `  00` | 모두 꺼짐 |

FND 워드(AXI GPIO 1): `[15:0]` 자리별 nibble(자리 0 = 오른쪽), `[19:16]` 자리 켜짐, `[23:20]` 점. `p3_fnd_scan`이 자리당 2^17클록(1.31 ms)씩 돌아가며 Low 활성으로 구동한다.

## 4. 파일

| 파일 | 내용 |
|---|---|
| `reference/digit_reference.py` | 모델·MODEL_ID·전처리·골든·프레임·FND 표시 규칙(정본), 표본 생성, C 헤더 생성 |
| `reference/digit_samples.txt` | MNIST t10k 숫자별 첫 2장 + INT8 모델 오분류 첫 2장(index 33, 63), 22장 |
| `reference/soc_sim_check.py` | SoC xsim 프레임 생성·기록 판정 |
| `host/p3_digit_host.py` | PC 호스트: 이미지·MNIST·표본 → 프레임 → 보드(`--port`) 또는 협동 시뮬레이션(`--cosim`) → CSV·UART 원문 로그, `--error-suite` |
| `sw/digit_app.c`·`digit_app.h`·`digit_io.h`·`digit_io_xil.c`·`main.c` | MicroBlaze V 펌웨어(22장 드라이버 재사용). 플랫폼 경계는 `digit_io.h` 세 함수 |
| `host/digit_io_host.c`·`digit_cosim_main.c` | 같은 펌웨어의 PC 빌드(표준 입출력 = UART, 22장 FIFO 브리지 = NPU RTL) |
| `rtl/p3_fnd_scan.v`·`rtl/basys3_soc28_top.v` | FND 스캔, 28장 Top |
| `tb/tb_p3_fnd_scan.sv`·`tb/tb_soc28_uart.sv` | FND 핀 시험, SoC 전체 UART 시험 |
| `constraints/basys3_soc28.xdc` | 21장 활성 줄 + seg/dp/an 12핀 |
| `synth/soc28_bd.tcl`·`synth/soc28_uart_sim.tcl` | BD 변경·구현·XSA, SoC xsim |
| `scripts/run_sim.sh`·`build_soc.sh`·`run_soc_sim.sh` | PC 검증, Vivado+Vitis 빌드, SoC xsim |

`ch22/vitis/vitis_build.py`는 플랫폼 이름을 `P3_PLAT_NAME`으로 바꿀 수 있게만 했다(기본값 그대로, 22·23장 동작 동일).

## 5. 실행

```bash
bash part03/ch28/scripts/run_sim.sh                                   # PC: 기준모델·FND RTL·종단간 협동 시뮬레이션·변이 (약 1분)
VIVADO_SETTINGS=… VITIS_SETTINGS=… bash part03/ch28/scripts/build_soc.sh   # 21장 build 필요, 약 25분
VIVADO_SETTINGS=… bash part03/ch28/scripts/run_soc_sim.sh                 # SoC xsim, 수 시간
# 보드(사용자와 함께): 비트스트림·ELF 적재 후
python3 part03/ch28/host/p3_digit_host.py --port /dev/ttyUSB1 --error-suite \
        --csv board.csv --log board_uart.log                            # 표본 22장 + 오류 시험
python3 part03/ch28/host/p3_digit_host.py --port /dev/ttyUSB1 --mnist-dir <MNIST raw> --limit 200 --csv … --log …
python3 part03/ch28/host/p3_digit_host.py --port /dev/ttyUSB1 --images my_digit.png [--invert] --csv … --log …
```

## 6. 결과 (실제 실행)

| 근거 | 결과 |
|---|---|
| 기준모델 | `DIGIT_REFERENCE_SELFTEST_PASS model_id=f16c4f12 frame_bytes=795` (CRC16 검사값 0x29B1, 잔여값 0, x=0 → 점수=Bias, FND 규칙) |
| FND RTL | `RTL_SIM_PASS FND_SCAN vectors=36 digit_changes=9` — 9개 워드 × 4자리 핀 값 = Python, Reset 시 모두 꺼짐, 자리 순서 0→1→2→3 |
| 종단간 협동 시뮬레이션 (PC 호스트 → 펌웨어 C → AXI NPU RTL) | 22장 모두 **10개 점수 = PC 골든**, NPU class = CPU class = 골든, DISP 값 = 표시 규칙 (`validation/rtl_cosim.csv`) |
| 정확도(표본 22장, 두 근거 따로) | PC 골든 19/22, RTL 장치 19/22. 틀린 3장(index 8: 5→6, 33: 4→0, 63: 3→2)은 골든도 같은 답 → `MODEL_MISCLASS`(모델 한계, 하드웨어 불일치 아님). 18장 t10k 전체 INT8 정확도 92.56%와는 표본 구성이 달라 비교하지 않는다 |
| 오류 시험 11종 | CRC 1비트 반전, 모델 ID 불일치, 화소 범위, 미정의 명령, 잡음 뒤 잘못된 명령(junk=5), 잡음 뒤 정상 프레임(junk=4), 짧은 프레임 시간 초과, 시간 초과 뒤 정상, **가중치 미적재(NPU ERR_CODE 9) 후 ABORT 복구**, 복구 뒤 정상, 식별 — 모두 기대 응답·표시 |
| 펌웨어 변이 8종 | 표시 class·오류 코드 표시·CRC 검사·범위 검사·모델 ID 검사·자체 시험 복구·잡음 계수·재동기 제거 → **8/8 검출** |
| Vivado 구현 | WNS +0.420 ns, WHS +0.020 ns, Bitstream·XSA (`validation/soc_summary.md`) |
| Vitis ELF | 32,912 B, xparameters: NPU 0x44A0_0000, GPIO1 0x4001_0000, UART 0x4060_0000 |
| SoC 전체 xsim | **NOT_COMPLETE** — 1차 실행은 부팅 응답(`READY`·`DISP fnd=000FF16C`)까지만 받고 중단됨. 재실행 결과를 `validation/soc_uart_sim.log`로 남긴 뒤 이 행을 갱신한다 |
| **Basys3 실물** | **NOT_RUN** — `ch27/docs/BOARD_CHECKLIST.md` 28장 항목, 사용자와 함께 |

## 7. 알려진 한계

- 정확도는 18장 단일층 784→10 모델 수준이다(t10k 92.56%). 손으로 그린 PNG는 MNIST 전처리(중앙 정렬·20×20 크기 맞춤)를 하지 않으므로 정확도가 더 낮을 수 있다. 이 장은 그 전처리를 추가하지 않았다.
- 보드에서 프레임 1장 전송에 약 69 ms(795바이트 × 86.8 µs), NPU 종단간 약 10.8 ms, CPU 대조 추론 약 18 ms(23장 값)가 든다.
- 바이트 간격 제한은 보드에서 폴링 횟수(`DIGIT_RX_POLLS` 3,000,000)라 실제 시간은 빌드 최적화에 따라 다르다. PC 빌드는 300 ms.
- 인터럽트는 쓰지 않는다(폴링).
