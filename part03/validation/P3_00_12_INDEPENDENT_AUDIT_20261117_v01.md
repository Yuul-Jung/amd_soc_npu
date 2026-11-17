# 제3부 00~12장 독립 점검 보고서 v01

> 기준일: 2026-11-17 / 저장소: `Yuul-Jung/amd_soc_rtl` / 범위: `part03/`
>
> **판정 원칙:** 저장소 API를 이용한 정적 검사·문서 원본 비교는 RTL 시뮬레이션, Vivado 합성 또는 실물 동작과 구분한다.

## 1. 확인 및 개선

| 항목 | 수행한 확인 | 판정 |
|---|---|---|
| 교재 구성 | `index.html` 및 `ch00~ch12` HTML 13개; `course.json` | 파일 존재 확인 |
| 교재 버전 | 장별 `_v02.html` 13개와 `course.json: v02` 일치, 구 `_v01.html` 작업 트리에서 정리 | 정적 확인 |
| 상대경로 | HTML 14개에서 `href/src` 참조 중 내부 파일 링크 44개, 누락 0개; 페이지 내 앵커 누락 0개 | 독립 정적 검사 PASS |
| 상단 사진 | 기존 비공개 `amd_soc` Raw URL 대신 공개 `rule_md`의 **동일한 Git blob**(`fff5df1a2b58078f4523b825441b4cc9708de035`)을 참조, 14개 HTML에 반영 | 파일 동일성·참조 정적 확인 / 브라우저 표시 별도 미확인 |
| 원본 01~10장 | SHA-256 매니페스트 79개 기록의 원본 파일 중 중복을 제거한 실제 파일 55개의 해시 대조 | **55/55 일치** (실행 재검증 아님) |
| Basys3 XDC | `Digilent/digilent-xdc/Basys-3-Master.xdc`와 클록/BTNC/USB UART/LED/FND 32개 핀 직접 비교 | **32/32 일치**, 중복 0; 10ns 클록 제약 존재 |
| 정적 검사기 | `check_static.py`에 기존 누락된 실제 상대경로·앵커·비공개 헤더 이미지 참조 검사를 추가 | 로직 단위 Python 시험 PASS / 저장소 전체 `check_static.py` 실행은 미실행 |
| 신규 RTL | 00·11·12장 RTL 및 TB 파일 존재, 신규 UART FIFO 16바이트 커밋 확인 | 작성·코드 열람, **RTL_SIM_PASS 아님** |

## 2. GitHub 반영

- `dccf8ca5c4455b62725580cd0e51879951b124dd` — 상단 이미지 참조의 비공개 의존성 해소, HTML v02 및 목차 동기화.
- `a91b5245ee172196da226cae024f6b415fa3513d` — 실제 HTML 링크 검증을 `check_static.py`에 추가.
- 기존 ch01~ch10 RTL 원본 및 SHA-256 매니페스트는 변경하지 않음.

## 3. 자동 실행 게이트 — 현재 실패 (원인 미확정)

GitHub Actions 워크플로 `P3 00-12 RTL Regression`에서 실패를 확인했다.

| Run ID | 대상 커밋 | 현재 확인 |
|---|---|---|
| 44027355652 | `8964c7d` | failure |
| 44027598172 | `fecae86` | failure |
| 44028813672 | `dccf8ca` | failure; failed jobs 재실행(attempt 2)도 failure |

- 세 실행에서 해당 Job의 상세 단계 `steps`가 `null`, `logs_url`이 `null`로 반환됐고 아티팩트가 없었다. 이 기록으로는 **RTL 컴파일이 실제로 시작되었는지**, 어디서 실패했는지 확인할 수 없다.
- 실행 Job 기록이 없다는 사실만으로 RTL 소스가 실패했다거나, GitHub 과금·러너 설정이 문제라고 단정하지 않는다.
- 독립 검사에 사용한 현재 실행 환경에는 `iverilog`, `vvp`, `vivado`가 없어 RTL 시뮬레이션·합성을 직접 수행하지 못했다.
- 따라서 **`RTL_SIM_PASS`, `SYNTH_TIMING_PASS`, `BOARD_PASS`, `WEB_PASS` 미부여**.

## 4. 잔여 Gate

1. CI Job 초기화 실패 원인을 GitHub Actions의 실행/계정/러너 환경에서 확인하고 로그를 복구해야 한다. CI가 정상 기동하면 `python3 part03/validation/check_static.py`와 `bash part03/mini_npu/scripts/run_batch_00_12.sh` 결과를 확보한다.
2. 신규 UART Core의 RX/TX 16바이트 FIFO는 동시 push/pop, full/empty, reset, RX overrun 등 별도 경계 테스트가 필요하다. **새 기능이므로 실행 검증 대기**.
3. 제3부 03장 `mac_pipeline_core.v`가 12장에 직접 인스턴스화되지 않은 것은 문서에 구분돼 있으며, 통합 완료로 보고하지 않는다.
4. Vivado에서 DSP/BRAM 실제 추론·자원·Timing 보고서를 확보하고, Basys3 물리 UART/LED/FND 동작 및 브라우저 표시를 별도 확인한다.

**독립 판정:** HTML/원본 소스 해시/XDC 정적 무결성 통과. 자동 회귀·합성·실물·웹 표시 성공은 미확인. 기존 정상 소스 보존, 필수 수정 우선.
