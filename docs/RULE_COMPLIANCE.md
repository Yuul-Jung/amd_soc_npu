# rule_md 적용 판정표 — ch00~ch12 학습안내서

기준: `rule_md` 커밋 `d1b8278d` (로컬 사본 `rule_md/`) · 판정 2026-11-18 · 판정어는 flowchart-rules 12절·STANDARD 10.4의 **통과 / 실패 / 미검증 / 해당 없음**.

| 규칙 | 항목 | 판정 | 근거·조치 |
|---|---|---|---|
| STANDARD 2 | 책장 사진 1800×380, 흐림 없음 | 통과 | `assets/education/hero-bookshelf.jpg` = rule_md `d1b8278d` 원본(1800×380, EXIF 없음). 외부 주소 의존 제거 |
| STANDARD 2 | 헤더 높이 160~220px | 통과 | 1366px에서 214px (`docs/RENDER_AUDIT.md`) |
| STANDARD 2 | 바탕 `#F1F2EE`·강조 `#4635B1`·글꼴 IBM Plex | 통과 | `site.css` 변수, 렌더 점검에서 바탕색 확인 |
| STANDARD 3 | 절 00·01… 번호, 빈 절·장식 섹션 없음 | 통과 | 생성기 10절 고정. index 장식 칩 제거 |
| STANDARD 3 | 코드 언어 명시, 예상 출력은 코드와 분리 | 통과 | 코드 박스 `파일 · 언어 · 상태`, 05절 기대 출력 별도 박스 |
| STANDARD 3 · MBV 5 | 소스/신호 이름과 구조도 일치 | 통과 | 구조도·포트 표를 RTL 선언에서 자동 생성, FSM 표는 생성기가 `localparam`과 대조 |
| STANDARD 4 | 좌측 장·절 탐색, 모바일 메뉴, Escape, 이전/다음/INDEX | 통과 | 렌더 점검 14페이지 (390px 메뉴 열기·Escape 닫기 포함) |
| STANDARD 4·10.3 | 코드 복사가 실제 소스만 복사 | 통과 | 렌더 점검: 첫 Verilog 박스 클립보드 = `pre` 원문 |
| STANDARD 5.2 | Ubuntu 명령에 기능 설명 | 통과 | 실행 명령마다 `# 기능` 주석 (`run_note`) |
| STANDARD 5.3 | 사족 배제 | 통과 | 설명 문단 → 표(포트·판정·코드 읽기) |
| STANDARD 6 | 파일명 `_vNN`, 구버전 삭제, `course.json` 사이트 v02 | 통과 | 생성기가 같은 장 이전 버전 삭제 |
| STANDARD 7 | 실행 검증 로그 보유 표시 | 통과 | 05절 출처 경로, 09절 게이트 = `validation/` 증거 |
| STANDARD 7 | 계정·토큰·내부 경로 미노출 | 통과 | 로그 `<repo>` 치환, 생성물에 `/home`·`/root`·`/tmp` 없음(검사) |
| STANDARD 7 | GitHub Pages 실제 배포 확인 | 통과 | `docs/RENDER_AUDIT_PAGES.md` (배포본 점검) |
| STANDARD 9 · INTEGRATION 2·5 | README·AGENTS에 중앙 규칙 링크(SHA 고정) | 통과 | README "교육용 HTML 공통 제작 규칙" 절, AGENTS 기준 목록 |
| STANDARD 10.1 | 폭 1920·1366·1024·768·390·320 가로 넘침 없음 | 통과 | 렌더 점검. 표는 가로 스크롤 영역, 긴 경로 줄바꿈 |
| STANDARD 10.2 | 다크 테마·인쇄 | 해당 없음 / 미검증 | 교육용은 밝은 테마 고정. 인쇄 미검증 |
| STANDARD 10.3 | 유지보수용 CSS·JS는 들여쓰기·주석 원본, 배포용 압축본 별도 | 실패 | `assets/education/site.css`·`site.js`가 압축본만 있음(원본 저장소에서 이관). 정본 템플릿 원본을 받아 별도 보관 필요 |
| STANDARD 10.4 | 본문 바로가기·초점 표시·reduced-motion | 통과 | 바로가기는 Tab 초점 때만 표시, `:focus-visible`, `prefers-reduced-motion` |
| STANDARD 10.4 | JS 없이 본문 읽힘 | 통과 | 본문·코드·표는 정적 HTML, JS는 탐색·복사만 |
| STANDARD 10.4 | 스크린리더 실제 낭독, Safari·Firefox | 미검증 | Chromium만 점검 |
| flowchart 1.3 | 구현 도식/개념 도식 구분 | 통과 | 구조도 제목 줄 "구현 도식" |
| flowchart 1.4·8.2 | 없는 전이를 그리지 않음 | 통과 | 상태를 화살표 없이 나열, 전이는 `case(state)` 기준 표(10·11장) |
| flowchart 8.2 | 상태도(SVG) | 미검증 | 전이표로 대체. 상태도 SVG는 미제작 |
| flowchart 5 | 라벨 = 실제 코드명 + 한글 설명 | 통과 | 13장 모든 Top 포트 한글 설명, 누락 시 생성 실패 |
| flowchart 8.3 | 클록·리셋 구분, 보드 핀/내부 신호 구분 | 통과 | 점선 화살표 = 클록·리셋, 12장 "Basys3 외부 핀"·핀 번호 |
| flowchart 11.2 | 글자·선 겹침 없음 | 통과 | 렌더 점검의 SVG 글자 상자 교차 검사 |
| code-style 1 | 검증된 원본 코드 무수정 | 통과 | 안내서 코드 = 저장소 파일 원문(일치 검사), RTL 미수정 |
| code-style 10.2 | 코드 박스 파일명·언어·원본/검증 상태 | 통과 | 예: `ch01/rtl/mac_core.v · verilog · 원본 · RTL_SIM 통과 2026-11-18`, Vivado 스크립트는 `⚠ 미검증` |
| MBV 6 · code-dev 5 | 호스트·RTL 시뮬·Vivado·보드 구분, 미실행은 미검증 | 통과 | 게이트 6종 분리, SYNTH_TIMING·TIMING_SIM 실행 대기, BOARD 미실시 |
| methodology ① | 원자 커밋·Co-Authored-By | 통과 | 커밋 이력 |

## 남은 실패·미검증

1. **STANDARD 10.3 (실패):** 공통 CSS·JS 유지보수용 원본. 정본 `rule_md` 템플릿에는 자산이 포함되지 않으므로(SOURCE.md 범위), 기준 디자인 저장소(`ai-agent-engineering`)의 원본을 확인해 `assets/education/src/`에 보관하는 작업이 필요하다.
2. **flowchart 8.2 (미검증):** 10·11장 FSM 상태도 SVG.
3. **STANDARD 10.2·10.4 (미검증):** 인쇄, 스크린리더, Safari·Firefox.
