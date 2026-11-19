#!/usr/bin/env python3
"""4장 784 가속기 보드 PC 쪽 도구: 명령을 바이트로 바꿔 보내고 응답을 출력한다.

  python3 p04/host/p04_send.py --dry digit 92 int8      # 보낼 명령 수·바이트만 (보드 없이)
  python3 p04/host/p04_send.py /dev/ttyUSB1 Q 65536     # 4-1 INT8·INT16 양자화
  python3 p04/host/p04_send.py /dev/ttyUSB1 digit 92 int8    # 4-2 Bias 10 → A → 13타일(V 10·X·T) → 클래스
  python3 p04/host/p04_send.py COM3 digit 92 int16      # 4-3 같은 그림을 INT16으로
  python3 p04/host/p04_send.py COM3 pe 6                # 4-4 타일 6으로 PE4·PE8·PE1 클록 비교
  (pip install pyserial 필요. 115200 8N1. 그림은 part03/ch18/reference/mnist_rtl_samples.txt의 표본 16개)

명령 형식은 p04/rtl/p04_console.v 머리말. 'digit'·'pe'는 p04/reference/p04_model.py와 같은 순서로 보낸다.
"""
import json
import struct
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
INT = lambda s: int(s, 0)


def elems(vals, wide):
    out = b""
    for v in vals:
        out += struct.pack(">h", v) if wide else bytes([v & 0xFF])
    return out


def quant(bits):
    from part03.ch18.reference.precision_reference import quantize_model
    m = json.loads((ROOT / "part03/ch18/reference/mnist_linear_f32.json").read_text(encoding="utf-8"))
    return quantize_model(m, bits)


def sample(idx):
    for ln in (ROOT / "part03/ch18/reference/mnist_rtl_samples.txt").read_text(encoding="utf-8").splitlines():
        f = ln.split()
        if f and f[0] == str(idx):
            return int(f[1]), [int(v) for v in f[5:]]
    raise SystemExit(f"표본에 시험 #{idx}가 없다 (part03/ch18/reference/mnist_rtl_samples.txt)")


def digit(idx, prec):
    from part03.ch17.reference.tile784_reference import tile_ranges
    from part03.ch18.reference.precision_reference import quantize_x
    p, bits = (1, 16) if prec == "int16" else (0, 8)
    qm, (label, px) = quant(bits), sample(idx)
    xq, wide = quantize_x(px, bits), p == 1
    cmds = [(b"B" + bytes([p, c]) + (qm["b"][c] & ((1 << 40) - 1)).to_bytes(5, "big"), "B") for c in range(10)]
    cmds.append((b"A" + bytes([p]), "A"))
    for t, (s, n) in enumerate(tile_ranges()):
        cmds += [(b"V" + bytes([p, c, n]) + elems(qm["w"][c][s:s + n], wide), "V") for c in range(10)]
        cmds.append((b"X" + bytes([p, 64]) + elems(xq[s:s + n] + [0] * (64 - n), wide), "X"))
        cmds.append((b"T" + bytes([p, t]), f"T {t}"))
    return cmds, f"시험 #{idx}, 숫자 {label}, {prec.upper()}"


def pe(tile):
    from part03.ch17.reference.tile784_reference import tile_ranges
    from part03.ch18.reference.precision_reference import quantize_x
    qm, (_, px) = quant(8), sample(92)
    s, _ = tile_ranges()[tile]
    cmds = [(b"U" + bytes([g, c, 64]) + elems(qm["w"][c][s:s + 64], False), "U") for g in (4, 8) for c in range(10)]
    cmds.append((b"X" + bytes([0, 64]) + elems(quantize_x(px, 8)[s:s + 64], False), "X"))
    cmds += [(b"K\x04", "K 4"), (b"K\x08", "K 8")]
    for c in range(10):
        cmds += [(b"U" + bytes([1, c, 64]) + elems(qm["w"][c][s:s + 64], False), "U"), (b"K\x01", f"K 1 (class {c})")]
    return cmds, f"타일 {tile} (시험 #92 INT8)"


def encode(args):
    op, a = args[0], args[1:]
    if op == "S":
        return [(b"S", "S")], ""
    if op == "Q":
        return [(b"Q" + struct.pack(">i", INT(a[0])), "Q")], ""
    if op == "digit":
        return digit(INT(a[0]), a[1] if len(a) > 1 else "int8")
    if op == "pe":
        return pe(INT(a[0]) if a else 6)
    raise SystemExit("모르는 명령: " + op)


def main(argv):
    if len(argv) < 2:
        raise SystemExit(__doc__)
    port, (cmds, what) = argv[0], encode(argv[1:])
    total = sum(len(d) for d, _ in cmds)
    if port == "--dry":
        print(f"{what} 명령 {len(cmds)}개, 보낼 바이트 {total} (115200 bps로 약 {total * 10 / 115200:.2f}초)")
        return 0
    import serial                           # pyserial (보드에서만 필요)
    bad, t0 = 0, time.time()
    with serial.Serial(port, 115200, timeout=2) as s:
        for data, note in cmds:
            s.write(data)
            reply = s.read_until(b"\n").decode("ascii", "replace")
            if note not in ("B", "V", "X", "U", "A") or not reply.startswith("OK"):
                print(note, "→", reply.strip())
            bad += not reply.strip() or reply.startswith(("E", "?"))
    print(f"{what}: 명령 {len(cmds)}개, {total}바이트, {time.time() - t0:.2f}초, 실패 {bad}개")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
