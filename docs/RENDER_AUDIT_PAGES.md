# 화면 점검 결과 (자동 생성)

`python3 tools/guide/audit_render.py --base https://yuul-jung.github.io/amd_soc_npu/` · 대상: https://yuul-jung.github.io/amd_soc_npu/ · chromium 157.0.8103.78 (Playwright)

검사: 화면 폭 1920·1366·1024·768·390·320px 가로 넘침, 헤더 높이(1366px), 책장 사진·바탕색, 장 탐색, 이전/다음 링크, 390px 모바일 메뉴 열기·Escape 닫기, 코드 복사 버튼 수, 첫 Verilog 박스 복사 원문 일치, SVG 글자 겹침

| 페이지 | 판정 | 근거 |
|---|---|---|
| index.html | 통과 | 헤더 214px · 코드 박스 1 |
| ch00_uart_echo_v05.html | 통과 | 헤더 214px · 코드 박스 14 |
| ch01_mac_v05.html | 통과 | 헤더 214px · 코드 박스 7 |
| ch02_dsp_v05.html | 통과 | 헤더 214px · 코드 박스 7 |
| ch03_mac_pipeline_v05.html | 통과 | 헤더 214px · 코드 박스 7 |
| ch04_bram_v05.html | 통과 | 헤더 214px · 코드 박스 7 |
| ch05_fixed_v05.html | 통과 | 헤더 214px · 코드 박스 7 |
| ch06_precision_v05.html | 통과 | 헤더 214px · 코드 박스 7 |
| ch07_vector_dot_v05.html | 통과 | 헤더 214px · 코드 박스 7 |
| ch08_pe4_v05.html | 통과 | 헤더 214px · 코드 박스 7 |
| ch09_dense_v05.html | 통과 | 헤더 214px · 코드 박스 7 |
| ch10_npu_core_v05.html | 통과 | 헤더 214px · 코드 박스 7 |
| ch11_uart_register_v05.html | 통과 | 헤더 214px · 코드 박스 8 |
| ch12_integrated_npu_v05.html | 통과 | 헤더 214px · 코드 박스 20 |
| ch13_mnist_8x8_v02.html | 통과 | 헤더 214px · 코드 박스 7 |

다른 브라우저 결과: `docs/RENDER_AUDIT*_firefox.md`·`*_webkit.md`. 인쇄·접근성: `docs/A11Y_PRINT_AUDIT.md`.
