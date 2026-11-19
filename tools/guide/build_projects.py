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


def decode(b):
    """보낼 바이트 → PC 도구(pNN_send.py) 명령 꼴. 1장·2장 명령 형식을 모두 안다."""
    c, n = chr(b[0]), len(b)
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
    return b.decode("ascii")


def case_file(p, stage):
    return rd(f"{p['id']}/tb/{p['id']}_cases_s{stage}.txt").splitlines()


def case_tx(p, stage, subj=None):
    """사례 파일의 보낼 바이트 → PC 도구 명령 꼴."""
    out = []
    for ln in case_file(p, stage):
        f = ln.split()
        if not f or f[0].startswith("#") or f[0] == "END":
            continue
        if subj and f[0] != subj:
            continue
        n = int(f[2], 16)
        out.append(decode(bytes(int(x, 16) for x in f[3:3 + n])))
    return out


def end_led(p, stage):
    for ln in case_file(p, stage):
        if ln.startswith("END "):
            return ln.split()[1].upper()
    return "????"


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
    g.append(gate("pass", "BOARD_PASS", e.board_path) if e.board else gate("todo", "BOARD_PASS", "⚠ 미실시 · 실물 보드 확인 대기"))
    return g


# ── 화면 조각 ─────────────────────────────────────────────────────────────────
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
        rtl, board = subj_state[s["code"]]
        cls = "done" if rtl == "pass" and board == "pass" else ""
        rows.append(f'<li class="{cls}"><span class="code">{s["code"]}</span><span><a href="#{sid(s)}">{s["title"]}</a> '
                    f'<small>(구 {int(s["ch"][2:]):02d}장 · {s["when"]})</small><br>{s["see"]}</span>'
                    f'<span class="st">시뮬 {WORD[rtl]} · 보드 {WORD[board]}</span></li>')
    rows.append(f'<li class="demo"><span class="code">시연</span><span><a href="#demo">장 시연</a><br>{p["demo"]}</span>'
                f'<span class="st">보드 {"통과" if e.board else "⚠ 미실시"}</span></li>')
    return '      <ol class="steps" aria-label="이 장의 서브젝트와 진행 상태">' + "".join(rows) + "</ol>"


def sid(s):
    return "s" + s["code"].replace("-", "_")


def board_table(p, e, s):
    tx = case_tx(p, s["stage"], s["code"])
    rx = e.cases(s["stage"], s["code"])
    if not rx or len(tx) != len(rx):
        return f"      <p>⚠ 장 Top 시뮬레이션 기록 없음 — <code>{p['run']}</code> 실행 뒤 다시 생성</p>"
    rows = "".join(f"<tr><td>{i+1}</td><td class=\"nw\"><code>{sw:0{p['sw_bits']}b}</code></td><td class=\"nw\"><code>{esc(t)}</code></td>"
                   f"<td class=\"nw\"><code>{esc(r)}</code></td></tr>" for i, (t, (_, sw, r)) in enumerate(zip(tx, rx)))
    led = end_led(p, s["stage"])
    note = s.get("led_note", p["led_note"])
    return f"""      <table>
        <thead><tr><th>순서</th><th>{p['sw_label']}</th><th>PC 명령 (<code>{os.path.basename(p['host'])}</code>)</th><th>보드 응답 (UART)</th></tr></thead>
        <tbody>{rows}</tbody>
      </table>
      <p>끝난 뒤 LED: <code>0x{led}</code> ({note}). 응답 출처: 장 Top 시뮬레이션 STAGE={s['stage']} (<code>{e.rtl_path}</code>, 바이트 단위 대조).</p>"""


def subject_section(p, e, s, c, ce):
    n, k = s["stage"], s["ch"]
    used = top_sources(p)
    unused = [x for x in c["new"] if x.endswith((".v", ".sv")) and x not in used]
    unused_note = (f'      <p>※ {"·".join(f"<code>{os.path.basename(x)}</code>" for x in unused)}는 구 {int(k[2:]):02d}장 단독 실습용이라 '
                   f'{p["number"]}장 Top 빌드에는 넣지 않습니다.</p>') if unused else ""
    build = f"vivado -mode batch -nojournal -source {p['vivado_tcl']} -tclargs {n}"
    top = p["top"]["module"]
    syn = e.stage_synth(n)
    syn_txt = (("통과 · " if syn.startswith("SYNTH_TIMING_PASS") else "✗ ") + bg.short(syn.split(" ", 4)[-1], 70)) if syn \
        else "⚠ 미검증 (VS Code Vivado 실행 대기)"
    subj_gates = [(cls, name, note.replace(" (08절)", " (구 장 OOC)")) for cls, name, note in bg.gates(c, ce) if name != "HTML_PASS"]
    pat = c.get("evidence", {}).get("pattern", r"_PASS|PYTHON_VECTORS|^\|")
    chk = "".join(f"<tr><td><code>{a}</code></td><td>{b}</td></tr>" for a, b in c["checks"])
    tbref = "\n".join(bg.code(x, ce) for x in c["tb"] + c["ref"])
    details = (f'      <details class="full"><summary>이 서브젝트의 테스트벤치·기준 모델 (전체 코드 {len(c["tb"]) + len(c["ref"])}개)</summary>\n'
               f"{tbref}\n      </details>") if tbref else ""
    return f"""      <p class="verdict"><b>학습목표 (보드):</b> {s['see']}</p>
      <h3>보드에서 볼 것</h3>
      <ol>
        <li>이 서브젝트까지 넣은 비트스트림을 만듭니다: <code>{build}</code> → <code>build/vivado/{p['id']}_s{n}/{top}.bit</code></li>
        <li>Hardware Manager로 보드에 내려받고 <code>python3 {p['host']} &lt;포트&gt; …</code>로 아래 순서대로 보냅니다 (115200 8N1). {p.get('sw_note', '')}</li>
      </ol>
{board_table(p, e, s)}
      <h3>추가 코드 (구 {int(k[2:]):02d}장 그대로)</h3>
{unused_note}
{chr(10).join(bg.code(x, ce) for x in c["new"])}
      <h3>시뮬레이션 기대 화면</h3>
      <div class="codeblock"><div class="codebar"><span>Ubuntu Terminal · 서브젝트 단독 시험</span></div>
        <pre><code>{esc(c['run'])}</code></pre></div>
      <div class="codeblock"><div class="codebar"><span>기대 출력 ({ce.tool} · {bg.file_date(ce.rtl_path)} · 출처 {ce.rtl_path})</span></div>
        <pre><code>{esc(bg.excerpt(ce.rtl, pat)) or '⚠ 실행 로그 없음'}</code></pre></div>
{details}
      <h3>판정 줄</h3>
      <table>
        <thead><tr><th>확인 항목</th><th>의미</th></tr></thead>
        <tbody>{chk}<tr><td>장 Top STAGE={n} 시뮬레이션</td><td>위 '보드에서 볼 것' 응답과 바이트 단위로 같음 · {"통과" if e.cases(n, s['code']) else "⚠ 기록 없음"}</td></tr>
        <tr><td>장 Top STAGE={n} 합성·타이밍</td><td>{syn_txt}</td></tr></tbody>
      </table>
{bg.gate_row(subj_gates)}"""


def build(p, course, chs_by_id, all_chs, pages, all_projects):
    e = ProjectEvidence(p)
    subj = [(s, chs_by_id[s["ch"]], bg.Evidence(chs_by_id[s["ch"]], chs_by_id)) for s in p["subjects"]]
    state = {}
    for s, c, ce in subj:
        gs = {name: cls for cls, name, _ in bg.gates(c, ce)}
        top_ok = bool(e.cases(s["stage"], s["code"]))
        rtl = "pass" if gs["RTL_SIM_PASS"] == "pass" and top_ok else ("fail" if gs["RTL_SIM_PASS"] == "fail" else "todo")
        state[s["code"]] = (rtl, "pass" if e.board else "todo")

    # 구조도: 장 Top과 MAC 묶음. 모듈 출처를 서브젝트 번호로 표시한다.
    pseudos = [{"id": q["id"], "new": [x for x in q["skeleton"] if x.endswith(".v")]} for q in all_projects]
    origin = bg.module_origin(all_chs + pseudos)
    ch2code = {s["ch"]: s["code"] for s in p["subjects"]}

    def relabel(svg):
        for ch, code in ch2code.items():
            svg = svg.replace(f"{ch} 재사용", f"{code} (구 {int(ch[2:]):02d}장)")
        for q in all_projects:
            svg = svg.replace(f"{q['id']} 재사용", f"{q['number']}장에서 가져옴")
            if q["id"] != p["id"]:
                for qs in q["subjects"]:
                    svg = svg.replace(f"{qs['ch']} 재사용", f"{qs['code']} ({q['number']}장에서 가져옴)")
        svg = re.sub(r"ch(\d\d) 재사용", lambda m: f"구 {m.group(1)}장 (이전 장)", svg)
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
    s00 = f"""      <p><b>장 시연 (보드):</b> {p['demo']}</p>
      <p>편성: {p['days']}일 · 서브젝트 {len(p['subjects'])}개 · 서브젝트마다 보드 확인 1번 + 장 시연.</p>
{road(course, p, pages)}
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
          <tr><td>장 뼈대 (02절에서 입력)</td><td>{'<br>'.join(f'<code>{x}</code>' for x in p['skeleton'])}</td></tr>
        </tbody>
      </table>"""
    s02 = f"""      <ol>
        <li>VS Code에서 저장소 루트(<code>amd_soc_npu/</code>)를 엽니다. 도구: <code>iverilog</code> 12 이상, <code>python3</code>, Vivado 2024.2 (합성·비트스트림), 보드 터미널(115200 8N1) 또는 <code>pip install pyserial</code>.</li>
        <li>아래 장 뼈대 파일을 경로 그대로 입력합니다. 서브젝트 모듈은 각 서브젝트 절에서 씁니다.</li>
        <li>STAGE 값 = 끝낸 서브젝트 수: {p['subjects'][0]['code']}만 끝냈으면 1, {p['subjects'][-1]['code']}까지 끝냈으면 {len(p['subjects'])}. 아직 없는 모듈은 들어가지 않으므로 빌드가 됩니다.</li>
      </ol>
{chr(10).join(bg.code(x, e) for x in p['skeleton'])}"""
    secs = [("장 목표·진행 위치", s00, "s00"), ("최종 구조도·가져오는 파일", s01, "s01"), ("준비 · 장 뼈대", s02, "s02")]
    for s, c, ce in subj:
        secs.append((f"서브젝트 {s['code']} · {s['title']} <small>(구 {int(s['ch'][2:]):02d}장)</small>", subject_section(p, e, s, c, ce), sid(s)))

    full = e.cases(len(p["subjects"]))
    tx = case_tx(p, len(p["subjects"]))
    rows = "".join(f"<tr><td>{subj_code}</td><td class=\"nw\"><code>{sw:0{p['sw_bits']}b}</code></td><td class=\"nw\"><code>{esc(t)}</code></td><td class=\"nw\"><code>{esc(r)}</code></td></tr>"
                   for t, (subj_code, sw, r) in zip(tx, full))
    viv = "\n".join(e.viv) or f"⚠ Vivado 실행 기록 없음 (VS Code: {os.path.basename(p['vivado_tcl'])} → {p['id']}/validation/vivado_impl_YYYYMMDD.txt)"
    demo = f"""      <p>STAGE=4 비트스트림 하나로 모든 서브젝트를 차례로 보여 줍니다. 아래 응답은 장 Top 시뮬레이션이 바이트 단위로 대조한 값입니다.</p>
      <table>
        <thead><tr><th>서브젝트</th><th>{p['sw_label']}</th><th>PC 명령</th><th>보드 응답</th></tr></thead>
        <tbody>{rows}</tbody>
      </table>
      <p>끝난 뒤 LED: <code>0x{end_led(p, len(p["subjects"]))}</code> ({p["subjects"][-1].get("led_note", p["led_note"])}). btnC를 누르면 처음 상태로 돌아갑니다.</p>
      <div class="codeblock"><div class="codebar"><span>Ubuntu Terminal · 장 Top 시뮬레이션 (STAGE 1~4)</span></div>
        <pre><code>{esc(p['run'])}</code></pre></div>
      <div class="codeblock"><div class="codebar"><span>기대 출력 ({e.tool} · {bg.file_date(e.rtl_path)} · 출처 {e.rtl_path})</span></div>
        <pre><code>{esc(bg.excerpt(e.lines, rf"^(PYTHON_{e.tag}_(SELF|VEC)|{e.tag}_TOP|RTL_SIM)"))}</code></pre></div>
      <div class="codeblock"><div class="codebar"><span>Vivado (VS Code) · STAGE 1~4 비트스트림</span></div>
        <pre><code>vivado -mode batch -nojournal -source {p['vivado_tcl']}
{esc(viv)}</code></pre></div>
      <details class="full"><summary>장 Top 테스트벤치·기준 모델 (전체 코드)</summary>
{chr(10).join(bg.code(x, e) for x in p['tb'] + p['ref'])}
      </details>"""
    secs.append(("장 시연", demo, "demo"))

    used = top_sources(p)
    rep = "".join(f"<tr><td>{s['code']}</td><td>{int(s['ch'][2:]):02d}장</td><td>{'<br>'.join(f'<code>{os.path.basename(x)}</code>' + ('' if x in used else ' ※') for x in c['new'] if x.endswith(('.v', '.sv')))}</td>"
                  f"<td>{WORD[state[s['code']][0]]}</td><td>{'통과' if e.stage_synth(s['stage']) and e.stage_synth(s['stage']).startswith('SYNTH_TIMING_PASS') else '⚠ 미검증'}</td>"
                  f"<td>{WORD[state[s['code']][1]]}</td></tr>" for s, c, _ in subj)
    hand = "".join(f"<tr><td><code>{a}</code></td><td>{b}</td></tr>" for a, b in p["handoff"])
    s_last = f"""      <table>
        <thead><tr><th>서브젝트</th><th>구 장</th><th>추가 RTL</th><th>시뮬레이션 (단독 + 장 Top)</th><th>합성 (장 Top STAGE)</th><th>보드</th></tr></thead>
        <tbody>{rep}</tbody>
      </table>
      <p>※ = 구 장 단독 실습 파일이라 장 Top 빌드(<code>{p['vivado_tcl']}</code>)에는 들어가지 않음.</p>
      <table>
        <thead><tr><th>다음 장으로 넘기는 파일</th><th>사용처</th></tr></thead>
        <tbody>{hand}</tbody>
      </table>
      <p>장 게이트 (<code>{p['id']}/validation/</code> 증거 기준 자동 표시):</p>
{bg.gate_row(project_gates(p, e))}"""
    secs.append(("누적 보고·인계", s_last, "s_report"))

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


def main(check):
    course = json.loads(rd("course_projects.json"))
    projects = load_projects()
    chs = bg.load_chapters()
    by_id = {c["id"]: c for c in chs}
    pages = {p["id"]: pfname(p) for p in projects}
    outputs = {pfname(p): build(p, course, by_id, chs, pages, projects) for p in projects}
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
