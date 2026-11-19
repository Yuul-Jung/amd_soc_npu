# VS Code 지시문 — 제3부 SoC를 동결 주소맵(안 A)으로 (2026-11-19)

> VS Code에 붙여 넣을 한 줄:
> `git fetch origin && git show origin/restructure/projects:docs/plan/VSCODE_DIRECTIVE_A.md` 를 읽고 그대로 수행해 줘. 질문 없이 진행하고, 끝나면 7절 형식으로 보고해.

## 0. 결정 (웹 Claude·사용자 확정)

| 항목 | 결정 |
|---|---|
| 13~31장 코드 기준 | **VS Code 판 전체** (`vscode/part03-ch13-31`). 웹 판 13~31장 코드는 쓰지 않는다 |
| 5·6장 SoC 주소 | **동결 주소맵(안 A)** — 아래 2절 |
| 표시기 | 28장 `axi_gpio_1` + `p3_fnd_scan` 대신 표준 7세그먼트 IP `ip_seg7`(ID `SEG7`)을 **21장 SoC부터** 넣는다 |
| 28~31장 하드웨어 | 21장 비트스트림·XSA를 그대로 쓰고 ELF만 새로 만든다 (28장 BD 별도 빌드 폐지) |

## 1. 충돌을 막는 작업 경계

| 누가 | 브랜치 | 고치는 곳 |
|---|---|---|
| VS Code | `vscode/part03-ch13-31` (지금 브랜치 계속) | `part03/` 아래만 |
| 웹 Claude | `restructure/projects` | `docs/`·`tools/guide/`·`AGENTS.md` (이 파일 포함) |

- `main`에는 둘 다 푸시하지 않는다. 원본 `Yuul-Jung/amd_soc_rtl`과 제1부 11장 원본 프로젝트는 고치지 않는다 (복제본만).
- 이 지시문과 `docs/plan/handoff/`는 읽기만 한다. 필요한 파일은 `part03/` 안으로 **복사**해서 쓴다.

## 2. 목표 주소맵 (MicroBlaze V Data 주소 공간)

| 인덱스 | 블록 | 베이스 | 범위 | 지금 (VS Code 21장) |
|---|---|---|---|---|
| — | LMB BRAM | 0x0000_0000 | 64 KB | 같음 |
| [00] | `axi_gpio_0` LED(16)/SW(16) | 0x4000_0000 | 64 KB | 같음 |
| [01] | `axi_gpio_btn` BTN 4비트 (btn[3]=U·[2]=D·[1]=L·[0]=R, 인터럽트 켬) | 0x4001_0000 | 64 KB | 없음 → **추가** (11장 BD에 이미 있으면 주소만) |
| [02] | `axi_uartlite_0` 115200 | 0x4002_0000 | 64 KB | 0x4060_0000 → **변경** |
| [03] | `axi_timer_0` | 0x4003_0000 | 64 KB | 0x41C0_0000 → **변경** |
| [04] | `axi_intc_0` | 0x4004_0000 | 64 KB | 0x4120_0000 → **변경** |
| [05] | IIC | 0x4005_0000 | — | 넣지 않음 (자리만 비움) |
| [06] | `ip06_seg7` = `ip_seg7` 1.0 | 0x4006_0000 | 64 KB | 없음 → **추가** |
| — | `p3_npu_0` | 0x44A0_0000 | 4 KB | 같음 |

인터럽트: `xlconcat` 입력 **16개**로 바꾼다. 쓰지 않는 입력은 상수 0.

| INTC 입력 | 연결 | 지금 |
|---|---|---|
| In0 | `axi_timer_0/interrupt` | 같음 |
| In1 | `axi_uartlite_0/interrupt` (예약 — 연결은 하되 펌웨어는 켜지 않음) | NPU → **변경** |
| In2 | 0 (IIC 예약) | — |
| In3 | `axi_gpio_btn/ip2intc_irpt` | — |
| In4~In11 | 0 (C 시리즈 확장 블록 예약, `soc_map.h`) | — |
| **In12** | `p3_npu_0/irq_o` (C00 예약칸 In12~In14의 첫 칸) | In1 |
| In13~In15 | 0 | — |

## 3. 할 일 (순서대로, 단계마다 원자 커밋)

1. **미커밋 정리 먼저.** 27~29장 미커밋 8개, `common/sw`, 30·31장을 장 단위 원자 커밋으로 올리고 푸시한다. 30장 비트스트림·28장 xsim 미완료는 그대로 `NOT_RUN`으로 둔다(2절 작업 뒤 다시 만든다).
2. **SEG7 IP 가져오기.** `docs/plan/handoff/ip_seg7/` 세 파일(`ip_seg7.v`, `axil_slave.v`, `ip_std.v`)을 `part03/common/rtl/ip_std/`로 복사한다. 내용은 고치지 않는다. 짧은 Icarus TB로 VALUE·MODE·RAW 쓰기/읽기와 0xFFF0 ID = 0x53454737을 확인하고 로그를 남긴다.
3. **21장 BD 변경** (`ch21/synth/soc_npu_bd.tcl`, 복제 프로젝트에서만): 2절 표대로 주소 변경·BTN GPIO·SEG7(모듈 참조 또는 IP 패키징, 쉬운 쪽)·concat 16입력. 사용자 Top에 `seg[6:0]`·`dp`·`an[3:0]`·`btn[3:0]` 포트를 핀 연결만으로 추가 (Top은 배선만, MBV_SOC §4). 핀은 Basys-3-Master.xdc 그대로.
4. **검사 스크립트 강화** (`ch21/scripts/check_bd.tcl` 또는 같은 역할): Address Editor 값을 2절 표와 한 줄씩 대조해 `ADDR_MAP_A_PASS`/`FAIL`, INTC 입력 번호를 대조해 `IRQ_MAP_A_PASS`/`FAIL`을 찍는다. 겹침 없음 검사는 그대로.
5. **21장 재빌드**: `scripts/build_soc.sh` → 비트스트림·XSA. `validation/soc_summary.md`를 새 값(주소 표, WNS·WHS, LUT·FF·BRAM·DSP, SHA-256)으로 다시 쓴다. 이전 값은 Git 이력에만 남긴다.
6. **펌웨어**: 22장부터 주소는 `xparameters.h`만 쓴다(하드코딩 금지). `rg -n '0x4060|0x41C0|0x4120|0x4001' part03`이 BD 검사 기대값 외에는 0건이어야 한다. NPU 인터럽트를 쓰는 코드는 INTC 비트 12로. 22장 드라이버에 표시 코드를 추가한다: 추론 뒤 클래스를 LED 한 개 + 7세그먼트 오른쪽 자리(VALUE), 왼쪽 두 자리는 그림 번호.
7. **다시 돌릴 것**: 22 ELF → 23 SoC 시뮬(CPU·NPU 클록 값 갱신) → 25 report_power(같은 SAIF 절차) → 27 `run_all` (`LEVEL=sim`과 가능하면 `LEVEL=vivado`) → 28 ELF(21장 XSA로 플랫폼, `basys3_soc28_top`·`soc28_bd.tcl`·`axi_gpio_1`·`p3_fnd_scan`은 삭제하고 `p3_fnd_scan`은 RTL 시험용으로만 남길지 판단해 보고) → 29·30·31 ELF + `ELF_MEM_PASS`. 24장 OOC 스윕은 주소와 무관하므로 다시 돌리지 않는다.
8. **보드 점검표** `ch27/docs/BOARD_CHECKLIST.md`: 비트스트림·XSA·ELF SHA를 새 값으로, 7세그먼트·BTN 항목을 서브젝트마다 하나 이상 넣는다. 모두 `NOT_RUN` 유지.

## 4. 지킬 것

- 실행하지 않은 것은 `NOT_RUN`/`⚠ 미검증`. 추정값(전력)은 추정이라 적는다.
- 로그에는 개인 경로를 `<repo>`로 바꿔 넣는다. 토큰·계정 정보 금지.
- 커밋 끝 줄은 지금까지와 같은 Co-Authored-By 형식.
- 타이밍을 못 맞추면(WNS < 0) 억지로 고치지 말고 결과 그대로 보고한다.

## 5. 웹 Claude가 그동안 하는 것

1장(구 00~03장) 시범 전환: 생성기를 "장 페이지 + 서브젝트 절" 구조로 바꾸고 미리보기를 만든다. VS Code 작업과 파일이 겹치지 않는다.

## 6. 판단이 필요하면

추측하지 말고 보고서의 "판단 필요" 칸에 적고 다음 항목으로 넘어간다 (예: 11장 BD에 BTN GPIO가 이미 다른 주소로 있는 경우, SEG7을 모듈 참조로 넣을 수 없는 경우).

## 7. 보고 형식

| 항목 | 결과 (PASS/FAIL/NOT_RUN) | 증거 파일 | 값 |
|---|---|---|---|
| 미커밋 정리 | | 커밋 해시 | |
| SEG7 TB | | | ID 읽기값 |
| ADDR_MAP_A / IRQ_MAP_A | | | |
| 21장 비트스트림 | | `soc_summary.md` | WNS·WHS·LUT·SHA |
| 22~31장 ELF | | | 크기·스택 끝 |
| 23장 클록 | | | CPU·NPU |
| 25장 전력 | | | CPU·NPU mJ |
| 27장 run_all | | | |
| 판단 필요 | | | |

마지막 커밋 해시와 브랜치 이름을 적는다.
