# 5-6 SoC 전력·추론당 에너지 추정 (Vivado 2024.2 report_power, 실제 실행)

> 5-2 배선 완료 설계. SAIF는 5-4와 같은 SoC 행동 시뮬레이션의 구간별 토글률. **추정치이며 보드 전력 측정이 아니다.**

| 활동률 | 전체(W) | 동적(W) | 정적(W) | p3_npu_0(W) | microblaze_riscv_0(W) | 신뢰도 |
|---|---:|---:|---:|---:|---:|---|
| 기본 토글률(vectorless) | 0.234 | 0.161 | 0.073 | 0.021 | 0.012 | Low |
| CPU 추론 구간 SAIF | 0.253 | 0.180 | 0.073 | 0.012 | 0.021 | Medium |
| NPU 추론 구간 SAIF | 0.256 | 0.183 | 0.073 | 0.012 | 0.021 | Medium |

| 추론 경로 | 시간(5-4, 100 MHz) | 전체 전력(W) | 추론당 에너지(mJ) | 동적만(mJ) |
|---|---:|---:|---:|---:|
| CPU 정수 추론 | 18.165 ms | 0.253 | 4.596 | 3.270 |
| NPU 종단간 | 10.802 ms | 0.256 | 2.765 | 1.977 |

- 추론당 에너지 비(CPU/NPU): 전체 1.66배, 동적 1.65배

SAIF 매칭(Vivado 로그):

- `INFO: [Power 33-167] Parsing SAIF file cpu.saif`
- `INFO: [Power 33-177] SAIF annotation done from file cpu.saif`
- `INFO: [Power 33-26] Design nets matched = 2300 of 15469`
- `INFO: [Power 33-167] Parsing SAIF file npu.saif`
- `INFO: [Power 33-177] SAIF annotation done from file npu.saif`
- `INFO: [Power 33-26] Design nets matched = 2317 of 15469`
