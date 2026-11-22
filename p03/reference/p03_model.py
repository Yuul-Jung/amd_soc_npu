#!/usr/bin/env python3
"""3장 8×8 MNIST 보드 기준 모델.

명령 순서를 정하고 보드가 돌려줄 응답을 계산해 p03/tb/p03_cases_s{STAGE}.txt (STAGE 1~4)로 쓴다.
같은 줄 순서로 p03/tb/p03_case_labels_s{STAGE}.txt에 안내서 표시용 설명을 쓴다.
계산은 서브젝트(VS Code 판 구 15·16장) 기준 모델 함수 dense · infer · argmax_lowest를 그대로 쓴다.
시연 프레임: MNIST t10k에서 숫자 0~9마다 첫 그림 (p03/model/train_p03.py의 to8x8 전처리).

  python3 p03/reference/p03_model.py
"""
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "host_tools"))
sys.path.insert(0, str(ROOT / "p03" / "model"))
sys.path.insert(0, str(ROOT / "part03" / "ch15" / "reference"))
sys.path.insert(0, str(ROOT / "part03" / "ch16" / "reference"))
from part03.host_tools.p3_integer_reference import argmax_lowest   # noqa: E402
from dense_reference import dense                                   # noqa: E402  (3-3 구15장)
from mlp_reference import infer                                     # noqa: E402  (3-4 구16장)
from mnist_idx import images, labels                                # noqa: E402
from train_p03 import to8x8                                         # noqa: E402

CASES_OUT = ROOT / "p03" / "tb" / "p03_cases_s%d.txt"
LABELS_OUT = ROOT / "p03" / "tb" / "p03_case_labels_s%d.txt"
MODEL = json.loads((ROOT / "p03" / "model" / "p03_models.json").read_text(encoding="utf-8"))
CRLF = "\r\n"
NEED = {"S": 0, "F": 1, "p": 1, "W": 4, "B": 5, "R": 0, "H": 0, "G": 0, "Z": 1, "M": 0}
MIN_STAGE = {"W": 2, "B": 2, "R": 2, "H": 3, "G": 3, "Z": 4, "M": 4}
SHAPE = {0: (10, 64), 1: (8, 64), 2: (10, 8)}          # 층 → (class 수, 입력 수)


def h(v, n):
    return format(v & ((1 << (4 * n)) - 1), "0%dX" % n)


class Board:
    def __init__(self, stage):
        self.stage = stage
        self.frame = None                    # 들고 있는 프레임 (64 INT8)
        self.w = {L: [[None] * n_in for _ in range(n_out)] for L, (n_out, n_in) in SHAPE.items()}
        self.b = {L: [0] * n_out for L, (n_out, _) in SHAPE.items()}
        self.shift = 0
        self.view, self.cls, self.cls_ok, self.fshort, self.flong = 0, 0, False, False, False

    def step(self, data):
        c = chr(data[0])
        if c in "\r\n":
            return ""
        if c not in NEED or self.stage < MIN_STAGE.get(c, 1):
            return "?" + CRLF
        p = data[1:1 + NEED[c]]
        if c == "S":
            return "I" + CRLF
        if c == "F":
            n = p[0]
            if not 1 <= n <= 80:
                return "ERR" + CRLF
            px = [struct.unpack("b", bytes([v]))[0] for v in data[2:]]
            assert len(px) == n
            self.frame = px if n == 64 else None
            self.fshort, self.flong = n < 64, n > 64
            return "F:" + ("OK" if n == 64 else "SHORT" if n < 64 else "LONG") + CRLF
        if c == "p":
            if p[0] >= 64 or self.frame is None:
                return "ERR" + CRLF
            v = self.frame[p[0]]
            self.view = v & 0xFFFF
            return "P:" + h(v, 2) + CRLF
        if c in "WB":
            L, cl = p[0], p[1]
            if L > 2 or (L > 0 and self.stage < 3) or cl >= SHAPE[L][0]:
                return "ERR" + CRLF
            if c == "W":
                if p[2] >= SHAPE[L][1]:
                    return "ERR" + CRLF
                self.w[L][cl][p[2]] = struct.unpack("b", bytes([p[3]]))[0]
            else:
                v = int.from_bytes(bytes(p[2:5]), "big")
                self.b[L][cl] = v - (1 << 24) if v >> 23 else v
            return "OK" + CRLF
        if c == "Z":
            if p[0] >= 32:
                return "ERR" + CRLF
            self.shift = p[0]
            return "OK" + CRLF
        if self.frame is None:                # 프레임 없는 start → 코어 error_o
            return "ERR" + CRLF
        x = self.frame
        if c == "M":
            hid, scores, cls = infer(x, self.w[1], self.b[1], self.w[2], self.b[2], self.shift)
            body = "".join(h(v, 2) for v in hid) + " " + ",".join(h(s, 7) for s in scores)
        else:
            L = {"R": 0, "H": 1, "G": 2}[c]
            xin = x[:SHAPE[L][1]]
            for row in self.w[L]:
                assert None not in row, "안 쓴 가중치"
            scores = dense(xin, self.w[L], self.b[L])
            cls = argmax_lowest(scores)
            body = ",".join(h(s, 7) for s in scores)
        self.view, self.cls, self.cls_ok = cls, cls, True
        return c + "%X:" % cls + body + CRLF

    def led(self):
        onehot = (1 << self.cls) if self.cls_ok else 0
        return onehot | (int(self.frame is not None) << 15) | (int(self.fshort) << 14) | (int(self.flong) << 13)


def frame(px):
    return [ord("F"), len(px)] + [v & 0xFF for v in px]


def W(L, c, a, v):
    return [ord("W"), L, c, a, v & 0xFF]


def B(L, c, v):
    return [ord("B"), L, c] + list((v & 0xFFFFFF).to_bytes(3, "big"))


def load(L, w, b):
    """층 L 가중치·Bias 전체를 쓰는 명령 목록 (PC 도구 'load'와 같은 순서)."""
    out = [W(L, c, i, v) for c, row in enumerate(w) for i, v in enumerate(row)]
    return out + [B(L, c, v) for c, v in enumerate(b)]


def demo_frames():
    imgs, labs = images("test"), labels("test")
    first = {}
    for k, lab in enumerate(labs):
        first.setdefault(lab, k)
        if len(first) == 10:
            break
    return [(d, first[d], to8x8(imgs[first[d]])) for d in range(10)]


def build_cases():
    demo = demo_frames()
    lin, mlp = MODEL["linear"], MODEL["mlp"]
    cases = []                               # (서브젝트, 바이트, 설명)
    add = lambda s, d, t="": cases.append((s, d, t))
    d7, d0, d3 = demo[7], demo[0], demo[3]
    add("3-1", [ord("S")])
    add("3-1", frame(d7[2]), f"F 64 (시험 #{d7[1]}, 숫자 7)")
    add("3-1", [ord("p"), 0]); add("3-1", [ord("p"), 27]); add("3-1", [ord("p"), 36])
    add("3-1", frame(d7[2][:63]), "F 63 (짧은 프레임)")
    add("3-1", [ord("p"), 0])
    add("3-1", frame(d7[2] + [0]), "F 65 (긴 프레임)")
    add("3-1", frame(d7[2]), f"F 64 (시험 #{d7[1]}, 숫자 7)")
    for cmd in load(0, lin["w"], lin["b"]):
        add("3-2", cmd, "load linear")
    for d, k, px in (d7, d0, d3):
        add("3-2", frame(px), f"F 64 (시험 #{k}, 숫자 {d})")
        add("3-2", [ord("R")])
    for cmd in load(1, mlp["w1"], mlp["b1"]) + load(2, mlp["w2"], mlp["b2"]):
        add("3-3", cmd, "load mlp")
    add("3-3", frame(d3[2]), f"F 64 (시험 #{d3[1]}, 숫자 3)")
    add("3-3", [ord("H")]); add("3-3", [ord("G")])
    add("3-4", [ord("Z"), mlp["shift"]])
    for d, k, px in demo:
        add("3-4", frame(px), f"F 64 (시험 #{k}, 숫자 {d})")
        add("3-4", [ord("M")])
    return cases


def self_test():
    b = Board(4)
    assert b.step([ord("M")]) == "ERR\r\n"                       # 프레임 없음
    assert b.step(frame([1] * 63)) == "F:SHORT\r\n" and b.frame is None
    assert b.step(frame([1] * 64)) == "F:OK\r\n"
    assert b.step([ord("p"), 5]) == "P:01\r\n"
    assert b.step(W(2, 0, 8, 1)) == "ERR\r\n"                   # 8→10 층은 주소 0~7
    assert b.step(B(1, 8, 0)) == "ERR\r\n"                      # 64→8 층은 class 0~7
    assert Board(2).step(W(1, 0, 0, 1)) == "ERR\r\n"            # 3-2 빌드에는 층 0만
    assert Board(1).step([ord("R")]) == "?\r\n"
    assert h(-1, 7) == "FFFFFFF"
    print("PYTHON_P03_SELF_TEST_PASS")


def main():
    self_test()
    cases = build_cases()
    for stage in range(1, 5):
        b = Board(stage)
        lines = ["# subject sw n_tx tx... n_rx rx... (16진수). p03_model.py가 만든다. 직접 고치지 않는다."]
        labs = []
        sel = [x for x in cases if int(x[0][2]) <= stage]
        if stage == 1:
            sel = sel + [("3-1", [ord("R")], "")]                   # 3-1 빌드에는 코어가 없다 → '?'
        for subj, data, text in sel:
            resp = b.step(data).encode()
            lines.append(" ".join([subj, "0", "%x" % len(data)] + ["%02x" % v for v in data]
                                  + ["%x" % len(resp)] + ["%02x" % v for v in resp]))
            labs.append(text)
        lines.append("END %04x" % b.led())
        CASES_OUT.with_name(CASES_OUT.name % stage).write_text("\n".join(lines) + "\n", encoding="utf-8")
        LABELS_OUT.with_name(LABELS_OUT.name % stage).write_text("\n".join(labs) + "\n", encoding="utf-8")
        print("PYTHON_P03_VECTORS stage=%d cases=%d final_led=0x%04X" % (stage, len(sel), b.led()))
    b = Board(4)
    hits = 0
    for subj, data, text in cases:
        r = b.step(data)
        if subj == "3-4" and r.startswith("M"):
            d = int(prev.split("숫자 ")[1].rstrip(")"))
            hits += int(r[1], 16) == d
            print(f"PYTHON_P03_DEMO {prev} → 클래스 {r[1]}")
        prev = text
    print(f"PYTHON_P03_DEMO_HITS {hits}/10 (MLP, t10k 숫자별 첫 그림)")
    for k in ("linear", "mlp"):
        print(f"PYTHON_P03_MODEL {k} int8_test_acc={MODEL[k]['int8_test_acc']} float_test_acc={MODEL[k]['float_test_acc']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
