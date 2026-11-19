#!/usr/bin/env python3
"""4장 784 가속기 보드 기준 모델.

명령 순서를 정하고 보드가 돌려줄 응답을 계산해 p04/tb/p04_cases_s{STAGE}.txt (STAGE 1~4)와
표시용 설명 p04/tb/p04_case_labels_s{STAGE}.txt를 쓴다.
계산은 서브젝트 기준 모델 함수를 그대로 쓴다:
  4-1 구06장: 05장 quantize (INT8 SHIFT 8, INT16 SHIFT 4)
  4-2·4-3 VS Code 판 구17·18장: quantize_model · quantize_x · model(13타일 외부 누산)
  4-4 VS Code 판 구19장: config_cycles (1PE·4PE·8PE 클록)
시연 그림: 18장 고정 표본 파일의 시험 #92 (숫자 9, 18장 PC 평가에서 INT8 → 4, INT16 → 9).

  python3 p04/reference/p04_model.py
"""
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "ch05" / "reference"))
from fixed_reference import quantize                                         # noqa: E402  (구05장)
from part03.host_tools.p3_integer_reference import dot_signed                # noqa: E402
from part03.ch17.reference.tile784_reference import model, tile_ranges       # noqa: E402  (구17장)
from part03.ch18.reference.precision_reference import quantize_model, quantize_x  # noqa: E402  (구18장)
from part03.ch19.reference.arch_reference import config_cycles               # noqa: E402  (구19장)

CASES_OUT = ROOT / "p04" / "tb" / "p04_cases_s%d.txt"
LABELS_OUT = ROOT / "p04" / "tb" / "p04_case_labels_s%d.txt"
F32 = ROOT / "part03" / "ch18" / "reference" / "mnist_linear_f32.json"
SAMPLES = ROOT / "part03" / "ch18" / "reference" / "mnist_rtl_samples.txt"
ACC_W, BIAS_W = 41, 40
DEMO = 92                         # 시험 번호
PE_TILE = 6                       # 4-4에서 쓰는 타일 (그림 가운데 줄)
CRLF = "\r\n"
NEED = {"S": 0, "Q": 4, "B": 7, "V": 3, "A": 1, "X": 2, "T": 2, "U": 3, "K": 1}
MIN_STAGE = {"B": 2, "V": 2, "A": 2, "X": 2, "T": 2, "U": 4, "K": 4}


def h(v, n):
    return format(v & ((1 << (4 * n)) - 1), "0%dX" % n)


def sample(idx):
    for ln in SAMPLES.read_text(encoding="utf-8").splitlines():
        f = ln.split()
        if f and f[0] == str(idx):
            return int(f[1]), [int(v) for v in f[2:5]], [int(v) for v in f[5:]]
    raise KeyError(idx)


class Engine:
    """p3_tile784_10 한 개의 바깥 동작 (17장 상태 표 중 이 장에서 쓰는 부분)."""

    def __init__(self, bits):
        self.bits = bits
        self.state = "IDLE"
        self.bank = [[None] * 64 for _ in range(10)]
        self.w = [[None] * 784 for _ in range(10)]      # 이번 추론에 실제로 쓰인 가중치
        self.b = [0] * 10
        self.x = [None] * 784
        self.next = 0
        self.frame = None


class Board:
    def __init__(self, stage):
        self.stage = stage
        self.eng = [Engine(8), Engine(16)]
        self.pe = {1: [None] * 64, 4: [[None] * 64 for _ in range(10)], 8: [[None] * 64 for _ in range(10)]}
        self.view, self.cls, self.cls_ok = 0, 0, False

    def held8(self):
        return self.eng[0].frame is not None

    def step(self, data):
        c = chr(data[0])
        if c not in NEED or self.stage < MIN_STAGE.get(c, 1):
            return "?" + CRLF
        hd, body = data[1:1 + NEED[c]], data[1 + NEED[c]:]
        if c == "S":
            return "I" + CRLF
        if c == "Q":
            v = struct.unpack(">i", bytes(hd))[0]
            q8, o8 = quantize(v, 8, 8, 1, 1)
            q16, o16 = quantize(v, 16, 4, 1, 1)
            self.view = q16 & 0xFFFF
            return "Q:%s,%s O:%d%d" % (h(q8, 2), h(q16, 4), o8, o16) + CRLF
        if c in "UK":
            g = hd[0]
            if g not in (1, 4, 8) or (c == "U" and not (hd[1] < 10 and 1 <= hd[2] <= 64)):
                return "ERR" + CRLF
            if c == "U":
                vals = [struct.unpack("b", bytes([v]))[0] for v in body]
                for i, v in enumerate(vals):
                    if g == 1:
                        self.pe[1][i] = v
                    else:
                        self.pe[g][hd[1]][i] = v
                return "OK" + CRLF
            x = self.eng[0].frame
            assert x is not None
            cyc = config_cycles()
            if g == 1:
                scores = [dot_signed(x, self.pe[1])]
                n = cyc["PE1_pass"]
            else:
                scores = [dot_signed(x, row) for row in self.pe[g]]
                n = cyc["PE%d" % g]
            self.view = n
            return "K%d:%s " % (g, h(n, 4)) + ",".join(h(s, 7) for s in scores) + CRLF
        p = hd[0]
        if p > 1 or (p == 1 and self.stage < 3):
            return "ERR" + CRLF
        e = self.eng[p]
        wide = p == 1
        if c == "B":
            if hd[1] >= 10:
                return "ERR" + CRLF
            assert e.state == "IDLE"
            v = int.from_bytes(bytes(hd[2:7]), "big")
            e.b[hd[1]] = v - (1 << 40) if v >> 39 else v
            return "OK" + CRLF
        if c in "VX":
            if wide:
                vals = [struct.unpack(">h", bytes(body[2 * i:2 * i + 2]))[0] for i in range(len(body) // 2)]
            else:
                vals = [struct.unpack("b", bytes([v]))[0] for v in body]
            if c == "V":
                if not (hd[1] < 10 and 1 <= hd[2] <= 64):
                    return "ERR" + CRLF
                for i, v in enumerate(vals):
                    e.bank[hd[1]][i] = v
                return "OK" + CRLF
            if hd[1] != 64:
                return "ERR" + CRLF
            e.frame = vals
            return "OK" + CRLF
        if c == "A":
            assert e.state == "IDLE"
            e.state, e.next = "LOAD", 0
            return "OK" + CRLF
        # T
        t = hd[1]
        if t >= 13:
            return "ERR" + CRLF
        if e.state != "LOAD":
            return "E1" + CRLF                                  # 17장 ERR_STATE
        assert t == e.next and e.frame is not None
        s, n = tile_ranges()[t]
        for cl in range(10):
            e.w[cl][s:s + n] = e.bank[cl][:n]
        e.x[s:s + n] = e.frame[:n]
        e.frame = None                                          # 타일이 끝나면 프레임을 놓는다
        e.next += 1
        if t < 12:
            self.view = t
            return "T%X" % t + CRLF
        _, scores, cls, ovf = model(e.x, e.w, e.b, ACC_W, BIAS_W, e.bits)
        e.state = "IDLE"
        self.view, self.cls, self.cls_ok = cls, cls, True
        return "C%X:" % cls + ",".join(h(v, 11) for v in scores) + (" V" if ovf else "") + CRLF

    def led(self):
        onehot = (1 << self.cls) if self.cls_ok else 0
        return onehot | (int(self.eng[1].frame is not None) << 14) | (int(self.held8()) << 15)


def elems(vals, wide):
    out = []
    for v in vals:
        out += list(struct.pack(">h", v)) if wide else [v & 0xFF]
    return out


def run_784(p, qm, xq, add, tag):
    """784 추론 한 번: Bias 10 → A → 타일마다 V 10 · X · T (PC 도구 'digit'과 같은 순서)."""
    wide = p == 1
    for cl in range(10):
        add([ord("B"), p, cl] + list((qm["b"][cl] & ((1 << 40) - 1)).to_bytes(5, "big")), f"load Bias {tag}")
    add([ord("A"), p], "")
    for t, (s, n) in enumerate(tile_ranges()):
        for cl in range(10):
            add([ord("V"), p, cl, n] + elems(qm["w"][cl][s:s + n], wide), f"load W {tag} 타일 {t}")
        xt = xq[s:s + n] + [0] * (64 - n)
        add([ord("X"), p, 64] + elems(xt, wide), f"X {p} 64 ({tag} 타일 {t} x{', 16 + 0 48개' if n < 64 else ''})")
        add([ord("T"), p, t], "")


def build_cases():
    label, preds, px = sample(DEMO)
    m = json.loads(F32.read_text(encoding="utf-8"))
    q8m, q16m = quantize_model(m, 8), quantize_model(m, 16)
    x8, x16 = quantize_x(px, 8), quantize_x(px, 16)
    cases = []
    add = lambda subj: (lambda d, t="": cases.append((subj, d, t)))
    a = add("4-1")
    a([ord("S")])
    for v in (768, 384, -384, 65536, 0x7FFFFFFF):
        a([ord("Q")] + list(struct.pack(">i", v)))
    a = add("4-2")
    a([ord("T"), 0, 5])                                       # IDLE에서 T → E1
    run_784(0, q8m, x8, a, "INT8")
    a = add("4-3")
    run_784(1, q16m, x16, a, "INT16")
    a = add("4-4")
    s, n = tile_ranges()[PE_TILE]
    for g in (4, 8):
        for cl in range(10):
            a([ord("U"), g, cl, 64] + elems(q8m["w"][cl][s:s + 64], False), f"load PE{g} 타일 {PE_TILE}")
    a([ord("X"), 0, 64] + elems(x8[s:s + 64], False), f"X 0 64 (INT8 타일 {PE_TILE} x)")
    a([ord("K"), 4]); a([ord("K"), 8])
    for cl in range(10):
        a([ord("U"), 1, cl, 64] + elems(q8m["w"][cl][s:s + 64], False), f"U 1 {cl} 64 (PE1에 class {cl} 가중치)")
        a([ord("K"), 1])
    return cases, (label, preds)


def self_test():
    b = Board(4)
    assert b.step([ord("Q")] + list(struct.pack(">i", 768))) == "Q:03,0030 O:00\r\n"
    assert b.step([ord("Q")] + list(struct.pack(">i", 65536))) == "Q:7F,1000 O:10\r\n"
    assert b.step([ord("T"), 0, 0]) == "E1\r\n"
    assert Board(2).step([ord("A"), 1]) == "ERR\r\n"                     # INT16은 4-3부터
    assert Board(1).step([ord("A"), 0]) == "?\r\n"
    c = config_cycles()
    assert (c["PE1_pass"], c["PE4"], c["PE8"]) == (70, 206, 138)
    print("PYTHON_P04_SELF_TEST_PASS")


def main():
    self_test()
    cases, (label, preds) = build_cases()
    for stage in range(1, 5):
        b = Board(stage)
        lines = ["# subject sw n_tx tx... n_rx rx... (16진수). p04_model.py가 만든다. 직접 고치지 않는다."]
        labs = []
        sel = [x for x in cases if int(x[0][2]) <= stage]
        if stage == 1:
            sel = sel + [("4-1", [ord("A"), 0], "")]               # 4-1 빌드에는 784 엔진이 없다 → '?'
        for subj, data, text in sel:
            resp = b.step(data).encode()
            lines.append(" ".join([subj, "0", "%x" % len(data)] + ["%02x" % v for v in data]
                                  + ["%x" % len(resp)] + ["%02x" % v for v in resp]))
            labs.append(text)
            if stage == 4 and resp[:1] in (b"C", b"K"):
                print("PYTHON_P04_CASE %s %s" % (subj, resp.decode().strip()[:40]))
        lines.append("END %04x" % b.led())
        CASES_OUT.with_name(CASES_OUT.name % stage).write_text("\n".join(lines) + "\n", encoding="utf-8")
        LABELS_OUT.with_name(LABELS_OUT.name % stage).write_text("\n".join(labs) + "\n", encoding="utf-8")
        print("PYTHON_P04_VECTORS stage=%d cases=%d tx_bytes=%d final_led=0x%04X"
              % (stage, len(sel), sum(len(d) for _, d, _ in sel), b.led()))
    print(f"PYTHON_P04_DEMO sample=#{DEMO} label={label} pc_pred_float={preds[0]} int8={preds[1]} int16={preds[2]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
