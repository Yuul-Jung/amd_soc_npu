# 제1부 이관·변환 점검 기록 (자동 생성)

원본: `Yuul-Jung/amd_soc_rtl part01 @ 019832bf1e400e3ddc778be8402f584687eefdea` → `part01/` (원본 파일은 그대로 보존, 개인 경로만 `~`로 치환).
생성: `python3 tools/part01/build_part01.py` — 직접 수정하지 않는다.

## 장별 요소 개수 (원본 <main> → 새 안내서 본문)

그림 누락 방지를 위해 img·figure·svg·pre·table·section·details 개수가 같아야 생성기가 통과한다.

| 장 | 새 파일 | img | figure | svg | pre | table | section | details | 개요 카드 | 판정 |
|---|---|---|---|---|---|---|---|---|---|---|
| 01 | [p1_01_microblaze_bram_v01.html](../part01/p1_01_microblaze_bram_v01.html) | 4→4 | 4→4 | 0→0 | 1→1 | 8→8 | 14→14 | 0→0 | 3 | 통과 |
| 02 | [p1_02_clock_reset_v01.html](../part01/p1_02_clock_reset_v01.html) | 1→1 | 1→1 | 0→0 | 2→2 | 8→8 | 12→12 | 0→0 | 3 | 통과 |
| 03 | [p1_03_bram_program_v01.html](../part01/p1_03_bram_program_v01.html) | 13→13 | 13→13 | 0→0 | 1→1 | 13→13 | 21→21 | 0→0 | 3 | 통과 |
| 04 | [p1_04_memory_map_v01.html](../part01/p1_04_memory_map_v01.html) | 0→0 | 3→3 | 3→3 | 1→1 | 13→13 | 16→16 | 0→0 | 3 | 통과 |
| 05 | [p1_05_axi_v01.html](../part01/p1_05_axi_v01.html) | 3→3 | 3→3 | 0→0 | 0→0 | 11→11 | 14→14 | 0→0 | 3 | 통과 |
| 06 | [p1_06_axi_gpio_v01.html](../part01/p1_06_axi_gpio_v01.html) | 18→18 | 18→18 | 0→0 | 9→9 | 18→18 | 17→17 | 2→2 | 3 | 통과 |
| 07 | [p1_07_axi_uartlite_v01.html](../part01/p1_07_axi_uartlite_v01.html) | 43→43 | 43→43 | 0→0 | 5→5 | 13→13 | 30→30 | 6→6 | 3 | 통과 |
| 07.1 | [p1_07_1_uart_echo_c_v01.html](../part01/p1_07_1_uart_echo_c_v01.html) | 1→1 | 1→1 | 0→0 | 9→9 | 9→9 | 12→12 | 0→0 | 3 | 통과 |
| 08 | [p1_08_axi_timer_v01.html](../part01/p1_08_axi_timer_v01.html) | 36→36 | 36→36 | 0→0 | 1→1 | 9→9 | 23→23 | 0→0 | 0 | 통과 |
| 08.1 | [p1_08_1_timer_c_v01.html](../part01/p1_08_1_timer_c_v01.html) | 0→0 | 0→0 | 0→0 | 12→12 | 3→3 | 14→14 | 0→0 | 3 | 통과 |
| 09 | [p1_09_axi_intc_v01.html](../part01/p1_09_axi_intc_v01.html) | 32→32 | 32→32 | 0→0 | 3→3 | 13→13 | 35→35 | 0→0 | 0 | 통과 |
| 09.1 | [p1_09_1_intc_c_v01.html](../part01/p1_09_1_intc_c_v01.html) | 0→0 | 0→0 | 0→0 | 12→12 | 0→0 | 12→12 | 0→0 | 3 | 통과 |
| 10 | [p1_10_integration_v01.html](../part01/p1_10_integration_v01.html) | 8→8 | 8→8 | 0→0 | 2→2 | 14→14 | 29→29 | 0→0 | 0 | 통과 |
| 10.1 | [p1_10_1_integration_c_v01.html](../part01/p1_10_1_integration_c_v01.html) | 0→0 | 0→0 | 0→0 | 20→20 | 0→0 | 20→20 | 0→0 | 3 | 통과 |
| 11 | [p1_11_user_top_v01.html](../part01/p1_11_user_top_v01.html) | 0→0 | 0→0 | 0→0 | 4→4 | 5→5 | 6→6 | 0→0 | 0 | 통과 |

## 링크

- 깨진 상대 링크: 0개
- 제1부 장끼리의 링크는 새 안내서로, `code/`·`docs/`·`validation/` 텍스트 파일은 원본과 같이 UTF-8 소스 보기로 연결.
- `github.com/Yuul-Jung/soc/blob/…/MicroBlaze_V_SoC01_41/…` 링크는 이관본(`part01/legacy/…`)으로 바꿈.

- 보존본 안의 알려진 깨짐 1건: `part01/legacy/pages/soc/ch01_microblaze_bram_v01.html`(amd_soc_rtl의 01장 시범판)은 amd_soc_rtl 최상위 `assets/education/site-theme.css`를 가리켜 이 저장소에서는 공통 스타일 없이 보인다. 새 안내서 `p1_01_microblaze_bram_v01.html`이 대체하므로 원본은 고치지 않았다.

## 미검증

- ⚠ 미검증: 원본 GUI 캡처 이미지 안의 화면 글자(창 제목의 사용자 경로 등)는 자동 점검 대상이 아님.
- ⚠ 미검증: Vivado·Vitis·보드 재실행 없음 — 원본 기록만 옮김.
