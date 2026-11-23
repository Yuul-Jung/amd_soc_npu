#!/usr/bin/env python3
"""손글씨 숫자 인식 NPU 시스템 기준모델·UART 프레임 규약(표준 라이브러리만, PNG는 Pillow 선택).

실습 모드: **28×28·784 타일링**(4-2 13타일 하드웨어, 4-3 INT8 학습 모델). 8×8·64 모드는 쓰지 않는다.
모델 연결: 4-3 mnist_linear_f32.json → quantize_model(…, 8) → model_w[10][784]·model_b[10]
  MODEL_ID = zlib.crc32(w 바이트(class 우선, int8 2의 보수) ‖ b 각 int64 little-endian)  — 펌웨어도 부팅 때 같은 값을 계산
전처리: 28×28 8비트 회색조(MNIST 극성: 흰 글씨·검은 바탕), x_q = div_round_away(pixel·127, 255) ∈ 0..127
Golden: 4-2 model(x, w, b, 41, 40, 8) → 10개 점수·class(동점은 낮은 번호)

UART 프레임(PC → 보드, 115200 8N1):
  'P' '3' CMD  PAYLOAD  CRC16(상위 먼저)    CRC16/CCITT-FALSE(poly 0x1021, init 0xFFFF)를 CMD‖PAYLOAD에 계산
  CMD 'I' 식별, payload 없음               → "P3_DIGIT READY model=%08x model_ok=1 mode=784x8 tiles=13"
  CMD 'X' 추론, img_id u16 ‖ model_id u32 ‖ x[784] int8 (LE, 총 790바이트)
                                           → "RESULT img=… model=… npu_class=… cpu_class=… match=… rc=… status=… scores=s0,…,s9"
  CMD 'T' 가중치 미적재 자체 시험           → "SELFTEST w_missing err_code=9 recovered=1"
  오류                                     → "ERROR img=<id|-1> code=<n> name=<NAME> detail=<n> junk=<n>"
  매 응답 뒤                               → "DISP fnd=%08x led=%04x" (보드 GPIO에 쓴 값과 같은 값)
"""
import argparse
import json
import struct
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from part03.ch17.reference.tile784_reference import model  # noqa: E402
from part03.ch18.reference.precision_reference import (  # noqa: E402
    MODEL, quantize_model, quantize_x, read_idx,
)

HERE = Path(__file__).resolve().parent
SAMPLES = HERE / "digit_samples.txt"
N_IN, N_CLASS, PIX_MAX = 784, 10, 127
SYNC = b"P3"
CMD_ID, CMD_INFER, CMD_SELFTEST = b"I", b"X", b"T"
# 펌웨어 오류 코드(FND 마지막 자리에 표시하는 값과 같다)
ERR = {"CRC": 1, "TIMEOUT": 2, "CMD": 3, "MODEL": 4, "RANGE": 5, "NPU": 6, "MISMATCH": 7}
# FND 표시 워드(AXI GPIO 1, 32비트): [15:0] 자리별 16진 nibble(자리 0이 오른쪽), [19:16] 자리 켜짐, [23:20] 점
FND_ON_SHIFT, FND_DP_SHIFT = 16, 20
LED_VALID, LED_ERROR = 1 << 15, 1 << 14
SEG7 = [0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F, 0x77, 0x7C, 0x39, 0x5E, 0x79, 0x71]  # gfedcba


def crc16(data, crc=0xFFFF):
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def load_qmodel():
    return quantize_model(json.loads(MODEL.read_text()), 8)


def model_bytes(qm):
    w = bytes(v & 0xFF for row in qm["w"] for v in row)
    return w + b"".join(struct.pack("<q", v) for v in qm["b"])


def model_id(qm):
    return zlib.crc32(model_bytes(qm)) & 0xFFFFFFFF


def golden(x_q, qm):
    _, scores, cls, ovf = model(x_q, qm["w"], qm["b"], 41, 40, 8)
    assert not ovf
    return scores, cls


def frame(cmd, payload=b""):
    body = cmd + payload
    return SYNC + body + struct.pack(">H", crc16(body))   # CRC는 상위 바이트 먼저(수신 잔여값 0)


def infer_frame(img_id, mid, x_q):
    return frame(CMD_INFER, struct.pack("<HI", img_id, mid) + bytes(v & 0xFF for v in x_q))


def fnd_result(img_id, cls):
    return ((img_id & 0xFF) << 8) | cls | (0b1101 << FND_ON_SHIFT), (1 << cls) | LED_VALID


def fnd_error(img_id, code):
    on = 0b1111 if img_id >= 0 else 0b0011
    return (((img_id & 0xFF) << 8) if img_id >= 0 else 0) | (0xE << 4) | code | (on << FND_ON_SHIFT), LED_ERROR


def fnd_boot(mid):
    return ((mid >> 16) & 0xFFFF) | (0b1111 << FND_ON_SHIFT), 0


def fnd_segments(word, digit):
    """Basys3 FND 한 자리의 핀 값(모두 Low 활성): (an[3:0], seg[6:0], dp)."""
    on = (word >> (FND_ON_SHIFT + digit)) & 1
    dp = (word >> (FND_DP_SHIFT + digit)) & 1
    nib = (word >> (4 * digit)) & 0xF
    an = 0xF & ~(1 << digit) if on else 0xF
    seg = (~SEG7[nib] & 0x7F) if on else 0x7F
    return an, seg, 0 if (on and dp) else 1


def parse_kv(line):
    out = {}
    for tok in line.split()[1:]:
        if "=" in tok:
            k, v = tok.split("=", 1)
            out[k] = v
    return out


def load_image(path, invert=False):
    """28×28 회색조 PNG/PGM 등(Pillow). 크기가 다르면 오류: 확대·축소 규칙은 학습 전처리에 없으므로 임의로 하지 않는다."""
    from PIL import Image
    img = Image.open(path).convert("L")
    if img.size != (28, 28):
        raise ValueError(f"{path}: 28x28 이미지가 필요하다 (현재 {img.size})")
    px = list(img.getdata())
    return [255 - p for p in px] if invert else px


def read_samples(path=SAMPLES):
    rows = []
    for line in path.read_text().splitlines():
        if line.startswith("#") or not line.strip():
            continue
        v = list(map(int, line.split()))
        rows.append({"index": v[0], "label": v[1], "pixels": v[2:]})
    return rows


def make_samples(mnist_dir, out):
    """t10k에서 숫자별 첫 2장 + 4-3 INT8 모델이 틀리는 첫 2장(모델 오분류 분류 확인용)."""
    xs = read_idx(mnist_dir / "t10k-images-idx3-ubyte")
    ys = read_idx(mnist_dir / "t10k-labels-idx1-ubyte")
    qm = load_qmodel()
    picked, per = [], {d: 0 for d in range(10)}
    for i, y in enumerate(ys):
        if per[y] < 2:
            per[y] += 1
            picked.append(i)
        if all(v == 2 for v in per.values()):
            break
    wrong = []
    for i in range(len(ys)):
        if i not in picked and golden(quantize_x(xs[i], 8), qm)[1] != ys[i]:
            wrong.append(i)
            if len(wrong) == 2:
                break
    lines = ["# index label pixel0..783 (MNIST t10k, Yann LeCun et al.; 28장 숫자별 2장 + INT8 오분류 2장)"]
    lines += [" ".join(map(str, [i, ys[i]] + xs[i])) for i in sorted(picked) + wrong]
    out.write_text("\n".join(lines) + "\n")
    print(f"SAMPLES_DONE n={len(picked) + len(wrong)} wrong={wrong}")


def write_header(out):
    qm = load_qmodel()
    mid = model_id(qm)
    lines = ["/* 자동 생성: part03/ch28/reference/digit_reference.py (18장 INT8 모델, 28×28·784 모드) */",
             "#ifndef DIGIT_MODEL_H", "#define DIGIT_MODEL_H", "#include <stdint.h>",
             f"#define DIGIT_MODEL_ID 0x{mid:08x}u",
             "static const int8_t model_w[10][784] = {"]
    lines += ["  {" + ",".join(map(str, row)) + "}," for row in qm["w"]]
    lines += ["};", "static const int64_t model_b[10] = {" + ",".join(f"{v}LL" for v in qm["b"]) + "};",
              "#endif", ""]
    out.write_text("\n".join(lines))
    print(f"DIGIT_HEADER_DONE model_id={mid:08x}")


def selftest():
    assert crc16(b"123456789") == 0x29B1                      # CRC-16/CCITT-FALSE 검사값
    qm = load_qmodel()
    x = quantize_x([0] * N_IN, 8)
    f = infer_frame(0x1234, model_id(qm), x)
    assert len(f) == 2 + 1 + 6 + N_IN + 2 and f[:3] == b"P3X"
    assert crc16(f[2:]) == 0                                   # 수신 쪽: CRC 포함 전체 CRC가 0
    assert golden(x, qm)[0] == qm["b"]                         # x=0이면 점수 = Bias
    assert fnd_result(0x1A7, 7) == (0x0D_A707, 0x8080)
    assert fnd_error(-1, ERR["CRC"]) == (0x03_00E1, LED_ERROR)
    assert fnd_segments(0x0D_A707, 0) == (0b1110, ~0x07 & 0x7F, 1)
    assert fnd_segments(0x0D_A707, 1) == (0xF, 0x7F, 1)        # 꺼진 자리
    assert fnd_segments(0x1F_0008, 0) == (0b1110, 0x00, 0)     # 8 + 점
    print(f"DIGIT_REFERENCE_SELFTEST_PASS model_id={model_id(qm):08x} frame_bytes={len(f)}")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--selftest", action="store_true")
    p.add_argument("--header", type=Path)
    p.add_argument("--make-samples", type=Path, metavar="MNIST_RAW_DIR")
    p.add_argument("--fnd-vectors", type=Path)
    a = p.parse_args()
    if a.selftest:
        selftest()
    if a.header:
        write_header(a.header)
    if a.make_samples:
        make_samples(a.make_samples, SAMPLES)
    if a.fnd_vectors:
        words = [0x0D_A707, 0x0F_0123, 0x0F_4567, 0x0F_89AB, 0x0F_CDEF, 0xFF_8888, 0x03_00E1, 0x00_FFFF, 0x05_0000]
        with a.fnd_vectors.open("w") as f:
            for w in words:
                for d in range(4):
                    an, seg, dp = fnd_segments(w, d)
                    f.write(f"{w:08x} {d} {an:x} {seg:02x} {dp}\n")
        print(f"FND_VECTORS words={len(words)} rows={4 * len(words)}")


if __name__ == "__main__":
    main()
