# Basys3 + MicroBlaze V SoC — 교육자료 정리본

[**통합 학습안내서 열기**](index.html)

| 과정 | 연결 | 상태 |
|---|---|---|
| 제1부 · 기본 SoC 01–11장 | [part01](part01/index.html) | 01–10장 기존 `soc` 원본 링크 연결, 11장 HTML·RTL·C·XDC·검증 기록 복사 |
| 제2부 01–10장 | [part02_1](part02_1/index.html) | 배포용 HTML·SVG 복사, 개발 자료 이관 미완료 |
| 제2부 11–20장 | [part02_2](part02_2/guide/index.html) | HTML·11–20장 원본 개발자료 복사 |
| 제2부 전체 목차 | [part02](part02/index.html) | 제2부 전반/후반 연결 |
| HTML 및 코드 작성 규칙 | [rule_md](rule_md/) | 원본 규칙 복사 |

## 원본 보존 및 근거

- `Yuul-Jung/soc`: 변경하지 않음. 제1부 01~10장 기존 HTML 원본 보존
- `Yuul-Jung/amd_soc`: 변경하지 않음. 이관 대상 자료 원본 보존
- `amd_soc` main `c506461e4ab0842c68e8afcaaaf605afea170463` 기준 제1부·제2부 01–10장
- `amd_soc` work/part02-second-half-20261110 `8068ec462793b55e1d201b5b8c08096c43c5e7e7` 기준 제2부 11–20장

## 검증과 미완료
- 각 장 자료는 **정적 복사** 기준이며, Vivado·Vitis·실물 시험의 새로운 성공을 뜻하지 않음
- 제1부 11장 기존 사용자 보드 동작 확인 기록 유지, 개별 시험 로그 확인 여부는 검증 문서 참조
- 제2부 11~20장의 PR #2는 원본 저장소에서 Draft/충돌 상태였음
- `part02_1/ch01`~`ch10`의 RTL·C·테스트·PNG 원본 전체는 아직 복사되지 않음
- `tools/import_remaining.py`로 원본 커밋에서 이관과 Git Blob SHA 확인 가능. 실제 실행 여부는 별도 확인

## 관리 및 브랜치 정리

- [GitHub 브랜치 정리 대장](docs/BRANCH_CLEANUP_20261117.md): 브랜치별 보존·삭제 후보 및 검증 게이트
