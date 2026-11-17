# 제1부·제2부 학습안내서 공통 HTML 재편집 계획

## 현재 복사 확정
- 제1부 `soc/MicroBlaze_V_SoC01_41` → `part01/legacy/`: 1,393/1,393 Git Blob SHA 일치.
- 제2부 01~10장 + 원본 배포 교재 → `part02_1/`: 507/507 Git Blob SHA 일치.
- 제2부 11~20장 + 통합 교재 → `part02_2/`: 147/147 Git Blob SHA 일치.
- 이 숫자는 **원본 대 사본 무결성만 확인**한 결과이며 웹 표시·Vivado·Vitis·보드 검증은 포함하지 않음.

## 고정 기술 흐름
제1부 01~10장(AMD 제공 IP 기반 CPU/BRAM/AXI) → 제1부 11장(P1-11 사용자 Top + SW0/LED0) → 제2부 P2-01(11장 SoC 복제 후 사용자 AXI LED IP 연결) → P2-02~20(주변장치·센서·통합). 구 41장 11절과 신편 P1-11 혼용 금지.

## HTML 표준 및 수정 범위
- 기본: [표준](https://github.com/Yuul-Jung/rule_md/blob/d1b8278d41fca8f5e3960736f3ac9d377e462fda/web/education-html/STANDARD.md), [연동](https://github.com/Yuul-Jung/rule_md/blob/d1b8278d41fca8f5e3960736f3ac9d377e462fda/web/education-html/INTEGRATION.md).
- 페이지: 책장 이미지, 좌측 240px 목차, 밝은 테마, 모바일 서랍, 현재 장/절 활성화, 이전/다음/INDEX, 코드 복사, 접근성.
- 원본 내용: 실제 C·RTL 코드, GUI 단계, 표·그림·인용·검증 상태를 보존. 기존 HTML을 Markdown으로 강제 변환하다 SVG/상호작용이 소실되면 안 됨.
- 파일명: 교재 배포 결과 `chNN_topic_v02.html`처럼 버전업, 원본 HTML은 보호; `index.html`은 진입점으로 유지.
- `rule_md` 중앙 표준에 직접 기능을 덧씌우지 않고 `amd_soc_rtl`에서 적용한다.

## 장별 제작 게이트
1. 기존 HTML·코드·이미지·소스 파일 대조 → 변경 금지 대상 표시.
2. 페이지 템플릿과 장·절 내비게이션 적용 → 재사용 가능한 CSS/JS 연결.
3. 본문 원문을 훼손하지 않은 새 교재 버전 생성.
4. 텍스트·표·그림·코드/연결 명칭 대조.
5. 내부 링크·이미지·데이터 파일 확인, 320/390/768/1024/1366/1920 화면 및 키보드 탐색 검사.
6. 원본 교재와 신규 HTML 비교 후 승인된 장만 INDEX 전환.
7. RTL TB/AXI SIM, Vivado 합성, Vitis 컴파일, 실물 검증은 별도 결과로 기록.

## 작업 단계
- A. 정책 등록·공통 템플릿 분리, 메인/제1부/제2부 INDEX 우선 정돈.
- B. 제1부 01~10장(보조 07.1~10.1 포함) 및 P1-11 디자인 통일, 원본 유지.
- C. 제2부 01~10장 디자인 통일; 명령 `LED ON`/`LED OFF`/`STATUS`, AXI 규격·원본 코드 고정.
- D. 제2부 11~20장 및 12.1~12.4 실습 디자인 통일.
- E. 전 장 통합 링크·이미지·코드·공개 안전 점검과 실제 웹 배포 확인.

완료 기준: 코드를 재작성한 사실이 아닌, 전 장 교재의 시각·내용·링크·탐색 동작을 원본과 대조하고 검사한 증거.

## 이번 변경 단계별 확인 기록 (2026-11-17)

- 기본 정책·작성 규칙: `AGENTS.md`, `rule_md` 기준 커밋 고정.
- 공통 교육형 CSS·JS: `assets/education/site.css`, `site.js`, `site-theme.css`. 상단 책장 사진은 중앙 `rule_md`의 공개 원본 URL 참조이며 브라우저 로드 검증 미완료.
- 학습 목차 5개: `index.html`, `part01/index.html`, `part02/index.html`, `part02_1/index.html`, `part02_2/index.html`.
- 다섯 목차에 대해 GitHub 파일 존재 기준 내부 링크 **78/78개** 확인. 브라우저 UI/모바일/코드복사는 미실행.
- 제1부 01장 시범 재편집: `part01/legacy/pages/soc/ch01_microblaze_bram_v01.html`; 원본 HTML은 그대로 보존. 본문 section 14개·pre 1개 보존, 정적 상대 링크 17/17개 파일 존재 확인.
- 제2부 01장 시범 재편집: `part02_1/ch01_axi_led_v01.html`; 원본 HTML은 그대로 보존. 원본 section 20개 + 선수학습 section 1개, pre 7개 보존, 정적 상대 링크 6/6개 파일 존재 확인.
- 원본 01~10장 교재·11장·제2부 전체 장별 신규 버전 제작은 **미완료**. 시범 페이지는 실브라우저 레이아웃·기능 검증이 끝날 때까지 INDEX 정본 링크로 전환하지 않는다.
- Vivado/Vitis 합성·소프트웨어 빌드·보드 실물 검증은 새로 실행하지 않았다.
