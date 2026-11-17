# 제1부 11장(P1-11) — 독립 적대적 검증

- **검증일:** 2026-11-01 (Asia/Seoul)
- **검토 기준:** `Yuul-Jung/soc` 원본 기준 `main d6eed5d6e730bd903a9474968c8c2f5d76be926d`. 이번 검토 중 `VALIDATION.md`의 확정된 사양 오기만 교정한 커밋: `accfb13cca4cc1ecd86e24ee3943786a92c243a5`.
- **방법:** GitHub 현재 파일 읽기/상호 대조 + XDC 파싱 + HDL 정적 연결 검사 + 10장 C 비트 마스크를 기준으로 262,144가지 조합에 대한 참조 모델 검사 + AMD 2024.2 공식 문서 대조.
- **독립성:** 다른 AI에 질의·검토 의뢰하지 않음. 실제 Basys3/Vivado/Vitis에 접근하거나 해당 프로그램을 실행한 결과가 아님.
- **총괄 판정:** **조건부 보류** (소스의 고정 배선은 정적 일치, 실제 Wrapper·합성·보드 게이트 미검증). **현재 확인된 P0 결함 없음**은 P0 없음이 증명되었다는 뜻이 아님.

## 1. 증거 자료

| 파일 | 검토 내용 |
|---|---|
| `part01/files/p1_11/step1_basys3_soc11_top.v` | 하위 `soc10_integration_wrapper` 포트 연결, 순수 Top 규칙 |
| `part01/files/p1_11/step2_basys3_soc11_top.v` | `soc10_led[15:0]` 수신, LED13 고정 OFF, 나머지 출력 연결 |
| `part01/chapters/11_user_top_io_remap.html` | 실습 절차, 소스 코드 일치, 링크, 단계 구분 |
| `part01/chapters/P1-11_user_top_preview.html` | 정식 HTML과 동일한지 확인 |
| `MicroBlaze_V_SoC01_41/code/soc10/main.c` | `SW_LED_MASK=0x00003FFFU`, `UART_LED_MASK=0x00004000U`, `HEARTBEAT_LED_MASK=0x00008000U` |
| `MicroBlaze_V_SoC01_41/code/soc10/basys3_soc10_integrated.xdc` | 36개 입력/출력 핀 매핑, 3.3 V IO 기준, 신호 이름·중복 검사 |
| `VALIDATION.md` | 1/2단계 동등성 요구와 실제 10장 C 코드 대조 |
| `part01/files/p1_11/verification_record.md` | 미실시 상태 분리 및 2단계 회귀 예외 |

공식 확인 자료:
- [AMD UG994 2024.2 — Vivado IP Integrator](https://docs.amd.com/r/2024.2-English/ug994-vivado-ip-subsystems) (BD와 생성 HDL Wrapper의 통합/출력)
- [AMD UG1400 2024.2 — Updating the Hardware Specification](https://docs.amd.com/r/2024.2-English/ug1400-vitis-embedded/Updating-the-Hardware-Specification) (Vitis `Switch XSA` 절차)
- [AMD 2024.2 — Exporting the XSA](https://docs.amd.com/r/2024.2-English/Vitis-Tutorials-Embedded-Software/Exporting-the-XSA?contentId=U2PyKN_n8ugmmnjhXshvsg) (`Include bitstream` 선택)

## 2. 정적 검사 결과

| 검사 | 결과·한계 |
|---|---|
| XDC 핀·포트 매핑 | **정적 일치**: 36개 포트, 36개 패키지 핀, 중복 없음, 전부 LVCMOS33. W5/clk, U18/btnC, U1/sw13, N3/LED13, P1/LED14, L1/LED15, B18/RsRx, A18/RsTx |
| 1단계 Top | **정적 일치**: clk, btnC, sw[15:0], led[15:0], RsRx, RsTx 그대로 하위 Wrapper에 전달 |
| 2단계 Top | **정적 일치**: Wrapper의 16비트 LED 출력을 `soc10_led`로 받고, 보드 `led[12:0]`·`led[14]`·`led[15]`를 재연결, `led[13]`은 `1'b0`으로 연결 |
| 10장 C/RTL 출력 관계 | **참조 모델 일치**: 65,536가지 스위치 값 × UART 2상태 × heartbeat 2상태, **262,144건 불일치 0** |
| Top 순수 배선 | **정적 일치**: `always`, `initial`, FSM, MUX/산술 정책 없음. `assign`은 비트 연결·상수 출력만 |
| HTML 정합성 | 두 HTML 파일 내용 동일, 두 Verilog 코드 블록이 각각 원본 `.v`와 일치(소스 정적 확인); 상대경로가 해당 GitHub 파일 구조와 일치 |
| 실제 Vivado RTL 컴파일 | **미실시**. 자동 생성 `soc10_integration_wrapper.v`의 실제 선언·포트폭 불확정 |
| Synthesis/Implementation/Timing/DRC | **미실시** |
| XSA·Vitis 플랫폼·기존 ELF 회귀 | **미실시** |
| Basys3 보드 LED/SW/UART/Timer/Reset | **미실시** |

> 262,144건은 C 출력 비트 마스크와 Verilog 연결 문장을 사람이 재구성한 **정수 참조 모델** 시험이다. HDL 시뮬레이터·Vivado 합성·실물 동작을 대신하지 않는다.

## 3. 결함/차단 항목

### P1-01 — 실제 BD Wrapper 포트 일치 확인 불가 (미해결, 구현 차단)

- `soc10_integration_wrapper.v`의 **실제 생성된 HDL 모듈 선언부**를 현재 GitHub 기본 브랜치에서 찾지 못했다. 검색된 이름은 11장 예제에서 사용한 **인스턴스 참조**뿐이다.
- XDC는 **최상위 핀 이름과 핀 번호의 근거**다. XDC만으로 하위 Wrapper의 정확한 포트 이름·방향·비트폭을 확정할 수 없다.
- 따라서 두 `.v` 소스가 기존 실제 BD Wrapper와 함께 컴파일된다고 **확정 판정하지 않는다**.
- **필수 조치:** 실물 복제 프로젝트의 `soc10_integration_wrapper.v` 선언부와 Top의 6개 포트를 대조하고, Synthesis/Elaboration의 메시지 및 계층 캡처를 저장한다. 어긋나면 **신규 Top 연결만 최소 수정**한다. 교재에는 별도의 경고 상자 대신 GUI 절차 1행으로 배치한다.

### P1-02 — 1단계 요구사항에 잘못된 SW/LED 미러 표기 (문서 교정 완료)

- 교정 전 `VALIDATION.md`에는 `SW[15:0]→LED[15:0]`을 기능 동등성처럼 기재해 놓았다.
- 실제 10장 C의 `SW_LED_MASK`는 `0x3FFF`이므로 **SW0~13→LED0~13**, **LED14는 UART 명령**, **LED15는 Timer 인터럽트 heartbeat**이다. SW14·SW15는 입력으로 읽지만 물리 LED14·LED15를 미러링하지 않는다.
- **수정:** `VALIDATION.md`에서 **'포트의 1:1 연결'과 '실제 소프트웨어 출력 기능'을 분리**하였다. 수정 커밋 `accfb13cca4cc1ecd86e24ee3943786a92c243a5`.
- 이 문구 변경이 실제 하드웨어 시험 완료를 의미하지 않는다.

### P1-03 — 2단계 물리 LED13 단일 드라이버/합성 증거 없음 (미해결, 검증 차단)

- RTL 소스에는 `led[13] = 1'b0`이라는 임시 연결이 있지만, Vivado에서 N3의 I/O 드라이버 생성, Wrapper `soc10_led[13]` 경로 최적화, I/O DRC·타이밍은 확인하지 못했다.
- 합성 결과에서 미사용 Wrapper bit13이 최적화되어도 **그 자체로 오류라고 판정할 수 없다**. 핵심은 외부 N3의 하나의 확정된 구동원과 나머지 신호 기능 유지이다.
- **필수 조치:** 2단계는 1단계와 별도 Bitstream 생성 → 구현 후 N3 핀·출력 경로·DRC 확인 → SW13을 변화시키며 LED13 OFF/나머지 기능 정상 여부 실측.

### P1-04 — 1·2단계 ELF/Bitstream/Board 재현 데이터 없음 (미해결, 최종 판정 차단)

- 교재는 두 단계의 새 Bitstream/XSA를 요구하지만, 11장 기준 Vivado/Vitis 프로젝트·실행 로그가 없다.
- **필수 조치:** 1단계/2단계 각각 XSA·Bitstream 버전, 동일 ELF 재사용 가능 여부, 새 앱 빌드, SW/UART/Timer/Reset 보드 결과를 분리 기록한다. 기존 10장 결과를 자동 승계하지 않는다.

### P2-01 — Vitis 2024.2 플랫폼 갱신 절차 구체화 (선택 편집 개선)

- HTML의 `Platform 갱신`만으로는 실행 위치가 불명확하다.
- UG1400 2024.2의 `platform component → Settings → vitis-comp.json → Switch XSA` 경로를 한 줄로 표기하면 따라하기 재현성이 높아진다.
- 다만 로컬 플랫폼 파일이 실제 존재하는지와 해당 컴포넌트 종류는 확인 전이다.

### P2-02 — 단계 소스 두 개의 모듈명 동일 (실습 주의)

- `step1_basys3_soc11_top.v`와 `step2_basys3_soc11_top.v` 모두 `module basys3_soc11_top`을 선언한다.
- 두 파일을 **같은 Design Sources에 동시에 추가**하면 중복 정의 문제가 생길 수 있다.
- HTML은 기존 `basys3_soc11_top.v` **내용 교체**로 안내하고 있다. 학생이 파일 추가가 아닌 교체를 했는지 Sources에서 확인하면 된다. 1·2단계 소스를 서로 다른 프로젝트/스냅샷으로 보관하는 것도 가능하다.

## 4. 현재 기술적 결론

- **정적 동작 계약:** 1단계에서 SW0~13 미러·UART LED14·Timer LED15, 2단계에서 SW13→LED13만 제외하고 LED13을 OFF 고정하는 연결은 **기존 10장 소프트웨어 마스크 및 XDC와 모순이 없다**.
- **실제 설계 판정:** 미확정. 10장 자동 생성 Wrapper의 포트 선언·Vivado 합성/배치배선/DRC/Timing·ELF와 새 XSA·실물 회귀는 실증되지 않았다.
- **발견된 확정 문서 오류:** 1건(`VALIDATION.md` 잘못된 16비트 SW 미러 표현) — 교정 완료.
- **잔여 검증 차단:** P1-01/03/04. **P0 확정 0건, P1 4건(교정 1·미해결 3), P2 2건.**
- **독립성:** ChatGPT 단독 정적 검증. 다른 AI 의견 인용/요청·협의 없음.

**최소 실물 검증 순서:** 실제 Wrapper 포트 확인 → 1단계 Elaboration/Synthesis/Bitstream/XSA/ELF/보드 → 2단계 코드 교체·Elaboration/Synthesis/N3/Bitstream/XSA/ELF/보드. 검증 기록은 `verification_record.md`에 별도로 보존한다.
