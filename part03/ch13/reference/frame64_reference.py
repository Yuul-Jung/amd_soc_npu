#!/usr/bin/env python3
"""8×8 INT8 입력 프레임 계약 기준모델·시험 벡터 생성·RTL 결과 비교.

계산 규칙은 host_tools/p3_integer_reference.py의 함수만 조합한다.
- 픽셀 양자화: sat_int8(round_shift_away(pixel_u8, 1))  (0..255 -> 0..127)
- 저장 순서: addr = row*8 + col (행 우선)
- 프레임 규칙: 64번째 바이트에만 last. 짧으면 err_short, 길면 err_long 후 다음 last까지 버림.
"""
import argparse
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from part03.host_tools.p3_integer_reference import sat_int8, round_shift_away  # noqa: E402

# 0~9 숫자 8×8 비트맵(1=획). 실제 MNIST 다운샘플이 아닌 데이터 계약 시험용 합성 숫자.
GLYPHS = {
    0: ["..####..", ".#....#.", "#......#", "#......#",
        "#......#", "#......#", ".#....#.", "..####.."],
    1: ["...##...", "..###...", ".#.##...", "...##...",
        "...##...", "...##...", "...##...", ".######."],
    2: ["..####..", ".#....#.", "......#.", ".....#..",
        "....#...", "...#....", "..#.....", ".######."],
    3: [".#####..", "......#.", "......#.", "..####..",
        "......#.", "......#.", "......#.", ".#####.."],
    4: ["....##..", "...#.#..", "..#..#..", ".#...#..",
        "########", ".....#..", ".....#..", ".....#.."],
    5: [".######.", ".#......", ".#......", ".#####..",
        "......#.", "......#.", ".#....#.", "..####.."],
    6: ["..####..", ".#......", "#.......", "#.####..",
        "##....#.", "#......#", ".#....#.", "..####.."],
    7: ["########", "......#.", ".....#..", "....#...",
        "...#....", "...#....", "...#....", "...#...."],
    8: ["..####..", ".#....#.", ".#....#.", "..####..",
        ".#....#.", "#......#", ".#....#.", "..####.."],
    9: ["..####..", ".#....#.", "#......#", ".#....##",
        "..####.#", ".......#", "......#.", "..####.."],
}


def quantize_pixel_u8(pixel):
    """8비트 무부호 밝기(0..255)를 signed INT8 입력(0..127)으로 변환한다."""
    if not 0 <= pixel <= 255:
        raise ValueError("pixel must be 0..255")
    return sat_int8(round_shift_away(pixel, 1))


def glyph_frame(digit):
    """획=255, 획 옆=128(회색), 배경=0 밝기를 양자화해 64원소 행 우선 벡터로 만든다."""
    rows = GLYPHS[digit]
    assert len(rows) == 8 and all(len(r) == 8 for r in rows)
    out = []
    for r in range(8):
        for c in range(8):
            if rows[r][c] == "#":
                p = 255
            elif (c > 0 and rows[r][c - 1] == "#") or (c < 7 and rows[r][c + 1] == "#"):
                p = 128
            else:
                p = 0
            out.append(quantize_pixel_u8(p))
    return out


def model(stream):
    """RTL 계약의 기준 상태기계. 수락될 프레임 목록과 오류 횟수를 반환한다."""
    state, buf, frames, short, long_ = "FILL", [], [], 0, 0
    drop_next = False
    for item in stream:
        kind = item[0]
        if kind == "R":
            state, buf = "FILL", []
            continue
        if kind == "Q":
            drop_next = True
            continue
        _, value, last = item
        if state == "FILL":
            buf.append(value)
            if last:
                if len(buf) == 64:
                    if drop_next:
                        drop_next = False  # FULL 상태에서 Reset되어 출력되지 않음
                    else:
                        frames.append(buf)
                else:
                    short += 1
                buf = []
            elif len(buf) == 64:
                long_ += 1
                buf, state = [], "DROP"
        elif state == "DROP" and last:
            state = "FILL"
    return frames, short, long_


def frame_items(values, last_at=None):
    last_at = len(values) if last_at is None else last_at
    return [("D", v, i + 1 == last_at) for i, v in enumerate(values)]


def build_stream():
    rng = random.Random(1313)
    s = []
    for d in range(10):
        s += frame_items(glyph_frame(d))
    # 행 우선 순서: 값 = 주소-32 (0행0열=-32, 7행7열=31)
    s += frame_items([i - 32 for i in range(64)])
    # 부호 경계와 모든 위치가 다른 값
    s += frame_items([-128, 127, 0, -1] * 16)
    s += frame_items([((i * 37) % 256) - 128 for i in range(64)])
    # 짧은 프레임 2종(63바이트, 1바이트)
    s += frame_items([5] * 63)
    s += frame_items([7])
    # 긴 프레임 2종(65바이트: 65번째 last로 재동기, 70바이트) 후 정상 프레임
    s += frame_items([9] * 65)
    s += frame_items([11] * 70)
    s += frame_items([rng.randint(-128, 127) for _ in range(64)])
    # 수신 중 Reset: 30바이트 후 Reset, 이어서 정상 프레임
    s += frame_items([3] * 30, last_at=0)
    s.append(("R",))
    s += frame_items([rng.randint(-128, 127) for _ in range(64)])
    # DROP 상태에서 Reset: last 없는 64바이트 -> DROP, Reset 후 정상 프레임
    s += frame_items([4] * 64, last_at=0)
    s.append(("R",))
    s += frame_items([rng.randint(-128, 127) for _ in range(64)])
    # FULL 상태(ack 전)에서 Reset: 출력되지 않아야 함
    s.append(("Q",))
    s += frame_items([rng.randint(-128, 127) for _ in range(64)])
    for _ in range(20):
        s += frame_items([rng.randint(-128, 127) for _ in range(64)])
    return s


def selftest():
    assert [quantize_pixel_u8(p) for p in (0, 1, 2, 3, 128, 254, 255)] == [0, 1, 1, 2, 64, 127, 127]
    for bad in (-1, 256):
        try:
            quantize_pixel_u8(bad)
        except ValueError:
            pass
        else:
            raise AssertionError("pixel range check missing")
    g1 = glyph_frame(1)
    assert len(g1) == 64 and g1[3] == 127 and g1[0] == 0 and g1[2] == 64
    assert all(0 <= v <= 127 for d in range(10) for v in glyph_frame(d))
    frames, short, long_ = model(frame_items([1] * 63) + frame_items([2] * 64))
    assert frames == [[2] * 64] and short == 1 and long_ == 0
    frames, short, long_ = model(frame_items([1] * 66) + frame_items([2] * 64))
    assert frames == [[2] * 64] and long_ == 1


def generate(out):
    selftest()
    stream = build_stream()
    frames, short, long_ = model(stream)
    with (out / "stream.txt").open("w") as f:
        for item in stream:
            if item[0] == "D":
                f.write(f"D {item[1] & 0xff:02x} {int(item[2])}\n")
            else:
                f.write(f"{item[0]} 00 0\n")
    with (out / "expected.txt").open("w") as f:
        for fr in frames:
            f.write(" ".join(f"{v & 0xff:02x}" for v in fr) + "\n")
        f.write(f"ERR {short} {long_}\n")
    print(f"PYTHON_FRAME64_SELF_TEST_PASS items={len(stream)} frames={len(frames)} "
          f"short={short} long={long_} seed=1313")


def compare(out, actual):
    exp = (out / "expected.txt").read_text().split("\n")
    got = actual.read_text().split("\n")
    if exp != got:
        for i, (e, g) in enumerate(zip(exp, got)):
            if e != g:
                print(f"FAIL line {i}: expected={e[:60]} got={g[:60]}")
                break
        print(f"lines expected={len(exp)} got={len(got)}")
        raise SystemExit("PYTHON_RTL_COMPARE_FAIL")
    print(f"PYTHON_RTL_COMPARE_PASS frames={len(exp) - 2} bit_exact=1")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--actual", type=Path)
    a = p.parse_args()
    if a.actual:
        compare(a.out, a.actual)
    else:
        generate(a.out)
