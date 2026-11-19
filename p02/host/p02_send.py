#!/usr/bin/env python3
"""2장 4뉴런 NPU 보드 PC 쪽 도구: 명령을 바이트로 바꿔 보내고 응답 한 줄을 받아 출력한다.

  python3 p02/host/p02_send.py --dry X 0 3            # 보낼 바이트만 출력 (보드 없이)
  python3 p02/host/p02_send.py /dev/ttyUSB1 D 4       # X·W0 내적
  python3 p02/host/p02_send.py COM3 2                 # (sw2 올림) 11장 고정 그룹 2 추론
  (pip install pyserial 필요. 115200 8N1)

명령 (p02/rtl/p02_console.v, 11장 uart_npu_command_controller.v와 같은 형식):
  S | X addr v | W n addr v | x addr | w n addr | Q v32 | D len | P len | B n v40 | L len | N len
  11장 (sw2 = 1): S | X | W | B | R len | 0 1 2 3
"""
import struct
import sys

INT = lambda s: int(s, 0)


def encode(args):
    op, a = args[0], [INT(x) for x in args[1:]]
    if op in ("S", "0", "1", "2", "3"):
        return op.encode()
    if op == "X":
        return b"X" + bytes([a[0]]) + struct.pack(">h", a[1])
    if op == "W":
        return b"W" + bytes([a[0], a[1]]) + struct.pack(">h", a[2])
    if op == "x":
        return b"x" + bytes([a[0]])
    if op == "w":
        return b"w" + bytes([a[0], a[1]])
    if op == "Q":
        return b"Q" + struct.pack(">i", a[0])
    if op == "B":
        return b"B" + bytes([a[0]]) + (a[1] & ((1 << 40) - 1)).to_bytes(5, "big")
    if op in ("D", "P", "L", "N", "R"):
        return op.encode() + bytes([a[0]])
    raise SystemExit("모르는 명령: " + op)


def main(argv):
    if len(argv) < 2:
        raise SystemExit(__doc__)
    port, data = argv[0], encode(argv[1:])
    print("TX", data.hex(" "))
    if port == "--dry":
        return 0
    import serial                           # pyserial (보드에서만 필요)
    with serial.Serial(port, 115200, timeout=2) as s:
        s.write(data)
        reply = s.read_until(b"\n")
    print("RX", repr(reply.decode("ascii", "replace")))
    return 0 if reply else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
