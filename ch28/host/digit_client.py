#!/usr/bin/env python3
"""28장 PC 쪽 프로그램: 손글씨 PGM을 전처리해 보드로 보내고 응답을 PC 정수 계산과 비교한다.
  보드:  python3 ch28/host/digit_client.py --port /dev/ttyUSB1 그림.pgm   (pyserial 필요)
  시험:  --frames 파일  : 보낼 바이트를 파일로 쓴다 (05절 시뮬레이션 입력)
         --check 응답파일 : 응답 줄을 PC 계산과 비교한다"""
from __future__ import annotations
import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "ch28" / "reference"), str(ROOT / "ch18" / "reference")]
from preprocess import mnist_like, read_pgm, to_x784     # noqa: E402
from precision_rtl import load, scores                    # noqa: E402
from p3_integer_reference import argmax_lowest            # noqa: E402


def frame(x):
    assert len(x) == 784
    return b"N" + bytes(x) + bytes([sum(x) & 0xFF])


def expect(x):
    w, b, _ = load(8)
    s = scores(x, w, b)
    return f"CLASS {argmax_lowest(s)} S " + " ".join(map(str, s))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pgm", nargs="*"); ap.add_argument("--port"); ap.add_argument("--frames"); ap.add_argument("--check")
    a = ap.parse_args()
    xs = [to_x784(mnist_like(read_pgm(p))) for p in a.pgm]
    if a.frames:                                          # 05절 시험 틀: 정상 틀들, 검사합 틀림, 범위 밖, 잡음 뒤 정상
        bad_sum = bytearray(frame(xs[0])); bad_sum[-1] ^= 0xFF
        bad_rng = bytearray(frame(xs[1])); bad_rng[5] = 200; bad_rng[-1] = (sum(bad_rng[1:-1])) & 0xFF
        data = b"".join(frame(x) for x in xs) + bytes(bad_sum) + bytes(bad_rng) + b"\r\n?junk" + frame(xs[-1])
        Path(a.frames).write_bytes(data)
        Path(a.frames + ".expect").write_text("\n".join([expect(x) for x in xs] + ["ERR SUM", "ERR RANGE", expect(xs[-1])]) + "\n")
        print(f"CLIENT_FRAMES bytes={len(data)} frames={len(xs) + 3} (정상 {len(xs)}, 검사합 틀림 1, 범위 밖 1, 잡음 뒤 정상 1)")
    if a.port:
        import serial                                     # pyserial (보드 실행 때만)
        with serial.Serial(a.port, 115200, timeout=5) as s:
            for p, x in zip(a.pgm, xs):
                s.write(frame(x))
                got = s.readline().decode().strip()
                print(f"{p}: board='{got[:40]}…' pc='{expect(x)[:40]}…' {'SAME' if got == expect(x) else 'DIFF'}")


if __name__ == "__main__":
    main()
