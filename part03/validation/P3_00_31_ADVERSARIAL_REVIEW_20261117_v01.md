# 제3부 00~31장 적대적 검증 및 제작 보고서 v01

> 기준: 2026-11-17, `Yuul-Jung/amd_soc_rtl/main`; 공통 기준 `Yuul-Jung/soc/CURRICULUM.md`, `MIGRATION.md`, `VALIDATION.md`, `COLLABORATION.md` 및 `rule_md`.
>
> **확정 범위: 준비 00장 + 정규 01~31장 = HTML 32개. ch32 이후는 미포함.**
> 작성, 호스트 코드 실행, RTL 시뮬레이션, Vivado 합성/타이밍, 실물 보드, 실제 웹 렌더링은 서로 독립 Gate다.

## 1. 실제 제작/검증 범위

| 항목 | 확보 증거 | 검증 판정 |
|---|---|---|
| 00~12장 원형 NPU | 기존 RTL/테스트벤치 보존; 32개 공통 탐색으로 버전 v03 갱신 | HTML 구조 확인 / 기존 RTL 수정 없음 |
| 13~19장 MNIST/MLP | 7개 HTML, `host_tools/p3_integer_reference.py`, 독립 테스트 | Python 호스트 기준모델 8개 테스트 PASS |
| 20~27장 AXI/SoC·성능/전력/CNN | 8개 HTML과 단계별 제어 레지스터/드라이버·설계 예제 | **설계·교육용 가이드만 작성. AXI RTL/IP/BD/Vitis 실장 미검증** |
| 28~31장 종합 | 4개 HTML과 코드/검증 요구조건 | **교육용 가이드만 작성. 안전/보안 실장 미검증** |
| 목차·공통 탐색 | `part03/index.html`, `course.json`; 총 32장·번호 00~31 연속 | GitHub 저장소 실제 파일/참조 대조 PASS |
| HTML 링크 | 각 32개 장의 상대 CSS/JS 링크 64개 대조, 32개 모두 COURSE 32항목 탑재 | API 기반 정적 검증 PASS |
| 독립 Python 코드 | Python 3.13.5에서 정수 모델과 독립 unittest(8 tests) 실행 | **HOST_MODEL_PASS (8/8)** |
| 원본 01~10장 | 기존 소스·해시 이력 유지, 새 변경 없음 | 보존; 금회 RTL 재실행 아님 |
| 신규 00/11/12장 | 실행 스크립트·TB 준비 | **RTL_SIM_PASS 미부여** |
| 13~31장 신규 RTL | 10분류 RTL, AXI IP, Vivado BD, 모터/암호 RTL 등 실장 필요 | **미구현/미검증** |
| Vivado 합성/타이밍, 보드 | 새 환경에서 해당 실행 증거 없음 | **미검증** |
| GitHub Pages 실렌더/모바일 | 실제 브라우저 시험 증거 없음 | **미검증** |

호스트 실험은 실제 GitHub Blob SHA가 일치하는 `p3_integer_reference.py`와 `test_p3_integer_reference.py`를 별도 Python 3.13.5 환경에서 실행했다. `python3 -m unittest part03.host_tools.test_p3_integer_reference -v` 실행 8개 테스트 전체 성공.

## 2. 적대적 검토 결과 및 조치

| 중요도 | 발견 사항 | 반영 및 잔여 Gate |
|---|---|---|
| P1 | 기존 `soc/CURRICULUM.md`의 제3부 '01부터 10장 가안'이 현행 31장과 불일치 | 공통 교육과정 파일에 준비 00 + 01~31 확정 내용 갱신 |
| P1 | 제3부 정적 검사기가 13개 차시로 고정됨 | `check_static.py`의 연속 번호·ID·INDEX 총 32장 검사로 수정 |
| P1 | 12장 `npu_engine4`는 4분류/최대 64입력: 10분류를 자동 지원하지 않음 | 14~17장에 4PE 3그룹, valid lane 및 784 타일링 계약을 명시; **RTL 미구현** |
| P1 | UART FIFO 변경 후 README/기존 테크트리에서 'RX FIFO 없음'으로 표기 | 16바이트 RX/TX FIFO로 문서 수정; 경계/Overrun 재검증 미수행 |
| P1 | 8×8 축소 MNIST와 28×28 원본, 4분류 데모와 숫자 10분류 혼동 가능 | 전처리 모델·가중치·실제 입력 차원 및 출력 수를 분리 |
| P1 | 20~22장 AXI/IP 및 C는 레지스터 계약 예시이며 실제 컴파일러 주소가 없음 | Address Editor/XSA/`xparameters.h` 기반 실값 확인 요구, 성공 주장은 금지 |
| P1 | 산업안전 상태 분류와 모터 안전 정지를 동일하게 취급할 위험 | 비상정지·인터록·전기적 보호는 NPU와 독립 분리 |
| P1 | 31장 SHA-256 일반 해시를 인증이라 오인할 위험 | AES-128 CTR 기밀성·HMAC-SHA-256 인증, Replay/Nonce/Atomic Commit 분리 |
| P2 | 단순 이론적 MAC 수와 실제 FPGA Throughput을 혼동할 위험 | 19/23/24/25장에서 BRAM 공급, 파이프라인, 자원·전력 실측을 별도 필수 증거로 지정 |

## 3. 확인된 31장 고정 테크트리

- 준비 00: 물리 UART Echo
- 01~12: MAC → DSP48E1 → Pipeline → BRAM → 고정소수점 → INT8/16 → Dot → 4PE → Dense → NPU4 → UART 모델 적재 → NPU4 통합
- 13~19: MNIST 8×8/10분류 → 4PE 그룹화 → 64→10 → 64→8→10 → 784 타일 → 정밀도 비교 → 자원/처리량 구조 비교
- 20~27: AXI4-Lite 제어 IP → MicroBlaze V SoC → Vitis C → CPU/NPU 성능 → Timing/Resource → Power/Energy → Tiny CNN → 통합
- 28~31: 손글씨 숫자 인식 → 센서 융합 상태감시 → NPU 보조 모터 제어 → AES/HMAC 보안 UART
- **제외:** 32장부터의 산업안전 특화 후속 장은 정규 31장 목차에 등록하지 않음.

## 4. 후속 검증 Gate

1. **VS Code 신규 RTL:** `bash part03/mini_npu/scripts/run_batch_00_12.sh`와 FIFO 경계 TB를 실행하고 로그/소스 SHA 확보.
2. **13~19 RTL 구현:** 4PE 그룹 스케줄·10개 Score·784 타일·다층 Dense를 새 모듈로 구현, Python 기준모델과 비교.
3. **20~27 SoC:** AXI AW/W 독립 핸드셰이크·B/R 역압력·레지스터·Vitis 실제 주소, Vivado 자원/Timing, 보드 확인.
4. **28~31 종합:** 사용자 입력→예측·경보/모터 정책/암호 인증 모델 적재를 각기 독립 검증. 기능안전·보안 적합성은 과제 밖 별도 평가.
5. **HTML 실물 웹:** 링크 정적 검사와 별도로 브라우저·반응형·메뉴/복사·보안 노출 확인.

**최종 판정:** 제3부 00~31장 차시 범위 확정 및 HTML 안내서 작성, 단독 Python 8건 시험 PASS. 13~31장 신규 회로 구현·RTL Sim·AXI SoC 빌드·실물 시험은 미완료이므로 `RTL_SIM_PASS`, `SYNTH_TIMING_PASS`, `BOARD_PASS`를 부여하지 않는다.
