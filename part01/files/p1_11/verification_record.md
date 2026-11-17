# 제1부 11장(P1-11) — 사용자 Top·1비트 GPIO 실습 검증 기록

## 0. 프로젝트 및 기준

- 10장 원본: `/home/jung/soc/hw/soc10_integration/soc10_integration.xpr` (원본 보존 목표; 2026-11-01 화면에서는 아직 10장 XPR을 열어 작업 중이므로 실제 불변 여부 미확인)
- 11장 복제 XPR(목표): `/home/jung/soc/hw/soc11_user_top/soc11_user_top.xpr` (제공 화면에서는 독립 XPR 미확인)
- 11장 BD/Wrapper: `soc11_integration.bd` / `soc11_integration_wrapper.v` (제공된 Vivado Sources 계층에서 존재 확인; 현재 10장 프로젝트 경로)
- 사용자 Top: `part01/files/p1_11/basys3_soc11_top.v`
- 11장 XDC: `part01/files/p1_11/basys3_soc11_top.xdc`
- 11장 C 소스: `part01/files/p1_11/main_soc11.c`
- 10장 실제 사용자 제공 XDC 포트: `sw_tri_i[15:0]`, `led_tri_o[15:0]`, `UART_0_rxd`, `UART_0_txd`
- 생성 Wrapper 인스턴스 계층: **화면 확인** / 모듈 선언부 포트 방향·비트폭: **미확인**
- 11장 설계·실물 검증: Top 계층·타이밍·전력 화면 일부 확보. **2026-11-02 사용자가 실물 동작 확인을 명시적으로 회신**. 개별 기능 시험 로그·독립 XPR 경로·Critical Warning 해소는 별도 기록 없음.

## 1. Vivado · 사용자 Top

| 확인 항목 | 기대 결과 | 실측/캡처 |
|---|---|---|
| BD 복제·주소 | 11장 XPR에서 `File → Save Block Design As`로 `soc11_integration.bd` 생성, 원래 BD IP·Address Editor 설정 확인 | 미실시 |
| Wrapper 생성 포트 | 새 Wrapper의 `sw_tri_i`, `led_tri_o`, `UART_0_rxd`, `UART_0_txd`, `clk`, `btnC` 확인 | Wrapper 이름/계층 확인; 포트 선언부는 미확인 |
| Top 계층 | `basys3_soc11_top → u_soc11 : soc11_integration_wrapper → soc11_integration` | **제공 스크린샷에서 계층 확인** (여전히 10장 XPR) |
| XDC | 36개 I/O 핀 이름·전압·주파수·중복 제약 검사 | 미실시 |
| Synthesis · Implementation | 회로 합성·배치배선·DRC·Timing 확인 | 미실시 |
| Bitstream · XSA | 11장 새 하드웨어 파일 생성 | Vitis Platform Output의 `basys3_soc11_top.xsa`와 Debug 구성의 `basys3_soc11_top.bit` 화면 확인. Bitstream 생성 로그는 별도 미첨부 |

## 2. Vitis · 보드

| 확인 항목 | 기대 결과 | 실측/캡처 |
|---|---|---|
| Platform | 11장 XSA 기반 `soc11_user_top_platform` 구성·Build | Platform Output의 `basys3_soc11_top.xsa`, `soc11_user_top_platform.xpfm` 화면 확인. Build 성공 로그는 미첨부 |
| Application | `soc11_user_top_app` / standalone `microblaze_riscv_0` / ELF 준비 | Empty Application Summary와 Debug의 `.elf` 연결 화면 확인. Build 로그는 별도 미첨부 |
| SW0 → LED0 | SW0 OFF/ON에 맞춰 LED0 OFF/ON | 미실시 |
| SW1~13 → LED1~13 | 11장 C 예제에서는 미반영, LED1~13 OFF | 미실시 |
| UART 1/0 → LED14 | UART 터미널 115200 8N1, ON/OFF | 미실시 |
| Timer → LED15 | Timer/INTC heartbeat | 미실시 |
| BTNC | 시스템 Reset | 미실시 |

**2026-11-02 사용자 보고:** Basys3 실물에서 11장 동작 확인. 아래 항목별 `미실시`는 **개별 시험 결과가 아직 공유되지 않은 상태**로서, 사용자의 전체 동작 확인 회신과 구분한다.

## 3. 범위

- **실습 예시:** SW0 → LED0 한 비트. 이후 목적에 따라 스위치·LED 비트/표시 정책 변경 가능.
- GPIO 16비트 폭, 새로 복제한 BD의 내부 IP 연결·설정, AXI Address Map, 클록, Reset, UART/Timer IP는 유지한다. 10장 원본 BD는 그대로 보존한다.
- 10장 전체 기능 동등성, 기존 ELF 재실행, LED13 별도 하드웨어 분리는 본 실습 필수 조건이 아니다.
- Vivado·Vitis·보드 결과를 실제 확보한 경우에만 PASS를 기록한다.

## 4. 2026-11-01 사용자 Vivado 캡처 — 화면 확인 기록

**근거:** 대화에 제공된 image(20261101-141927).png, image(20261101-142131).png, image(20261101-142435).png, image(20261101-142504).png, image(20261101-142559).png. 원본 이미지는 Git 저장소에 아직 첨부하지 않았다.

| 캡처 | 실제 확인 | 판정 |
|---|---|---|
| 141927 | Vivado 2024.2: basys3_soc11_top → u_soc11 : soc11_integration_wrapper → soc11_integration_i. Basys-3-Master.xdc Enabled. 상단 프로젝트 경로는 여전히 soc10_integration XPR, Synthesis/Implementation Out-of-date 표시 | 사용자 Top 계층은 화면 확인. 11장 독립 프로젝트 보존 분리 필요 |
| 142131 | Timing: WNS +1.347ns, TNS 0.000ns, WHS +0.016ns, THS 0.000ns, WPWS +3.000ns, TPWS 0.000ns, failing endpoints 0 | 해당 Timing 화면은 양호. 현 최종 설계/독립 XPR과의 대응 및 클록 경고 해소 전 최종 PASS 미판정 |
| 142435 | 예상 On-Chip Power 0.205W (Dynamic 0.132W, Static 0.073W), Junction 26.0°C, Confidence Level Low | 저신뢰도 추정치. 실측 전력·온도가 아님 |
| 142504 | Critical Warning: Constraints 18-1056과 18-1055는 기존 clk 클록을 sys_clk_pin 정의가 덮어씀 (둘 다 10.000ns), Synth 8-6895는 증분 합성 DCP 재사용 부적합 및 기본 흐름으로 계속 진행 | 다른 클록 참조 제약이 무시될 수 있어 클록/제약 확인 필요. DCP 재사용 실패만으로 기능 오류 단정 금지 |
| 142559 | Critical Warning 3건, 일반 Warning 267건 표시 | 267건은 개별 미검토; 모두 무해하다고 단정하지 않음 |

**다음 확인:** ① 11장 독립 XPR로 Save As 후 실제 경로 확인 ② Open Implemented Design에서 report_clocks·check_timing·최신 Timing Summary 확인 및 클록 중복 제약 검토 ③ 새 Bitstream/XSA·Vitis ELF·Basys3 실물 검증. 10장 기능 동등성 시험은 요구하지 않음.

## 5. 2026-11-02 Vitis GUI 및 사용자 실물 동작 확인

**사용자 회신:** “동작 확인 함” — 11장 SoC/Vitis 프로그램을 실제 Basys3에서 동작 확인. **상태: 사용자 확인 실물 동작**. 개별 기능별 시험 로그가 첨부되었다는 뜻은 아니다.

| 근거 화면 | 확인 사실 | 판정 |
|---|---|---|
| Vitis Explorer `soc11_user_top_platform` | Output → hw의 `basys3_soc11_top.xsa`, `soc11_user_top_platform.xpfm`와 Platform 출력 트리 | Platform 산출물 화면 확인 |
| Empty Application Summary | `soc11_user_top_app`, Workspace `/home/jung/soc/sw`, Platform `soc11_user_top_platform`, Domain `standalone_microblaze_riscv_0` | 새 11장 Application 구성 화면 확인 |
| BSP `xparameters.h` | `XPAR_XGPIO_0_BASEADDR 0x40000000`, `XPAR_XINTC_0_BASEADDR 0x41200000`, AXI GPIO 16비트 Dual Channel | GPIO·INTC 매크로 화면 확인 |
| Vitis Debug `launch.json` | `basys3_soc11_top.bit` 지정, Program Device 선택, `microblaze_riscv_0` 대상 및 `soc11_user_top_app.elf` 연결 | 다운로드·실행 구성 화면 확인 |
| 사용자 직접 회신 | “동작 확인 함” | **실물 보드 동작 확인(사용자 보고)** |

**검증 경계:** 전체 동작은 사용자 실물 확인으로 기록한다. SW0·LED0, UART·LED14, Timer·LED15, Reset의 개별 시험 로그, Vivado 클록 덮어쓰기 Critical Warning 해소, 독립 11장 XPR 경로는 추가 근거가 없으므로 각각 별도 완료로 기록하지 않는다. 현재 동작하는 하드웨어·소프트웨어를 이 이유만으로 불필요하게 재설계하지 않는다.
