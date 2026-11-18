# amd_soc_npu 제작·검증 필수 규칙

## 저장소 목적
`Yuul-Jung/amd_soc_rtl` 제3부(소형 NPU·MicroBlaze V·종합 과제) 자료를 고도화한 독립 NPU 교육과정.
00~12장 RTL 품질 향상 + 13~31장 RTL 신규 구현 + 전 장 HTML v04 이상 업그레이드가 핵심 작업.

## 원본·작업 경계
- 원본 `Yuul-Jung/amd_soc_rtl`은 **절대 변경하지 않는다**.
- 각 장의 RTL·TB·HTML 개선은 버전 접미사(`_v04.html`, `_v02.html`)로 구분한다.
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
├── assets/education/   ← site.css · site-theme.css · site.js (공통)
├── rule_md/            ← 중앙 규칙 사본
├── docs/               ← 내부 감사·검증 기록
├── tools/              ← 정적 검사·SHA 확인 스크립트
├── host_tools/         ← Python 기준 정수 모델
├── .github/workflows/  ← CI (정적 검사·RTL 시뮬레이션)
└── ch{NN}/             ← 장별 디렉터리
    ├── rtl/            ← Verilog/SystemVerilog 소스
    ├── tb/             ← 테스트벤치
    ├── reference/      ← Python 기준 모델
    ├── scripts/        ← run_sim.sh
    ├── validation/     ← 시뮬레이션 로그·SHA
    └── docs/README.md  ← 장 개요
```

## HTML 교재 제작
- STANDARD.md: 책장 사진 1800×380, `#F1F2EE` 바탕, `#4635B1` 강조, 좌측 탐색, 860px 모바일 메뉴, 이전/다음/INDEX.
- 버전 규칙: ch00~ch12는 v04부터, ch13~ch31은 v02부터 시작.
- 원본에 없는 하드웨어 실행 결과·GUI 캡처를 성공 사례처럼 조작하지 않는다.
- 미검증 항목은 `⚠ 미검증` 뱃지를 명시한다.

## 검증 게이트 (각 장 독립)
| 게이트 | 의미 |
|---|---|
| `HTML_PASS` | 링크·탐색·모바일·코드복사 정상 |
| `HOST_MODEL_PASS` | Python 기준 정수 모델 단위 시험 통과 |
| `RTL_SIM_PASS` | Icarus/Verilator RTL 시뮬레이션 통과 |
| `SYNTH_TIMING_PASS` | Vivado 합성·타이밍 통과 |
| `BOARD_PASS` | 실물 Basys3 동작 확인 |

- 위 게이트는 서로 대체할 수 없다.
- 각 장 `validation/` 폴더에 증거 파일을 보관한다.

## 동결 SoC 하드웨어 사양 (ch20~ch31 AXI 연동 기준)
로컬메모리 0x0000_0000 · GPIO LED/SW 0x4000_0000 · GPIO BTN 0x4001_0000
UART Lite 0x4002_0000 · Timer 0x4003_0000 · INTC 0x4004_0000
IIC 0x4005_0000 · SEG7 0x4006_0000
클록 100 MHz · 리셋 btnC(Active-High) · UART 115200 bps

## 커밋 원칙
- 원본 보존과 신규/수정 콘텐츠는 별도 원자 커밋.
- 민감 정보·개인 경로·토큰은 공개 산출물에 포함 불가.

작업 기준 시점: 2026-11-18. 중앙 규칙 커밋: `d1b8278d41fca8f5e3960736f3ac9d377e462fda`.
