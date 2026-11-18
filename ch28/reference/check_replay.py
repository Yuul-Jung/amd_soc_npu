#!/usr/bin/env python3
"""28장: 펌웨어 응답(PC 실행) + RTL 재생 읽기 값으로 실제 보드가 보낼 응답 줄을 만들어 PC 기대 줄과 비교한다."""
import sys

actual, host_out, expect = sys.argv[1:4]
runs, cur = [], None
for op, off, val in (l.split() for l in open(actual)):
    off, val = int(off), int(val)
    if op == "P":
        cur = {"s": []}; runs.append(cur)
    elif cur is not None and 0x40 <= off <= 0x64:
        cur["s"].append(val - (1 << 32) if val >= 1 << 31 else val)
    elif cur is not None and off == 0x08:
        cur["c"] = val
lines = [l.strip() for l in open(host_out) if l.strip() and not l.startswith("===")]
it = iter(runs)
board = [(lambda r: f"CLASS {r['c']} S " + " ".join(map(str, r["s"])))(next(it)) if l.startswith("CLASS") else l for l in lines]
want = [l.strip() for l in open(expect) if l.strip()]
for k, (g, w) in enumerate(zip(board, want)):
    print(f"REPLY {k}: {g[:60]}{'…' if len(g) > 60 else ''} {'OK' if g == w else 'DIFF'}")
ok = board == want
print(f"{'PROTOCOL_RTL_COMPARE_PASS' if ok else 'PROTOCOL_RTL_COMPARE_FAIL'} replies={len(board)} inferences={len(runs)}")
sys.exit(0 if ok else 1)
