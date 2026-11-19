#!/usr/bin/env python3
"""3장 8×8 MNIST 보드 PC 쪽 도구: 명령을 바이트로 바꿔 보내고 응답을 출력한다.

  python3 p03/host/p03_send.py --dry digit 0          # 보낼 바이트만 (시험 #0, 숫자 7)
  python3 p03/host/p03_send.py /dev/ttyUSB1 load linear   # 64→10 모델 650개 명령 적재 (3-2)
  python3 p03/host/p03_send.py /dev/ttyUSB1 load mlp      # 64→8·8→10 + shift (3-3·3-4)
  python3 p03/host/p03_send.py COM3 digit 18          # 시험 #18 그림을 8×8로 줄여 F 64 전송
  python3 p03/host/p03_send.py COM3 M                 # MLP 추론
  (pip install pyserial 필요. 115200 8N1. MNIST는 host_tools/mnist_idx.py가 data/mnist에 받는다)

명령 (p03/rtl/p03_console.v): S | F 화소… | p addr | W 층 class addr v | B 층 class v | R | H | G | Z shift | M
"""
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INT = lambda s: int(s, 0)


def frame(px):
    return b"F" + bytes([len(px)]) + bytes(v & 0xFF for v in px)


def W(L, c, a, v):
    return b"W" + bytes([L, c, a, v & 0xFF])


def B(L, c, v):
    return b"B" + bytes([L, c]) + (v & 0xFFFFFF).to_bytes(3, "big")


def model():
    return json.loads((ROOT / "p03" / "model" / "p03_models.json").read_text(encoding="utf-8"))


def encode(args):
    """명령 하나 → [(바이트, 설명)] (load는 여러 개)."""
    op, a = args[0], args[1:]
    if op in ("S", "R", "H", "G", "M"):
        return [(op.encode(), op)]
    if op == "p":
        return [(b"p" + bytes([INT(a[0])]), "p")]
    if op == "Z":
        return [(b"Z" + bytes([INT(a[0])]), "Z")]
    if op == "W":
        return [(W(*map(INT, a)), "W")]
    if op == "B":
        return [(B(*map(INT, a)), "B")]
    if op == "F":
        return [(frame([INT(v) for v in a]), "F")]
    if op == "digit":
        sys.path.insert(0, str(ROOT / "host_tools"))
        sys.path.insert(0, str(ROOT))
        sys.path.insert(0, str(ROOT / "p03" / "model"))
        from mnist_idx import images, labels
        from train_p03 import to8x8
        k = INT(a[0])
        return [(frame(to8x8(images("test")[k])), f"시험 #{k}, 숫자 {labels('test')[k]}")]
    if op == "load":
        m = model()
        if a[0] == "linear":
            L = [(0, m["linear"]["w"], m["linear"]["b"])]
            shift = None
        else:
            L = [(1, m["mlp"]["w1"], m["mlp"]["b1"]), (2, m["mlp"]["w2"], m["mlp"]["b2"])]
            shift = m["mlp"]["shift"]
        out = []
        for layer, w, b in L:
            out += [(W(layer, c, i, v), "W") for c, row in enumerate(w) for i, v in enumerate(row)]
            out += [(B(layer, c, v), "B") for c, v in enumerate(b)]
        if shift is not None:
            out.append((b"Z" + bytes([shift]), "Z"))
        return out
    raise SystemExit("모르는 명령: " + op)


def main(argv):
    if len(argv) < 2:
        raise SystemExit(__doc__)
    port, cmds = argv[0], encode(argv[1:])
    if port == "--dry":
        for data, note in cmds[:3]:
            print("TX", data.hex(" "), "#", note)
        if len(cmds) > 3:
            print(f"... 모두 {len(cmds)}개 명령")
        return 0
    import serial                           # pyserial (보드에서만 필요)
    bad = 0
    with serial.Serial(port, 115200, timeout=2) as s:
        for data, note in cmds:
            s.write(data)
            reply = s.read_until(b"\n").decode("ascii", "replace")
            if len(cmds) == 1 or not reply.startswith("OK"):
                print(note, "→", repr(reply))
            bad += not reply.strip() or reply.startswith(("ERR", "?"))
    if len(cmds) > 1:
        print(f"{len(cmds)}개 명령, 실패 {bad}개")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
