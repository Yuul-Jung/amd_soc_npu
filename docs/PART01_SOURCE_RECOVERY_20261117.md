# 제1부 정본 복원 · 제1부 11장 → 제2부 연결 교정 대장

> 내부 이관·검증 관리 자료. 학습안내서 배포 본문에 이력·경고 문구를 섞지 않는다.

## 1. 사용자 확정 원칙

- `Yuul-Jung/soc`에 완성한 **제1부 01~10장 원본 교재·이미지·CSS·JS·소스·검증 자료를 통째로 복사**한다.
- 그 다음 `amd_soc/part01`에서 작성한 **신규 제1부 11장(P1-11, 사용자 Top과 SW0 → LED0)**을 후속 장으로 연결한다.
- 제2부 01장(P2-01)은 이 **P1-11의 SoC 구조와 Wrapper**를 기반으로 별도의 사용자 AXI IP 실습을 진행한다.
- 구 `MicroBlaze_V_SoC01_41/pages/soc/11_register_map_design_principles.html`은 **기존 41장 교재의 11장**이며 신편 P1-11과 다르다. 번호가 같다는 이유로 혼동하지 않는다.
- **`amd_soc`, `soc` 원본은 수정하지 않고**, `amd_soc_rtl`만 정리한다.
- 기존 실습 프로젝트·교재 디자인과 코드 내용은 보존하고, 소스와 자산 누락·탐색 경로만 보정한다.

## 2. 정본과 계보

| 자료 | 원본 저장소 경로 | 정리 저장소 경로 |
|---|---|---|
| 제1부 01~10장 HTML(보조 07.1/08.1/09.1/10.1 포함, 14개) | `soc/MicroBlaze_V_SoC01_41/pages/soc/` | `part01/legacy/pages/soc/` |
| 원본 교재의 상대경로 자산 | `soc/MicroBlaze_V_SoC01_41/{assets,images,code,manifests,validation,...}` | `part01/legacy/` 아래 **동일한 하위 구조** |
| 신규 제1부 11장 | `amd_soc/part01/chapters/`, `amd_soc/part01/files/p1_11/` | `part01/chapters/`, `part01/files/p1_11/` |
| 제2부 01장 사용자 AXI LED | `amd_soc/part02/chapters/P2_01_Lesson_20261106/` | `part02_1/ch01/` |
| 제2부 02~10장 | `amd_soc/part02/chapters/` 및 `part02_v2/` | `part02_1/` |
| 제2부 11~20장 | `amd_soc` 작업 브랜치 `work/part02-second-half-20261110` | `part02_2/` |

소스 고정 기준:
- `soc/main` — `33e6a7da5fbbf0de7e698a556db42b8eac74abd7`
- `amd_soc/main` 사본 기준 — `c506461e4ab0842c68e8afcaaaf605afea170463`
- `amd_soc` 제2부 후반 브랜치 — `8068ec462793b55e1d201b5b8c08096c43c5e7e7`

## 3. 2026-11-17 이관 상태와 링크 감사

### 제1부 01~10장

- 14개 원본 HTML 파일: 전부 복사, 원본 Git Blob SHA 일치.
- 전체 `MicroBlaze_V_SoC01_41` 원본은 **1,393개 파일**. 본 회차 교정 중 `part01/legacy`에 보존한 파일은 71개로, 이 71개 모두 원본 Blob SHA와 일치.
- 원본 HTML 14개의 상대 `href/src` 참조 **515건** 확인.
- 현재 복사본에서 존재하는 대상 **236건**, 없는 대상 **279건**.
- 미해결 고유 경로 **121개**: PNG·JPG·WebP 등 바이너리 자산 **120개(참조 277건)**, 구 41장 원본의 11장 HTML 링크 **1개(참조 2건)**.
- 이 121개 경로의 **원본 파일은 `soc` 저장소에 존재**한다.
- 구 11장 참조는 신규 P1-11과 혼동 우려가 있으므로 별도 링크 규칙을 검토해야 하며, 구 41장 교재를 신편 11장으로 표시하지 않는다.
- `tools/check_part01_assets.py`로 로컬 상대경로 참조 누락 전수 검사 가능.

### 신규 제1부 11장 → 제2부 01장

- 신규 P1-11 HTML, RTL, XDC, C, 검증 기록은 `part01/`에 위치한다.
- 기존 `amd_soc` P2-01 README의 출발점은 명시적으로 `soc11_user_top`이며 **원본 프로젝트를 변경하지 않는다**.
- P2-01 사용자 Top 예제는 `soc11_integration_wrapper`를 재사용하면서 신규 `p2_led_o`를 BD 외부 포트로 연결한다.
- P2-01 원본 18개 중 텍스트 기반 16개는 `part02_1/ch01/`에 복사해 SHA 일치를 확인했으며, PNG 미리보기 2개는 미복사.
- P2-01 C는 실제 `USER_IP_BASEADDR` 등록을 요구하므로 주소 확인 없이 보드 기능 검증 완료로 판정하지 않는다.

## 4. 최종 복원 절차

1. 바이너리 파일을 보존할 수 있는 **로컬 Git 클론**을 사용한다. GitHub 텍스트 커넥터는 PNG·WebP를 UTF-8로 받아올 수 없으므로 이를 복사 완료로 주장하지 않는다.
2. 기존 프로젝트 `/home/jung/soc`와 겹치지 않는 **별도 작업 폴더**에 원본 `soc`, `amd_soc`, 대상 `amd_soc_rtl`을 각각 클론한다.
3. `tools/complete_migration.py`로 원본 두 저장소의 지정 커밋 전체를 새 저장소로 무손실 복사한다. 스크립트는 사전 점검(dry run), 같은 이름의 다른 내용 차단, 모든 Blob SHA 확인 기능을 가진다.
4. `python3 tools/check_part01_assets.py --list`를 실행해 제1부 14개 페이지의 누락 링크가 0인지 확인한다. 구 41장 11장과 신편 P1-11의 링크 체계는 별도 확인한다.
5. 제1부 11장 검증 기록의 실물 확인 및 미검증 항목을 보존한다.
6. P2-01은 P1-11을 **복제한 신규 프로젝트**에서 시작하며, P1-11 원본 XPR·BD·Wrapper·C를 덮어쓰지 않는다.
7. 제2부 RTL·C·XDC·테스트벤치와 HTML·이미지를 각 장별로 검사한다.
8. 정적 링크 확인과 실제 Vivado/Vitis·RTL 시뮬레이션·실물 시험은 각각 별도 결과로 보고한다.

**현재 최종 독립 교재 복원: 미완료.** GitHub 연결만으로 바이너리 120개를 가져올 수 없어, 본 대장은 안전한 복원을 위한 실제 현황 및 실행 기준이다.
