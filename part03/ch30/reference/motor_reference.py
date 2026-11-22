#!/usr/bin/env python3
"""30장: NPU 추천 + 독립 모터 안전 코어 기준모델(정본, 표준 라이브러리만). 교육용이며 기능안전 인증 로직이 아니다.

구조(가이드 1절): 센서 창 → 29장 guard·NPU·경보 정책(펌웨어) → 추천(방향·속도) → AXI GPIO 명령 워드
                → p3_motor_safety(명령 승인·워치독 → 독립 인터록 → 방향·데드타임·램프·PWM) → IN1/IN2/ENA
NPU·CPU는 명령 워드만 쓴다. 핀은 코어만 구동하며 E-Stop·고장·과열·워치독·트립·리밋은 AI 점수와 무관하게 우선한다.

추천 규칙(펌웨어 recommend): 29장 정책 상태 NORMAL → 운전자 방향·80 %, WARNING → 운전자 방향·30 %,
                             FAULT·UNKNOWN → STOP. 운전자 방향은 'D' 명령(기본 FWD).
코어 클록 규칙은 rtl/p3_motor_safety.v 머리말과 같다. Core.step()은 (현재 상태·입력의 조합 출력) 후 클록 갱신.
"""
import argparse
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

STOP, FWD, REV = 0, 1, 2
L_ESTOP, L_FAULT, L_OTEMP, L_WD, L_RESET = 1, 2, 4, 8, 16
NORMAL, WARNING, FAULT, UNKNOWN = 0, 1, 2, 3
DUTY_OF_STATE = {NORMAL: 80, WARNING: 30, FAULT: 0, UNKNOWN: 0}
BOARD = dict(PWM_PERIOD=5000, DEAD_CYC=10_000_000, WD_CYC=50_000_000, RAMP_CYC=100_000)
COSIM = dict(PWM_PERIOD=200, DEAD_CYC=3000, WD_CYC=400_000, RAMP_CYC=40)
UNIT = dict(PWM_PERIOD=100, DEAD_CYC=9, WD_CYC=70, RAMP_CYC=3)


def cmd_word(d, duty, kick, clr=0):
    return (duty & 0x7F) | ((d & 3) << 8) | ((clr & 1) << 12) | ((kick & 1) << 15)


class Core:
    def __init__(self, PWM_PERIOD, DEAD_CYC, WD_CYC, RAMP_CYC):
        self.P, self.DEAD, self.WD, self.RAMP = PWM_PERIOD, DEAD_CYC, WD_CYC, RAMP_CYC
        assert self.P % 100 == 0
        self.reset()

    def reset(self):
        self.kick_q = self.clr_q = self.cmd_err = 0
        self.req_dir = STOP
        self.req_duty = self.wd_cnt = 0
        self.latched = L_RESET
        self.drive_dir = STOP
        self.dead = self.ramp = self.pwm = self.duty = 0

    def comb(self, cmd, estop, fault, otemp, lim_f, lim_r):
        wd_exp = int(self.wd_cnt == 0)
        trip = int(self.latched != 0)
        hard = estop or fault or otemp or wd_exp or trip
        lim_block = (self.drive_dir == FWD and lim_f) or (self.drive_dir == REV and lim_r)
        gate = int(not hard and not lim_block)
        in1 = int(gate and self.drive_dir == FWD)
        in2 = int(gate and self.drive_dir == REV)
        ena = int((in1 or in2) and self.pwm < self.duty * (self.P // 100))
        status = (self.duty | self.cmd_err << 7 | self.drive_dir << 8 | self.req_dir << 10 | gate << 12
                  | int(self.dead != 0) << 13 | trip << 14 | wd_exp << 15 | self.latched << 16
                  | estop << 21 | fault << 22 | otemp << 23 | lim_f << 24 | lim_r << 25
                  | in1 << 26 | in2 << 27 | ena << 28)
        return dict(in1=in1, in2=in2, ena=ena, status=status, gate=gate, wd_exp=wd_exp, trip=trip, hard=hard)

    def step(self, cmd, estop=0, fault=0, otemp=0, lim_f=0, lim_r=0, rst=0):
        if rst:
            self.reset()
            return None
        o = self.comb(cmd, estop, fault, otemp, lim_f, lim_r)
        kick_ev = ((cmd >> 15) & 1) ^ self.kick_q
        clr_ev = ((cmd >> 12) & 1) ^ self.clr_q
        d, u = (cmd >> 8) & 3, cmd & 0x7F
        ok = d != 3 and u <= 100
        # 인터록 래치(현재 req_dir·wd_cnt 기준)
        cause = (estop * L_ESTOP) | (fault * L_FAULT) | (otemp * L_OTEMP) | (o["wd_exp"] * L_WD)
        nl = self.latched | cause
        if clr_ev and self.req_dir == STOP:
            nl = cause | (self.latched & cause)
        # 구동(현재 레지스터 기준)
        req_ok = not o["hard"] and not (self.req_dir == FWD and lim_f) and not (self.req_dir == REV and lim_r)
        dd, dead, ramp, duty = self.drive_dir, self.dead, self.ramp, self.duty
        if not req_ok or self.req_dir == STOP or (dd != STOP and dd != self.req_dir):
            duty, ramp = 0, 0
            if dd != STOP:
                dd, dead = STOP, self.DEAD
            elif dead:
                dead -= 1
        elif dd == STOP:
            ramp = 0
            if dead:
                dead -= 1
            else:
                dd = self.req_dir
        elif self.req_duty < duty:
            duty, ramp = self.req_duty, 0
        elif self.req_duty > duty:
            if ramp == self.RAMP - 1:
                duty, ramp = duty + 1, 0
            else:
                ramp += 1
        else:
            ramp = 0
        # 명령 승인·워치독
        if kick_ev:
            self.wd_cnt = self.WD
            self.cmd_err = int(not ok)
            self.req_dir = d if ok else STOP
            self.req_duty = u if ok and d != STOP else 0
        elif self.wd_cnt:
            self.wd_cnt -= 1
        self.kick_q, self.clr_q = (cmd >> 15) & 1, (cmd >> 12) & 1
        self.latched = nl
        self.drive_dir, self.dead, self.ramp, self.duty = dd, dead, ramp, duty
        self.pwm = 0 if self.pwm == self.P - 1 else self.pwm + 1
        return o


class Invariant:
    """클록마다 확인하는 안전 성질(코어 출력과 입력만 본다)."""

    def __init__(self, dead):
        self.dead, self.off_run, self.last_dir, self.viol, self.since_reset_clear = dead, 10 ** 9, 0, [], False

    def check(self, n, o, estop, fault, otemp, lim_f, lim_r, trip, wd_exp):
        on = o["in1"] or o["in2"] or o["ena"]
        if on and (estop or fault or otemp or trip or wd_exp):
            self.viol.append((n, "output while hard stop"))
        if o["in1"] and o["in2"]:
            self.viol.append((n, "in1 and in2"))
        if (o["in1"] and lim_f) or (o["in2"] and lim_r):
            self.viol.append((n, "drive into limit"))
        if o["ena"] and not (o["in1"] or o["in2"]):
            self.viol.append((n, "ena without direction"))
        d = FWD if o["in1"] else REV if o["in2"] else 0
        if d:
            if self.last_dir and d != self.last_dir and self.off_run < self.dead:
                self.viol.append((n, f"reverse after {self.off_run} off cycles"))
            self.last_dir, self.off_run = d, 0
        else:
            self.off_run += 1


def unit_vectors(out, n_rand=120000, seed=3001):
    """RTL 코어 벡터: rst cmd estop fault otemp lim_f lim_r | in1 in2 ena status (UNIT 파라미터)."""
    rng = random.Random(seed)
    c = Core(**UNIT)
    rows, kick, clr = [], 0, 0
    inv = Invariant(UNIT["DEAD_CYC"])
    ins = dict(estop=0, fault=0, otemp=0, lim_f=0, lim_r=0)
    cmd = 0

    def emit(rst=0, n=1):
        for _ in range(n):
            o = c.step(cmd, rst=rst, **ins)
            if o is None:
                rows.append(f"1 {cmd:08x} 0 0 0 0 0 0 0 0 00000000")
                continue
            inv.check(len(rows), o, trip=o["trip"], wd_exp=o["wd_exp"], **ins)
            rows.append(f"0 {cmd:08x} {ins['estop']} {ins['fault']} {ins['otemp']} {ins['lim_f']} {ins['lim_r']} "
                        f"{o['in1']} {o['in2']} {o['ena']} {o['status']:08x}")

    def send(d, duty, clear=False, n=1):
        nonlocal cmd, kick, clr
        kick ^= 1
        cmd = cmd_word(d, duty, kick, clr)
        emit(n=n)
        if clear:                                   # kick 다음 쓰기에서 clear(같은 클록 WD 재장전은 다음 클록부터)
            clr ^= 1
            cmd = cmd_word(d, duty, kick, clr)
            emit(n=n)

    emit(rst=1, n=2)
    emit(n=5)                                       # Reset 뒤: 명령 없어도 출력 0
    send(FWD, 50, n=3)                              # 해제 전 FWD: 트립 유지
    send(STOP, 0, clear=True, n=3)                  # 해제
    send(FWD, 60, n=40)                             # 데드타임(0) → FWD, 램프
    send(FWD, 20, n=10)                             # 즉시 감속
    send(REV, 40, n=40)                             # 반전: DEAD 동안 off
    ins["estop"] = 1
    emit(n=5)                                       # 조합 차단 + 래치
    ins["estop"] = 0
    send(REV, 40, clear=True, n=5)                  # 운전 명령 중 해제 요청 → 거부(트립 유지)
    send(STOP, 0, clear=True, n=3)
    send(REV, 40, n=30)
    ins["lim_r"] = 1
    emit(n=5)                                       # 진행 방향 리밋: 차단(래치 없음)
    send(FWD, 30, n=30)                             # 반대 방향은 허용
    ins["lim_r"] = 0
    emit(n=UNIT["WD_CYC"] + 5)                      # kick 없음 → 워치독 만료·래치
    send(FWD, 30, n=5)
    send(STOP, 0, clear=True, n=3)
    send(FWD, 101, n=5)                             # 무효 명령 → STOP + cmd_err
    send(3, 10, n=5)
    for name in ("fault", "otemp"):
        send(FWD, 70, n=20)
        ins[name] = 1
        emit(n=3)
        ins[name] = 0
        send(STOP, 0, clear=True, n=3)
    active, left, last = None, 0, (FWD, 70)                            # 무작위 운전: 명령·짧은 고장·트립 뒤 STOP+해제·워치독 공백·Reset
    for _ in range(n_rand):
        r = rng.random()
        if active and left == 0:
            ins[active], active = 0, None
        if r < 0.0005:
            emit(rst=1)
        elif r < 0.001:
            emit(n=UNIT["WD_CYC"] + rng.randint(1, 10))
        elif r < 0.004 and active is None:
            active, left = rng.choice(list(ins)), rng.randint(1, 25)
            ins[active] = 1
            emit()
        elif c.latched and r < 0.06:
            send(STOP, 0, clear=True)
        elif r < 0.03:
            send(*last)                                 # 같은 명령 재전송(kick = 워치독 갱신)
        elif r < 0.034:
            last = (rng.choice([STOP, FWD, FWD, FWD, REV, REV, 3]), rng.choice([0, 15, 40, 70, 100, 100, 101]))
            send(*last, clear=rng.random() < 0.1)
        else:
            emit()
        left = max(0, left - 1)
    out.write_text("\n".join(rows) + "\n")
    ena_on = sum(1 for r in rows if r.split()[0] == "0" and r.split()[9] == "1")
    print(f"MOTOR_UNIT_VECTORS n={len(rows)} ena_on={ena_on} invariant_violations={len(inv.viol)}")
    assert not inv.viol, inv.viol[:5]


def selftest():
    c = Core(**UNIT)
    for _ in range(5):
        assert c.step(cmd_word(FWD, 50, 0))["in1"] == 0           # Reset 뒤 해제 전에는 움직이지 않는다
    assert c.latched & L_RESET
    # 가이드 4절 예제와 같은 우선순위: estop·fault·데이터 끊김(fresh 아님)이면 출력 0
    c = Core(**UNIT)
    c.step(cmd_word(STOP, 0, 1))
    c.step(cmd_word(STOP, 0, 1, 1))
    for _ in range(3 + UNIT["DEAD_CYC"]):
        c.step(cmd_word(FWD, 80, 0, 1))
    seen = [c.step(cmd_word(FWD, 80, 0, 1)) for _ in range(20)]
    assert any(o["in1"] for o in seen)
    assert c.step(cmd_word(FWD, 80, 0, 1), estop=1)["in1"] == 0
    assert c.step(cmd_word(FWD, 80, 0, 1))["in1"] == 0              # 래치: 풀려도 해제 전까지 0
    print("MOTOR_REFERENCE_SELFTEST_PASS")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--selftest", action="store_true")
    p.add_argument("--unit-vectors", type=Path)
    a = p.parse_args()
    if a.selftest:
        selftest()
    if a.unit_vectors:
        unit_vectors(a.unit_vectors)


if __name__ == "__main__":
    main()
