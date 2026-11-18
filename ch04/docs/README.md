# P3-04 동기 메모리 계약

Issue #9 기준. `bram_sync_buffer(DATA_WIDTH=16, ADDR_WIDTH=8)`는 256단어 버퍼다.
포트는 `clk, resetn, wr_en, wr_addr, wr_data, rd_en, rd_addr, rd_data, rd_valid`다.
상승 에지 k의 요청은 k 직후 출력되며 에지 전 조합 출력은 없다.
Reset은 읽기 출력/Valid만 0으로 만들고 저장 배열은 보존한다. Reset 중 쓰기는 무시한다.
rd_en=0이면 rd_data 유지, rd_valid=0. 입력/가중치는 같은 RTL의 독립 인스턴스다.
동일 주소 동시 읽기/쓰기는 금지한다. 미기록 주소 읽기도 금지하며 Python/TB가 탐지한다.
서로 다른 주소 동시 읽기/쓰기는 허용한다. 메모리 초기값은 X이며 0으로 가정하지 않는다.
`ram_style`은 합성 의도다. 합성·타이밍·보드·Vitis는 미수행이다.

```bash
bash part03/ch04/scripts/run_sim.sh
```

기본 16비트/256단어와 비교 8비트/8단어를 고정 seed 304로 실행한다.
01~03장 회귀 로그는 validation에 별도로 보존한다.
