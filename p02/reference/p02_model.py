#!/usr/bin/env python3
"""2장 4뉴런 NPU 보드 기준 모델.

명령 순서(보낼 바이트, sw[3:2])를 정하고 보드가 돌려줄 응답을 계산해
p02/tb/p02_cases_s{STAGE}.txt (STAGE = 끝낸 서브젝트 수 1~8)로 쓴다. TB는 이 파일만 보고 판정한다.
계산은 서브젝트(구 장) 기준 모델 함수를 그대로 쓴다: 05 quantize, 07 dot, 09 dense.

  python3 p02/reference/p02_model.py
"""
import os
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
for ch in ("ch01", "ch05", "ch07", "ch09"):
    sys.path.insert(0, str(ROOT / ch / "reference"))
from mac_reference import wrap              # noqa: E402  (1-2)
from fixed_reference import quantize        # noqa: E402  (2-2)
from dot_reference import dot               # noqa: E402  (2-3)
from dense_reference import dense           # noqa: E402  (2-5)

OUT = ROOT / "p02" / "tb" / "p02_cases_s%d.txt"
CRLF = "\r\n"
NEED = {"S": 0, "X": 3, "W": 4, "x": 1, "w": 2, "Q": 4, "D": 1, "P": 1, "B": 6, "L": 1, "N": 1}
MIN_STAGE = {"Q": 2, "D": 3, "P": 4, "B": 5, "L": 5, "N": 6}


def h(v, n):
    return format(v & ((1 << (4 * n)) - 1), "0%dX" % n)


class Board:
    def __init__(self, stage):
        self.stage = stage
        self.x = [None] * 64                     # 안 쓴 칸은 None (RTL에서는 X)
        self.w = [[None] * 64 for _ in range(4)]
        self.bias = [0] * 4
        self.view = 0
        self.x_seen = [False] * 64               # 2-8 엔진의 적재 확인 비트
        self.w_seen = [[False] * 64 for _ in range(4)]
        self.cls = 0                             # 마지막 추론 클래스 (STAGE 8 표시)
        self.done = False
        self.err = False

    # ── 디버그 콘솔 (sw[2] = 0) ──
    def console(self, data):
        c = chr(data[0])
        if c in "\r\n":
            return ""
        if c not in NEED or self.stage < MIN_STAGE.get(c, 1):
            return "?" + CRLF
        p = data[1:]
        assert len(p) == NEED[c], (c, data)
        if c == "S":
            return "I" + CRLF
        bad = ((c in "Xx" and p[0] >= 64) or (c in "Ww" and (p[0] >= 4 or p[1] >= 64))
               or (c == "B" and p[0] >= 4) or (c in "DPLN" and not 1 <= p[0] <= 64))
        if bad:
            return "ERR" + CRLF
        s16 = lambda hi, lo: struct.unpack(">h", bytes([hi, lo]))[0]
        if c == "X":
            self.x[p[0]] = s16(p[1], p[2])
            return "OK" + CRLF
        if c == "W":
            self.w[p[0]][p[1]] = s16(p[2], p[3])
            return "OK" + CRLF
        if c == "B":
            self.bias[p[0]] = wrap(int.from_bytes(bytes(p[1:6]), "big"), 40)
            return "OK" + CRLF
        if c in "xw":
            v = self.x[p[0]] if c == "x" else self.w[p[0]][p[1]]
            assert v is not None, "안 쓴 칸을 읽음"
            self.view = v & 0xFFFF
            return c.upper() + ":" + h(v, 4) + CRLF
        if c == "Q":
            v = struct.unpack(">i", bytes(p))[0]
            q, ov = quantize(v, 8, 8, 1, 1)
            self.view = q & 0xFFFF
            return "Q:%s O:%d" % (h(q, 2), ov) + CRLF
        n = p[0]
        xs = self.x[:n]
        ws = [row[:n] for row in self.w]
        assert None not in xs, "안 쓴 X"
        if c == "D":
            assert None not in ws[0]
            r = dot(xs, ws[0], 40)
            self.view = r & 0xFFFF
            return "D:" + h(r, 10) + CRLF
        if c == "P":
            assert all(None not in r for r in ws)
            rs = [dot(xs, r, 40) for r in ws]
            self.view = rs[0] & 0xFFFF
            return "P:" + ",".join(h(r, 10) for r in rs) + CRLF
        assert all(None not in r for r in ws)
        vals, mask = dense(xs, ws, self.bias, 16, 40, 0)      # L·N: Dense(+Bias, ReLU, 16비트)
        self.view = vals[0] & 0xFFFF
        return c + ":" + ",".join(h(v, 4) for v in vals) + " O:%X" % mask + CRLF

    # ── 2-7 명령 해석기 (sw[2] = 1) ──
    def write(self, kind, n, a, v):
        if kind == "X":
            self.x[a] = v
            self.x_seen[a] = True
        elif kind == "W":
            self.w[n][a] = v
            self.w_seen[n][a] = True
        else:
            self.bias[n] = v

    def infer(self, length, engine4):
        xs, ws = self.x[:length], [r[:length] for r in self.w]
        if engine4:                              # 2-8 엔진: 원시 점수 = 내적 + Bias, 적재 확인
            if not (all(self.x_seen[:length]) and all(all(r[:length]) for r in self.w_seen)):
                self.err = True
                return "ERR" + CRLF
            scores = [wrap(dot(xs, r, 40) + b, 41) for r, b in zip(ws, self.bias)]
        else:                                    # 누적 npu_core: Dense 결과(ReLU, 16비트)를 41비트로
            scores, _ = dense(xs, ws, self.bias, 16, 40, 0)
        cls = 0
        for i in range(1, 4):
            if scores[i] > scores[cls]:
                cls = i
        self.cls, self.done = cls, True
        return "C%d:" % cls + ",".join(h(s, 11) for s in scores) + CRLF

    def engine(self, data, engine4):
        c = chr(data[0])
        if c in "\r\n":
            return ""
        if c in "0123":                          # 고정 그룹: X0·X1, W[n][0·1], Bias 0, 길이 2
            k = int(c)
            self.write("X", 0, 0, -1 if k & 2 else 1)
            self.write("X", 0, 1, -1 if k & 1 else 1)
            for n in range(4):
                self.write("W", n, 0, -1 if n & 2 else 1)
                self.write("W", n, 1, -1 if n & 1 else 1)
            for n in range(4):
                self.write("B", n, 0, 0)
            return self.infer(2, engine4)
        if c == "S":
            return "I" + CRLF
        p = data[1:]
        ok = ((c == "X" and p[0] < 64) or (c == "W" and p[0] < 4 and p[1] < 64)
              or (c == "B" and p[0] < 4) or (c == "R" and 1 <= p[0] <= 64))
        if c not in "XWBR" or not ok:
            self.err = True
            return "ERR" + CRLF
        if c == "R":
            return self.infer(p[0], engine4)
        s16 = struct.unpack(">h", bytes(p[-2:]))[0] if c in "XW" else 0
        if c == "X":
            self.write("X", 0, p[0], s16)
        elif c == "W":
            self.write("W", p[0], p[1], s16)
        else:
            self.write("B", p[0], 0, wrap(int.from_bytes(bytes(p[1:6]), "big"), 40))
        return "OK" + CRLF

    def step(self, sw, data):
        eng = self.stage >= 7 and bool(sw & 1)          # sw 값 = sw[3:2]
        e4 = self.stage >= 8 and bool(sw & 2)
        return (self.engine(data, e4) if eng else self.console(data)).encode()

    def led(self):
        if self.stage < 8:
            return self.view
        return (1 << self.cls) | (int(self.done) << 14) | (int(self.err) << 15)


def cmd(c, *b):
    return [ord(c)] + list(b)


def X(a, v):
    return cmd("X", a, *struct.pack(">h", v))


def W(n, a, v):
    return cmd("W", n, a, *struct.pack(">h", v))


def B(n, v):
    return cmd("B", n, *(v & ((1 << 40) - 1)).to_bytes(5, "big"))


def Q(v):
    return cmd("Q", *struct.pack(">i", v))


# (서브젝트, sw[3:2], 보낼 바이트). 안내서 '보드에서 볼 것'과 같은 순서. 서브젝트마다 필요한 값을 스스로 쓴다.
CASES = [
    ("2-1", 0, cmd("S")),
    ("2-1", 0, X(0, 3)), ("2-1", 0, X(1, -2)),
    ("2-1", 0, cmd("x", 0)), ("2-1", 0, cmd("x", 1)),
    ("2-1", 0, W(0, 0, 5)), ("2-1", 0, cmd("w", 0, 0)),
    ("2-1", 0, cmd("x", 64)),
    ("2-2", 0, Q(768)), ("2-2", 0, Q(384)), ("2-2", 0, Q(-384)), ("2-2", 0, Q(65536)), ("2-2", 0, Q(-65536)),
    ("2-3", 0, X(0, 1)), ("2-3", 0, X(1, 2)), ("2-3", 0, X(2, 3)), ("2-3", 0, X(3, 4)),
    ("2-3", 0, W(0, 0, 5)), ("2-3", 0, W(0, 1, 6)), ("2-3", 0, W(0, 2, 7)), ("2-3", 0, W(0, 3, 8)),
    ("2-3", 0, cmd("D", 4)), ("2-3", 0, W(0, 3, -8)), ("2-3", 0, cmd("D", 4)), ("2-3", 0, cmd("D", 0)),
    ("2-4", 0, W(1, 0, 1)), ("2-4", 0, W(1, 1, 1)), ("2-4", 0, W(1, 2, 1)), ("2-4", 0, W(1, 3, 1)),
    ("2-4", 0, W(2, 0, -1)), ("2-4", 0, W(2, 1, -1)), ("2-4", 0, W(2, 2, -1)), ("2-4", 0, W(2, 3, -1)),
    ("2-4", 0, W(3, 0, 0)), ("2-4", 0, W(3, 1, 0)), ("2-4", 0, W(3, 2, 0)), ("2-4", 0, W(3, 3, 2)),
    ("2-4", 0, cmd("P", 4)),
    ("2-5", 0, B(0, 0)), ("2-5", 0, B(1, -20)), ("2-5", 0, B(2, 100)), ("2-5", 0, B(3, 65536)),
    ("2-5", 0, cmd("L", 4)),
    ("2-6", 0, cmd("N", 4)), ("2-6", 0, cmd("N", 2)),
    ("2-7", 1, cmd("S")), ("2-7", 1, cmd("0")), ("2-7", 1, cmd("1")), ("2-7", 1, cmd("2")), ("2-7", 1, cmd("3")),
    ("2-7", 0, cmd("x", 0)),
    ("2-8", 1, cmd("2")), ("2-8", 3, cmd("2")), ("2-8", 3, cmd("1")),
]


def self_test():
    b = Board(8)
    assert b.console(Q(384)) == "Q:02 O:0\r\n"                 # 1.5 → 반올림 2
    assert b.console(Q(65536)) == "Q:7F O:1\r\n"               # 포화
    b.console(X(0, 1)); b.console(W(0, 0, -3))
    assert b.console(cmd("D", 1)) == "D:FFFFFFFFFD\r\n"
    # 고정 그룹 1: X = (+1, -1). 원시 점수 0, 2, -2, 0 → 2-8 엔진은 그대로, 누적 core는 ReLU로 -2 → 0
    assert b.engine(cmd("1"), True) == "C1:00000000000,00000000002,FFFFFFFFFFE,00000000000\r\n"
    assert b.engine(cmd("1"), False) == "C1:00000000000,00000000002,00000000000,00000000000\r\n"
    assert Board(1).console(cmd("Q")) == "?\r\n"
    print("PYTHON_P02_SELF_TEST_PASS")


def main():
    self_test()
    for stage in range(1, 9):
        b = Board(stage)
        lines = ["# subject sw n_tx tx... n_rx rx... (16진수). p02_model.py가 만든다. 직접 고치지 않는다."]
        cases = [x for x in CASES if int(x[0][2]) <= stage]
        if stage == 1:
            cases = cases + [("2-1", 0, cmd("Q"))]   # 2-1 빌드에는 양자화기가 없다 → '?'
        for subj, sw, data in cases:
            resp = b.step(sw, data)
            lines.append(" ".join([subj, "%x" % sw, "%x" % len(data)] + ["%02x" % v for v in data]
                                  + ["%x" % len(resp)] + ["%02x" % v for v in resp]))
            if stage == 8:
                print("PYTHON_P02_CASE %s sw=%d%d rx=%r" % (subj, sw >> 1, sw & 1, resp.decode()))
        lines.append("END %04x" % b.led())
        OUT.with_name(OUT.name % stage).write_text("\n".join(lines) + "\n", encoding="utf-8")
        print("PYTHON_P02_VECTORS stage=%d cases=%d final_led=0x%04X" % (stage, len(cases), b.led()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
