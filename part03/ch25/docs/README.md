# 제25장 · 전력·추론당 에너지 추정

> (변경) 안 A(2026-11-19): 21장 SoC(BTN GPIO·SEG7 추가)로 다시 실행한 **Vivado 추정값**이다. 시간은 23장 클록 수 그대로.

## 1. 방법

```text
21장 배선 완료 SoC ─ report_power (vectorless: 기본 토글률)
23장 SoC 행동 xsim(같은 ELF·같은 입력) ─ log_saif ─┬─ cpu.saif : 1~18 ms   (CPU 정수 추론 구간 안쪽)
                                                    └─ npu.saif : 19~28.9 ms (NPU 종단간 추론 구간 안쪽)
   └─ read_saif -strip_path tb_soc_bench/dut → report_power (구간별)
추론당 에너지 = 전체 전력 × 23장 측정 시간(100 MHz 클록 수)
```

| 항목 | 내용 |
|---|---|
| 신규 파일 | `synth/soc_power_sim.tcl`, `synth/soc_power_report.tcl`, `scripts/run_power.sh`, `reference/power_summary.py` |
| 재사용 | 21장 구현 프로젝트, 23장 시뮬레이션 프로젝트(복제)·TB·ELF |
| 구간 | 시뮬레이션이 결정적이라 23장 결과(CPU 18.17 ms, NPU 10.80 ms, 종료 29.04 ms)로 정하고 경계에 여유를 둠 |

## 2. 결과 (`validation/power_summary.md`)

| 활동률 | 전체(W) | 동적(W) | 정적(W) | p3_npu_0(W) | microblaze_riscv_0(W) | 신뢰도 |
|---|---:|---:|---:|---:|---:|---|
| 기본 토글률(vectorless) | 0.234 | 0.161 | 0.073 | 0.021 | 0.012 | Low |
| CPU 추론 구간 SAIF | 0.253 | 0.180 | 0.073 | 0.012 | 0.021 | Medium |
| NPU 추론 구간 SAIF | 0.256 | 0.183 | 0.073 | 0.012 | 0.021 | Medium |

| 추론 경로 | 시간 | 전체 전력 | **추론당 에너지** | 동적만 |
|---|---:|---:|---:|---:|
| CPU 정수 추론 | 18.165 ms | 0.253 W | **4.596 mJ** | 3.270 mJ |
| NPU 종단간 | 10.802 ms | 0.256 W | **2.765 mJ** | 1.977 mJ |

구간별 계층 전력(SAIF, W): clk_wiz_1 0.106 / 0.106, LMB 메모리 0.030 / 0.033, MicroBlaze V 0.021 / 0.020, **NPU 0.011 / 0.012**, SmartConnect 0.003 / 0.003 (CPU 구간 / NPU 구간).

- 두 구간 전력이 거의 같다. 전력의 대부분이 **MMCM(클록 생성) 0.106 W와 정적 0.073 W**이고, NPU는 종단간 시간 대부분을 AXI 쓰기를 기다리며 보내 활동률이 낮다.
- 그래서 에너지 비 **1.66배는 거의 시간 비(1.68배)**다. 에너지를 줄이려면 23장과 같은 결론 — 데이터 이동 시간을 줄여야 한다. NPU 블록만의 동적 에너지는 0.012 W × 10.8 ms ≈ 0.13 mJ.
- NPU가 쉬는 CPU 구간에도 NPU 0.011 W: 클록 게이팅이 없어 클록 트리·레지스터가 계속 동작한다.

## 3. 신뢰도와 한계

- SAIF 매칭 **15%**(15,469개 넷 중 2,300 / 2,317). 행동 시뮬레이션의 신호 이름이 구현 넷리스트와 일부만 맞고, 나머지 넷은 기본 토글률로 추정됐다(Vivado 신뢰도 Medium). 게이트 수준 시뮬레이션 SAIF를 쓰면 매칭이 오른다(미실행).
- 시간이 오래 걸린다: SAIF 기록 SoC xsim 약 1시간.
- **보드 전력 측정이 아니다.** Basys3에는 전력 측정 회로가 없어 실측 비교도 하지 않는다.

## 4. 실행

```bash
VIVADO_SETTINGS=<Vivado>/settings64.sh bash part03/ch25/scripts/run_power.sh   # 21·23장 build 필요
```

기대 출력: `SOC_RTL_SIM_PASS`, `SOC_POWER_REPORT_DONE`, `POWER_SUMMARY cpu_mJ=4.596 npu_mJ=2.765`
