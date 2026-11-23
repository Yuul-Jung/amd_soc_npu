#!/usr/bin/env python3
"""PC 호스트: 가상 센서 창(합성 데이터·고장 주입) → UART 프레임 → 보드(또는 PC 시뮬레이션) → 응답 판정·CSV.

전송 경로(같은 규약, reference/sensor_reference.py 머리말):
  --port /dev/ttyUSBx   실제 Basys3(6-1 Bitstream + 6-3 ELF)                  → target=fpga
  --cosim "<명령>"       PC 빌드 펌웨어 + NPU RTL(표준 입출력)              → target=rtl_cosim
시험 묶음(기본 모두):
  scenario  정책 전이(부팅 UNKNOWN → 3회 연속 하향, 즉시 상향, FAULT 래치·ACK)와 센서 고장 주입
            (결측·지연·범위 밖·고착 → NPU 없이 UNKNOWN/FAULT)
  dataset   시험셋 창 --limit 개: 장치 응답 = 기대(특징·점수·후보·상태·표시). 정확도는 골든·장치 따로
  errors    CRC·모델 ID·미정의 명령(연속 3회 → LINK_BAD UNKNOWN)·잡음·짧은 프레임·링크 시간 초과·식별
판정: 모든 응답 줄의 필드와 DISP 값이 sensor_reference.Firmware 기대와 같아야 PASS.
CSV:  target,step,suite,kind,seq,label,expect_cand,dev_cand,expect_state,dev_state,latch,ok,detail
"""
import argparse
import csv
import shlex
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from part03.ch29.reference.sensor_reference import (  # noqa: E402
    CMD_ACK, CMD_ID, D_MISS, FAULT, NORMAL, T_MISS, TEST, UNKNOWN, WARNING, Firmware, dataset, features,
    frame, golden, load_qmodel, model_id, parse_kv, sensor_frame,
)


class ProcTransport:
    def __init__(self, cmd):
        import selectors
        self.p = subprocess.Popen(shlex.split(cmd), stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        self.sel = selectors.DefaultSelector()
        self.sel.register(self.p.stdout, selectors.EVENT_READ)
        self.buf = b""

    def write(self, data):
        self.p.stdin.write(data)
        self.p.stdin.flush()

    def readline(self, timeout):
        end = time.monotonic() + timeout
        while b"\n" not in self.buf:
            left = end - time.monotonic()
            if left <= 0 or not self.sel.select(left):
                return None
            chunk = self.p.stdout.read1(4096)
            if not chunk:
                return None
            self.buf += chunk
        line, self.buf = self.buf.split(b"\n", 1)
        return line.decode(errors="replace").strip()

    def close(self):
        self.p.stdin.close()
        return self.p.wait(timeout=600)


class SerialTransport:
    def __init__(self, port, baud):
        import serial
        self.s = serial.Serial(port, baud, bytesize=8, parity="N", stopbits=1, timeout=0.1)
        self.buf = b""

    def write(self, data):
        self.s.write(data)
        self.s.flush()

    def readline(self, timeout):
        end = time.monotonic() + timeout
        while b"\n" not in self.buf:
            if time.monotonic() > end:
                return None
            self.buf += self.s.read(256)
        line, self.buf = self.buf.split(b"\n", 1)
        return line.decode(errors="replace").strip()

    def close(self):
        self.s.close()
        return 0


def hexint(s):
    return int(s, 16)


class Host:
    def __init__(self, tr, timeout, log, fw, target, writer):
        self.tr, self.timeout, self.log, self.fw = tr, timeout, log, fw
        self.target, self.w, self.step = target, writer, 0
        self.n = self.passed = self.unsolicited = 0
        self.fails = []

    def read_block(self):
        """DISP로 끝나는 응답 묶음 하나. 식별 응답(P3_SENSOR)은 DISP 없이 한 줄."""
        lines = []
        while True:
            line = self.tr.readline(self.timeout)
            if line is None:
                return lines
            self.log.write(line + "\n")
            lines.append(line)
            if line.startswith("DISP") or (line.startswith("P3_SENSOR") and len(lines) == 1):
                return lines

    def transact(self, data, expect):
        """expect: Firmware 기대 dict 또는 그 dict를 만드는 함수(요청 직전에 모델을 진행). 보드에서 요청과 무관한
        LINK_TIMEOUT 묶음이 끼어들면 모델에도 반영하고 다시 읽는다."""
        if data:
            self.tr.write(data)
        while True:
            lines = self.read_block()
            if (expect is None or not callable(expect) or expect.__name__ != "link_timeout") and lines \
                    and lines[0].startswith("STATE src=LINK_TIMEOUT"):
                self.fw.link_timeout()
                self.unsolicited += 1
                continue
            return lines, (expect() if callable(expect) else expect)

    def check(self, suite, data, expect, label="", extra=None):
        lines, e = self.transact(data, expect)
        ok, detail, dev = compare(lines, e, extra or {})
        self.step += 1
        self.n += 1
        self.passed += ok
        if not ok:
            self.fails.append((suite, self.step, detail))
        st = parse_kv(next((ln for ln in lines if ln.startswith("STATE")), ""))
        self.w.writerow(dict(target=self.target, step=self.step, suite=suite, kind=e["kind"], seq=e.get("seq", ""),
                             label=label, expect_cand=e.get("cand", ""), dev_cand=st.get("cand", ""),
                             expect_state=e.get("state", ""), dev_state=dev.get("state", ""),
                             latch=dev.get("latch", ""), ok=int(ok), detail=detail))
        print(f"STEP {self.step:3d} {suite:8s} {e['kind']:6s} {'PASS' if ok else 'FAIL'} {detail}")
        return ok, dev


def compare(lines, e, extra):
    """반환 (ok, 설명, 장치 주 줄 필드)."""
    disp = parse_kv(lines[-1]) if lines and lines[-1].startswith("DISP") else None
    main = lines[0] if lines else ""
    kv = parse_kv(main)
    errs = []

    def need(cond, what):
        if not cond:
            errs.append(what)

    if e["kind"] == "STATE":
        need(main.startswith("STATE"), "no STATE")
        for k in ("src",):
            need(kv.get(k) == e[k], f"{k}={kv.get(k)}")
        for k in ("seq", "cand", "state", "latch", "fmask", "umask"):
            need(kv.get(k) == str(e[k]), f"{k}={kv.get(k)}/{e[k]}")
        if "guard" in e:
            need(kv.get("guard") == e["guard"], f"guard={kv.get('guard')}")
        if e.get("guard") == "OK":
            need(kv.get("feat") == ",".join(map(str, e["feat"])), f"feat={kv.get('feat')}/{e['feat']}")
            need(kv.get("scores") == ",".join(map(str, e["scores"])), "scores")
            need(kv.get("npu") == str(e["npu"]) and kv.get("cpu") == str(e["npu"]) and kv.get("match") == "1", "npu/cpu")
        elif e.get("guard") in ("FAULT", "UNKNOWN"):
            need(kv.get("npu") == "-1" and kv.get("feat") == "-", "npu ran on invalid input")
    elif e["kind"] == "ERROR":
        need(main.startswith("ERROR"), "no ERROR")
        need(kv.get("code") == str(e["code"]) and kv.get("seq") == str(e["seq"]), f"code={kv.get('code')}")
        st = e.get("state_line")
        sl = next((ln for ln in lines[1:] if ln.startswith("STATE")), None)
        need((st is None) == (sl is None), "LINK_BAD line")
        if st and sl:
            skv = parse_kv(sl)
            need(skv.get("src") == "LINK_BAD" and skv.get("state") == str(st["state"])
                 and skv.get("latch") == str(st["latch"]) and skv.get("cand") == str(UNKNOWN), "LINK_BAD fields")
            kv = skv
    elif e["kind"] == "ACK":
        need(main.startswith("ACK"), "no ACK")
        for k in ("ok", "state", "latch"):
            need(kv.get(k) == str(e[k]), f"{k}={kv.get(k)}/{e[k]}")
    elif e["kind"] == "ID":
        need(main.startswith("P3_SENSOR") and hexint(kv.get("model", "0")) == e["model"] and kv.get("model_ok") == "1",
             "identify")
        return not errs, ";".join(errs) or main, kv
    for k, v in extra.items():
        need(kv.get(k) == str(v), f"{k}={kv.get(k)}/{v}")
    need(disp is not None and (hexint(disp["fnd"]), hexint(disp["led"])) == (e["fnd"], e["led"]),
         f"disp={disp}/fnd={e['fnd']:08x},led={e['led']:04x}")
    return not errs, ";".join(errs) or main, kv


def pick(ds, qm, cls, n):
    return [s for s in ds if golden(features(s), qm)[1] == cls][:n]


def run_scenario(h, picks, mid):
    fw = h.fw
    N, W, F = picks
    seq = iter(range(100, 1000))
    it = {NORMAL: iter(N), WARNING: iter(W), FAULT: iter(F)}

    def send(c=None, s=None, why=""):
        s = s or next(it[c])
        k = next(seq)
        h.check("scenario", sensor_frame(k, mid, s), lambda: fw.sensor(k, mid, s), label=why)

    def ack():
        h.check("scenario", frame(CMD_ACK), fw.ack)

    base = N[-1]
    for c in (NORMAL, NORMAL, NORMAL, WARNING, NORMAL, NORMAL, NORMAL, FAULT, NORMAL, NORMAL, NORMAL):
        send(c)                                       # 부팅 UNKNOWN → NORMAL(3회) → WARNING 즉시 → NORMAL → FAULT 래치 유지
    ack()                                             # 래치 해제(ok=1), 상태는 FAULT 유지
    for c in (NORMAL, NORMAL, NORMAL):
        send(c)
    ack()                                             # 래치 없음: ok=0
    send(s=dict(base, t=[T_MISS] + base["t"][1:]), why="temp_missing")
    for c in (WARNING, NORMAL, NORMAL):               # 3개 중 가장 심각한 WARNING으로 하향
        send(c)
    send(s=dict(base, age=[0, 0, 900]), why="dist_stale")
    send(s=dict(base, d=[D_MISS] * 8), why="dist_missing")
    for c in (NORMAL, NORMAL, NORMAL):
        send(c)
    send(s=dict(base, t=[150 * 16] * 8), why="temp_range")
    ack()
    send(s=dict(base, v=[3] * 8), why="vib_stuck_low")
    ack()
    send(s=dict(base, v=[4090] * 8), why="vib_stuck_high")
    ack()
    send(s=dict(base, d=[0] * 8), why="dist_range")
    ack()
    send(s=dict(base, t=[T_MISS] * 8, d=[500] * 8, age=[0, 600, 0]), why="multi_fault")
    ack()
    for c in (NORMAL, NORMAL, NORMAL):
        send(c)
    assert fw.pol.state == NORMAL and not fw.pol.latch


def run_dataset(h, ds, qm, mid, limit):
    stats = dict(n=0, golden=0, dev=0)
    for i, s in enumerate(ds[:limit]):
        k = 2000 + i
        ok, dev = h.check("dataset", sensor_frame(k, mid, s), lambda: h.fw.sensor(k, mid, s), label=s["label"])
        stats["n"] += 1
        stats["golden"] += golden(features(s), qm)[1] == s["label"]
        stats["dev"] += dev.get("npu") == str(s["label"])
    return stats


def run_errors(h, ds, mid, short_wait):
    fw = h.fw
    s = ds[0]
    good = sensor_frame(77, mid, s)
    bad = bytearray(good)
    bad[20] ^= 0x01
    h.check("errors", bytes(bad), lambda: fw.proto_error("CRC"), extra={"bad": 1})
    h.check("errors", sensor_frame(78, mid ^ 1, s), lambda: fw.proto_error("MODEL", 78), extra={"bad": 2})
    h.check("errors", frame(b"Z", b"\x01"), lambda: fw.proto_error("CMD"))           # 연속 3회 → LINK_BAD
    h.check("errors", b"\x55\xaaP4" + good, lambda: fw.sensor(77, mid, s), extra={"junk": 4})
    h.tr.write(good[:30])
    time.sleep(short_wait)
    h.check("errors", b"", lambda: fw.proto_error("TIMEOUT"))
    h.check("errors", good, lambda: fw.sensor(77, mid, s))
    h.check("errors", b"", fw.link_timeout)          # 아무것도 보내지 않으면 링크 감시가 UNKNOWN을 낸다
    h.check("errors", good, lambda: fw.sensor(77, mid, s))
    h.check("errors", frame(CMD_ID), dict(kind="ID", model=mid))


def main():
    p = argparse.ArgumentParser()
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--port")
    g.add_argument("--cosim")
    p.add_argument("--baud", type=int, default=115200)
    p.add_argument("--timeout", type=float, default=30.0, help="응답 줄 대기(초). 보드 링크 감시 시험은 이보다 짧아야 한다")
    p.add_argument("--short-wait", type=float, default=None)
    p.add_argument("--limit", type=int, default=60, help="dataset 묶음 창 수(시험셋 1500개 중)")
    p.add_argument("--suites", default="scenario,dataset,errors")
    p.add_argument("--csv", type=Path, required=True)
    p.add_argument("--log", type=Path, required=True, help="장치가 보낸 UART 줄 원문")
    a = p.parse_args()
    target = "fpga" if a.port else "rtl_cosim"
    qm = load_qmodel()
    mid = model_id(qm)
    fw = Firmware(qm)
    ds = dataset(*TEST)
    # 표본 선택(골든 계산 수 초)은 장치 연결 전에 끝낸다: 도중에 하면 펌웨어 링크 감시가 반응한다
    picks = [pick(ds, qm, c, 30) for c in (NORMAL, WARNING, FAULT)]
    tr = SerialTransport(a.port, a.baud) if a.port else ProcTransport(a.cosim)
    with a.log.open("w") as log, a.csv.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["target", "step", "suite", "kind", "seq", "label", "expect_cand", "dev_cand",
                                          "expect_state", "dev_state", "latch", "ok", "detail"])
        w.writeheader()
        h = Host(tr, a.timeout, log, fw, target, w)
        if a.port:                                     # 보드: 정책 상태를 알 수 있도록 btnC Reset 뒤 부팅 줄부터 받는다
            print("보드의 btnC(Reset)를 누르세요: 부팅 줄(P3_SENSOR READY)을 기다립니다")
            tr.s.reset_input_buffer()
            while True:
                line = tr.readline(120)
                if line is None:
                    print("SENSOR_HOST_FAIL no boot line")
                    return 1
                if line.startswith("P3_SENSOR READY"):
                    break
        else:
            line = tr.readline(a.timeout)
        log.write(f"{line}\n")
        kv = parse_kv(line or "")
        boot_ok = bool(line and hexint(kv.get("model", "0")) == mid and kv.get("model_ok") == "1"
                       and kv.get("bias_rc") == "0")
        lines = h.read_block()
        b = fw.boot()
        disp = parse_kv(lines[-1]) if lines else {}
        boot_ok = boot_ok and bool(disp) and (hexint(disp["fnd"]), hexint(disp["led"])) == (b["fnd"], b["led"])
        print(f"BOOT {'PASS' if boot_ok else 'FAIL'} :: {line} {lines}")
        h.n += 1
        h.passed += boot_ok
        h.check("id", frame(CMD_ID), dict(kind="ID", model=mid))
        suites = a.suites.split(",")
        st = dict(n=0, golden=0, dev=0)
        if "scenario" in suites:
            run_scenario(h, picks, mid)
        if "dataset" in suites:
            st = run_dataset(h, ds, qm, mid, a.limit)
        if "errors" in suites:
            run_errors(h, ds, mid, a.short_wait if a.short_wait else (1.0 if a.cosim else 5.0))
    rc = tr.close()
    n = max(st["n"], 1)
    print(f"SENSOR_HOST_SUMMARY target={target} checks={h.passed}/{h.n} unsolicited_link_timeout={h.unsolicited} "
          f"dataset={st['n']} golden_label_acc={st['golden']}/{st['n']} ({100 * st['golden'] / n:.1f}%) "
          f"device_label_acc={st['dev']}/{st['n']} ({100 * st['dev'] / n:.1f}%) proc_rc={rc}")
    for suite, step, detail in h.fails[:10]:
        print(f"FAIL_DETAIL {suite} step={step} {detail}")
    ok = h.passed == h.n and rc == 0
    print("SENSOR_HOST_PASS" if ok else "SENSOR_HOST_FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
