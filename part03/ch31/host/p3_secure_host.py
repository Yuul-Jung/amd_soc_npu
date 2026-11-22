#!/usr/bin/env python3
"""31장 PC 호스트: 보안 모델 적재(Encrypt-then-MAC) + 공격·고장 시험 + 적재 전후 추론 확인 → CSV.

  --cosim "<명령>"  PC 빌드 펌웨어 + Icarus NPU RTL      --port <포트>  Basys3(28장 Bitstream + 31장 ELF)
  --key-file F     보드용 키(저장소 밖, 16진 96자). 없으면 TEST 키(펌웨어도 TEST 키로 빌드됐어야 한다)
시험: 모델 A로 추론 → 모델 B 보안 적재(COMMIT) → B로 추론(점수 = B 골든) → 거부·전송 오류 시험 17종(각각 활성 모델 B 유지)
      → 인증 실패가 시퀀스를 소비하지 않음 → A 재적재(seq 6) → A로 추론.
판정: 응답 필드와 표시(DISP)가 secure_reference.Device 기대와 같아야 한다. 추론 점수는 활성 모델의 PC 골든과 같아야 한다.
키 값은 화면·로그·CSV에 쓰지 않는다(지문만).
"""
import argparse
import csv
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from part03.ch29.host.p3_sensor_host import ProcTransport, SerialTransport  # noqa: E402
from part03.ch29.reference import sensor_reference as s29  # noqa: E402
from part03.ch31.reference.secure_reference import (  # noqa: E402
    REJ, TEST_KEYS, Device, blob, key_fp, load_qmodel_b, secure_payload,
)


class Host:
    def __init__(self, tr, timeout, log, w, target, dev, test_key):
        self.tr, self.timeout, self.log, self.w, self.target, self.dev = tr, timeout, log, w, target, dev
        self.test_key, self.last_reject, self.n, self.passed, self.fails, self.step = test_key, 0, 0, 0, [], 0

    def block(self):
        lines = []
        while True:
            line = self.tr.readline(self.timeout)
            if line is None:
                return lines
            self.log.write(line + "\n")
            lines.append(line)
            if line.startswith("DISP") or (line.startswith("P3_SECURE") and len(lines) == 1):
                return lines

    def disp_expect(self):
        mid = s29.model_id(self.dev.qm)
        return ((mid >> 16) & 0xFFFF) | (0xF << 16), self.dev.bank | (1 << 14 if self.last_reject else 0) \
            | (1 << 13 if self.test_key else 0)

    def record(self, name, ok, errs, main):
        self.step += 1
        self.n += 1
        self.passed += ok
        if not ok:
            self.fails.append((self.step, name, errs))
        self.w.writerow(dict(target=self.target, step=self.step, name=name, ok=int(ok), detail=";".join(errs),
                             line=main or ""))
        print(f"STEP {self.step:3d} {name:24s} {'PASS' if ok else 'FAIL'} {';'.join(errs) or (main or '')[:140]}")

    def check_disp(self, lines, errs):
        d = s29.parse_kv(lines[-1]) if lines and lines[-1].startswith("DISP") else None
        exp = self.disp_expect()
        if not d or (int(d["fnd"], 16), int(d["led"], 16)) != exp:
            errs.append(f"disp={d}/{exp[0]:08x},{exp[1]:04x}")

    def secure(self, name, payload, raw=None):
        """raw가 있으면 그 바이트를 보낸다(전송 변조). 기대는 Device.secure(payload)."""
        self.tr.write(raw if raw is not None else s29.frame(b"M", payload))
        e = self.dev.secure(payload)
        self.last_reject = 0 if e["result"] == "COMMIT" else REJ[e["reason"]]
        lines = self.block()
        main = next((ln for ln in lines if ln.startswith("SECURE")), None)
        kv = s29.parse_kv(main or "")
        errs = [] if main else [f"no SECURE: {lines}"]
        for k, v in e.items():
            want = f"{v:08x}" if k in ("model", "active") else str(v)
            if kv.get(k) != want:
                errs.append(f"{k}={kv.get(k)}/{want}")
        self.check_disp(lines, errs)
        self.record(name, not errs, errs, main)
        return e

    def error(self, name, raw, code, wait=0.0):
        self.tr.write(raw)
        if wait:
            time.sleep(wait)
        lines = self.block()
        main = next((ln for ln in lines if ln.startswith("ERROR")), None)
        kv = s29.parse_kv(main or "")
        errs = [] if main and kv.get("code") == str(code) else [f"want ERROR code={code}: {lines}"]
        if kv.get("active") != f"{s29.model_id(self.dev.qm):08x}":
            errs.append(f"active={kv.get('active')}")
        self.check_disp(lines, errs)
        self.record(name, not errs, errs, main)

    def infer(self, name, s, seq):
        qm = self.dev.qm
        self.tr.write(s29.sensor_frame(seq, s29.model_id(qm), s))
        lines = self.block()
        main = next((ln for ln in lines if ln.startswith("INFER")), None)
        kv = s29.parse_kv(main or "")
        sc, cls = s29.golden(s29.features(s), qm)
        errs = []
        if kv.get("model") != f"{s29.model_id(qm):08x}":
            errs.append(f"model={kv.get('model')}")
        if kv.get("scores") != ",".join(map(str, sc)) or kv.get("npu") != str(cls) or kv.get("match") != "1":
            errs.append(f"scores={kv.get('scores')}/{sc} npu={kv.get('npu')}/{cls}")
        self.check_disp(lines, errs)
        self.record(name, not errs, errs, main)
        return cls


def suite(h, keys, ds, cosim):
    qa, qb = s29.load_qmodel(), load_qmodel_b()
    ida, idb = s29.model_id(qa), s29.model_id(qb)
    pa, pb = blob(qa), blob(qb)
    nonce = iter(bytes([i]) * 8 for i in range(1, 255))
    diff = [s for s in ds if s29.golden(s29.features(s), qa)[1] != s29.golden(s29.features(s), qb)[1]][:2]
    samples = ds[:3] + diff                        # 두 모델의 class가 다른 창 포함
    for i, s in enumerate(samples):
        h.infer(f"infer_model_a_{i}", s, 10 + i)
    h.secure("load_model_b", secure_payload(keys, 1, pb, idb, next(nonce)))
    for i, s in enumerate(samples):
        h.infer(f"infer_model_b_{i}", s, 20 + i)
    good2 = secure_payload(keys, 2, pa, ida, next(nonce))
    ln = 27 + len(pa)
    h.secure("tamper_ciphertext", secure_payload(keys, 2, pa, ida, next(nonce), tamper=40))
    h.secure("tamper_tag", secure_payload(keys, 2, pa, ida, next(nonce), tamper=ln + 5))
    h.secure("tamper_header_seq", secure_payload(keys, 2, pa, ida, next(nonce), tamper=1))
    h.secure("tamper_header_model", secure_payload(keys, 2, pa, ida, next(nonce), tamper=6))
    short = bytearray(secure_payload(keys, 2, pa, ida, next(nonce)))
    short[25] -= 1                                 # 길이 필드 1 줄임(뒤 바이트가 태그로 밀림)
    h.secure("length_field_minus1", bytes(short)[:-1])
    big = secure_payload(keys, 2, bytes(300), ida, next(nonce))
    h.secure("length_over_256", big)
    h.secure("wrong_mac_key", secure_payload((keys[0], bytes(32)), 2, pa, ida, next(nonce)))
    h.secure("version_2", secure_payload(keys, 2, pa, ida, next(nonce), ver=2))
    h.secure("replay_seq1", secure_payload(keys, 1, pb, idb, next(nonce)))
    h.secure("nonce_not_bound", secure_payload(keys, 2, pa, ida, next(nonce), iv_seq=7))
    h.secure("forged_seq_1000", secure_payload((keys[0], b"\x55" * 32), 1000, pa, ida, next(nonce)))
    h.secure("wrong_enc_key_auth_ok", secure_payload((bytes(16), keys[1]), 3, pa, ida, next(nonce)))   # seq 3 소비
    h.secure("model_id_mismatch", secure_payload(keys, 4, pa, idb, next(nonce)))                     # seq 4 소비
    h.secure("replay_consumed_seq3", secure_payload(keys, 3, pa, ida, next(nonce)))
    raw = bytearray(s29.frame(b"M", good2))
    raw[50] ^= 0x10
    h.error("transport_crc", bytes(raw), 1)
    h.error("cut_mid_frame", s29.frame(b"M", good2)[:60], 2, wait=1.0 if cosim else 5.0)
    for i, s in enumerate(samples[-2:]):
        h.infer(f"still_model_b_{i}", s, 30 + i)
    bad_id = bytearray(pa)
    bad_id[8] ^= 0xFF                              # 평문 안의 model_id만 틀림(헤더는 실제 계산값) → MODEL
    h.secure("blob_internal_id_bad", secure_payload(keys, 5, bytes(bad_id), ida, next(nonce)))
    h.secure("load_model_a_seq6", secure_payload(keys, 6, pa, ida, next(nonce)))
    for i, s in enumerate(samples[-2:]):
        h.infer(f"infer_model_a_again_{i}", s, 40 + i)
    h.tr.write(s29.frame(b"I"))
    lines = h.block()
    kv = s29.parse_kv(lines[0] if lines else "")
    ok = bool(lines) and kv.get("model") == f"{ida:08x}" and kv.get("last_seq") == "6" \
        and kv.get("key_fp") == f"{key_fp(keys):08x}"
    h.record("identify", ok, [] if ok else [str(lines)], lines[0] if lines else None)


def main():
    p = argparse.ArgumentParser()
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--port")
    g.add_argument("--cosim")
    p.add_argument("--baud", type=int, default=115200)
    p.add_argument("--timeout", type=float, default=60.0)
    p.add_argument("--key-file")
    p.add_argument("--csv", type=Path, required=True)
    p.add_argument("--log", type=Path, required=True)
    a = p.parse_args()
    if a.key_file:
        raw = bytes.fromhex(Path(a.key_file).read_text().strip())
        keys, test = (raw[:16], raw[16:]), 0
    else:
        keys, test = TEST_KEYS, 1
    ds = s29.dataset(*s29.TEST)[:400]
    s29.load_qmodel()
    tr = SerialTransport(a.port, a.baud) if a.port else ProcTransport(a.cosim)
    target = "fpga" if a.port else "rtl_cosim"
    dev = Device(keys, s29.load_qmodel())
    with a.log.open("w") as log, a.csv.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["target", "step", "name", "ok", "detail", "line"])
        w.writeheader()
        h = Host(tr, a.timeout, log, w, target, dev, test)
        if a.port:
            print("보드의 btnC(Reset)를 누르세요: 부팅 줄(P3_SECURE READY)을 기다립니다")
            tr.s.reset_input_buffer()
        line = tr.readline(120 if a.port else a.timeout)
        while a.port and line is not None and not line.startswith("P3_SECURE READY"):
            line = tr.readline(120)
        log.write(f"{line}\n")
        kv = s29.parse_kv(line or "")
        ok = bool(line) and kv.get("model_ok") == "1" and kv.get("bias_rc") == "0" \
            and kv.get("key_fp") == f"{key_fp(keys):08x}" and kv.get("test_key") == str(test) and kv.get("last_seq") == "0"
        lines = h.block()
        errs = [] if ok else [f"boot={line}"]
        h.check_disp(lines, errs)
        h.record("boot", not errs, errs, line)
        suite(h, keys, ds, a.cosim is not None)
    rc = tr.close()
    print(f"SECURE_HOST_SUMMARY target={target} checks={h.passed}/{h.n} key_fp={key_fp(keys):08x} test_key={test} proc_rc={rc}")
    for step, name, errs in h.fails[:10]:
        print(f"FAIL_DETAIL step={step} {name} {';'.join(errs)}")
    ok = h.passed == h.n and rc == 0
    print("SECURE_HOST_PASS" if ok else "SECURE_HOST_FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
