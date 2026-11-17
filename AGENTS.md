# amd_soc_rtl 제작·검증 필수 규칙

## 원본·작업 경계
- 원본 `Yuul-Jung/soc` 및 `Yuul-Jung/amd_soc`는 **절대 변경하지 않는다**.
- 이 저장소의 `part01/legacy/`는 제1부 01~10장의 **정본 복사본**이다. 이름이 'legacy'라도 폐기 대상이 아니다.
- 기존 HTML·이미지·RTL·C·XDC·테스트벤치의 **내용과 상대경로는 먼저 보존**한다.
- 신편 제1부 11장(`part01/chapters/`와 `part01/files/p1_11/`)은 01~10장의 후속이고, 제2부는 P1-11의 SoC를 시작점으로 삼는다.
- 원본 구 41장 교재의 제11장과 신편 P1-11은 다르다. 합쳐서 번호를 변경하지 않는다.

## 반드시 읽을 기준 (우선순위)
1. 실제 실행 증거·공식 기술 사양·개인정보 보호.
2. [교육용 HTML 고정 표준](https://github.com/Yuul-Jung/rule_md/blob/d1b8278d41fca8f5e3960736f3ac9d377e462fda/web/education-html/STANDARD.md).
3. [규칙 적용 절차](https://github.com/Yuul-Jung/rule_md/blob/d1b8278d41fca8f5e3960736f3ac9d377e462fda/web/education-html/INTEGRATION.md).
4. [공통 코드 작성 규칙](https://github.com/Yuul-Jung/rule_md/blob/d1b8278d41fca8f5e3960736f3ac9d377e462fda/code/code-development-rules.md), [공통 코드 스타일](https://github.com/Yuul-Jung/rule_md/blob/d1b8278d41fca8f5e3960736f3ac9d377e462fda/common/code-style-rules.md).
5. [FPGA/SoC 상세 규칙](https://github.com/Yuul-Jung/rule_md/blob/d1b8278d41fca8f5e3960736f3ac9d377e462fda/fpga-soc/MBV_SOC_rules.md), [구조도 규칙](https://github.com/Yuul-Jung/rule_md/blob/d1b8278d41fca8f5e3960736f3ac9d377e462fda/common/flowchart-rules.md).
6. [프로젝트 내부 규칙 사본](rule_md/AGENTS.md). 상위 HTML 표준과 충돌하면 HTML 표준 우선.

## HTML 교재 제작
- `STANDARD.md`의 책장 사진 1800×380, 밝은 바탕 #F1F2EE, 보라색 #4635B1, 좌측 장/절 탐색, 860px 이하 모바일 메뉴, 이전/다음/INDEX, 접근성·코드복사·버전 규칙을 준수.
- 먼저 정본 원고와 그림·파일별 SHA, 코드·표·본문·링크를 읽고, 배포용 교재의 **기능과 디자인만 필요한 만큼 개선**한다.
- 장별 새 결과물은 `chNN_topic_vNN.html`로 버전 구분하고 `index.html`은 고정한다. 원본 교재는 변경 없이 보존하며 새 결과물 검증 후 링크를 전환한다.
- 원본에 없는 코드·GUI 스크린샷·하드웨어 실행 결과를 생성해 실제 성공 사례처럼 표시하지 않는다.
- 본문에 제작·검증 메타 메모나 사족을 삽입하지 않는다. 내부 감사 문서는 `docs/`에서 관리.
- `rule_md`는 기본 HTML 규칙을 변경하지 않고, 코드 최적화 같은 추가 규칙만 병렬 적용.

## 필수 검증·커밋 게이트
- 원본과 파일 누락·Blob SHA 확인 → 파일/이미지/CSS/JS 링크 검사 → 장별 탐색/복사/모바일 검사.
- 실제 실행 기록이 있는 항목만 PASS. 검증 미실시는 NOT_RUN 또는 미검증.
- RTL 시뮬레이션, AXI 동작, 합성/타이밍, Vitis, 실물 보드 확인은 서로 구분한다.
- 기존 Vivado/Vitis 성공 프로젝트, 원본 XPR/BD/Wrapper/C, 보드 핀/클록/리셋/주소맵을 디자인 목적으로 수정하지 않는다.
- 원본 교재 보존과 새 디자인 작성은 별도 원자 커밋으로 관리한다.
- 민감 정보·계정·개인 경로·토큰이 공개 산출물에 포함되지 않도록 확인한다.

작업 기준 시점: 2026-11-17. 중앙 규칙 커밋: `d1b8278d41fca8f5e3960736f3ac9d377e462fda`.
