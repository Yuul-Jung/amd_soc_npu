# 화면 점검 결과 (자동 생성)

`python3 tools/guide/audit_render.py --browser webkit` · 대상: 로컬 파일 · webkit 26.6 (Playwright)

검사: 화면 폭 1920·1366·1024·768·390·320px 가로 넘침, 헤더 높이(1366px), 책장 사진·바탕색, 장 탐색, 이전/다음 링크, 390px 모바일 메뉴 열기·Escape 닫기, 코드 복사 버튼 수, SVG 글자 겹침

| 페이지 | 판정 | 근거 |
|---|---|---|
| index.html | 통과 | 헤더 213px · 코드 박스 1 |
| ch00_uart_echo_v05.html | 통과 | 헤더 213px · 코드 박스 14 |
| ch01_mac_v05.html | 통과 | 헤더 213px · 코드 박스 7 |
| ch02_dsp_v05.html | 통과 | 헤더 213px · 코드 박스 7 |
| ch03_mac_pipeline_v05.html | 통과 | 헤더 213px · 코드 박스 7 |
| ch04_bram_v05.html | 통과 | 헤더 213px · 코드 박스 7 |
| ch05_fixed_v05.html | 통과 | 헤더 213px · 코드 박스 7 |
| ch06_precision_v05.html | 통과 | 헤더 213px · 코드 박스 7 |
| ch07_vector_dot_v05.html | 통과 | 헤더 213px · 코드 박스 7 |
| ch08_pe4_v05.html | 통과 | 헤더 213px · 코드 박스 7 |
| ch09_dense_v05.html | 통과 | 헤더 213px · 코드 박스 7 |
| ch10_npu_core_v05.html | 통과 | 헤더 213px · 코드 박스 7 |
| ch11_uart_register_v05.html | 통과 | 헤더 213px · 코드 박스 8 |
| ch12_integrated_npu_v05.html | 통과 | 헤더 213px · 코드 박스 20 |
| ch13_mnist_8x8_v02.html | 통과 | 헤더 213px · 코드 박스 9 |
| ch14_group10_v02.html | 통과 | 헤더 213px · 코드 박스 7 |
| ch15_dense_64x10_v02.html | 통과 | 헤더 213px · 코드 박스 9 |
| ch16_mlp_64_8_10_v02.html | 통과 | 헤더 213px · 코드 박스 8 |
| ch17_tiled_784_v02.html | 통과 | 헤더 213px · 코드 박스 7 |
| ch18_precision_v02.html | 통과 | 헤더 213px · 코드 박스 10 |
| ch19_pe_compare_v02.html | 통과 | 헤더 213px · 코드 박스 7 |
| ch20_axi_lite_v02.html | 통과 | 헤더 213px · 코드 박스 6 |
| ch21_soc_bd_v02.html | 통과 | 헤더 213px · 코드 박스 7 |
| ch22_vitis_driver_v02.html | 통과 | 헤더 213px · 코드 박스 16 |
| ch23_cpu_vs_npu_v02.html | 통과 | 헤더 213px · 코드 박스 9 |
| ch24_resource_timing_v02.html | 통과 | 헤더 213px · 코드 박스 6 |
| ch25_power_energy_v02.html | 통과 | 헤더 213px · 코드 박스 6 |
| ch26_tiny_cnn_v02.html | 통과 | 헤더 213px · 코드 박스 7 |
| ch27_npu_system_v02.html | 통과 | 헤더 213px · 코드 박스 16 |
| ch28_handwriting_v02.html | 통과 | 헤더 213px · 코드 박스 15 |
| ch29_sensor_ai_v02.html | 통과 | 헤더 213px · 코드 박스 7 |
| ch30_motor_interlock_v02.html | 통과 | 헤더 213px · 코드 박스 7 |
| ch31_secure_frame_v02.html | 통과 | 헤더 213px · 코드 박스 11 |

다른 브라우저 결과: `docs/RENDER_AUDIT*_firefox.md`·`*_webkit.md`. 인쇄·접근성: `docs/A11Y_PRINT_AUDIT.md`.
