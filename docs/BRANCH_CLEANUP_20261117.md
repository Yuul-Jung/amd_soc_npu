# GitHub 브랜치 정리 대장

기준일: 2026-11-17  
대상: `Yuul-Jung/amd_soc`(원본), `Yuul-Jung/amd_soc_rtl`(정리본)  
원칙: 원본 `soc`, `amd_soc`의 파일·커밋을 지우거나 병합하지 않고, 정리본의 `main`에 작업 상태를 기록한다.

## 브랜치는 폴더가 아니다

`work/part02-second-half-20261110`의 `work/`는 Git 브랜치 이름의 일부다. 웹의 **Code → main** 파일 목록에는 보이지 않는다. GitHub의 **Branches** 메뉴 또는 브랜치 선택 메뉴에서 확인해야 한다.

- [amd_soc 브랜치 전체 목록](https://github.com/Yuul-Jung/amd_soc/branches)
- [제2부 11~20장 작업 브랜치](https://github.com/Yuul-Jung/amd_soc/tree/work/part02-second-half-20261110)
- [제2부 PR #2](https://github.com/Yuul-Jung/amd_soc/pull/2)
- [정리 저장소 amd_soc_rtl/main](https://github.com/Yuul-Jung/amd_soc_rtl)

## 실제 비교 결과

2026-11-17 GitHub 비교 API에서 `amd_soc/main` 기준으로 확인한 결과:

| 브랜치 | main보다 앞선 커밋 | main보다 뒤처진 커밋 | 변경 파일 | 결정 |
|---|---:|---:|---:|---|
| `main` | — | — | — | 원본 유지 |
| `work/amd_soc_rtl-copy-organize-20261117` | 0 | 1 | 0 | 삭제 가능 후보; 현재 삭제 미실행 |
| `migration/import-part01-part03` | 2 | 103 | 12 | PR #1 병합 완료이나 다른 이력 존재; 자동 삭제 금지 |
| `work/part02-second-half-20261110` | 344 | 42 | 157 | 보존 필수; PR #2 초안/충돌 |
| `docs/p3-25ch-course-index` | 9 | 40 | 11 | 제3부 자료 비교 완료 전 보존 |
| `feat/p3-01-mac` | 3 | 40 | 8 | 제3부 자료 비교 완료 전 보존 |
| `feat/p3-02-dsp` | 4 | 40 | 18 | 제3부 자료 비교 완료 전 보존 |
| `feat/p3-03-pipeline` | 5 | 40 | 28 | 제3부 자료 비교 완료 전 보존 |

`ahead` 커밋이 있다는 사실은 그 코드가 `main`에 없는 독자 자료라는 보장이 아니다. 삭제 전 **커밋·파일 내용 비교와 이관처 검증**을 수행해야 한다.

## 정리 판정

1. **유지**: `amd_soc/main`과 `amd_soc_rtl/main`.
2. **보존**: 제2부 11~20장 브랜치. 기존 RTL·C·HTML·테스트 및 검증 이력의 보존 기준이며, `amd_soc_rtl`에 모든 자료를 무손실 복사해 재검증하기 전까지 제거하지 않는다.
3. **보류**: 제3부 관련 4개 브랜치 및 과거 이관 브랜치. 원본 파일·커밋을 정확히 비교한 이후 판단한다.
4. **삭제 후보**: `work/amd_soc_rtl-copy-organize-20261117`. `main`과 비교해 독립 커밋 0개·변경 파일 0개다. **GitHub 브랜치 삭제 작업은 아직 실행하지 않았다.**

## 신 저장소 자료 구성 및 한계

- `part01/`: 제1부 목차 및 11장 보존 파일.
- `part01/legacy/`: 구 제1부 01~10장 HTML 원본 복사 중. 이미지·공통 JS/CSS·관련 문서가 아직 모두 복사되지 않았다.
- `part02_1/`: 제2부 01~10장 배포 교재·SVG 복사. RTL·C·TB·PNG 전체 이관은 미완료.
- `part02_2/`: 제2부 11~20장 배포 교재, RTL·C·테스트 자료 복사.
- `rule_md/`: 기존 규칙 파일 복사.
- `index.html`: 통합 입구. 로컬 원본 01~10장 의존 관계가 완결될 때까지 일부 `soc`의 외부 원본 링크를 유지한다.

이관 원본 고정 커밋:
- `soc/main`: `33e6a7da5fbbf0de7e698a556db42b8eac74abd7`
- `amd_soc/main` (이관 기준): `c506461e4ab0842c68e8afcaaaf605afea170463`
- `amd_soc` 11~20장 작업: `8068ec462793b55e1d201b5b8c08096c43c5e7e7`

`tools/complete_migration.py`는 이관을 위한 도구로 작성되어 있다. 스크립트 존재 자체가 복사·검증 실행을 뜻하지 않는다. 바이너리·상대경로·해시 검증을 완료하기 전에는 **완료**로 표시하지 않는다.

## 검증 게이트

- 원본과 목적지 파일별 Git Blob SHA 일치 확인
- HTML·CSS·JS·이미지·다운로드 상대경로 및 클릭 검사
- RTL·C·XDC·테스트벤치·검증 파일 인벤토리 전수 대조
- 기존 시뮬레이션 증거와 신규 실행 결과 구분
- Vivado 합성·Vitis·실물 보드는 미실행이면 미실행으로 유지
- 완료 후 정리 후보 브랜치 삭제, `amd_soc/main` 보호 정책은 별도 설정
