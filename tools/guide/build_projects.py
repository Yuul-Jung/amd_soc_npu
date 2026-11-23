#!/usr/bin/env python3
"""장(프로젝트) 안내서 생성기 — 개편판 (docs/PROJECT_PLAN.md).

  python3 tools/guide/build_projects.py          # pNN_*.html 재생성
  python3 tools/guide/build_projects.py --check  # 디스크 내용과 다르면 exit 1 (CI)

단일 원본:
  course_projects.json      장 목록 (진행 위치 표시)
  pNN/project.json          장 목표·서브젝트·장 뼈대 파일
  chNN/chapter.json         서브젝트 내용 (구 장, 코드·시험·판정)
  pNN/validation/, chNN/validation/   게이트 증거
보드 기대 화면은 pNN 장 Top 시뮬레이션 로그(PNN_CASE_PASS 줄)와 사례 파일(pNN/tb/pNN_cases_sN.txt)에서만 가져온다.
페이지 HTML은 직접 수정하지 않는다.
"""
import glob, json, os, re, sys, types

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_guides as bg   # noqa: E402  (같은 폴더의 장 단위 생성기: 코드 상자·구조도·게이트 공용)

ROOT, rd, esc = bg.ROOT, bg.rd, bg.esc
WORD = {"pass": "통과", "fail": "✗ 실패", "todo": "⚠ 미검증", "na": "해당 없음"}

EXTRA_CSS = """<style>
.road{display:grid;grid-template-columns:repeat(7,minmax(0,1fr));gap:6px;list-style:none;padding:0;margin:12px 0}
.road li{border:1px solid #c9c4ea;border-radius:6px;padding:8px 6px;font-size:13px;text-align:center;background:#fff;min-width:0;word-break:keep-all;overflow-wrap:anywhere}
.road li b{display:block;font-size:12px;color:#4635b1}
.road li.now{background:#4635b1;color:#fff;border-color:#4635b1}
.road li.now b{color:#fff}
.road li.plan{color:#595959;border-style:dashed}
.steps{list-style:none;padding:0;margin:12px 0;display:grid;gap:6px}
.steps li{display:grid;grid-template-columns:4.2em 1fr auto;gap:10px;align-items:center;border-left:6px solid #c9c4ea;background:#fff;padding:8px 12px;border-radius:0 6px 6px 0}
.steps li.done{border-left-color:#2d8a52}
.steps li.demo{border-left-color:#4635b1;font-weight:600}
.steps .code{font:700 15px var(--mono,monospace);color:#4635b1}
.steps li>span{min-width:0;overflow-wrap:anywhere}
.steps li code{word-break:break-all}
.steps .st{font-size:13px;white-space:nowrap}
.verdict{border:1px solid #c9c4ea;border-radius:6px;padding:8px 12px;background:#faf9ff;margin:10px 0}
details.full{margin:10px 0}
td.nw,th.nw{white-space:nowrap}
details.full>summary{cursor:pointer;font-weight:600}
@media (max-width:860px){.road{grid-template-columns:repeat(4,minmax(0,1fr))}.steps li{grid-template-columns:3.6em 1fr}.steps .st{grid-column:2}}
</style>
"""


def pfname(p):
    return f"{p['id']}_{p['slug']}_{p['version']}.html"


def load_projects():
    out = []
    for f in sorted(glob.glob(os.path.join(ROOT, "p[0-9][0-9]", "project.json"))):
        with open(f, encoding="utf-8") as fh:
            p = json.load(fh)
        assert p["id"] == os.path.basename(os.path.dirname(f)), f
        out.append(p)
    return out


# ── 증거 ──────────────────────────────────────────────────────────────────────
class ProjectEvidence:
    """장 Top 증거: RTL 로그(STAGE 1~4)와 Vivado 요약."""

    def __init__(self, p):
        self.tag = p["id"].upper()
        self.rtl_path = bg.latest(p["evidence"]["rtl_log"])
        self.lines = bg.log_lines(self.rtl_path)
        self.tool = bg.sim_tool(self.lines)
        self.rtl_ok = any(ln.startswith("RTL_SIM_PASS") for ln in self.lines) and not any(
            re.search(r"FATAL|RTL_SIM_FAIL", ln) for ln in self.lines)
        self.host = next((ln.strip() for ln in self.lines if re.match(r"PYTHON_\w*SELF_TEST_PASS", ln)), None)
        self.viv_path = bg.latest(p["evidence"]["vivado"])
        self.viv = [ln.strip() for ln in bg.log_lines(self.viv_path) if ln.startswith("SYNTH_TIMING_")]
        self.board_path = bg.latest(f"{p['id']}/validation/board_*.md")
        self.board = bool(self.board_path and re.search(r"\bBOARD_PASS\b", rd(self.board_path)))
        # bg.code()가 쓰는 속성 (코드 상자 상태 줄)
        self.rtl_pass = ["RTL_SIM_PASS"] if self.rtl_ok else []
        self.rtl_fail = [] if self.rtl_ok else ["fail"]
        self.synth = self.viv[0] if self.viv and all(v.startswith("SYNTH_TIMING_PASS") for v in self.viv) else (
            next((v for v in self.viv if v.startswith("SYNTH_TIMING_FAIL")), None))

    def stage_synth(self, n):
        return next((v for v in self.viv if f" STAGE={n} " in v + " "), None)

    def cases(self, stage, subj=None):
        """(sw, 응답 문자열) — 장 Top 시뮬레이션이 실제로 대조한 줄."""
        out = []
        for ln in self.lines:
            m = re.match(self.tag + r'_CASE_PASS stage=(\d+) (\S+) sw=(\d+) rx="(.*)"$', ln.strip())
            if m and int(m.group(1)) == stage and (subj is None or m.group(2) == subj):
                out.append((m.group(2), int(m.group(3)), m.group(4)))
        return out


def s16(b):
    return int.from_bytes(b, "big", signed=True)


def decode(b, pid=""):
    """보낼 바이트 → PC 도구(pNN_send.py) 명령 꼴. 장마다 명령 형식이 다르다."""
    c, n = chr(b[0]), len(b)
    if pid == "p04":
        if c in "AK" and n == 2:
            return f"{c} {b[1]}"
        if c == "T" and n == 3:
            return f"T {b[1]} {b[2]}"
        if c == "Q" and n == 5:
            return f"Q {s16(b[1:5])}"
    if pid == "p03":
        s8 = lambda v: v - 256 if v > 127 else v
        if c == "W" and n == 5:
            return f"W {b[1]} {b[2]} {b[3]} {s8(b[4])}"
        if c == "B" and n == 6:
            return f"B {b[1]} {b[2]} {s16(b[3:6])}"
        if c in "pZ" and n == 2:
            return f"{c} {b[1]}"
        if c == "F":
            return f"F {b[1]} (화소 {n - 2}바이트)"
    if c == "M" and n == 5:
        return f"M {s16(b[1:3])} {s16(b[3:5])}"
    if c == "X" and n == 4:
        return f"X {b[1]} {s16(b[2:4])}"
    if c == "W" and n == 5:
        return f"W {b[1]} {b[2]} {s16(b[3:5])}"
    if c == "x" and n == 2:
        return f"x {b[1]}"
    if c == "w" and n == 3:
        return f"w {b[1]} {b[2]}"
    if c == "Q" and n == 5:
        return f"Q {s16(b[1:5])}"
    if c == "B" and n == 7:
        return f"B {b[1]} {s16(b[2:7])}"
    if c in "DPLNR" and n == 2:
        return f"{c} {b[1]}"
    if all(32 <= v < 127 for v in b):
        return b.decode("ascii")
    return b[:1].decode("ascii", "replace") + " " + b[1:].hex(" ")     # 해석 규칙이 없는 명령: 16진수로


def case_file(p, stage):
    return rd(f"{p['id']}/tb/{p['id']}_cases_s{stage}.txt").splitlines()


def case_labels(p, stage):
    """모델이 함께 쓴 표시용 설명 (사례 줄과 같은 순서). 없으면 빈 목록."""
    path = f"{p['id']}/tb/{p['id']}_case_labels_s{stage}.txt"
    return rd(path).split("\n") if os.path.exists(os.path.join(ROOT, path)) else []


def case_tx(p, stage, subj=None):
    """사례 파일의 보낼 바이트 → PC 도구 명령 꼴 (설명이 있으면 설명)."""
    out, k = [], 0
    labels = case_labels(p, stage)
    for ln in case_file(p, stage):
        f = ln.split()
        if not f or f[0].startswith("#") or f[0] == "END":
            continue
        lab = labels[k] if k < len(labels) else ""
        k += 1
        if subj and f[0] != subj:
            continue
        n = int(f[2], 16)
        out.append(lab or decode(bytes(int(x, 16) for x in f[3:3 + n]), p["id"]))
    return out


def merged(tx, rx):
    """같은 설명·같은 응답이 4줄 넘게 이어지면 한 줄로 (모델 적재 등). → [(명령, sw, 응답, 개수)]"""
    out = []
    for t, (_, sw, r) in zip(tx, rx):
        if out and t.startswith("load") and out[-1][0] == t and out[-1][2] == r:
            out[-1][3] += 1
        else:
            out.append([t, sw, r, 1])
    return out


def cmd_cell(t, n):
    return f"python3 … {esc(t)}" + (f" ({n}개 명령)" if n > 1 else "") if t.startswith("load") else esc(t)


def end_led(p, stage):
    for ln in case_file(p, stage):
        if ln.startswith("END "):
            return ln.split()[1].upper()
    return "????"


def synth_from_md(spec):
    """VS Code 판 Vivado 요약 표(.md)에서 배선 후 WNS를 읽어 게이트로. → (cls, note)"""
    path = spec["path"]
    if not os.path.exists(os.path.join(ROOT, path)):
        return "todo", "⚠ 미검증 · Vivado 기록 없음"
    text = rd(path)
    text = text[text.index(spec["after"]):] if spec["after"] in text else ""
    head, wns = None, []
    for ln in text.splitlines():
        cells = [c.strip() for c in ln.strip().strip("|").split("|")]
        if ln.startswith("| 구성"):
            if head and "WNS(ns)" not in cells:      # 다음 요약 표: 여기서 멈춘다
                break
            head = cells
        elif head and ln.startswith("|") and cells[0] in spec["rows"]:
            if spec.get("first_only") and len(wns) == len(spec["rows"]):
                break                                # 스윕 표: 구성별 첫 줄(10 ns)만
            wns.append(float(cells[head.index("WNS(ns)")]))
    if len(wns) != len(spec["rows"]):
        return "todo", "⚠ 미검증 · Vivado 표에서 해당 구성을 찾지 못함"
    ok = min(wns) >= 0
    what = f"{len(wns)}구성 " if len(wns) > 1 else ""
    return ("pass" if ok else "fail"), (f"{'' if ok else '✗ '}OOC 배선 후 {what}WNS {'최소 ' if len(wns) > 1 else ''}{min(wns):+.3f} ns"
                                        f" ({spec['src']}) · <code>{path}</code>")


def top_sources(p):
    """장 Top 빌드에 실제로 들어가는 RTL (Vivado Tcl의 set rtl 목록)."""
    t = rd(p["vivado_tcl"])
    m = re.search(r"set rtl \{([^}]*)\}", t)
    return set(m.group(1).split()) if m else set()


def gate(cls, name, note):
    return (cls, name, note)


def project_gates(p, e):
    g = [gate("pass", "HTML_PASS", f"{p['version']} · 생성기")]
    g.append(gate("pass", "HOST_MODEL_PASS", e.host) if e.host else gate("todo", "HOST_MODEL_PASS", "⚠ 기준 모델 기록 없음"))
    if e.rtl_ok:
        g.append(gate("pass", "RTL_SIM_PASS", f"장 Top STAGE 1~{len(p['subjects'])} · {e.tool} · {bg.file_date(e.rtl_path)}"))
    elif e.rtl_path:
        g.append(gate("fail", "RTL_SIM_PASS", f"✗ {e.rtl_path}"))
    else:
        g.append(gate("todo", "RTL_SIM_PASS", "⚠ 미검증 · 시뮬레이션 증거 없음"))
    if len(e.viv) >= len(p["subjects"]) and all(v.startswith("SYNTH_TIMING_PASS") for v in e.viv):
        g.append(gate("pass", "SYNTH_TIMING_PASS", f"STAGE 1~{len(p['subjects'])} 비트스트림 · {bg.file_date(e.viv_path)}"))
    elif any(v.startswith("SYNTH_TIMING_FAIL") for v in e.viv):
        g.append(gate("fail", "SYNTH_TIMING_PASS", "✗ " + bg.short(next(v for v in e.viv if "FAIL" in v), 70)))
    else:
        g.append(gate("todo", "SYNTH_TIMING_PASS", "⚠ 미검증 · VS Code Vivado 실행 대기 (" + os.path.basename(p["vivado_tcl"]) + ")"))
    # Vivado 시뮬레이터(xsim)로 같은 TB를 돌린 기록: SIM=xsim bash pNN/scripts/run_sim.sh → validation/xsim_rtl_*.log
    xs = bg.latest(f"{p['id']}/validation/xsim_rtl_*.log")
    if xs:
        xl = bg.log_lines(xs)
        tool = next((ln[8:].strip() for ln in xl if ln.startswith("# tool:")), "Vivado xsim")
        okx = any(ln.startswith("RTL_SIM_PASS") for ln in xl)
        g.append(gate("pass" if okx else "fail", "XSIM_RTL_PASS",
                      f"{'' if okx else '✗ '}{esc(bg.short(tool, 40))} · Icarus와 같은 TB·판정 줄 · {bg.file_date(xs)} · <code>{xs}</code>"))
    else:
        g.append(gate("todo", "XSIM_RTL_PASS", "⚠ 미검증 · Vivado 시뮬레이터(xsim) 실행 대기 — 현재 근거는 Icarus Verilog"))
    drc = bg.drc_open(p["id"])
    if drc:
        g.append(gate(*drc))
    g.append(gate("pass", "BOARD_PASS", e.board_path) if e.board else gate("todo", "BOARD_PASS", "⚠ 미실시 · 실물 보드 확인 대기"))
    return g


# ── 화면 조각 ─────────────────────────────────────────────────────────────────
# 장 페이지는 학습자용이다: 검증 상태·증거 출처·날짜는 싣지 않는다 (그 내용은 docs/PROJECT_STATUS.md로 모은다).
STATUS = {}      # {장 id: [(구분, [(cls, 게이트, 설명)…])…]} — status_md()가 쓴다


def resp(r):
    """표에 보이는 보드 응답: 줄 끝 기호(\\r\\n)는 뺀다 (터미널에서는 줄바꿈으로 보인다)."""
    return esc(r.replace("\\r\\n", ""))


def paras(xs, cls=""):
    return "\n".join(f'      <p{cls}>{x}</p>' for x in ([xs] if isinstance(xs, str) else xs))


def pcode(path):
    """코드 상자 (경로 · 언어). 검증 상태 꼬리표는 붙이지 않는다."""
    return bg.code(path).replace(" · 원본</span>", "</span>", 1)


def plain(note):
    return re.sub(r"<[^>]+>", "", note)


def road(course, p, pages):
    items = []
    for x in course["projects"]:
        cls = "now" if x["id"] == p["id"] else ("" if x["id"] in pages else "plan")
        label = f"<b>{x['number']}장</b>{x['title']}"
        if x["id"] in pages and x["id"] != p["id"]:
            label = f'<a href="{pages[x["id"]]}">{label}</a>'
        cur = ' aria-current="step"' if cls == "now" else ""
        items.append(f'<li class="{cls}"{cur}>{label}</li>')
    return '      <ol class="road" aria-label="전체 장에서 지금 위치">' + "".join(items) + "</ol>"


def steps(p, e, subj_state):
    rows = []
    for s in p["subjects"]:
        rows.append(f'<li><span class="code">{s["code"]}</span><span><a href="#{sid(s)}">{s["title"]}</a><br>{s["see"]}</span>'
                    f'<span class="st">{s["when"]}</span></li>')
    rows.append(f'<li class="demo"><span class="code">시연</span><span><a href="#demo">장 시연</a><br>{p["demo"]}</span>'
                f'<span class="st">장 끝</span></li>')
    return '      <ol class="steps" aria-label="이 장의 서브젝트와 순서">' + "".join(rows) + "</ol>"


def sid(s):
    return "s" + s["code"].replace("-", "_")


def board_table(p, e, s):
    tx = case_tx(p, s["stage"], s["code"])
    rx = e.cases(s["stage"], s["code"])
    if not rx or len(tx) != len(rx):
        return f"      <p>⚠ 장 Top 시뮬레이션 기록 없음 — <code>{p['run']}</code> 실행 뒤 다시 생성</p>"
    swc = lambda sw: f"<td class=\"nw\"><code>{sw:0{p['sw_bits']}b}</code></td>" if p.get("sw_label") else ""
    swh = f"<th>{p['sw_label']}</th>" if p.get("sw_label") else ""
    rows = "".join(f"<tr><td>{i+1}</td>{swc(sw)}<td class=\"nw\"><code>{cmd_cell(t, n)}</code></td>"
                   f"<td class=\"nw\"><code>{resp(r)}{f' ×{n}' if n > 1 else ''}</code></td></tr>" for i, (t, sw, r, n) in enumerate(merged(tx, rx)))
    led = end_led(p, s["stage"])
    note = s.get("led_note", p["led_note"])
    return f"""      <table>
        <thead><tr><th>순서</th>{swh}<th>PC 명령</th><th>보드 응답</th></tr></thead>
        <tbody>{rows}</tbody>
      </table>
      <p>끝나면 LED가 <code>0x{led}</code>입니다 ({note}).</p>"""


def subject_section(p, e, s, c, ce):
    n, k = s["stage"], s["ch"]
    used = top_sources(p)
    unused = [x for x in c["new"] if x.endswith((".v", ".sv")) and x not in used]
    unused_note = (f'      <p>{"·".join(f"<code>{os.path.basename(x)}</code>" for x in unused)}는 이 서브젝트를 따로 시험할 때만 쓰고, '
                   f'장 Top 빌드에는 넣지 않습니다.</p>') if unused else ""
    build = f"vivado -mode batch -nojournal -source {p['vivado_tcl']} -tclargs {n}"
    top = p["top"]["module"]
    syn = e.stage_synth(n)
    syn_txt = (("통과 · " if syn.startswith("SYNTH_TIMING_PASS") else "✗ ") + bg.short(syn.split(" ", 4)[-1], 70)) if syn \
        else "⚠ 미검증 (VS Code Vivado 실행 대기)"
    subj_gates = [(cls, name, note.replace(" (08절)", " (구 장 OOC)")) for cls, name, note in bg.gates(c, ce) if name != "HTML_PASS"]
    if c.get("synth_md"):
        sc, sn = synth_from_md(c["synth_md"])
        subj_gates = [(sc, n, sn) if n == "SYNTH_TIMING_PASS" else (cl, n, no) for cl, n, no in subj_gates]
    # 구 장 단독 OOC 기록이 없으면, 이 서브젝트 모듈이 들어간 장 Top STAGE n 배선 결과로 판정한다 (출처를 적는다).
    if syn and syn.startswith("SYNTH_TIMING_PASS"):
        m = re.search(r"WNS=(\S+) WHS=(\S+)", syn)
        top_note = f"장 Top STAGE {n} 배선 후 WNS {m.group(1)} ns · WHS {m.group(2)} ns (구 장 단독 OOC 판정 없음) · {bg.file_date(e.viv_path)}"
        subj_gates = [("pass", gn, top_note) if gn == "SYNTH_TIMING_PASS" and cl == "todo" else (cl, gn, no) for cl, gn, no in subj_gates]
    pat = c.get("evidence", {}).get("pattern", r"_PASS|PYTHON_VECTORS|^\|")
    chk = "".join(f"<tr><td><code>{a}</code></td><td>{b}</td></tr>" for a, b in c["checks"])
    tbref = "\n".join(pcode(x) for x in c["tb"] + c["ref"])
    details = (f'      <details class="full"><summary>테스트벤치와 기준 모델 (전체 코드 {len(c["tb"]) + len(c["ref"])}개)</summary>\n'
               f"{tbref}\n      </details>") if tbref else ""
    STATUS.setdefault(p["id"], []).append((f"{s['code']} {s['title']}", subj_gates + [
        ("pass" if e.cases(n, s["code"]) else "todo", f"장 Top STAGE={n} 시뮬레이션", "응답 바이트 단위 대조" if e.cases(n, s["code"]) else "기록 없음"),
        ("pass" if syn and syn.startswith("SYNTH_TIMING_PASS") else ("fail" if syn else "todo"), f"장 Top STAGE={n} 합성·타이밍", plain(syn_txt))]))
    return f"""      <p class="verdict"><b>목표:</b> {s['see']}</p>
      <h3>해설</h3>
{paras(s['concept'])}
      <h3>작성할 코드</h3>
{unused_note}{f"      <p>{s['no_new_note']}</p>" if s.get("no_new_note") else ""}
{chr(10).join(pcode(x) for x in c["new"])}
      <h3>시뮬레이션</h3>
      <p>보드에 올리기 전에, 이 서브젝트까지 넣은 장 Top을 시뮬레이션합니다. 테스트벤치가 아래 '보드에서 확인' 표와 같은 명령을 UART 핀으로 넣고 응답을 한 바이트씩 비교합니다. 줄마다 <code>rx="…"</code>가 보드가 돌려준 응답이고, 마지막 줄이 <code>RTL_SIM_PASS</code>이면 통과입니다.</p>
      <div class="codeblock"><div class="codebar"><span>터미널 · 저장소 루트</span></div>
        <pre><code>{esc(p['run'])} {n}</code></pre></div>
      <div class="codeblock"><div class="codebar"><span>기대 출력</span></div>
        <pre><code>{esc(stage_out(e, n))}</code></pre></div>
      <h3>보드에서 확인</h3>
      <ol>
        <li>이 서브젝트까지 넣은 비트스트림을 만듭니다.<br><code>{build}</code><br>결과 파일: <code>build/vivado/{p['id']}_s{n}/{top}.bit</code></li>
        <li>Vivado Hardware Manager로 보드에 내려받습니다.</li>
        <li>PC에서 아래 표의 명령을 순서대로 보내고 응답을 비교합니다. 명령은 <code>python3 {p['host']} &lt;포트&gt; 명령</code> 꼴로 보냅니다.</li>
      </ol>
{board_table(p, e, s)}"""


def stage_out(e, n):
    """run_sim.sh n이 화면에 내는 줄: 그 STAGE의 사례 줄 + 판정 줄."""
    out, on = [], False
    for ln in e.lines:
        if ln.startswith("## STAGE="):
            on = ln.strip() == f"## STAGE={n}"
        elif on and re.match(rf"{e.tag}_(CASE_PASS|TOP)", ln):
            out.append(ln.rstrip())
    return "\n".join(out + ["RTL_SIM_PASS stages=1"])


def sch(s, chs_by_id):
    """서브젝트 내용: project.json에 직접 적은 장 정보(VS Code 판) 또는 chNN/chapter.json."""
    return s.get("chapter") or chs_by_id[s["ch"]]


def build(p, course, chs_by_id, all_chs, pages, all_projects):
    if p.get("mode") == "soc":
        return page(p, course, pages, build_soc(p, course, pages))
    e = ProjectEvidence(p)
    subj = [(s, sch(s, chs_by_id), bg.Evidence(sch(s, chs_by_id), chs_by_id)) for s in p["subjects"]]
    state = {}
    for s, c, ce in subj:
        gs = {name: cls for cls, name, _ in bg.gates(c, ce)}
        top_ok = bool(e.cases(s["stage"], s["code"]))
        rtl = "pass" if gs["RTL_SIM_PASS"] == "pass" and top_ok else ("fail" if gs["RTL_SIM_PASS"] == "fail" else "todo")
        state[s["code"]] = (rtl, "pass" if e.board else "todo")

    # 구조도: 장 Top과 MAC 묶음. 모듈 출처를 서브젝트 번호로 표시한다.
    pseudos = [{"id": q["id"], "new": [x for x in q["skeleton"] if x.endswith(".v")]} for q in all_projects]
    pseudos += [{"id": qs["ch"], "new": qs["chapter"]["new"]} for q in all_projects for qs in q["subjects"] if "chapter" in qs]
    origin = bg.module_origin(all_chs + pseudos)
    ch2code = {s["ch"]: s["code"] for s in p["subjects"]}

    def relabel(svg):
        for ch, code in ch2code.items():
            svg = svg.replace(f"{ch} 재사용", f"{code}에서 작성")
        for q in all_projects:
            svg = svg.replace(f"{q['id']} 재사용", f"{q['number']}장에서 가져옴")
            if q["id"] != p["id"]:
                for qs in q["subjects"]:
                    svg = svg.replace(f"{qs['ch']} 재사용", f"{qs['code']} ({q['number']}장에서 가져옴)")
        svg = re.sub(r"ch(\d\d) 재사용", "이전 장에서 가져옴", svg)
        return (svg.replace(">이번 장 신규<", ">장 뼈대 (제공)<")
                   .replace(">이전 장 파일 재사용(수정 없음)<", ">서브젝트에서 작성<"))

    fig_top = relabel(bg.svg_block(p["id"], p["top"]["file"], p["top"]["module"], origin, board=True))
    figs = "\n".join(f'      <p>{f["note"]}</p>\n'
                      f'      <div class="figure-wrap">{relabel(bg.svg_block(p["id"], f["file"], f["module"], origin, board=False))}</div>'
                      for f in p["figures"])
    top_c = {"id": p["id"], "top": p["top"], "port_notes": p["port_notes"]}

    imports = "".join(f"<li><code>{x}</code></li>" for x in p["imports"]) or "<li>없음 (첫 장)</li>"
    made = "".join(f"<tr><td>{s['code']} {s['title']}</td><td>{'<br>'.join(f'<code>{x}</code>' for x in c['new'])}</td></tr>"
                   for s, c, _ in subj)
    s00 = f"""{paras(p['intro'])}
      <p><b>장 끝에서 보드로 보여 줄 것:</b> {p['demo']}</p>
      <p>{p['days']}일 과정입니다. 아래 서브젝트 {len(p['subjects'])}개를 차례로 끝내며 그때마다 보드에서 확인하고, 마지막에 장 전체를 시연합니다.</p>
{steps(p, e, state)}"""
    s01 = f"""      <div class="figure-wrap">{fig_top}</div>
{bg.port_table(top_c, True)}
      <p>장 Top은 배선만 합니다. 기능은 하위 모듈에 있고, 서브젝트 모듈은 <code>STAGE</code>(끝낸 서브젝트 수)에 따라 하나씩 들어옵니다.</p>
{figs}
      <table>
        <thead><tr><th>구분</th><th>파일</th></tr></thead>
        <tbody>
          <tr><td>이전 장에서 가져오는 파일</td><td><ul>{imports}</ul></td></tr>
          {made}
          <tr><td>장 뼈대 (준비 절에 수록)</td><td>{'<br>'.join(f'<code>{x}</code>' for x in p['skeleton'])}</td></tr>
        </tbody>
      </table>"""
    s02 = f"""      <ol>
        <li>VS Code에서 저장소 루트(<code>amd_soc_npu/</code>)를 엽니다. 필요한 도구는 Vivado 2024.2(합성·시뮬레이션), <code>python3</code>, 그리고 PC에서 보드로 명령을 보낼 <code>pyserial</code>(<code>pip install pyserial</code>)입니다. 터미널에서 Vivado 명령이 잡히도록 <code>settings64.sh</code>를 먼저 불러옵니다.</li>
        <li>코드는 저장소에 모두 들어 있고, 안내서에도 전체를 실었습니다. 직접 입력하며 따라 해도 되고, 읽고 실행만 해도 됩니다. 아래는 장 전체의 틀이 되는 뼈대 파일이고, 서브젝트 모듈은 각 서브젝트 절에 있습니다.</li>
        <li>파일 경로의 <code>ch01</code>, <code>part03/ch14</code> 같은 폴더는 모듈별 작업 폴더 이름입니다. 이 안내서의 장·서브젝트 번호와는 관계가 없으므로 경로 그대로 쓰면 됩니다.</li>
        <li><code>&lt;포트&gt;</code>는 보드의 USB 시리얼 포트 이름입니다. Windows는 <code>COM3</code>, Linux는 <code>/dev/ttyUSB1</code> 같은 이름이고, 통신 설정은 115200 bps 8N1입니다.</li>
{f"        <li>{p['sw_note']}</li>{chr(10)}" if p.get("sw_note") else ""}        <li><code>STAGE</code>는 끝낸 서브젝트 수입니다. {p['subjects'][0]['code']}만 끝냈으면 1, {p['subjects'][-1]['code']}까지 끝냈으면 {len(p['subjects'])}입니다. 아직 작성하지 않은 모듈은 빌드에 들어가지 않으므로, 서브젝트를 하나 끝낼 때마다 바로 보드에 올려 볼 수 있습니다.</li>
      </ol>
      <h3>PC 명령 한눈에 보기</h3>
      <p>PC 도구 <code>{p['host']}</code>가 아래 명령을 바이트로 바꿔 보내고, 보드의 응답 한 줄을 화면에 보여 줍니다. 응답을 받은 뒤에 다음 명령을 보냅니다.</p>
      <table>
        <thead><tr><th>명령</th><th>하는 일</th><th>보드 응답</th></tr></thead>
        <tbody>{"".join(f'<tr><td class="nw"><code>{a}</code></td><td>{b}</td><td><code>{c_}</code></td></tr>' for a, b, c_ in p['commands'])}</tbody>
      </table>
      <h3>장 뼈대 코드</h3>
{chr(10).join(pcode(x) for x in p['skeleton'])}"""
    secs = [("이 장에서 만드는 것", s00, "s00"), ("전체 구조와 파일", s01, "s01"), ("준비", s02, "s02")]
    for s, c, ce in subj:
        secs.append((f"서브젝트 {s['code']} · {s['title']}", subject_section(p, e, s, c, ce), sid(s)))

    full = e.cases(len(p["subjects"]))
    tx = case_tx(p, len(p["subjects"]))
    subj_of = [x[0] for x in full]
    rows, k = "", 0
    for t, sw, r, n in merged(tx, full):
        swc = f"<td class=\"nw\"><code>{sw:0{p['sw_bits']}b}</code></td>" if p.get("sw_label") else ""
        rows += (f"<tr><td class=\"nw\">{subj_of[k]}</td>{swc}<td class=\"nw\"><code>{cmd_cell(t, n)}</code></td>"
                 f"<td class=\"nw\"><code>{resp(r)}{f' ×{n}' if n > 1 else ''}</code></td></tr>")
        k += n
    def result_row(label, pattern, tag):
        path = bg.latest(pattern)
        line = next((ln.strip() for ln in bg.log_lines(path) if ln.startswith(tag)), None)
        val = f"<code>{esc(line[len(tag):].strip())}</code>" if line else "—"
        return f"<tr><td>{label}</td><td>{val}</td></tr>"
    results = "".join(result_row(*r) for r in p.get("results", []))
    results = (f"""      <table>
        <thead><tr><th>PC에서 미리 확인하는 값</th><th>결과</th></tr></thead>
        <tbody>{results}</tbody>
      </table>
      <p>{p.get("results_note", "")}</p>""") if results else ""
    nsub = len(p["subjects"])
    demo = f"""      <p>STAGE={nsub} 비트스트림 하나로 모든 서브젝트를 처음부터 끝까지 이어서 보여 줍니다. 아래 순서대로 보내고 응답을 표와 비교합니다.</p>
      <table>
        <thead><tr><th class="nw">서브젝트</th>{f"<th>{p['sw_label']}</th>" if p.get("sw_label") else ""}<th>PC 명령</th><th>보드 응답</th></tr></thead>
        <tbody>{rows}</tbody>
      </table>
      <p>끝나면 LED가 <code>0x{end_led(p, nsub)}</code>입니다 ({p["subjects"][-1].get("led_note", p["led_note"])}). btnC를 누르면 처음 상태로 돌아갑니다.</p>
{results}
      <h3>시연 전 점검</h3>
      <p>보드에 올리기 전에 장 Top 전체를 시뮬레이션합니다. STAGE마다 <code>{e.tag}_TOP_RTL_SIM_PASS</code>가 나오면 됩니다.</p>
      <div class="codeblock"><div class="codebar"><span>터미널 · 장 Top 시뮬레이션 (STAGE 1~{nsub})</span></div>
        <pre><code>{esc(p['run'])}</code></pre></div>
      <div class="codeblock"><div class="codebar"><span>기대 출력</span></div>
        <pre><code>{esc(bg.excerpt(e.lines, rf"^(PYTHON_{e.tag}_(SELF|VEC)|{e.tag}_TOP|RTL_SIM)"))}</code></pre></div>
      <p>비트스트림은 아래 명령 한 번으로 STAGE 1~{nsub}을 모두 만듭니다. STAGE마다 <code>SYNTH_TIMING_PASS</code> 줄이 나오면 됩니다.</p>
      <div class="codeblock"><div class="codebar"><span>터미널 · Vivado</span></div>
        <pre><code>vivado -mode batch -nojournal -source {p['vivado_tcl']}</code></pre></div>
      <details class="full"><summary>장 Top 테스트벤치와 기준 모델 (전체 코드)</summary>
{chr(10).join(pcode(x) for x in p['tb'] + p['ref'])}
      </details>"""
    secs.append(("장 시연", demo, "demo"))

    used = top_sources(p)
    rep = "".join(f"<tr><td class=\"nw\">{s['code']} {s['title']}</td><td>{'<br>'.join(f'<code>{os.path.basename(x)}</code>' for x in c['new'] if x.endswith(('.v', '.sv')) and x in used) or '—'}</td>"
                  f"<td>{s['point']}</td></tr>" for s, c, _ in subj)
    hand = "".join(f"<tr><td><code>{a}</code></td><td>{b}</td></tr>" for a, b in p["handoff"])
    s_last = f"""      <p>이 장에서 만든 것과 배운 점을 정리합니다.</p>
      <table>
        <thead><tr><th>서브젝트</th><th>장 Top에 들어간 모듈</th><th>핵심</th></tr></thead>
        <tbody>{rep}</tbody>
      </table>
      <table>
        <thead><tr><th>다음 장으로 넘기는 파일</th><th>사용처</th></tr></thead>
        <tbody>{hand}</tbody>
      </table>"""
    STATUS.setdefault(p["id"], []).append(("장 전체", [(cl, gn, plain(no)) for cl, gn, no in project_gates(p, e)]))
    secs.append(("장 정리·다음 장으로", s_last, "s_report"))
    return page(p, course, pages, secs)


def page(p, course, pages, secs):
    body = "\n".join(f'    <section class="section" id="{i_id}">\n      <h2><span class="num">{i:02d}</span> {t}</h2>\n{b}\n    </section>'
                     for i, (t, b, i_id) in enumerate(secs))
    head = bg.HEAD.format(desc=f"Basys3 NPU {p['number']}장 프로젝트 · {p['name']}",
                          title=f"{p['number']}장 · {p['name']} ({p['version']})", chid=p["id"],
                          numstr=f"{p['number']}장 프로젝트 · {p['days']}일", ver=p["version"],
                          h1=f"제{p['number']}장 · {p['name']}", subtitle=p["goal"])
    head = head.replace("</head>", EXTRA_CSS + "</head>", 1)
    head = head.replace("tools/guide/build_guides.py — 직접 수정 금지, chapter.json을 고친 뒤 재생성",
                        "tools/guide/build_projects.py — 직접 수정 금지, project.json·chapter.json을 고친 뒤 재생성")
    nav = {"title": course["title"], "chapters": [
        {"id": x["id"], "number": x["number"], "title": x["title"], "file": pages[x["id"]]}
        for x in course["projects"] if x["id"] in pages]}
    foot = bg.FOOT.format(course="window.COURSE=" + json.dumps(nav, ensure_ascii=False, indent=1) + ";")
    return bg.wrap_tables(head + body + "\n" + foot)


# ── SoC 장 (5장~): 장 Top = 21장 비트스트림 하나, 서브젝트마다 ELF만 바뀐다 ───────────────
def md_table(text, start):
    """Markdown 표 하나(start 문자열로 시작하는 머리줄부터 빈 줄까지) → [[셀…]…] (머리줄 포함, 구분줄 제외)."""
    rows, on = [], False
    for ln in text.splitlines():
        if not on and ln.startswith(start):
            on = True
        if on:
            if not ln.startswith("|"):
                break
            cells = [c.strip() for c in ln.strip().strip("|").split("|")]
            if not all(re.fullmatch(r":?-+:?", c) for c in cells):
                rows.append(cells)
    return rows


def md_cell(s):
    """표 칸의 Markdown 일부(**굵게**, `코드`, <br>)만 HTML로."""
    s = esc(s).replace("&lt;br&gt;", "<br>")
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    return re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", s)


def html_table(rows, nw=()):
    cls = ' class="nw"'          # (Python 3.11: f-string 식 안에 역슬래시를 쓸 수 없다)
    head = "".join(f'<th{cls if i in nw else ""}>{md_cell(c)}</th>' for i, c in enumerate(rows[0]))
    body = "".join("<tr>" + "".join(f'<td{cls if i in nw else ""}>{md_cell(c)}</td>' for i, c in enumerate(r)) + "</tr>"
                   for r in rows[1:])
    return f"      <table>\n        <thead><tr>{head}</tr></thead>\n        <tbody>{body}</tbody>\n      </table>"


def checklist(p):
    """보드 점검표 1절의 B 항목 → {번호: (절차, 기대 결과, 판정)}."""
    out = {}
    for ln in rd(p["checklist"]).splitlines():          # 1절·1-28절… 표가 여러 개: B로 시작하는 줄 모두
        cells = [c.strip() for c in ln.strip().strip("|").split("|")]
        if ln.startswith("| B") and re.fullmatch(r"B\d+[a-z]?", cells[0]):
            out[cells[0]] = (cells[1], cells[2], cells[3] if len(cells) > 3 else "")
    return out


# 보드 점검표(VS Code 판 문서)의 칸을 학습자용 문장으로 다듬는다: 옛 장 번호·검증 출처 꼬리표를 뺀다.
CK_SUBS = [(r"\s*\(22장 협동 시뮬레이션과 같은 줄\)", ""), (r"\s*\(안 A 22장 표시\)", ""), (r"\s*\(협동 시뮬레이션 SHOW 줄\)", ""),
           (r"\s*부근\(23장 SoC xsim 값\)\. 차이가 있으면 원인 기록", ""), (r"21장 비트스트림", "5장 비트스트림"),
           (r"\s*\(`ch2[89]/validation/rtl_cosim\.csv`와 같은 (class|판정)\)", ""), (r"28장 펌웨어는", "이 펌웨어는"),
           (r", 협동 시뮬레이션\)", ")"), (r"골든", "PC 기준"), (r"사이클 값이 매번 같거나 차이를 기록\(캐시 없음·같은 클록이면 같아야 함\)", "클록 수가 매번 같습니다 (캐시가 없고 클록이 같으므로)"), (r"실측 주기\(초\)를 기록", "주기를 초 단위로 재 봅니다")]


def ck_clean(s):
    for a, b in CK_SUBS:
        s = re.sub(a, b, s)
    return s


def check_rows(p, items):
    ck = {k: (ck_clean(v[0]), ck_clean(v[1]), v[2]) for k, v in checklist(p).items()}
    miss = [i for i in items if i not in ck]
    if miss:
        raise SystemExit(f"{p['id']}: 보드 점검표에 없는 항목 {miss}")
    rows = [["순서", "할 일", "보드에서 보이는 것"]]
    rows += [[str(k + 1), ck[i][0], ck[i][1]] for k, i in enumerate(items)]
    return html_table(rows, nw=(0,))


def synth_from_grep(spec):
    path = spec["path"]
    m = re.search(spec["regex"], rd(path)) if os.path.exists(os.path.join(ROOT, path)) else None
    if not m:
        return "todo", "⚠ 미검증 · Vivado 기록 없음"
    ok = float(m.group("wns")) >= 0 and float(m.group("whs")) >= 0
    return ("pass" if ok else "fail"), (f"{'' if ok else '✗ '}WNS {m.group('wns')} ns · WHS {m.group('whs')} ns ({spec['src']}) · <code>{path}</code>")


def soc_subject_gates(s, c, ce):
    gs = [g for g in bg.gates(c, ce) if g[1] != "HTML_PASS"]
    date = c.get("evidence", {}).get("date")
    tool = c.get("evidence", {}).get("tool")
    if date:
        gs = [(cl, n, no.replace("날짜 미기록", date)) for cl, n, no in gs]
    if tool:
        gs = [(cl, n, no.replace("도구 버전 미기록", tool)) for cl, n, no in gs]
    syn = synth_from_md(c["synth_md"]) if c.get("synth_md") else synth_from_grep(c["synth_grep"]) if c.get("synth_grep") else None
    if syn:
        gs = [(syn[0], n, syn[1]) if n == "SYNTH_TIMING_PASS" else (cl, n, no) for cl, n, no in gs]
    for x in c.get("extra_gates", []):
        hit = next((ln.strip() for ln in bg.log_lines(x["path"]) if re.search(x["pattern"], ln)), None)
        gs.insert(-1, ("pass", x["name"], f"{bg.short(hit, 60)} · <code>{x['path']}</code>") if hit
                  else ("todo", x["name"], "⚠ 미검증 · 기록 없음"))
    if c.get("soc_timing"):                          # 장 Top과 다른 별도 SoC 비트스트림 (예: 30장)
        cl, note = synth_from_grep(c["soc_timing"])
        gs.insert(-1, (cl, "SOC_TIMING", note))
    if s.get("warn"):
        name, note = s.get("warn_gate", ["안 A 재실행", "⚠ 안 A 이전 빌드 기준 · VS Code 재실행 대기"])
        gs.insert(-1, ("todo", name, note))
    return gs


def soc_subject_section(p, s, c, ce, gs):
    date = c["evidence"].get("date", "날짜 미기록")
    pat = c.get("evidence", {}).get("pattern", r"_PASS")
    chk = "".join(f"<tr><td><code>{a}</code></td><td>{b}</td></tr>" for a, b in c["checks"])
    tbref = "\n".join(pcode(x) for x in c["tb"] + c["ref"])
    details = (f'      <details class="full"><summary>테스트벤치와 기준 모델 (전체 코드 {len(c["tb"]) + len(c["ref"])}개)</summary>\n'
               f"{tbref}\n      </details>") if tbref else ""
    board = check_rows(p, s["board_items"]) if s["board_items"] else ""
    STATUS.setdefault(p["id"], []).append((f"{s['code']} {s['title']}", [(cl, gn, plain(no)) for cl, gn, no in gs]
                                           + ([("todo", "주의", plain(s["warn"]))] if s.get("warn") else [])
                                           + ([("todo", "보드 점검표", "·".join(s["board_items"]) + " 미실시")] if s["board_items"] else [])))
    out = esc(bg.excerpt(bg.log_lines(ce.rtl_path), pat))
    return f"""      <p class="verdict"><b>목표:</b> {s['see']}</p>
      <h3>해설</h3>
{paras(s['concept'])}
      <h3>보드에서 확인</h3>
      <p>{s['board_note']}</p>
{board}
      <h3>작성할 코드</h3>
{chr(10).join(pcode(x) for x in c["new"])}
      <h3>실행과 기대 출력</h3>
      <div class="codeblock"><div class="codebar"><span>터미널 · 저장소 루트</span></div>
        <pre><code>{esc(c['run'])}</code></pre></div>
      <div class="codeblock"><div class="codebar"><span>기대 출력</span></div>
        <pre><code>{out}</code></pre></div>
{details}
      <h3>확인할 것</h3>
      <table>
        <thead><tr><th>확인 항목</th><th>의미</th></tr></thead>
        <tbody>{chk}</tbody>
      </table>"""


def build_soc(p, course, pages):
    subj = []
    for s in p["subjects"]:
        c = s["chapter"]
        ce = bg.Evidence(c, {})
        gs = soc_subject_gates(s, c, ce)
        if c.get("vivado_ran") and not ce.synth:     # 코드 상자 상태: Vivado(xsim·report_power 포함)로 실제 실행함
            ce.synth = "SYNTH_TIMING_PASS"
        subj.append((s, c, ce, gs))
    state = {}
    for s, c, ce, gs in subj:
        g = {n: cl for cl, n, _ in gs}
        rtl = "fail" if "fail" in g.values() else ("pass" if g.get("RTL_SIM_PASS") in ("pass", "na") else "todo")
        state[s["code"]] = (rtl, "todo")
    board_done = False

    class _E:            # steps()가 쓰는 속성
        board = board_done
    s00 = f"""{paras(p['intro'])}
      <p><b>장 끝에서 보드로 보여 줄 것:</b> {p['demo']}</p>
      <p>{p['days']}일 과정, 서브젝트 {len(p['subjects'])}개입니다. {p['plan_note']}</p>
{steps(p, _E, state)}"""

    summ = rd(p["soc_summary"])
    addr = md_table(summ, "| 인덱스")
    irq = md_table(summ, "| INTC 입력")
    top_c = {"id": p["id"], "top": p["top"], "port_notes": p["port_notes"]}
    made = "".join(f"<tr><td>{s['code']} {s['title']}</td><td>{'<br>'.join(f'<code>{x}</code>' for x in c['new'])}</td></tr>"
                   for s, c, _, _ in subj)
    imports = "".join(f"<li>{x}</li>" for x in p["imports"])
    s01 = f"""      <div class="figure-wrap">{bg.diagram_svg(p['diagram'], p['id'] + '-socmap', p['diagram_label'])}</div>
      <p>{p['diagram_note']}</p>
      <h3>주소맵 (Vivado Address Editor)</h3>
{html_table(addr, nw=(0, 2, 3))}
      <h3>인터럽트 (axi_intc 16입력)</h3>
{html_table(irq, nw=(0,))}
      <h3>보드 Top 포트 (<code>{p['top']['file']}</code>, 핀 연결만)</h3>
{bg.port_table(top_c, True)}
      <table>
        <thead><tr><th>구분</th><th>파일</th></tr></thead>
        <tbody>
          <tr><td>이전 장에서 가져오는 것</td><td><ul>{imports}</ul></td></tr>
          {made}
        </tbody>
      </table>"""
    prep = "".join(f"<li>{x}</li>" for x in p["prep"])
    s02 = f"""      <ol>
        {prep}
      </ol>"""
    secs = [("이 장에서 만드는 것", s00, "s00"), ("전체 구조와 주소맵", s01, "s01"), ("준비", s02, "s02")]
    for s, c, ce, gs in subj:
        secs.append((f"서브젝트 {s['code']} · {s['title']}", soc_subject_section(p, s, c, ce, gs), sid(s)))

    def result_row(label, pattern, tag):
        path = bg.latest(pattern)
        line = next((ln.strip() for ln in bg.log_lines(path) if ln.startswith(tag)), None)
        val = f"<code>{esc(line[len(tag):].strip())}</code>" if line else "—"
        return f"<tr><td>{label}</td><td>{val}</td></tr>"
    results = "".join(result_row(*r) for r in p["results"])
    impl = md_table(summ, "| 항목 | 값")
    demo = f"""      <p>{p['demo_intro']}</p>
{check_rows(p, p['demo_items'])}
      <table>
        <thead><tr><th>미리 알아 둘 값</th><th>결과</th></tr></thead>
        <tbody>{results}</tbody>
      </table>
      <p>{p['results_note']}</p>
      <h3>칩 전체 구현 결과 (배치·배선 후)</h3>
{html_table(impl)}
      <h3>한 번에 다시 돌리기</h3>
      <p>아래 명령은 이 장의 시뮬레이션을 처음부터 끝까지 다시 실행합니다. 마지막에 단계별 <code>PASS</code> 표가 나옵니다.</p>
      <div class="codeblock"><div class="codebar"><span>터미널 · 저장소 루트</span></div>
        <pre><code>{esc(p['run'])}</code></pre></div>"""
    secs.append(("장 시연", demo, "demo"))

    rep = "".join(f"<tr><td class=\"nw\">{s['code']} {s['title']}</td><td>{s['point']}</td></tr>" for s, c, ce, gs in subj)
    hand = "".join(f"<tr><td><code>{a}</code></td><td>{b}</td></tr>" for a, b in p["handoff"])
    syn = synth_from_grep(p["project_synth"])
    rtl_all = all(state[s["code"]][0] == "pass" for s in p["subjects"])
    STATUS.setdefault(p["id"], []).append(("장 전체", [
        ("pass" if rtl_all else "todo", "RTL_SIM_PASS", "서브젝트 시뮬레이션·정적 검사 모두 통과" if rtl_all else "미검증 서브젝트 있음"),
        (syn[0], "SYNTH_TIMING_PASS", plain(syn[1])),
        ("todo", "BOARD_PASS", f"미실시 · 보드 점검표 {p['demo_items'][0]}~{p['demo_items'][-1]} 대기")]))
    s_last = f"""      <p>이 장에서 만든 것과 배운 점을 정리합니다.</p>
      <table>
        <thead><tr><th>서브젝트</th><th>핵심</th></tr></thead>
        <tbody>{rep}</tbody>
      </table>
      <table>
        <thead><tr><th>다음 장으로 넘기는 것</th><th>사용처</th></tr></thead>
        <tbody>{hand}</tbody>
      </table>"""
    secs.append(("장 정리·다음 장으로", s_last, "s_report"))
    return secs


def status_md(projects):
    """장 페이지에서 뺀 검증 상태를 한곳에 모은다 (게이트·증거 출처·미실시 항목)."""
    sym = {"pass": "✅", "fail": "❌", "todo": "⏳", "na": "—"}
    out = ["# 장 프로젝트 검증 현황 (자동 생성)", "",
           "`python3 tools/guide/build_projects.py`가 `pNN/project.json`과 `validation/` 증거로 만든다. 직접 수정하지 않는다.",
           "장 페이지(학습안내서)에는 검증 상태를 싣지 않고 여기에 모은다.", "",
           "✅ 통과 · ❌ 실패 · ⏳ 실행 대기/미검증/미실시 · — 해당 없음", ""]
    for p in projects:
        out += [f"## {p['number']}장 · {p['name']} ([{pfname(p)}](../{pfname(p)}))", "", "| 구분 | 게이트 | 상태 | 근거 |", "|---|---|---|---|"]
        groups = STATUS.get(p["id"], [])
        for label, gs in sorted(groups, key=lambda x: x[0] != "장 전체"):
            for cl, gn, no in gs:
                out.append(f"| {label} | {gn} | {sym[cl]} | {no.replace('|', '/').replace(chr(10), ' ')} |")
        out.append("")
    return "\n".join(out)


def main(check):
    course = json.loads(rd("course_projects.json"))
    projects = load_projects()
    chs = bg.load_chapters()
    by_id = {c["id"]: c for c in chs}
    pages = {p["id"]: pfname(p) for p in projects}
    outputs = {pfname(p): build(p, course, by_id, chs, pages, projects) for p in projects}
    outputs["docs/PROJECT_STATUS.md"] = status_md(projects)
    stale = [os.path.relpath(f, ROOT) for p in projects for f in glob.glob(os.path.join(ROOT, f"{p['id']}_*_v*.html"))
             if os.path.basename(f) != pfname(p)]
    if check:
        diff = [k for k, v in outputs.items() if not os.path.exists(os.path.join(ROOT, k)) or rd(k) != v] + stale
        if diff:
            print("PROJECT_GUIDE_OUT_OF_DATE: python3 tools/guide/build_projects.py 실행 후 커밋")
            for d in diff:
                print("  -", d)
            return 1
        print(f"PROJECT_GUIDE_UP_TO_DATE projects={len(projects)}")
        return 0
    for k, v in outputs.items():
        with open(os.path.join(ROOT, k), "w", encoding="utf-8") as f:
            f.write(v)
    for s in stale:
        os.remove(os.path.join(ROOT, s))
    print(f"PROJECT_GUIDE_BUILT projects={len(projects)} removed={len(stale)}")
    return 0


if __name__ == "__main__":
    sys.exit(main("--check" in sys.argv))
