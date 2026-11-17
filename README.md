# Basys3 · MicroBlaze V — RTL 교육자료 정리 저장소

> **상태: 구조 정리 착수 / 전체 원본 복사 및 검증 미완료**

## 목적
기존 `Yuul-Jung/amd_soc`의 제2부 자료를 **복사**하여 장별로 찾기 쉬운 구조로 정리합니다. 원본 `Yuul-Jung/soc`와 `Yuul-Jung/amd_soc`를 변경하지 않습니다.

## 폴더 구조
- `part02/index.html` — 제2부 전체 학습 목차 (작성 예정)
- `part02_1/ch01` ~ `ch10` — 제2부 01–10장
- `part02_2/ch11` ~ `ch20` — 제2부 11–20장
- `rule_md/` — 기존 규칙을 출처와 커밋을 기록해 사본으로 관리

각 장은 `index.html`(배포 교재), `rtl/`, `sw/`, `xdc/`, `labs/`, `tests/`, `validation/`, `assets/`을 필요할 때만 사용합니다.

## 원본 기준 (2026-11-17 확인)
- 01–10장: `Yuul-Jung/amd_soc` `main` @ `c506461e4ab0842c68e8afcaaaf605afea170463`
- 11–20장: `Yuul-Jung/amd_soc` `work/part02-second-half-20261110` @ `8068ec462793b55e1d201b5b8c08096c43c5e7e7`
- 11–20장 원본 검토 PR: https://github.com/Yuul-Jung/amd_soc/pull/2 (Draft, 충돌 상태)
- HTML 규칙: 기존 `amd_soc/rule_md` 기준. 별도 규칙을 원본 대신 덮어쓰지 않습니다.

## 이관 승인 조건
1. 원본 전체 파일 목록과 파일별 SHA-256 또는 Git Blob SHA 대응표 확보
2. 01–20장 교재·RTL·C·XDC·테스트벤치·검증 로그 누락 없이 복사
3. 동일 파일의 복제본·구버전·정본을 구분하고 소스의 실제 변경을 피함
4. 내부 HTML 링크/이미지/JS/CSS 및 테스트 참조 경로 수정·확인
5. 시뮬레이션·합성·실물 검증을 각각 구분하고 미실행은 NOT_RUN 처리
6. 완료 전 기존 자료 삭제 및 원본 저장소의 브랜치 병합 금지

**이 README 생성은 자료 이관 또는 검사 완료를 뜻하지 않습니다.**
