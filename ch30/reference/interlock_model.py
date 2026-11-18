#!/usr/bin/env python3
"""30장 기준 모델: motor_interlock.v를 클록 단위로 옮긴 Python 모델 + 시나리오(입력 파형) + 안전 성질 검사.
시나리오는 모터 없이 출력만 보는 시험이다 (TICK=16, STEP=8, WD_LIMIT=400으로 줄여 시뮬레이션)."""
from __future__ import annotations
import sys

TICK, STEP, WD = 16, 8, 400


def model(ins):
    s = dict(armed=0, wd=WD, tick=0, pwm=0, rs=0, rd=0, dir=0, spd=0)
    out = []
    for estop_n, arm, en, sens, av, asp, adir in ins:
        estop = not estop_n
        wd_exp = s["wd"] >= WD
        bad = sens >= 4
        block = (wd_exp << 4) | (bad << 3) | ((not en) << 2) | ((not s["armed"]) << 1) | estop
        ok = block == 0
        pwm = ok and s["pwm"] < s["spd"]
        out.append((int(ok), int(pwm), s["dir"], s["spd"], block))
        tick = s["tick"] == TICK - 1
        target = 0 if s["rd"] != s["dir"] else s["rs"]
        n = dict(s)
        n["pwm"] = (s["pwm"] + 1) & 0xFF
        n["tick"] = 0 if tick else s["tick"] + 1
        if av: n["wd"], n["rs"], n["rd"] = 0, asp, adir
        elif not wd_exp: n["wd"] = s["wd"] + 1
        if estop: n["armed"] = 0
        elif arm and en and s["spd"] == 0: n["armed"] = 1
        if not ok: n["spd"] = 0
        elif tick:
            if s["spd"] == 0 and s["rd"] != s["dir"]: n["dir"] = s["rd"]
            elif target > s["spd"]: n["spd"] = s["spd"] + STEP if target - s["spd"] > STEP else target
            else: n["spd"] = s["spd"] - STEP if s["spd"] - target > STEP else target
        s = n
    return out


def scenario():
    """(구간 길이, estop_n, arm, enable, sensor, ai 주기, 속도, 방향, 설명)"""
    seg = [(50, 1, 0, 1, 0, 0, 0, 0, "무장 전: AI가 명령해도 정지"),
           (40, 1, 0, 1, 0, 20, 200, 0, "무장 전 AI 명령 200"),
           (5, 1, 1, 1, 0, 20, 200, 0, "무장"),
           (900, 1, 0, 1, 0, 20, 200, 0, "가속 (TICK마다 +8, 200까지)"),
           (600, 1, 0, 1, 0, 20, 120, 1, "반대 방향 요청: 0까지 감속 → 방향 전환 → 120을 향해 가속"),
           (100, 1, 0, 1, 4, 20, 120, 1, "센서 UNKNOWN → 즉시 정지"),
           (300, 1, 0, 1, 0, 20, 120, 1, "센서 정상 복귀: 0부터 다시 가속"),
           (60, 0, 0, 1, 0, 20, 120, 1, "비상정지 눌림"),
           (200, 1, 0, 1, 0, 20, 120, 1, "비상정지 풀림: 무장이 풀려 계속 정지"),
           (5, 1, 1, 1, 0, 20, 120, 1, "다시 무장"),
           (300, 1, 0, 1, 0, 20, 120, 1, "다시 가속"),
           (700, 1, 0, 1, 0, 0, 120, 1, "AI 명령 끊김 → 400클록 뒤 정지"),
           (200, 1, 0, 1, 0, 20, 60, 1, "AI 복귀"),
           (100, 1, 0, 0, 0, 20, 60, 1, "사용 스위치 끔"),
           (100, 1, 0, 1, 5, 20, 60, 1, "센서 FAULT")]
    ins, notes = [], []
    for n, en_n, arm, en, sens, per, sp, d, why in seg:
        notes.append((len(ins), why))
        for k in range(n):
            av = int(per > 0 and k % per == 0)
            ins.append((en_n, arm, en, sens, av, sp, d))
    return ins, notes


def properties(ins, out):
    errs = []
    for t, ((estop_n, arm, en, sens, av, sp, d), (ok, pwm, dr, spd, blk)) in enumerate(zip(ins, out)):
        if pwm and not ok: errs.append(f"t={t} 막힘인데 PWM")
        if (not estop_n or sens >= 4 or not en) and ok: errs.append(f"t={t} 안전 입력 위반인데 허용")
        if t and abs(spd - out[t - 1][3]) > STEP and spd != 0: errs.append(f"t={t} 속도 변화 > STEP")
        if t and dr != out[t - 1][2] and out[t - 1][3] != 0: errs.append(f"t={t} 움직이는 중 방향 전환")
    return errs


if __name__ == "__main__":
    ins, notes = scenario()
    out = model(ins)
    errs = properties(ins, out)
    if errs:
        print("\n".join(errs[:5])); print("PYTHON_INTERLOCK_PROPERTY_FAIL"); sys.exit(1)
    peak = max(o[3] for o in out)
    print(f"PYTHON_INTERLOCK_PROPERTY_PASS cycles={len(ins)} max_speed={peak} reversals={sum(1 for t in range(1, len(out)) if out[t][2] != out[t-1][2])}")
    if len(sys.argv) > 2 and sys.argv[1] == "--out":
        with open(sys.argv[2], "w") as f:
            f.writelines(" ".join(map(str, i)) + "\n" for i in ins)
        with open(sys.argv[2] + ".expect", "w") as f:
            f.writelines(" ".join(map(str, o)) + "\n" for o in out)
        ends = [s for s, _ in notes[1:]] + [len(out)]
        for (start, why), end in zip(notes, ends):           # 구간의 마지막 클록 출력
            o = out[end - 1]
            print(f"SCENE t={start:4d}~{end - 1:4d} {why} → 끝에서 en={o[0]} speed={o[3]} dir={o[2]} block=0b{o[4]:05b}")
