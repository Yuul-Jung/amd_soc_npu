# 학습안내서 현황 (자동 생성)

`python3 tools/guide/build_guides.py`가 `chNN/chapter.json`과 `chNN/validation/` 증거로 만든다. 직접 수정하지 않는다.

✅ 통과 · ❌ 실패 · ⏳ 실행 대기/미검증 · — 해당 없음

| 장 | 제목 | 안내서 | HOST | RTL_SIM | SYNTH_TIMING | TIMING_SIM | BOARD |
|---|---|---|---|---|---|---|---|
| 00 | UART Echo | [ch00_uart_echo_v05.html](../ch00_uart_echo_v05.html) | — | ✅ | ⏳ | — | ⏳ |
| 01 | DSP 추론 MAC 누산 | [ch01_mac_v05.html](../ch01_mac_v05.html) | ✅ | ✅ | ⏳ | — | ⏳ |
| 02 | DSP48E1 타깃 곱셈 | [ch02_dsp_v05.html](../ch02_dsp_v05.html) | ✅ | ✅ | ⏳ | — | ⏳ |
| 03 | MAC 2단계 파이프라인 | [ch03_mac_pipeline_v05.html](../ch03_mac_pipeline_v05.html) | ✅ | ✅ | ⏳ | — | ⏳ |
| 04 | BRAM 동기 버퍼 | [ch04_bram_v05.html](../ch04_bram_v05.html) | ✅ | ✅ | ⏳ | — | ⏳ |
| 05 | Fixed-Point Quantizer | [ch05_fixed_v05.html](../ch05_fixed_v05.html) | ✅ | ✅ | ⏳ | — | ⏳ |
| 06 | INT8·INT16 정밀도 비교 | [ch06_precision_v05.html](../ch06_precision_v05.html) | ✅ | ✅ | ⏳ | — | ⏳ |
| 07 | 벡터 내적 | [ch07_vector_dot_v05.html](../ch07_vector_dot_v05.html) | ✅ | ✅ | ⏳ | — | ⏳ |
| 08 | 4PE 병렬 어레이 | [ch08_pe4_v05.html](../ch08_pe4_v05.html) | ✅ | ✅ | ⏳ | — | ⏳ |
| 09 | Dense 4뉴런 레이어 | [ch09_dense_v05.html](../ch09_dense_v05.html) | ✅ | ✅ | ⏳ | — | ⏳ |
| 10 | 4뉴런 NPU Core | [ch10_npu_core_v05.html](../ch10_npu_core_v05.html) | ✅ | ✅ | ⏳ | — | ⏳ |
| 11 | UART 모델 적재 컨트롤러 | [ch11_uart_register_v05.html](../ch11_uart_register_v05.html) | ✅ | ✅ | ⏳ | — | ⏳ |
| 12 | 통합 NPU Top | [ch12_integrated_npu_v05.html](../ch12_integrated_npu_v05.html) | ✅ | ✅ | ⏳ | ⏳ | ⏳ |
| 13 | 8×8 손글씨·10분류 준비 | [ch13_mnist_8x8_v02.html](../ch13_mnist_8x8_v02.html) | ✅ | ✅ | ⏳ | — | ⏳ |
| 14 | 4PE 그룹·10개 출력 | [ch14_group10_v02.html](../ch14_group10_v02.html) | ✅ | ✅ | ⏳ | — | ⏳ |
| 15 | Dense 64→10 공통 블록 | [ch15_dense_64x10_v02.html](../ch15_dense_64x10_v02.html) | ✅ | ✅ | ⏳ | — | ⏳ |
| 16 | 2층 신경망 64→8→10 | [ch16_mlp_64_8_10_v02.html](../ch16_mlp_64_8_10_v02.html) | ✅ | ✅ | ⏳ | — | ⏳ |
| 17 | 784원소 타일 실행 | [ch17_tiled_784_v02.html](../ch17_tiled_784_v02.html) | ✅ | ✅ | ⏳ | — | ⏳ |
| 18 | Float32 · INT8 · INT16 정밀도 | [ch18_precision_v02.html](../ch18_precision_v02.html) | — | ✅ | ⏳ | — | ⏳ |
| 19 | 1·4·8PE 사이클 비교 | [ch19_pe_compare_v02.html](../ch19_pe_compare_v02.html) | — | ✅ | ⏳ | — | ⏳ |
| 20 | AXI4-Lite 레지스터 | [ch20_axi_lite_v02.html](../ch20_axi_lite_v02.html) | — | ✅ | ⏳ | — | ⏳ |
| 21 | MicroBlaze V + NPU 블록 설계 | [ch21_soc_bd_v02.html](../ch21_soc_bd_v02.html) | — | — | ⏳ | ⏳ | ⏳ |
| 22 | Vitis C 드라이버 | [ch22_vitis_driver_v02.html](../ch22_vitis_driver_v02.html) | — | ✅ | ⏳ | — | ⏳ |
| 23 | CPU · NPU 시간 비교 | [ch23_cpu_vs_npu_v02.html](../ch23_cpu_vs_npu_v02.html) | — | — | ⏳ | — | ⏳ |
| 24 | 자원 · 타이밍 · 임계 경로 | [ch24_resource_timing_v02.html](../ch24_resource_timing_v02.html) | — | — | ⏳ | — | ⏳ |
| 25 | 추정 전력 · 에너지 | [ch25_power_energy_v02.html](../ch25_power_energy_v02.html) | — | — | ⏳ | — | ⏳ |
| 26 | 3×3 소형 CNN | [ch26_tiny_cnn_v02.html](../ch26_tiny_cnn_v02.html) | ✅ | ✅ | ⏳ | — | ⏳ |
| 27 | 최종 NPU SoC | [ch27_npu_system_v02.html](../ch27_npu_system_v02.html) | — | ✅ | ⏳ | ⏳ | ⏳ |
| 28 | PC 손글씨 → 보드 분류 | [ch28_handwriting_v02.html](../ch28_handwriting_v02.html) | — | ✅ | ⏳ | — | ⏳ |
| 29 | 센서 유효성 + AI 상태 분류 | [ch29_sensor_ai_v02.html](../ch29_sensor_ai_v02.html) | ✅ | ✅ | ⏳ | — | ⏳ |
| 30 | AI 제안 · 모터 인터록 분리 | [ch30_motor_interlock_v02.html](../ch30_motor_interlock_v02.html) | — | ✅ | ⏳ | — | ⏳ |
| 31 | AES-128·HMAC 보안 UART | chapter.json 대기 | | | | | |
