# Basys3 + MicroBlaze V SoC — 교육과정 통합 정리본

[**통합 학습안내서 열기**](index.html)

## 교육과정

| 구분 | 학습 목차 | 원본 복사 상태 | HTML 표준 적용 상태 |
|---|---|---|---|
| 제1부 01~10장 + 신규 11장 | [제1부](part01/index.html) | 01~10장 원본 전체 + 11장 소스/교재 보존 | 통합 목차 완료, [01장 시범 버전](part01/legacy/pages/soc/ch01_microblaze_bram_v01.html) 제작 |
| 제2부 01~10장 | [전반부](part02_1/index.html) | 원본 자료 전수 복사 | 통합 목차 완료, [01장 시범 버전](part02_1/ch01_axi_led_v01.html) 제작 |
| 제2부 11~20장 | [후반부](part02_2/index.html) | 원본 자료 전수 복사 | 통합 목차 완료, 개별 장 순차 재편집 |
| 제2부 전체 | [공통 입구](part02/index.html) | — | 통합 목차 완료 |

**교육의 연결:** 제1부 01~10장 → 제1부 11장(사용자 Top) → 제2부 01장(사용자 AXI LED IP) → 제2부 후속 주변장치/통합 실습.

## 원본 복사 무결성 (2026-11-17 Git Blob SHA 대조)

- [`soc/MicroBlaze_V_SoC01_41/`](https://github.com/Yuul-Jung/soc/tree/33e6a7da5fbbf0de7e698a556db42b8eac74abd7/MicroBlaze_V_SoC01_41) → `part01/legacy/`: **1,393/1,393개 일치**
- `amd_soc` 제2부 01~10장/배포 HTML → `part02_1/`: **507/507개 일치**
- `amd_soc` 제2부 11~20장/배포 HTML → `part02_2/`: **147/147개 일치**
- 출처: `soc/main` `33e6a7da`, `amd_soc/main` `71cad8e1`, 후반 작업 브랜치 `8068ec46`.
- 위 세 원본 구간은 **정적 원본 파일 무손실 복사 완료**이며, 이를 Vivado/Vitis/보드 시험 성공으로 간주하지 않는다.
- 원본 `soc`, `amd_soc`는 이 정리 작업에서 수정하지 않는다. 구 41장 제11장과 신편 P1-11은 별개의 교재다.

## 교재 작성 규칙 — 이후 전체 콘텐츠 공통 적용

- [작업 시 필수 확인하는 `AGENTS.md`](AGENTS.md)
- [중앙 교육 HTML 고정 표준](https://github.com/Yuul-Jung/rule_md/blob/d1b8278d41fca8f5e3960736f3ac9d377e462fda/web/education-html/STANDARD.md)
- [제1부·제2부 HTML 재편집·검증 계획](docs/HTML_REBUILD_PLAN.md)
- [원본 규칙 사본](rule_md/README.md) / [MBV SoC 전용 규칙](rule_md/fpga-soc/MBV_SOC_rules.md)

기존 소스코드와 원본 교재를 보존하고, 새 디자인은 검증용 장별 버전 파일로 제작한 뒤 링크를 전환한다. 메인/부별 INDEX는 중앙 `rule_md` 스타일로 정리되었다.

## 작업 및 검증 이력

- [브랜치 보존·정리 대장](docs/BRANCH_CLEANUP_20261117.md)
- [제1부 이미지·링크 복원 이전 조사 기록](docs/PART01_SOURCE_RECOVERY_20261117.md) — **복사 진행 중 시점의 이력**이며 최신 상태는 본 README 참조
- [제1부 내부 자산 정적 검사](tools/check_part01_assets.py)
- 실제 웹 브라우저 반응형·모바일·코드 복사·GitHub Pages 배포와 합성/실물 검증은 별도 증거 필요.
