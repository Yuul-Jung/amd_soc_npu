# 제3부 · 준비~12장 제작 및 적대적 정적 검증 v01

> 기준: 2026-11-17 · 저장소 `Yuul-Jung/amd_soc_rtl/main`, 최초 소스 확인 `f85c661eebf9156c9d19acd6621275d0ea702ccd`, 이후 신규 통합 RTL/학습안내서 추가. **이 문서는 GitHub 실제 파일 및 HTML 정적 링크를 검사한 결과이며, Icarus RTL 시뮬레이션·Vivado 합성·실물 검증을 새로 수행했다는 뜻이 아님.**

## 1. 실제 생성된 범위

| 범위 | 코드·자료 | 실행 증거와 경계 |
|---|---|---|
| 00 UART 준비 | `common/rtl/uart_rx.v`, `uart_tx.v`, `uart_core.v`, `uart_echo_controller.v`; `ch00` Top/TB/실행기 | 새 Echo TB 작성, **현재 Icarus 재실행 미검증** |
| 01~10 기존 독립 RTL | `mac_core` → `dsp_multiplier` → `mac_pipeline_core` → `bram_sync_buffer` → `fixed_quantizer` → `precision_compare` → `vector_dot_core` → `pe_array4` → `dense_layer4` → `npu_core` | 각 장 RTL/TB/스크립트·이전 기록 보존; 새 UART 통합 성공을 의미하지 않음 |
| 11 UART 직접 모델 적재 | `uart_npu_command_controller.v`의 X/W/B/R 바이너리 명령과 주소·길이 검사 | UART RX/메모리 쓰기/ACK/결과 통합 TB 작성. 실제 시험 새 실행 필요 |
| 12 소형 NPU 통합 | `npu_engine4.v`, `npu_dsp_mac_lane.v`, `basys3_npu_top.v`, `npu_display_controller.v`, `npu_reset_controller.v`, XDC | 실제 DSP→등록 곱→누산 4PE, signed score·Argmax4. 실제 회로 기능 시뮬레이션 및 Vivado 합성 미검증 |
| 00~12 HTML | `part03/index.html` 및 `ch00~ch12` 13장 개별 페이지 | **14개 파일** 정적 링크/본문 구조 검사; 브라우저 실렌더·모바일 메뉴·웹 게시 확인은 미실행 |
| VS Code 환경 | `.vscode/tasks.json`, `run_batch_00_12.sh`, `run_demo.sh`, `run_engine.sh`, 독립 Vivado Tcl/Shell | 명령 준비 완료, 도구 실제 호출 여부는 VS Code 사용자 로컬 환경에서 확인 필요 |

## 2. 정적 분석 및 경로 무결성

- `part03/index.html` 및 00~12장 총 14개 HTML의 로컬 상대 `href`·`src`를 **GitHub 실제 저장소 트리**와 대조. **깨진 로컬 파일 경로 0건**.
- 14개 모두 `../assets/education/site.css`, `../assets/education/site.js`가 존재. 각 페이지의 좌측 내비게이션 스크립트·코드 영역 포함 확인.
- 소스에 내부 개인 절대경로, API 토큰·비밀키, 알려진 SSH IP가 포함되었는지 기본 문자열 검사. 매칭된 노출 패턴 0건. 추가 이미지·브라우저 렌더·메타데이터 검사 필요.
- **외부 이미지 의존성 14건:** 모든 HTML 헤더가 `https://raw.githubusercontent.com/Yuul-Jung/amd_soc/main/part03/assets/hero-bookshelf.jpg`을 참조한다. `amd_soc`이 비공개이거나 해당 Raw URL을 외부에서 읽을 수 없다면 책장 이미지는 표시되지 않는다. 이미지 파일을 `amd_soc_rtl`로 실제 복제하지 않았으므로 **표준 사진 로컬 자산 보존 / 브라우저 성공이라고 판정 금지**.
- `rule_md/AGENTS.md`, `code/code-development-rules.md`, `vscode/vscode-rules.md`, `web/education-html/STANDARD.md` 원칙에 따라 기존 원본 유지·기능별 분리·실제 검증 종류 구분.

## 3. 적대적 발견 및 보완

| 중요도 | 검사 | 확인/조치 |
|---|---|---|
| P0 | TB가 실제 UART 결과 대신 정답을 CSV에 쓰는 증거 왜곡 | `tb_npu_uart.sv`에서 **실제 TX 파형 복조 후 signed 41비트 점수를 디코딩해 기록**하도록 수정 |
| P0 | UART 텍스트 형식 경계 | 네 점수 구분 콤마 및 CR 문자를 수신 비트에서 확인하도록 TB 강화 |
| P1 | VS Code의 '01~10 회귀' Task가 실제로 00~12 전체 실행 | 별도 `part03/scripts/run_legacy_01_10.sh`를 작성하고 Task 대상 교체 |
| P1 | 03장 기존 MAC Pipeline 구현이 12장 최종 인스턴스로 직접 연결되지 않음 | **잔여 구현 차이**로 명시. 12장은 02 DSP 등록 곱 + 신규 signed 누산 2단계 구현; 직접 원본 03장 통합이라고 주장하지 않음 |
| P1 | UART RX 깊은 FIFO·CRC·중간 끊김·재전송 | **미지원/미검증**. STOP-AND-WAIT 계약으로 현 범위 한정; 11장 바이너리 프레임 무단 확장 금지 |
| P1 | X/W BRAM 진짜 FPGA BRAM·DSP 실제 배치 | `ram_style`·`use_dsp` 주석만으로 FPGA 자원 사용 확정 금지. 별도 Vivado Tcl을 추가했으나 실행 보고서 확보 전 NOT_RUN |
| P1 | 시험 자동 회귀 결과 파일 재사용 | `run_batch_00_12.sh`는 실행별 로그와 출력 파일 새로쓰기 시간을 검사. 터미널에서 실제 실행하기 전 이전 로그와 혼합 금지 |
| P1 | HTML 교육 표준 실물 점검 | 로컬 링크는 정적 정상, **외부 책장 이미지·브라우저 화면/모바일 동작/웹 배포**는 미확인 |
| P2 | 코드 입력 명령/출력 부호 | 4샘플 raw 점수는 각각 `[2,0,0,-2]`, `[0,2,-2,0]`, `[0,-2,2,0]`, `[-2,0,0,2]`. 12장은 ReLU 전 원점수 표시. 동점 낮은 번호 우선 |

## 4. VS Code에서 실제로 수행할 최종 게이트

```bash
# ① Icarus, Python 사용 가능 여부
command -v iverilog
command -v vvp
command -v python3

# ② 01~10장 기존 회귀 — 신규 통합과 결과 분리
bash part03/scripts/run_legacy_01_10.sh

# ③ 00장 UART Echo 실핀 비트파형 시험
bash part03/ch00/scripts/run_sim.sh

# ④ 12장 UART 외 DSP 4PE NPU 엔진 검증
bash part03/mini_npu/scripts/run_engine.sh

# ⑤ 11~12장 실제 UART RX→NPU→UART TX + PC 정수 대조
bash part03/mini_npu/scripts/run_demo.sh

# ⑥ 00~12장 전체 회귀 보고서 생성
bash part03/mini_npu/scripts/run_batch_00_12.sh

# ⑦ Vivado 설치 환경에서만 신규 독립 프로젝트 합성
bash part03/mini_npu/scripts/run_vivado_synth.sh
```

`run_demo.sh`는 실제 Icarus TX 복조 CSV와 PC 정수 기준 모델 비교를 모두 통과해야 하며, 실행이 중단되면 결과를 PASS로 인정하지 않는다.

### 판정

- **소스 및 개별 HTML 00~12장 작성:** FILE_PRESENT / SOURCE_REVIEWED.
- **기존 01~10장 단독 RTL:** 원본의 과거 PASS 이력 존재, 이 검토에서 재실행하지 않음.
- **신규 00/11/12장 RTL 시뮬레이션:** NOT_RUN, 사용자 VS Code에서 실제 실행 필요.
- **Vivado 합성/Timing:** NOT_RUN.
- **Basys3 실물 UART·LED·FND:** NOT_RUN, 후반 사용자와 공동 일괄 검증.
- **HTML 실제 브라우저·GitHub Pages:** NOT_RUN, 외부 hero 이미지 접근은 미확인.

**다음 최우선 작업:** VS Code에서 00~12 전체 회귀의 진짜 컴파일/시뮬레이션/CSV 결과 확보. 실패가 나오면 해당 신설 코드만 최소 수정하고 원본 01~10장 RTL은 보존한다.
