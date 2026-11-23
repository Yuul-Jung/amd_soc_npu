#!/usr/bin/env python3
"""보안 모델 적재(Encrypt-then-MAC: AES-128-CTR + HMAC-SHA-256) 기준모델(정본, 표준 라이브러리만).
교육용 구현이다. 상용 보안 제품이 아니며 Basys3는 키 보호 저장소·Secure Boot·Tamper 방어를 제공하지 않는다.

역할 구분: AES-128(FIPS 197)·CTR(SP 800-38A) = 기밀성만, HMAC-SHA-256(FIPS 198-1) = 키 기반 무결성·인증.
SHA-256 Digest만으로는 인증이 아니고, AES-CTR만으로는 변조를 막지 못한다. HMAC은 Replay를 막지 못하므로 시퀀스를 따로 둔다.

키: 암호화 키 16바이트와 MAC 키 32바이트를 분리. 저장소에는 결정적으로 만든 **TEST 키**만 있다(TEST_KEYS).
    보드용 키는 저장소 밖 파일(P3_KEY_FILE: 16진 48바이트)에서 build/ 헤더로 만든다. 로그에는 지문만:
    key_fp = SHA-256("P3KF" ‖ enc ‖ mac)[0:4] (big-endian u32)
모델 평문(blob, 54바이트): "P3MD" ‖ ver u16=1 ‖ n_cls u8=3 ‖ n_feat u8=6 ‖ model_id u32 ‖ w[3][6] int8 ‖ b[3] int64
    model_id는 6-3 규칙(5-1 IP 형태로 늘린 w[10][784] ‖ b[10]의 CRC32)
보안 프레임('M' 명령 payload, 정수는 LE):
    ver u8=1 ‖ seq u32 ‖ model_id u32 ‖ iv 16 ‖ len u16 ‖ ct[len] ‖ tag 32
    iv = nonce64 ‖ seq u32(BE) ‖ ctr u32(BE)=0   (CTR 카운터는 마지막 32비트 BE 증가, SP 800-38A)
    tag = HMAC-SHA-256(mac_key, "P3SM" ‖ ver ‖ seq ‖ model_id ‖ iv ‖ len ‖ ct)   (헤더 전체 + 암호문)
장치 처리 순서(이 순서가 규격이다): CRC16(전송) → ver → len ≤ 256 → **MAC(일정시간 비교)** → seq > last_seq(Replay)
    → iv의 seq·ctr 결속(Nonce 재사용 금지) → last_seq ← seq(소비) → 복호 → 스테이징 검사(len·magic·차원·model_id·Bias 범위)
    → **원자적 커밋**(활성 뱅크 전환 + NPU Bias 재적재, 실패 시 이전 모델 유지). MAC 확인 전에는 복호하지 않는다.
거부 코드: 1 VERSION, 2 LENGTH, 3 AUTH, 4 REPLAY, 5 NONCE, 6 MODEL, 7 COMMIT(NPU Bias 적재 실패)
"""
import argparse
import hashlib
import hmac
import json
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from part03.ch18.reference.precision_reference import quantize_model  # noqa: E402
from part03.ch29.reference import sensor_reference as s29  # noqa: E402

HERE = Path(__file__).resolve().parent
MODEL_B_JSON = HERE / "model_b_f32.json"
MAX_LEN = 256
BLOB_LEN = 54
MAC_LABEL = b"P3SM"
REJ = {"VERSION": 1, "LENGTH": 2, "AUTH": 3, "REPLAY": 4, "NONCE": 5, "MODEL": 6, "COMMIT": 7}
TEST_KEYS = (hashlib.sha256(b"P3-CH31-TEST-ENC-KEY").digest()[:16], hashlib.sha256(b"P3-CH31-TEST-MAC-KEY").digest())

# ---------------------------------------------------------------- AES-128 (FIPS 197, 암호화 방향만: CTR에는 이것만 필요)
SBOX = [0] * 256


def _init_sbox():
    p = q = 1
    while True:                                  # GF(2^8) 역원과 아핀 변환(FIPS 197 5.1.1)
        p = p ^ ((p << 1) & 0xFF) ^ (0x1B if p & 0x80 else 0)
        q ^= q << 1
        q ^= q << 2
        q ^= q << 4
        q &= 0xFF
        if q & 0x80:
            q ^= 0x09
        x = q ^ (q << 1 | q >> 7) ^ (q << 2 | q >> 6) ^ (q << 3 | q >> 5) ^ (q << 4 | q >> 4)
        SBOX[p] = (x ^ 0x63) & 0xFF
        if p == 1:
            break
    SBOX[0] = 0x63


_init_sbox()


def xtime(a):
    return ((a << 1) ^ (0x1B if a & 0x80 else 0)) & 0xFF


def key_expand(key):
    w = [list(key[4 * i:4 * i + 4]) for i in range(4)]
    rcon = 1
    for i in range(4, 44):
        t = list(w[i - 1])
        if i % 4 == 0:
            t = [SBOX[b] for b in t[1:] + t[:1]]
            t[0] ^= rcon
            rcon = xtime(rcon)
        w.append([a ^ b for a, b in zip(w[i - 4], t)])
    return [sum(w[4 * r:4 * r + 4], []) for r in range(11)]


def aes128_encrypt_block(key, block):
    rk = key_expand(key)
    s = [b ^ k for b, k in zip(block, rk[0])]
    for r in range(1, 11):
        s = [SBOX[b] for b in s]
        s = [s[(i + 4 * (i % 4)) % 16] for i in range(16)]        # ShiftRows(열 우선 상태)
        if r != 10:
            m = []
            for c in range(4):
                a = s[4 * c:4 * c + 4]
                t = a[0] ^ a[1] ^ a[2] ^ a[3]
                m += [a[i] ^ t ^ xtime(a[i] ^ a[(i + 1) % 4]) for i in range(4)]
            s = m
        s = [b ^ k for b, k in zip(s, rk[r])]
    return bytes(s)


def ctr_xcrypt(key, iv, data):
    out, ctr = bytearray(), int.from_bytes(iv, "big")
    for i in range(0, len(data), 16):
        cb = ((ctr & ~0xFFFFFFFF) | ((ctr + i // 16) & 0xFFFFFFFF)).to_bytes(16, "big")
        ks = aes128_encrypt_block(key, cb)
        out += bytes(a ^ b for a, b in zip(data[i:i + 16], ks))
    return bytes(out)


def key_fp(keys):
    return int.from_bytes(hashlib.sha256(b"P3KF" + keys[0] + keys[1]).digest()[:4], "big")


# ---------------------------------------------------------------- 모델 blob
def load_qmodel_b():
    qm = quantize_model(json.loads(MODEL_B_JSON.read_text()), 8)
    w = [row + [0] * (s29.N_IN - s29.N_FEAT) for row in qm["w"]] + [[0] * s29.N_IN for _ in range(s29.N_CLASS - s29.N_CLS)]
    return dict(qm, w=w, b=list(qm["b"]) + [s29.UNUSED_BIAS] * (s29.N_CLASS - s29.N_CLS))


def blob(qm):
    w = bytes(v & 0xFF for row in qm["w"][:s29.N_CLS] for v in row[:s29.N_FEAT])
    out = b"P3MD" + struct.pack("<HBBI", 1, s29.N_CLS, s29.N_FEAT, s29.model_id(qm)) + w
    out += b"".join(struct.pack("<q", v) for v in qm["b"][:s29.N_CLS])
    assert len(out) == BLOB_LEN
    return out


def parse_blob(p):
    """장치와 같은 스테이징 검사. 반환 qm(5-1 형태) 또는 None."""
    if len(p) != BLOB_LEN or p[:4] != b"P3MD":
        return None
    ver, nc, nf, mid = struct.unpack_from("<HBBI", p, 4)
    if ver != 1 or nc != s29.N_CLS or nf != s29.N_FEAT:
        return None
    w = [list(struct.unpack_from("<6b", p, 12 + 6 * c)) + [0] * (s29.N_IN - 6) for c in range(3)]
    b = list(struct.unpack_from("<3q", p, 30))
    if any(not -(1 << 39) <= v < (1 << 39) for v in b) or any(v == -128 for row in w for v in row):
        return None
    qm = dict(w=w + [[0] * s29.N_IN for _ in range(7)], b=b + [s29.UNUSED_BIAS] * 7)
    return qm if s29.model_id(qm) == mid else None


# ---------------------------------------------------------------- 프레임
def secure_payload(keys, seq, plaintext, model_id, nonce64, iv_seq=None, ctr0=0, ver=1, length=None, tamper=None):
    iv = nonce64 + struct.pack(">II", seq if iv_seq is None else iv_seq, ctr0)
    ct = ctr_xcrypt(keys[0], iv, plaintext)
    hdr = struct.pack("<BII", ver, seq, model_id) + iv + struct.pack("<H", len(ct) if length is None else length)
    tag = hmac.new(keys[1], MAC_LABEL + hdr + ct, hashlib.sha256).digest()
    p = bytearray(hdr + ct + tag)
    if tamper is not None:
        p[tamper] ^= 0x01
    return bytes(p)


def secure_frame(*a, **k):
    return s29.frame(b"M", secure_payload(*a, **k))


class Device:
    """장치 기대 상태: last_seq, 활성 모델."""

    def __init__(self, keys, qm):
        self.keys, self.qm, self.last_seq, self.bank = keys, qm, 0, 0

    def secure(self, payload):
        ver, seq, mid = struct.unpack_from("<BII", payload, 0)
        iv = payload[9:25]
        ln = struct.unpack_from("<H", payload, 25)[0]
        if ver != 1:
            return self._rej("VERSION", seq)
        if ln > MAX_LEN or len(payload) != 27 + ln + 32:
            return self._rej("LENGTH", seq)
        ct, tag = payload[27:27 + ln], payload[27 + ln:]
        if not hmac.compare_digest(tag, hmac.new(self.keys[1], MAC_LABEL + payload[:27 + ln], hashlib.sha256).digest()):
            return self._rej("AUTH", seq)
        if seq <= self.last_seq:
            return self._rej("REPLAY", seq)
        if struct.unpack(">II", iv[8:16]) != (seq, 0):
            return self._rej("NONCE", seq)
        self.last_seq = seq
        qm = parse_blob(ctr_xcrypt(self.keys[0], iv, ct))
        if qm is None or s29.model_id(qm) != mid:
            return self._rej("MODEL", seq)
        self.qm, self.bank = qm, self.bank ^ 1
        return dict(result="COMMIT", seq=seq, model=s29.model_id(qm), bank=self.bank, last_seq=self.last_seq)

    def _rej(self, reason, seq):
        return dict(result="REJECT", reason=reason, code=REJ[reason], seq=seq, last_seq=self.last_seq,
                    active=s29.model_id(self.qm))


# ---------------------------------------------------------------- 시험 벡터
KAT_AES = [("000102030405060708090a0b0c0d0e0f", "00112233445566778899aabbccddeeff", "69c4e0d86a7b0430d8cdb78070b4c55a"),
           ("2b7e151628aed2a6abf7158809cf4f3c", "3243f6a8885a308d313198a2e0370734", "3925841d02dc09fbdc118597196a0b32")]
KAT_CTR = ("2b7e151628aed2a6abf7158809cf4f3c", "f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff",
           "6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51",
           "874d6191b620e3261bef6864990db6ce9806f66b7970fdff8617187bb9fffdff")
KAT_SHA = [(b"abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
           (b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")]
KAT_HMAC = [(b"\x0b" * 20, b"Hi There", "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"),
            (b"Jefe", b"what do ya want for nothing?", "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")]


def sha_blocks(msg):
    """SHA-256 패딩 후 512비트 블록 목록(RTL 압축 코어 입력)."""
    m = msg + b"\x80" + b"\x00" * ((55 - len(msg)) % 64) + struct.pack(">Q", 8 * len(msg))
    return [m[i:i + 64] for i in range(0, len(m), 64)]


def rtl_vectors(aes_out, sha_out, n_rand=200, seed=3101):
    import random
    rng = random.Random(seed)
    rows = [(bytes.fromhex(k), bytes.fromhex(p), bytes.fromhex(c)) for k, p, c in KAT_AES]
    key, ivb = bytes.fromhex(KAT_CTR[0]), int(KAT_CTR[1], 16)
    for i in range(2):                                           # CTR 키스트림 블록(SP 800-38A F.5.1)
        cb = (ivb + i).to_bytes(16, "big")
        rows.append((key, cb, aes128_encrypt_block(key, cb)))
    for _ in range(n_rand):
        k, p = rng.randbytes(16), rng.randbytes(16)
        rows.append((k, p, aes128_encrypt_block(k, p)))
    aes_out.write_text("".join(f"{k.hex()} {p.hex()} {c.hex()}\n" for k, p, c in rows))
    msgs = [m for m, _ in KAT_SHA] + [b"", rng.randbytes(64), rng.randbytes(119), rng.randbytes(200)]
    for k, d, _ in KAT_HMAC:                                     # HMAC = SHA-256 두 번(RTL은 압축 코어만)
        k0 = k.ljust(64, b"\x00")
        inner = bytes(a ^ 0x36 for a in k0) + d
        msgs += [inner, bytes(a ^ 0x5C for a in k0) + hashlib.sha256(inner).digest()]
    for _ in range(40):
        msgs.append(rng.randbytes(rng.randint(0, 300)))
    lines = []
    for m in msgs:
        bl = sha_blocks(m)
        lines.append(f"M {len(bl)} {hashlib.sha256(m).hexdigest()}")
        lines += [b.hex() for b in bl]
    sha_out.write_text("\n".join(lines) + "\n")
    print(f"CRYPTO_RTL_VECTORS aes={len(rows)} sha_msgs={len(msgs)} sha_blocks={sum(len(sha_blocks(m)) for m in msgs)}")


def write_header(out, key_file=None):
    if key_file:
        raw = bytes.fromhex(Path(key_file).read_text().strip())
        assert len(raw) == 48, "키 파일: 16진 96자(암호화 16바이트 ‖ MAC 32바이트)"
        keys, test = (raw[:16], raw[16:]), 0
    else:
        keys, test = TEST_KEYS, 1
    qa = s29.load_qmodel()
    lines = ["/* 자동 생성: part03/ch31/reference/secure_reference.py — 키가 들어 있으므로 저장소에 넣지 않는다(build/). */",
             "#ifndef SECURE_KEYS_H", "#define SECURE_KEYS_H", "#include <stdint.h>",
             f"#define SECURE_TEST_KEY {test}", f"#define SECURE_KEY_FP 0x{key_fp(keys):08x}u",
             "static const uint8_t enc_key[16] = {" + ",".join(f"0x{b:02x}" for b in keys[0]) + "};",
             "static const uint8_t mac_key[32] = {" + ",".join(f"0x{b:02x}" for b in keys[1]) + "};",
             "/* 부팅 모델 A(29장 모델과 같음) */",
             f"#define MODEL_A_ID 0x{s29.model_id(qa):08x}u",
             "static const uint8_t model_a_blob[54] = {" + ",".join(str(b) for b in blob(qa)) + "};",
             "#endif", ""]
    out.write_text("\n".join(lines))
    print(f"SECURE_HEADER_DONE test_key={test} key_fp={key_fp(keys):08x} model_a={s29.model_id(qa):08x}")


def selftest():
    for k, p, c in KAT_AES:
        assert aes128_encrypt_block(bytes.fromhex(k), bytes.fromhex(p)).hex() == c
    k, iv, pt, ct = KAT_CTR
    assert ctr_xcrypt(bytes.fromhex(k), bytes.fromhex(iv), bytes.fromhex(pt)).hex() == ct
    for m, d in KAT_SHA:
        assert hashlib.sha256(m).hexdigest() == d
    for k, m, d in KAT_HMAC:
        assert hmac.new(k, m, hashlib.sha256).hexdigest() == d
    cross = "cryptography_not_installed"
    try:                                                         # 독립 구현과 교차 확인(있으면)
        import os
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
        for _ in range(50):
            k, iv, d = os.urandom(16), os.urandom(12) + b"\xff\xff\xff\xf0", os.urandom(100)
            e = Cipher(algorithms.AES(k), modes.CTR(iv)).encryptor()
            ref = e.update(d) + e.finalize()
            mine = ctr_xcrypt(k, iv, d[:64])                     # 이 장의 카운터는 하위 32비트에서 감싼다: 감싸기 전 4블록만 비교
            assert ref[:64] == mine
        cross = "cryptography_match_50"
    except ImportError:
        pass
    qa, qb = s29.load_qmodel(), load_qmodel_b()
    assert parse_blob(blob(qa)) is not None and s29.model_id(parse_blob(blob(qb))) == s29.model_id(qb)
    assert s29.model_id(qa) != s29.model_id(qb)
    dev = Device(TEST_KEYS, qa)
    n = b"\x11" * 8
    good = secure_payload(TEST_KEYS, 5, blob(qb), s29.model_id(qb), n)
    assert dev.secure(secure_payload(TEST_KEYS, 5, blob(qb), s29.model_id(qb), n, tamper=40))["reason"] == "AUTH"
    assert dev.last_seq == 0                                     # 인증 실패는 시퀀스를 소비하지 않는다
    assert dev.secure(good)["result"] == "COMMIT" and dev.secure(good)["reason"] == "REPLAY"
    wrong = (TEST_KEYS[0], b"\x00" * 32)
    assert dev.secure(secure_payload(wrong, 6, blob(qa), s29.model_id(qa), n))["reason"] == "AUTH"
    assert dev.secure(secure_payload(TEST_KEYS, 6, blob(qa), s29.model_id(qa), n, iv_seq=5))["reason"] == "NONCE"
    print(f"SECURE_REFERENCE_SELFTEST_PASS aes_kat=2 ctr_kat=1 sha_kat=2 hmac_kat=2 cross={cross} "
          f"model_a={s29.model_id(qa):08x} model_b={s29.model_id(qb):08x} test_key_fp={key_fp(TEST_KEYS):08x}")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--selftest", action="store_true")
    p.add_argument("--header", type=Path)
    p.add_argument("--key-file", help="보드용 키 파일(저장소 밖). 없으면 TEST 키")
    p.add_argument("--rtl-vectors", nargs=2, type=Path, metavar=("AES", "SHA"))
    a = p.parse_args()
    if a.selftest:
        selftest()
    if a.header:
        write_header(a.header, a.key_file)
    if a.rtl_vectors:
        rtl_vectors(*a.rtl_vectors)


if __name__ == "__main__":
    main()
