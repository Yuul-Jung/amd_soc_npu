#!/usr/bin/env python3
"""1장 UART 계산기 PC 쪽 도구: 명령을 바이트로 바꿔 보내고 응답 한 줄을 받아 출력한다.

  python3 p01/host/p01_send.py --dry M 3 4          # 보낼 바이트만 출력 (보드 없이)
  python3 p01/host/p01_send.py /dev/ttyUSB1 C       # 누산값 0  → OK
  python3 p01/host/p01_send.py /dev/ttyUSB1 M 3 4   # 3×4 누산  → A:000000000C L:1
  (Windows는 COM3 같은 포트 이름. pip install pyserial 필요)

명령 형식은 p01/rtl/p01_calc_controller.v 머리말과 같다. 'M' 뒤 두 수는 signed16(-32768~32767).
"""
import struct
import sys


def encode(args):
    op = args[0]
    if op == "M":
        a, b = int(args[1], 0), int(args[2], 0)
        return b"M" + struct.pack(">hh", a, b)
    if len(op) == 1:
        return op.encode("ascii")          # C, S, 또는 에코할 글자
    raise SystemExit("명령은 M a b, C, S, 또는 글자 하나")


def main(argv):
    if len(argv) < 2:
        raise SystemExit(__doc__)
    port, args = argv[0], argv[1:]
    data = encode(args)
    print("TX", data.hex(" "))
    if port == "--dry":
        return 0
    import serial                           # pyserial (보드에서만 필요)
    with serial.Serial(port, 115200, timeout=1) as s:
        s.write(data)
        echo_only = len(data) == 1 and data not in (b"C", b"S")
        reply = s.read(1) if echo_only else s.read_until(b"\n")
    print("RX", repr(reply.decode("ascii", "replace")))
    return 0 if reply else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
