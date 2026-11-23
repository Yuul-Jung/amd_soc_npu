# Basys3 소형 NPU 교육과정 — 고도화판

[**학습안내서 열기**](index.html)

## 개요

`Yuul-Jung/amd_soc_rtl` 제3부 자료를 기반으로 고도화한 독립 NPU 교육과정입니다.

| 구간 | 장 | 내용 | 상태 |
|---|---|---|---|
| **제1부 선수 과정** | P1 01~11 | [MicroBlaze V 기본 SoC](part01/index.html) — BRAM·Clock/Reset·Memory Map·AXI·GPIO·UART·Timer·INTC·통합·사용자 Top | 안내서 v02 |
| **제2부 (독립)** | P2 00~20 | [사용자 AXI IP와 주변장치](part02/index.html) — LED·FND·버튼·PWM·센서·모터·SPI·I²C·1-Wire·통합 | 안내서 v02 |
| **소형 NPU** | 1장 | [UART 계산기](p01_uart_calc_v01.html) — 곱·누산 코어 세 가지 | 1일 |
| | 2장 | [4뉴런 NPU 보드](p02_npu4_board_v01.html) — BRAM·양자화·내적·4PE·Dense·통합 엔진 | 2일 |
| | 3장 | [8×8 MNIST](p03_mnist8x8_v01.html) — 프레임·10분류 코어·MLP | 2일 |
| | 4장 | [784 가속기](p04_tile784_v01.html) — 13타일 누산·INT8/INT16·PE 비교 | 1일 |
| | 5장 | [MicroBlaze V SoC](p05_mbv_soc_v01.html) — AXI NPU IP·C 드라이버·시간·전력 | 2일 |
| | 6장 | [응용 확장](p06_npu_apps_v01.html) — 손글씨 인식·센서 감시·모터 안전·보안 적재 | 2일 |

## 고도화 내용
- **안내서**: 장 프로젝트 1~6장 (생성기 `tools/guide/build_projects.py`). 검증 현황은 [docs/PROJECT_STATUS.md](docs/PROJECT_STATUS.md)
- **분담**: 코드·Vivado 실행은 VS Code, 안내서 관리는 생성기 — [docs/VSCODE_HANDOFF.md](docs/VSCODE_HANDOFF.md)
- **코드**: 서브젝트 코드는 `chNN/`·`part03/chNN/`, 장 Top은 `pNN/`
- **검증**: 장별 `validation/` 폴더에 시뮬레이션 로그·SHA 관리
- **CI**: GitHub Actions 정적 검사 자동화

## 원본 소스
- 제1부 원본: `Yuul-Jung/amd_soc_rtl/part01/` (019832b) → [`part01/`](part01/) 전체 이관, 안내서는 `python3 tools/guide/build_part.py part01`로 생성 — 편집 기록 [docs/PART01_EDIT_LOG.md](docs/PART01_EDIT_LOG.md)
- 제2부 원본: `Yuul-Jung/amd_soc_rtl/part02_1·part02_2/` (019832b) → [`part02/`](part02/) 전체 이관, `python3 tools/guide/build_part.py part02` — 편집 기록 [docs/PART02_EDIT_LOG.md](docs/PART02_EDIT_LOG.md)
- RTL 원본: [`Yuul-Jung/amd_soc_rtl/part03/`](https://github.com/Yuul-Jung/amd_soc_rtl/tree/main/part03)
- 규칙 기준: `rule_md` 커밋 `d1b8278d`

## 📘 교육용 HTML 공통 제작 규칙

이 저장소의 교육자료(웹페이지·강의 HTML)는 [Yuul-Jung 교육용 HTML 공통 표준](https://github.com/Yuul-Jung/rule_md/tree/d1b8278d41fca8f5e3960736f3ac9d377e462fda/web/education-html)을 적용합니다.

- [제작 규칙](https://github.com/Yuul-Jung/rule_md/blob/d1b8278d41fca8f5e3960736f3ac9d377e462fda/web/education-html/STANDARD.md)
- [다른 저장소 적용 안내](https://github.com/Yuul-Jung/rule_md/blob/d1b8278d41fca8f5e3960736f3ac9d377e462fda/web/education-html/INTEGRATION.md)
- [기준 디자인 사례](https://github.com/Yuul-Jung/ai-agent-engineering)

공통 책장 이미지, 컴팩트한 상단 배너, 좌측 전체 장/절 탐색, 모바일 메뉴, 파일 버전 및 검증 기준을 따릅니다. 기준 커밋은 `d1b8278d`로 고정하며 로컬 사본은 [`rule_md/`](rule_md/)에 있습니다.

## 작업 규칙
- [`AGENTS.md`](AGENTS.md) — AI 에이전트 필수 확인
- [`docs/VSCODE_HANDOFF.md`](docs/VSCODE_HANDOFF.md) — 코드·실행(VS Code)과 안내서 관리 분담
- [MBV SoC 전용 규칙](rule_md/fpga-soc/MBV_SOC_rules.md) · [구조도 규칙](rule_md/common/flowchart-rules.md) · [코드 스타일](rule_md/common/code-style-rules.md)

## 도면
- [svg-flow-editor](https://yuul-jung.github.io/svg-flow-editor/)로 편집하는 JSON이 원본, `python3 tools/diagram/export_svg.py`로 SVG 생성
  - 과정 흐름·모듈 테크트리: `diagrams/` (INDEX 01절)
  - FSM 상태도: `ch10/diagrams/`, `ch11/diagrams/` (각 장 01절)

## 검증 현황
- 장별 게이트(HOST·RTL_SIM·SYNTH_TIMING·TIMING_SIM·BOARD): [`docs/GUIDE_STATUS.md`](docs/GUIDE_STATUS.md) — `validation/` 증거로 자동 생성
- 화면 점검(폭 6종·탐색·복사·SVG): [`docs/RENDER_AUDIT.md`](docs/RENDER_AUDIT.md), 배포본 [`docs/RENDER_AUDIT_PAGES.md`](docs/RENDER_AUDIT_PAGES.md)
- 안내서: <https://yuul-jung.github.io/amd_soc_npu/>
