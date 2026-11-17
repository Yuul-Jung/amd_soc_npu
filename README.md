# Basys3 · MicroBlaze V — 제2부 RTL 자료 보존 및 정리

## 현재 상태

- `part02/index.html`: 제2부 01–20장 통합 입구
- `part02_1/`: 01–10장 배포용 HTML 및 SVG 복사 (개발 소스 전체 미이관)
- `part02_2/guide/`: 11–20장 HTML, 12.1–12.4 파생 실습, C/XDC 예제, 검증 스크립트 복사
- `part02_2/index.html`: 11–20장 링크

## 원본 및 커밋

- 01–10장: [amd_soc main](https://github.com/Yuul-Jung/amd_soc/tree/c506461e4ab0842c68e8afcaaaf605afea170463/part02) @ `c506461e4`
- 11–20장: [amd_soc work/part02-second-half-20261110](https://github.com/Yuul-Jung/amd_soc/tree/8068ec462793b55e1d201b5b8c08096c43c5e7e7/part02) @ `8068ec462`
- 원본과 복사본은 별도 저장소이며 원본은 변경하지 않습니다.

## 이관 게이트

1. 위 HTML 및 부속 자산 이외에 장별 RTL·C·TB·검증 기록은 **일괄 이관 완료 전**입니다.
2. 원본과 동일한 Git Blob SHA로 파일별 무손실 여부를 확인합니다.
3. 내부 링크 검사, RTL 시뮬레이션, Vivado 합성, Vitis, 실물 검증은 각기 별도 판정합니다.
4. 구 저장소의 PR #2는 병합 충돌·실행 검증 미해결 상태이며 이 정리 작업으로 성공 판정을 변경하지 않습니다.
5. 원본 삭제·강제 병합·성공 자료 수정은 금지합니다.
