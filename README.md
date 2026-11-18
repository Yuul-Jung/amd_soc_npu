# Basys3 소형 NPU 교육과정 — 고도화판

[**학습안내서 열기**](index.html)

## 개요

`Yuul-Jung/amd_soc_rtl` 제3부 자료를 기반으로 고도화한 독립 NPU 교육과정입니다.

| 구간 | 장 | 내용 | 상태 |
|---|---|---|---|
| UART 준비 | 00 | UART Echo RTL | HTML v04 · RTL 기존 로그 보존 |
| 독립 RTL | 01~12 | MAC·DSP·BRAM·4PE·통합 NPU | HTML v04 · RTL 기존 로그 보존 |
| 10분류 정수 | 13~19 | 8×8·MLP·784 타일·INT8/16 | HTML v02 · RTL 신규 구현 |
| AXI·SoC | 20~27 | AXI4-Lite·MBV·Vitis·성능 | HTML v02 · RTL 신규 구현 |
| 종합 과제 | 28~31 | MNIST·센서·모터·보안 UART | HTML v02 · RTL 신규 구현 |

## 고도화 내용
- **HTML**: ch00~12를 v03→v04로, ch13~31을 v01→v02로 품질 향상
- **RTL**: ch13~31에 Verilog 구현 및 테스트벤치 신규 추가
- **검증**: 장별 `validation/` 폴더에 시뮬레이션 로그·SHA 관리
- **CI**: GitHub Actions 정적 검사 자동화

## 원본 소스
- RTL 원본: [`Yuul-Jung/amd_soc_rtl/part03/`](https://github.com/Yuul-Jung/amd_soc_rtl/tree/main/part03)
- 규칙 기준: `rule_md` 커밋 `d1b8278d`

## 작업 규칙
- [`AGENTS.md`](AGENTS.md) — AI 에이전트 필수 확인
- [교육 HTML 표준](https://github.com/Yuul-Jung/rule_md/blob/d1b8278d41fca8f5e3960736f3ac9d377e462fda/web/education-html/STANDARD.md)
- [MBV SoC 전용 규칙](rule_md/fpga-soc/MBV_SOC_rules.md)

## 검증 현황 (2026-11-18)
- HTML 정적 검사: 미실시
- RTL 시뮬레이션 ch00~12: 원본 로그 이전 완료 후 재실행 예정
- RTL 시뮬레이션 ch13~31: 신규 구현 후 실행 예정
- Vivado 합성·보드: 미실시
