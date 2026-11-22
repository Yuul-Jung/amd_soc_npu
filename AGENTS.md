# amd_soc_npu 제작·검증 필수 규칙

## 저장소 목적
`Yuul-Jung/amd_soc_rtl` 제3부(소형 NPU·MicroBlaze V·종합 과제) 자료를 고도화한 독립 NPU 교육과정.
00~12장 RTL 품질 향상 + 13~31장 RTL 신규 구현 + 전 장 HTML v04 이상 업그레이드가 핵심 작업.

## 원본·작업 경계
- 원본 `Yuul-Jung/amd_soc_rtl`은 **절대 변경하지 않는다**.
- 각 장의 RTL·TB·HTML 개선은 버전 접미사(00~12장 `_v05.html`, 13~31장 `_v02.html`)로 구분하고, 버전을 올리면 이전 파일은 삭제한다(이력은 Git).
- `index.html`은 GitHub Pages 진입점으로 항상 유지한다.
- 기존 ch00~ch12 RTL(이미 시뮬레이션 로그 보유)은 최소 수정 원칙: 버그 수정·주석 보강·파라미터화만 허용.

## 반드시 읽을 기준 (우선순위)
1. 실제 실행 증거·공식 기술 사양·개인정보 보호.
2. [교육용 HTML 고정 표준](https://github.com/Yuul-Jung/rule_md/blob/d1b8278d41fca8f5e3960736f3ac9d377e462fda/web/education-html/STANDARD.md).
3. [규칙 적용 절차](https://github.com/Yuul-Jung/rule_md/blob/d1b8278d41fca8f5e3960736f3ac9d377e462fda/web/education-html/INTEGRATION.md).
4. [공통 코드 작성 규칙](https://github.com/Yuul-Jung/rule_md/blob/d1b8278d41fca8f5e3960736f3ac9d377e462fda/code/code-development-rules.md), [공통 코드 스타일](https://github.com/Yuul-Jung/rule_md/blob/d1b8278d41fca8f5e3960736f3ac9d377e462fda/common/code-style-rules.md).
5. [FPGA/SoC 상세 규칙](https://github.com/Yuul-Jung/rule_md/blob/d1b8278d41fca8f5e3960736f3ac9d377e462fda/fpga-soc/MBV_SOC_rules.md), [구조도 규칙](https://github.com/Yuul-Jung/rule_md/blob/d1b8278d41fca8f5e3960736f3ac9d377e462fda/common/flowchart-rules.md).
6. [프로젝트 내부 규칙 사본](rule_md/AGENTS.md). 상위 HTML 표준과 충돌하면 HTML 표준 우선.

## 디렉터리 구조
```
amd_soc_npu/
├── AGENTS.md           ← 이 파일 (AI 에이전트 필수 확인)
├── README.md
├── index.html          ← GitHub Pages 진입점
├── course.json         ← 장별 메타데이터
├── assets/education/   ← site.css · site.js (공통, 들여쓰기·주석 원본) · hero-bookshelf.jpg
├── rule_md/            ← 중앙 규칙 사본
├── diagrams/           ← 과정 흐름·모듈 테크트리 도면 (svg-flow-editor JSON·SVG)
├── docs/               ← 내부 감사·검증 기록
├── tools/              ← 정적 검사 · guide/(안내서 생성기) · diagram/(상태도 SVG) · vivado/(OOC 합성)
├── part01/            ← 제1부 MicroBlaze V 기본 SoC (amd_soc_rtl/part01 이관: legacy/·chapters/·files/ 원본 보존, p1_*_v02.html·index.html은 생성물)
├── host_tools/         ← Python 기준 정수 모델
├── .github/workflows/  ← CI (정적 검사·RTL 시뮬레이션)
└── ch{NN}/             ← 장별 디렉터리
    ├── rtl/            ← Verilog/SystemVerilog 소스
    ├── tb/             ← 테스트벤치
    ├── reference/      ← Python 기준 모델
    ├── scripts/        ← run_sim.sh
    ├── validation/     ← 시뮬레이션·Vivado 증거 (rtl_sim_*, vivado_ooc_*, vivado_impl_timesim_*, board_*)
    ├── chapter.json    ← 안내서 내용의 단일 원본
    ├── diagrams/       ← svg-flow-editor 도면 JSON(원본)·SVG(산출물)
    └── docs/README.md  ← 장 개요
```

## HTML 교재 제작
- STANDARD.md: 책장 사진 1800×380, `#F1F2EE` 바탕, `#4635B1` 강조, 좌측 탐색, 860px 모바일 메뉴, 이전/다음/INDEX.
- 버전 규칙: ch00~ch12는 현재 v05(실습 절차형), ch13~ch31은 v02부터 시작.
- **장 = 프로젝트 = HTML 1개, 서브젝트 = 장 안의 절** (개편 설계 [docs/PROJECT_PLAN.md](docs/PROJECT_PLAN.md), 2026-11-19 확정). 장마다 보드 Top 하나가 자라고 장 끝에서 보드 시연한다. 서브젝트 코드·증거 폴더는 `chNN/` 그대로 쓰고 화면에는 "3-2 그룹·argmax (구 14장)"로 표시한다.
- 장 페이지 절 구성: 00 장 목표·진행 위치(보드 시연 한 줄, 진행 막대) → 01 최종 구조도·가져오는 파일 → 02 준비 → 서브젝트 절 n-1…n-k (각: 보드에서 볼 것 · 추가 코드 · 시뮬레이션 기대 화면 · 판정 줄) → 장 시연 → 누적 보고·인계. 설명 문단은 최소화한다.
- 서브젝트의 학습목표는 "보드에서 무엇을 넣으면 무엇이 보이는가" 한 줄로 쓰고, 보드 확인은 서브젝트마다(최소 하루 2번) 한다.
- (개편 전 장 단위 v05·v02 안내서와 절 구성 00~09는 브랜치 `archive/v02-ch00-31`에 보관)
- **안내서 HTML·`index.html`·`docs/GUIDE_STATUS.md`는 직접 수정하지 않는다.** 내용은 `chNN/chapter.json`, 코드는 원본 파일, 게이트 배지는 `validation/` 증거에서 `python3 tools/guide/build_guides.py`가 만든다. CI가 `--check`로 어긋남을 막는다.
- 역할 분담: 코드·실행·증거·`chapter.json`은 VS Code Claude, 생성기·안내서 관리는 웹 Claude. 상세는 [docs/VSCODE_HANDOFF.md](docs/VSCODE_HANDOFF.md).
- 제1부(`part01/`) 안내서·INDEX와 편집 기록 `docs/PART01_EDIT_LOG.md`는 `python3 tools/part01/build_part01.py`가 원본 페이지(`part01/legacy/pages/soc/`, `part01/chapters/`)와 `part01/course.json`에서 만든다. 원본 페이지는 고치지 않는다. 배포 본문에는 제작·검증 메모(검증 완료·실기·계측·출처·원본 등)를 넣지 않고 생성기가 걸러내며, 그림·표·코드 개수가 원본과 다르면 생성기가 실패한다(CI `--check`).
- `window.COURSE` 탐색에는 실제 존재하는 장 파일만 넣는다.
- 구조도는 실제 RTL 선언에서 자동 생성하는 **구현 도식**이다. 포트 한글 설명(`port_notes`)과 FSM 전이표(`fsm`)는 `chapter.json`에 쓰고 생성기가 코드와 대조한다. FSM 상태도(`chNN/diagrams/`)와 과정 흐름·모듈 테크트리(`diagrams/`)는 [svg-flow-editor](https://github.com/Yuul-Jung/svg-flow-editor) JSON이 원본이며 `tools/diagram/export_svg.py`로 SVG를 만든다. 각 장 09절에 part03 규칙 5절 누적 보고 표를 둔다. 규칙별 판정은 [docs/RULE_COMPLIANCE.md](docs/RULE_COMPLIANCE.md), 화면 점검은 `tools/guide/audit_render.py`.
- 원본에 없는 하드웨어 실행 결과·GUI 캡처를 성공 사례처럼 조작하지 않는다.
- 미검증 항목은 `⚠ 미검증` 뱃지를 명시한다.

## 검증 게이트 (각 장 독립)
| 게이트 | 의미 |
|---|---|
| `HTML_PASS` | 링크·탐색·모바일·코드복사 정상 |
| `HOST_MODEL_PASS` | Python 기준 정수 모델 단위 시험 통과 |
| `RTL_SIM_PASS` | Icarus/Verilator RTL 시뮬레이션 통과 |
| `SYNTH_TIMING_PASS` | Vivado 합성·배치·배선 후 WNS≥0·WHS≥0 (00~10장 OOC 100 MHz, 12장 통합 Top + DRC 0) |
| `TIMING_SIM_PASS` | 12장 배선 후 넷리스트 + SDF(slow) xsim 시뮬레이션 통과 |
| `BOARD_PASS` | 실물 Basys3 동작 확인 |

- 위 게이트는 서로 대체할 수 없다.
- 각 장 `validation/` 폴더에 증거 파일을 보관한다.
- Vivado 게이트는 Vivado 설치 PC(VS Code)에서 `bash tools/run_vivado_all.sh`로 실행하고, 생성된 `validation/vivado_*` 파일을 커밋해야 확정한다. 오픈소스 도구 결과로 대체하지 않는다.
- 현재 실물 보드 확인은 하지 않는다(`BOARD_PASS` 미실시 표기).

## 동결 SoC 하드웨어 사양 (5·6장 = 구 ch20~ch31 AXI 연동 기준, 안 A 확정)
로컬메모리 0x0000_0000 · GPIO LED/SW 0x4000_0000 · GPIO BTN 0x4001_0000
UART Lite 0x4002_0000 · Timer 0x4003_0000 · INTC 0x4004_0000
IIC 0x4005_0000 · SEG7 0x4006_0000
클록 100 MHz · 리셋 btnC(Active-High) · UART 115200 bps

## 커밋 원칙
- 원본 보존과 신규/수정 콘텐츠는 별도 원자 커밋.
- 민감 정보·개인 경로·토큰은 공개 산출물에 포함 불가.

작업 기준 시점: 2026-11-18. 중앙 규칙 커밋: `d1b8278d41fca8f5e3960736f3ac9d377e462fda`.
