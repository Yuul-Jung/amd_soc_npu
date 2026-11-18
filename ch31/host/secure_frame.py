#!/usr/bin/env python3
"""31장 PC 쪽: 모델·그림을 AES-128-CTR로 암호화하고 HMAC-SHA256 태그를 붙인 틀을 만든다 (표준 라이브러리만).
AES는 파이썬으로 직접 구현했고 FIPS-197·SP 800-38A 시험 벡터로 확인한다. 시연용 키는 sw/demo_keys.h와 같다(공개 값).
--scenario 파일: 정상·재전송·변조·다른 키·되감기·잘못된 커밋·잘린 틀을 담은 틀 파일과 기대 판정을 쓴다."""
from __future__ import annotations
import hashlib
import hmac
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "ch18" / "reference"))

K_ENC, K_MAC, NONCE = bytes([0x31] * 16), bytes([0x4D] * 16), bytes([0x4E, 0x50, 0x55, 0x33, 0x31, 0, 0, 1])
SB = bytes.fromhex(
    "637c777bf26b6fc53001672bfed7ab76ca82c97dfa5947f0add4a2af9ca472c0b7fd9326363ff7cc34a5e5f171d8311504c723c31896059a071280e2eb27b275"
    "09832c1a1b6e5aa0523bd6b329e32f8453d100ed20fcb15b6acbbe394a4c58cfd0efaafb434d338545f9027f503c9fa851a3408f929d38f5bcb6da2110fff3d2"
    "cd0c13ec5f974417c4a77e3d645d197360814fdc222a908846eeb814de5e0bdbe0323a0a4906245cc2d3ac629195e479e7c8376d8dd54ea96c56f4ea657aae08"
    "ba78252e1ca6b4c6e8dd741f4bbd8b8a703eb5664803f60e613557b986c11d9ee1f8981169d98e949b1e87e9ce5528df8ca1890dbfe6426841992d0fb054bb16")


def xt(x):
    return ((x << 1) ^ (0x1B if x & 0x80 else 0)) & 0xFF


def aes_block(key, blk):
    rk, rcon = list(key), 1
    while len(rk) < 176:
        w = rk[-4:]
        if len(rk) % 16 == 0:
            w = [SB[w[1]] ^ rcon, SB[w[2]], SB[w[3]], SB[w[0]]]; rcon = xt(rcon)
        rk += [rk[-16 + k] ^ w[k] for k in range(4)]
    s = [b ^ k for b, k in zip(blk, rk[:16])]
    for r in range(1, 11):
        t = [SB[s[(i + 4 * (i % 4)) % 16]] for i in range(16)]
        if r != 10:
            for c in range(4):
                a = t[4 * c:4 * c + 4]; x = a[0] ^ a[1] ^ a[2] ^ a[3]
                t[4 * c:4 * c + 4] = [a[0] ^ x ^ xt(a[0] ^ a[1]), a[1] ^ x ^ xt(a[1] ^ a[2]), a[2] ^ x ^ xt(a[2] ^ a[3]), a[3] ^ x ^ xt(a[3] ^ a[0])]
        s = [b ^ k for b, k in zip(t, rk[16 * r:16 * r + 16])]
    return bytes(s)


def ctr(key, iv, data):
    out, c = bytearray(), int.from_bytes(iv, "big")
    for off in range(0, len(data), 16):
        ks = aes_block(key, c.to_bytes(16, "big")); c = (c + 1) % (1 << 128)
        out += bytes(a ^ b for a, b in zip(data[off:off + 16], ks))
    return bytes(out)


def selftest():
    assert aes_block(bytes(range(16)), bytes.fromhex("00112233445566778899aabbccddeeff")).hex() == "69c4e0d86a7b0430d8cdb78070b4c55a"
    assert ctr(bytes.fromhex("2b7e151628aed2a6abf7158809cf4f3c"), bytes.fromhex("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff"),
               bytes.fromhex("6bc1bee22e409f96e93d7e117393172a")).hex() == "874d6191b620e3261bef6864990db6ce"
    print("PYTHON_AES_VECTOR_PASS vectors=2 (FIPS-197 C.1, SP800-38A F.5.1)")


def frame(typ, counter, plain, k_enc=K_ENC, k_mac=K_MAC):
    head = b"S" + bytes([typ]) + struct.pack(">IH", counter, len(plain))
    ct = ctr(k_enc, NONCE + struct.pack(">I", counter) + bytes(4), plain)
    return head + ct + hmac.new(k_mac, head + ct, hashlib.sha256).digest()[:16]


def model_bytes():
    from precision_rtl import load
    w, b, _ = load(8)
    return bytes(v & 0xFF for row in w for v in row) + b"".join(struct.pack("<i", x) for x in b)


def scenario(out):
    m = model_bytes(); assert len(m) == 7880
    img = bytes(range(0, 128)) * 6 + bytes(16)
    h8 = lambda d: hashlib.sha256(d).hexdigest()[:16]
    F, E = [], []
    for k, off in enumerate(range(0, len(m), 1000)):                # 모델 8조각
        F.append(frame(1, k + 1, struct.pack(">H", off) + m[off:off + 1000])); E.append("OK_CHUNK")
    F.append(frame(2, 9, hashlib.sha256(m).digest())); E.append(f"OK_COMMIT {h8(m)}")
    good = frame(3, 10, img); F.append(good); E.append(f"OK_IMAGE {h8(img)}")
    F.append(good); E.append("ERR_REPLAY")                           # 같은 틀 다시
    bad = bytearray(frame(3, 11, img)); bad[20] ^= 1; F.append(bytes(bad)); E.append("ERR_MAC")   # 암호문 1비트 변조
    F.append(frame(3, 12, img, k_mac=bytes(16))); E.append("ERR_MAC")                           # 다른 키
    F.append(frame(3, 12, img)); E.append(f"OK_IMAGE {h8(img)}")    # 실패한 틀은 카운터를 올리지 않았음
    F.append(frame(3, 5, img)); E.append("ERR_REPLAY")              # 카운터 되감기 (태그는 맞음)
    m2 = bytes([m[0] ^ 0xFF]) + m[1:]
    F.append(frame(1, 20, struct.pack(">H", 0) + m2[:1])); E.append("OK_CHUNK")
    F.append(frame(2, 21, hashlib.sha256(m).digest())); E.append("ERR_COMMIT")   # 바뀐 준비 영역 ≠ 옛 해시 → 활성 모델 그대로
    F.append(frame(2, 22, hashlib.sha256(m2).digest())); E.append(f"OK_COMMIT {h8(m2)}")
    F.append(frame(3, 23, img)[:-3]); E.append("ERR_FORMAT")        # 잘린 틀
    with open(out, "wb") as f:
        for fr in F: f.write(struct.pack(">H", len(fr)) + fr)
    Path(out + ".expect").write_text("\n".join(E) + "\n")
    print(f"SECURE_FRAMES frames={len(F)} (모델 8조각+커밋, 그림, 재전송, 변조, 다른 키, 되감기, 커밋 거부·재커밋, 잘린 틀)")


if __name__ == "__main__":
    selftest()
    if len(sys.argv) > 2 and sys.argv[1] == "--scenario":
        scenario(sys.argv[2])
