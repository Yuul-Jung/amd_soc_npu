#!/usr/bin/env python3
"""1장 UART 계산기 기준 모델.

명령 순서(보낼 바이트, sw 값)를 정하고, 보드가 돌려줄 응답 바이트를 계산해
p01/tb/p01_cases_s{STAGE}.txt로 쓴다 (STAGE = 끝낸 서브젝트 수 1~4, 보드 Top 빌드 옵션과 같음).
TB는 이 파일만 보고 판정한다.

  python3 p01/reference/p01_model.py          # 자체 시험 + 사례 파일 생성
"""
import os
import struct
import sys

ACC_WIDTH = 40
CORE = {0: 2, 1: 3, 2: 4, 3: 4}  # sw 값 → 서브젝트 번호 (1-2 mac_core, 1-3 DSP+누산, 1-4 파이프라인)
LAT = {2: 1, 3: 2, 4: 2}         # 서브젝트별 지연 클록: 1-2 = 1, 1-3 = 곱 레지스터 + 누산 레지스터 = 2, 1-4 = 2
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "tb", "p01_cases_s%d.txt")


def wrap(v):
    """40비트 2의 보수로 접는다 (RTL 누산기와 같음)."""
    v &= (1 << ACC_WIDTH) - 1
    return v - (1 << ACC_WIDTH) if v >> (ACC_WIDTH - 1) else v


class Calc:
    def __init__(self, stage=4):
        self.acc = 0
        self.stage = stage

    def step(self, sel, data):
        """보낼 바이트 → 응답 바이트."""
        op = data[0]
        if self.stage < 2 and op != ord("S"):
            return bytes([op])      # 1-1까지: MAC 코어가 없어 'M'·'C'도 에코
        if op == ord("M"):
            a, b = struct.unpack(">hh", bytes(data[1:5]))
            self.acc = wrap(self.acc + a * b)
            core = min(CORE[sel], self.stage)           # 아직 없는 코어는 앞 코어가 대신
            text = "A:%010X L:%X\r\n" % (self.acc & ((1 << ACC_WIDTH) - 1), LAT[core])
            return text.encode()
        if op == ord("C"):
            self.acc = 0
            return b"OK\r\n"
        if op == ord("S"):
            return b"I\r\n"
        return bytes([op])          # 1-1 에코


def m(a, b):
    return [ord("M")] + list(struct.pack(">hh", a, b))


C = [ord("C")]

# (서브젝트, sw, 보낼 바이트). 안내서 '보드에서 볼 것' 절차와 똑같은 순서다.
# 서브젝트마다 'C'로 누산값을 0으로 만들고 시작하므로, 어느 서브젝트부터 보드에서 해도 화면이 같다.
CASES = [
    ("1-1", 0, [ord("Z")]),
    ("1-1", 0, [ord("5")]),
    ("1-1", 0, [ord("S")]),
    ("1-2", 0, C),
    ("1-2", 0, m(3, 4)),
    ("1-2", 0, m(3, 4)),
    ("1-3", 0, C),
    ("1-3", 1, m(3, 4)),
    ("1-3", 0, m(3, 4)),
    ("1-3", 1, m(-2, 5)),
    ("1-4", 0, C),
    ("1-4", 2, m(-32768, 32767)),
    ("1-4", 2, m(100, -7)),
    ("1-4", 0, m(32767, 32767)),
]


def self_test():
    c = Calc()
    assert c.step(0, m(3, 4)) == b"A:000000000C L:1\r\n"
    assert c.step(0, m(3, 4)) == b"A:0000000018 L:1\r\n"
    assert c.step(2, m(1, 1)) == b"A:0000000019 L:2\r\n"
    assert c.step(0, [ord("C")]) == b"OK\r\n"
    assert c.step(1, m(-1, 1)) == b"A:FFFFFFFFFF L:2\r\n"
    assert wrap((1 << 39)) == -(1 << 39)
    c3 = Calc(stage=3)
    assert c3.step(2, m(1, 1)) == b"A:0000000001 L:2\r\n"   # sw=2인데 1-4가 없으면 1-3 코어
    c2 = Calc(stage=2)
    assert c2.step(1, m(1, 1)) == b"A:0000000001 L:1\r\n"   # sw=1인데 1-3이 없으면 1-2 코어
    c1 = Calc(stage=1)
    assert c1.step(0, m(3, 4)) == b"M" and c1.step(0, [ord("S")]) == b"I\r\n"
    print("PYTHON_P01_SELF_TEST_PASS")


def main():
    self_test()
    for stage in range(1, 5):
        c = Calc(stage)
        lines = ["# subject sel n_tx tx... n_rx rx... (16진수). p01_model.py가 만든다. 직접 고치지 않는다."]
        cases = [x for x in CASES if int(x[0][2]) <= stage]
        if stage == 1:
            cases = cases + [("1-1", 0, m(3, 4)[:1])]   # 1-1 빌드에서 'M'은 에코
        for subj, sel, data in cases:
            resp = c.step(sel, data)
            lines.append(" ".join([subj, "%x" % sel, "%x" % len(data)] + ["%02x" % x for x in data]
                                  + ["%x" % len(resp)] + ["%02x" % x for x in resp]))
            if stage == 4:
                print("PYTHON_P01_CASE %s sw=%d tx=%s rx=%r" % (subj, sel, bytes(data).hex(), resp.decode()))
        lines.append("END %04x" % (c.acc & 0xFFFF))
        with open(OUT % stage, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        print("PYTHON_P01_VECTORS stage=%d cases=%d final_led=0x%04X" % (stage, len(cases), c.acc & 0xFFFF))
    return 0


if __name__ == "__main__":
    sys.exit(main())
