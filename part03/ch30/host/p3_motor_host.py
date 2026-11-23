#!/usr/bin/env python3
"""PC 호스트: 가상 센서 창 → 보드(또는 PC 시뮬레이션) → 정책 상태·추천·모터 상태 워드 판정 → CSV.

  --cosim "<명령>"  PC 빌드 펌웨어 + RTL(5-1 NPU + 6-4 모터 안전 코어). 'J' 주입으로 E-Stop·고장·과열·리밋·
                    클록 진행(워치독)을 넣는다. 코어 파라미터는 motor_reference.COSIM.
  --port <포트>     Basys3(6-4 Bitstream + ELF). 'J'는 거부된다 → 자동 단계만 하고 버튼·스위치 단계는 점검표(B18~)로.
판정: 정책(state·latch·npu·guard)은 6-3 Firmware 모델과 같아야 하고, 추천(rec_dir·rec_duty)은 motor_recommend 규칙,
      모터 상태 워드(st)는 단계별 술어(예: E-Stop 중 in1=0·ESTOP 래치, AI가 NORMAL이어도 구동 없음)를 만족해야 한다.
      핀 단위 안전 불변식은 PC 시뮬레이션 브리지 TB가 모든 클록에서 따로 센다(SAFETY_SUMMARY).
"""
import argparse
import csv
import struct
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from part03.ch29.host.p3_sensor_host import ProcTransport, SerialTransport, pick  # noqa: E402
from part03.ch29.reference.sensor_reference import (  # noqa: E402
    FAULT, NORMAL, T_MISS, TEST, UNKNOWN, WARNING, Firmware, dataset, frame, load_qmodel, model_id, parse_kv,
    sensor_frame,
)
from part03.ch30.reference.motor_reference import COSIM, FWD, REV, STOP  # noqa: E402

DUTY = {NORMAL: 80, WARNING: 30}
I_ESTOP, I_FAULT, I_OTEMP, I_LIMF, I_LIMR = 1, 2, 4, 8, 16
L_ESTOP, L_FAULT, L_OTEMP, L_WD, L_RESET = 1, 2, 4, 8, 16


def recommend(state, op_dir):
    return (op_dir, DUTY[state]) if state in DUTY else (STOP, 0)


def fields(st):
    return dict(duty=st & 0x7F, err=st >> 7 & 1, drive=st >> 8 & 3, req=st >> 10 & 3, gate=st >> 12 & 1,
                dead=st >> 13 & 1, trip=st >> 14 & 1, wd=st >> 15 & 1, latched=st >> 16 & 31, inputs=st >> 21 & 31,
                in1=st >> 26 & 1, in2=st >> 27 & 1, ena=st >> 28 & 1)


class Host:
    def __init__(self, tr, timeout, log, writer, target):
        self.tr, self.timeout, self.log, self.w, self.target = tr, timeout, log, writer, target
        self.fw = Firmware(load_qmodel())
        self.mid = self.fw.mid
        self.op_dir, self.n, self.passed, self.fails, self.step = FWD, 0, 0, [], 0

    def block(self):
        lines = []
        while True:
            line = self.tr.readline(self.timeout)
            if line is None:
                return lines
            self.log.write(line + "\n")
            lines.append(line)
            if line.startswith("DISP") or (line.startswith("P3_MOTOR") and len(lines) == 1):
                return lines

    def run(self, name, data, kind="MOTOR", src=None, policy=None, pred=None, why=""):
        """policy: 정책 기대(6-3 Firmware 결과 dict) 또는 None. pred(f): 모터 상태 술어 → 실패 설명 목록."""
        if data:
            self.tr.write(data)
        lines = self.block()
        errs = []
        main = next((ln for ln in lines if ln.startswith(kind)), None)
        kv = parse_kv(main or "")
        f = fields(int(kv["st"], 16)) if "st" in kv else {}
        if main is None:
            errs.append(f"no {kind}: {lines}")
        elif kind == "MOTOR":
            if src and kv.get("src") != src:
                errs.append(f"src={kv.get('src')}")
            fw = self.fw
            if policy is not None:
                for k in ("state", "latch"):
                    if kv.get(k) != str(policy[k]):
                        errs.append(f"{k}={kv.get(k)}/{policy[k]}")
                if "guard" in policy and kv.get("guard") != policy["guard"]:
                    errs.append(f"guard={kv.get('guard')}/{policy['guard']}")
                if policy.get("guard") == "OK" and kv.get("npu") != str(policy["npu"]):
                    errs.append(f"npu={kv.get('npu')}/{policy['npu']}")
            if kv.get("state") != str(fw.pol.state):
                errs.append(f"policy state={kv.get('state')}/{fw.pol.state}")
            rd, ru = recommend(fw.pol.state, self.op_dir)
            if src not in ("QUERY", "INJECT", "ADVANCE", "ACK", "BOOT", "CLEAR") and \
                    (kv.get("rec_dir"), kv.get("rec_duty")) != (str(rd), str(ru)):
                errs.append(f"rec={kv.get('rec_dir')},{kv.get('rec_duty')}/{rd},{ru}")
            if pred:
                errs += pred(f)
            disp = parse_kv(lines[-1]) if lines and lines[-1].startswith("DISP") else None
            fnd = (fw.pol.state << 12 | f.get("drive", 0) << 8 | f.get("duty", 0) | 0xF << 16
                   | (f.get("trip", 0) << 22))
            led = (1 << fw.pol.state) | (1 << 15 if fw.pol.state != NORMAL else 0) | (1 << 13 if fw.pol.latch else 0)
            if not disp or (int(disp["fnd"], 16), int(disp["led"], 16)) != (fnd, led):
                errs.append(f"disp={disp}/{fnd:08x},{led:04x}")
        elif kind == "ERROR" and pred:
            errs += pred(kv)
        ok = not errs
        self.step += 1
        self.n += 1
        self.passed += ok
        if not ok:
            self.fails.append((self.step, name, errs))
        self.w.writerow(dict(target=self.target, step=self.step, name=name, why=why, src=kv.get("src", kind),
                             state=kv.get("state", ""), rec_dir=kv.get("rec_dir", ""), rec_duty=kv.get("rec_duty", ""),
                             st=kv.get("st", ""), drive=f.get("drive", ""), duty=f.get("duty", ""),
                             trip=f.get("trip", ""), latched=f.get("latched", ""), ok=int(ok), detail=";".join(errs)))
        print(f"STEP {self.step:3d} {name:22s} {'PASS' if ok else 'FAIL'} {';'.join(errs) or (main or '')[:150]}")
        return f

    # ---- 동작 단위
    def sensor(self, name, s, seq, pred=None, why=""):
        fw = self.fw
        e = fw.sensor(seq, self.mid, s)
        return self.run(name, sensor_frame(seq, self.mid, s), src="FRAME", policy=e, pred=pred, why=why)

    def inject(self, name, mask, pred=None):
        return self.run(name, frame(b"J", struct.pack("<BI", 1, mask)), src="INJECT", pred=pred)

    def advance(self, name, n, pred=None):
        return self.run(name, frame(b"J", struct.pack("<BI", 2, n)), src="ADVANCE", pred=pred)

    def clear(self, name, pred=None):
        return self.run(name, frame(b"C"), src="CLEAR", pred=pred)

    def direction(self, name, d, pred=None):
        self.op_dir = d
        return self.run(name, frame(b"D", bytes([d])), src="DIR", pred=pred)

    def ack(self, name, pred=None):
        self.fw.pol.ack()
        return self.run(name, frame(b"A"), src="ACK", pred=pred)


def P(**want):
    """상태 워드 필드 = 값 술어."""
    def pred(f):
        return [f"{k}={f.get(k)}/{v}" for k, v in want.items() if f.get(k) != v]
    return pred


def has_latch(bit, present=True):
    def pred(f):
        return [] if bool(f["latched"] & bit) == present else [f"latched={f['latched']:05b} bit {bit} {present}"]
    return pred


def all_of(*ps):
    return lambda f: [e for p in ps for e in p(f)]


def cosim_suite(h, picks):
    N, W, F = (iter(x) for x in picks)
    seq = iter(range(300, 2000))
    nxt = {NORMAL: N, WARNING: W, FAULT: F}
    run_up = COSIM["DEAD_CYC"] + 80 * COSIM["RAMP_CYC"] + 2 * COSIM["PWM_PERIOD"]

    def s(c, name, pred=None, why=""):
        return h.sensor(name, next(nxt[c]), next(seq), pred, why)

    stopped = P(in1=0, in2=0, ena=0)
    for i in range(3):                                # 부팅 트립(RESET): NPU가 NORMAL이어도 움직이지 않는다
        s(NORMAL, f"boot_normal_{i}", all_of(stopped, has_latch(L_RESET)), "자동 재가동 금지")
    h.advance("boot_wait", run_up, all_of(stopped, P(trip=1)))
    h.clear("clear_reset", P(trip=0, latched=0, req=STOP))
    s(NORMAL, "normal_run", P(req=FWD, trip=0))
    h.advance("ramp_to_80", run_up, P(drive=FWD, duty=80, in1=1, in2=0, gate=1))
    s(WARNING, "warning_slow", P(req=FWD, duty=30, drive=FWD), "감속은 즉시")
    h.inject("estop_on", I_ESTOP, all_of(stopped, P(gate=0, drive=STOP), has_latch(L_ESTOP)))
    for i in range(3):                                # AI 결과가 NORMAL로 내려와도 E-Stop이 우선
        s(NORMAL, f"estop_ai_normal_{i}", all_of(stopped, has_latch(L_ESTOP)), "AI는 E-Stop을 넘을 수 없다")
    h.advance("estop_hold", run_up, stopped)
    h.inject("estop_off", 0, all_of(stopped, P(trip=1), has_latch(L_ESTOP)))
    s(NORMAL, "after_release_still_trip", all_of(stopped, P(trip=1)), "래치: 해제 명령 전까지 정지")
    h.clear("clear_estop", P(trip=0, latched=0))
    s(NORMAL, "resume", P(req=FWD))
    h.advance("resume_run", run_up, P(drive=FWD, duty=80, in1=1))
    h.inject("limit_fwd", I_LIMF, all_of(stopped, P(trip=0, drive=STOP)))   # 래치 없음, 진행 방향만 차단
    h.direction("reverse_off_limit", REV, P(req=REV))
    h.advance("reverse_run", run_up, P(drive=REV, in2=1, in1=0, trip=0))
    h.inject("limit_fwd_off", 0, P(drive=REV, in2=1))
    h.direction("forward_again", FWD, all_of(stopped, P(req=FWD)))
    h.advance("dead_time_half", COSIM["DEAD_CYC"] // 2, all_of(stopped, P(dead=1)), )
    h.advance("dead_time_done", run_up, P(drive=FWD, in1=1))
    s(FAULT, "npu_fault_stop", all_of(stopped, P(req=STOP, trip=0)), "AI FAULT → STOP 추천")
    for i in range(3):
        s(NORMAL, f"policy_latched_{i}", all_of(stopped, P(req=STOP)), "29장 FAULT 래치")
    h.ack("policy_ack")
    for i in range(3):
        s(NORMAL, f"after_ack_{i}", None)
    h.advance("run_after_ack", run_up, P(drive=FWD, duty=80, in1=1))
    base = picks[0][-1]
    h.sensor("temp_missing", dict(base, t=[T_MISS] + base["t"][1:]), next(seq), all_of(stopped, P(req=STOP)), "guard")
    for i in range(3):
        s(NORMAL, f"recover_{i}", None)
    h.advance("run_again", run_up, P(drive=FWD, in1=1))
    for name, bit, lb in (("fault", I_FAULT, L_FAULT), ("otemp", I_OTEMP, L_OTEMP)):
        h.inject(f"{name}_on", bit, all_of(stopped, has_latch(lb)))
        h.inject(f"{name}_off", 0, all_of(stopped, P(trip=1)))
        h.clear(f"clear_{name}", P(trip=0))
        s(NORMAL, f"{name}_resume", P(req=FWD))
        h.advance(f"{name}_run", run_up, P(drive=FWD, in1=1))
    h.run("query_no_kick", frame(b"Q"), src="QUERY", pred=P(drive=FWD))
    h.advance("watchdog_expire", COSIM["WD_CYC"] + 10, all_of(stopped, P(wd=1), has_latch(L_WD)), )
    s(NORMAL, "kick_after_wd", all_of(stopped, P(wd=0, trip=1)), "kick으로 만료는 풀려도 래치 유지")
    h.clear("clear_wd", P(trip=0, latched=0))
    s(NORMAL, "final_run", P(req=FWD))
    h.advance("final_ramp", run_up, P(drive=FWD, duty=80, in1=1))
    bad = bytearray(sensor_frame(999, h.mid, base))
    bad[20] ^= 1
    h.fw.proto_error("CRC")
    h.run("crc_error", bytes(bad), kind="ERROR", pred=lambda kv: [] if kv.get("code") == "1" else ["code"])
    h.fw.proto_error("CMD")
    h.run("bad_direction", frame(b"D", b"\x03"), kind="ERROR", pred=lambda kv: [] if kv.get("name") == "DIR" else ["name"])
    h.fw.proto_error("CMD")                           # 연속 3회 → UNKNOWN → STOP 추천
    h.run("bad_inject_op", frame(b"J", struct.pack("<BI", 9, 0)), kind="ERROR",
          pred=lambda kv: [] if kv.get("code") == "3" else ["code"])
    h.run("after_link_bad", frame(b"Q"), src="QUERY", pred=P(req=STOP))


def board_suite(h, picks):
    """주입 없이: 부팅 트립 → 해제 → NORMAL 운전(램프) → WARNING 감속 → FAULT 추천 정지 → 'J' 거부."""
    N, W, F = (iter(x) for x in picks)
    seq = iter(range(300, 2000))
    stopped = P(in1=0, in2=0, ena=0)
    h.sensor("boot_normal", next(N), next(seq), all_of(stopped, P(trip=1)))
    h.clear("clear_reset", P(trip=0))
    for i in range(10):                               # 약 0.2 s 동안 프레임 반복(DEAD 100 ms + 램프 80 ms)
        f = h.sensor(f"run_{i}", next(N), next(seq), P(req=FWD, trip=0))
        time.sleep(0.02)
    h.sensor("run_check", next(N), next(seq), P(drive=FWD, duty=80))
    h.sensor("warning", next(W), next(seq), P(duty=30))
    h.sensor("npu_fault", next(F), next(seq), all_of(stopped, P(req=STOP)))
    h.run("inject_rejected", frame(b"J", struct.pack("<BI", 1, 1)), kind="ERROR")
    h.fw.proto_error("CMD")
    return f


def main():
    p = argparse.ArgumentParser()
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--port")
    g.add_argument("--cosim")
    p.add_argument("--baud", type=int, default=115200)
    p.add_argument("--timeout", type=float, default=60.0)
    p.add_argument("--csv", type=Path, required=True)
    p.add_argument("--log", type=Path, required=True)
    a = p.parse_args()
    qm = load_qmodel()
    ds = dataset(*TEST)
    picks = [pick(ds, qm, c, 40) for c in (NORMAL, WARNING, FAULT)]   # 연결 전에 계산(링크 감시 회피)
    tr = SerialTransport(a.port, a.baud) if a.port else ProcTransport(a.cosim)
    target = "fpga" if a.port else "rtl_cosim"
    with a.log.open("w") as log, a.csv.open("w", newline="") as fcsv:
        w = csv.DictWriter(fcsv, fieldnames=["target", "step", "name", "why", "src", "state", "rec_dir", "rec_duty",
                                             "st", "drive", "duty", "trip", "latched", "ok", "detail"])
        w.writeheader()
        h = Host(tr, a.timeout, log, w, target)
        if a.port:
            print("보드의 btnC(Reset)를 누르세요: 부팅 줄(P3_MOTOR READY)을 기다립니다")
            tr.s.reset_input_buffer()
            line = None
            while line is None or not line.startswith("P3_MOTOR READY"):
                line = tr.readline(120)
                if line is None:
                    print("MOTOR_HOST_FAIL no boot line")
                    return 1
        else:
            line = tr.readline(a.timeout)
        log.write(f"{line}\n")
        kv = parse_kv(line or "")
        boot_ok = bool(line) and int(kv.get("model", "0"), 16) == h.mid and kv.get("model_ok") == "1"
        h.n += 1
        h.passed += boot_ok
        print(f"BOOT {'PASS' if boot_ok else 'FAIL'} :: {line}")
        h.run("boot_status", b"", src="BOOT", pred=all_of(P(in1=0, in2=0, ena=0, trip=1, req=STOP),
                                                           has_latch(L_RESET)))
        main_line = h.run("identify", frame(b"I"), kind="P3_MOTOR")
        del main_line
        if a.port:
            board_suite(h, picks)
        else:
            cosim_suite(h, picks)
    rc = tr.close()
    print(f"MOTOR_HOST_SUMMARY target={target} checks={h.passed}/{h.n} proc_rc={rc}")
    for step, name, errs in h.fails[:10]:
        print(f"FAIL_DETAIL step={step} {name} {';'.join(errs)}")
    ok = h.passed == h.n and rc == 0
    print("MOTOR_HOST_PASS" if ok else "MOTOR_HOST_FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
