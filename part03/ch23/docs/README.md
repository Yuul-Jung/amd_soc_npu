# 제23장 · 같은 SoC에서 CPU 대 NPU 비교

## 1. 측정 방법

```text
basys3_soc21_top (21장 SoC, (변경) 안 A 동결 주소맵 — 클록 수는 이전과 같음)
  MicroBlaze V ── bench.elf ──┬─ cpu_infer()   : 784×10 MAC 정수 추론(22장 C, 같은 데이터)
                              ├─ npu_set_bias(): Bias 10개 적재(모델당 1회)
                              └─ npu_infer()   : 13타일 W·X 레지스터 쓰기 + TILE_GO + 폴링 + 점수 읽기
  axi_timer_0 (100 MHz, 자유 증가) : 구간 앞뒤 TCR0 차 − 측정 자체 비용 = 클록 수
  axi_gpio_0 데이터 레지스터       : 결과 9단어를 차례로 기록 → 시뮬레이션 TB가 AXI 쓰기로 수집
```

| 항목 | 내용 |
|---|---|
| 신규 파일 | `sw/bench.c`, `tb/tb_soc_bench.sv`, `synth/soc_bench_sim.tcl`, `scripts/run_soc_bench.sh` |
| 재사용 | 21장 SoC 프로젝트(복제)·XSA, 22장 드라이버·`gen_model.py`·`vitis_build.py`(응용 이름·파일 목록 인자로 일반화) |
| ELF | `bench_board`(UART로 결과 출력, 실물용) / `bench_sim`(출력 없음, 시뮬레이션용). 둘 다 Vitis 기본 **Debug(-O0)** 빌드 |
| CPU 구성 | MicroBlaze V `-march=rv32i_zicsr_zifencei` — **M 확장 없음**, 곱셈은 소프트웨어(`__mulsi3`) |
| 데이터 | 18장 INT8 모델, MNIST t10k index 0 (label 7) |

## 2. SoC 전체 RTL 시뮬레이션 결과 (Vivado xsim, 실제 MicroBlaze V가 ELF 실행)

| 구간 | 클록(100 MHz) | 시간 | 비고 |
|---|---:|---:|---|
| CPU 정수 추론 | **1,816,547** | 18.17 ms | 소프트웨어 곱셈 7,840회 포함 |
| NPU Bias 적재 | 3,076 | 0.03 ms | 모델당 1회 |
| NPU 종단간 추론 | **1,080,161** | 10.80 ms | 레지스터 쓰기 약 9,400회 + 폴링 |
| NPU 연산만(참고) | 약 2,700 | 0.027 ms | 17장 RTL 측정: 타일 13 × 207클록 + 완료. SoC 안에서 따로 잰 값이 아님 |

- 결과: `cpu_class = npu_class = 7`, 10개 점수 CPU = NPU = 기대값, `rc = 0` → `SOC_RTL_SIM_PASS`
- **종단간 1.68배, 연산만 약 670배.** 시간의 99% 이상이 AXI4-Lite로 가중치·입력을 한 단어씩 쓰는 데 든다(타일마다 W 640 + X 64 = 704단어, 레지스터 쓰기 1회 평균 약 115클록). NPU 연산 자체가 아니라 **데이터 이동이 병목**이다 — 19장의 적재 병목 분석과 같은 결론.
- 개선 방향(이후 장): 가중치 상주 BRAM(모델 1회 적재), 여러 단어 묶어 쓰기, DMA·AXI4 burst, `-O2` 빌드, M 확장 CPU 구성과의 비교.

## 3. 실행

```bash
VIVADO_SETTINGS=<Vivado>/settings64.sh VITIS_SETTINGS=<Vitis>/settings64.sh \
  bash part03/ch23/scripts/run_soc_bench.sh       # 21장 build_soc.sh 결과 필요, xsim 약 50분
```

기대 출력:

```text
ELF bench_board text=26892 data=204 bss=3508 ...
ELF bench_sim text=19592 data=204 bss=3508 ...
SOC_BENCH cpu_cycles=1816547 npu_bias_cycles=3076 npu_cycles=1080161 cpu_class=7 npu_class=7 scores_match=1 rc=0 ...
SOC_RTL_SIM_PASS
```

## 4. 검증 경계

- 이 수치는 **SoC RTL 시뮬레이션 사이클**이다. 같은 RTL·같은 ELF라 보드에서도 같아야 하지만, **보드 실측(bench_board ELF의 UART 출력)은 사용자와 함께 확인**한다.
- PC CPU 시간과 비교한 배율은 만들지 않는다. 비교는 같은 SoC의 MicroBlaze V와 NPU 사이에서만 한다.
- `-O0` 빌드와 M 확장 없는 CPU 구성은 CPU 쪽에 불리하고 드라이버 쪽에도 불리하다. 최적화 빌드 비교는 아직 하지 않았다.
