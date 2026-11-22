#!/usr/bin/env python3
"""실습 안내서 생성기 (단일 원본: chNN/chapter.json + 실제 코드 + validation/ 증거).

  python3 tools/guide/build_guides.py          # 안내서·index.html·course.json·docs/GUIDE_STATUS.md 재생성
  python3 tools/guide/build_guides.py --check  # 디스크 내용과 다르면 목록 출력 후 exit 1 (CI)

안내서 HTML은 직접 수정하지 않는다. 내용은 chapter.json, 코드는 RTL/TB 파일,
게이트 배지는 validation/ 증거 파일에서만 결정된다.
"""
import glob, hashlib, html, json, os, re, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SITE_TITLE = "Basys3 소형 NPU 실습 (고도화판)"


def rd(p):
    with open(os.path.join(ROOT, p), encoding="utf-8") as f:
        return f.read()


def esc(s):
    return html.escape(s, quote=False)


def latest(pattern):
    """같은 종류 증거 중 날짜가 가장 늦은 파일. 날짜 없는 파일은 가장 오래된 것으로 본다."""
    files = sorted(glob.glob(os.path.join(ROOT, pattern)))
    if not files:
        return None
    dated = [f for f in files if re.search(r"_(\d{8})\.\w+$", f)]
    return os.path.relpath((dated or files)[-1], ROOT)


def file_date(p):
    m = re.search(r"_(\d{4})(\d{2})(\d{2})\.\w+$", p or "")
    return f"{m.group(1)}-{m.group(2)}-{m.group(3)}" if m else "날짜 미기록"


# ── 장 목록 ───────────────────────────────────────────────────────────────────
def load_chapters():
    chs = []
    for p in sorted(glob.glob(os.path.join(ROOT, "ch[0-9][0-9]", "chapter.json"))):
        with open(p, encoding="utf-8") as f:
            c = json.load(f)
        assert c["id"] == os.path.basename(os.path.dirname(p)), p
        chs.append(c)
    return chs


def fname(c):
    return f"{c['id']}_{c['slug']}_{c['version']}.html"


# ── Verilog 파서 ─────────────────────────────────────────────────────────────
def strip_comments(t):
    t = re.sub(r"/\*.*?\*/", "", t, flags=re.S)
    return re.sub(r"//[^\n]*", "", t)


def module_origin(chs):
    """'작성(new)' 목록에 처음 나온 장을 각 모듈의 출처로 본다."""
    org = {}
    for c in chs:
        for p in c["new"]:
            if p.endswith((".v", ".sv")) and "/tb/" not in p:
                for m in re.findall(r"^\s*module\s+(\w+)", strip_comments(rd(p)), re.M):
                    org.setdefault(m, c["id"])
    return org


def parse_ports(path, module):
    t = strip_comments(rd(path))
    m = re.search(r"\bmodule\s+" + module + r"\b(.*?)\)\s*;", t, re.S)
    hdr = re.sub(r"#\s*\((?:[^()]|\([^()]*\))*\)", "", m.group(1), count=1)
    ins, outs = [], []
    for d, body in re.findall(r"\b(input|output)\b(.*?)(?=\b(?:input|output)\b|$)", hdr, re.S):
        body = re.sub(r"\b(wire|reg|signed)\b", " ", body)
        width = ""
        wm = re.match(r"\s*(\[[^\]]+\])", body)
        if wm:
            width = wm.group(1).replace(" ", "")
            body = body[wm.end():]
        for name in [n.strip() for n in body.replace(")", "").split(",")]:
            if re.fullmatch(r"\w+", name):
                (ins if d == "input" else outs).append((name, width))
    return ins, outs


def parse_instances(path, origin):
    t = strip_comments(rd(path))
    gens = re.findall(r"\bgenerate\b(.*?)\bendgenerate\b", t, re.S)
    out = {}
    for mod in origin:
        pat = r"^\s*" + mod + r"\s*(?:#\s*\((?:[^()]|\([^()]*\))*\))?\s*(\w+)\s*\("
        for inst in re.findall(pat, t, re.M):
            mult = 1
            for g in gens:
                if re.search(r"\b" + mod + r"\b(?:[^;]|\n)*?\b" + inst + r"\s*\(", g):
                    m = re.search(r"for\s*\(\s*\w+\s*=\s*0\s*;\s*\w+\s*<\s*(\d+)", g)
                    mult = int(m.group(1)) if m else 1
            out.setdefault(mod, []).append((inst, mult))
    return out


CLK_RE = re.compile(r"^(clk\w*|s_axi_aclk|\w*_aclk)$")
RST_RE = re.compile(r"^(resetn|rst\w*|reset\w*|btnC|\w*_aresetn)$")


def port_kind(name, board):
    if CLK_RE.match(name):
        return "클록"
    if RST_RE.match(name):
        return "리셋"
    return "보드 핀" if board else "데이터·제어"


FSM_RE = re.compile(r"localparam\s*(?:\[[^\]]*\])?\s*((?:[A-Z_][A-Z0-9_]*\s*=\s*\d+\s*,\s*)+[A-Z_][A-Z0-9_]*\s*=\s*\d+)\s*;")


def st_present(relpath):
    return bool(FSM_RE.search(strip_comments(rd(relpath))))


def svg_block(chid, relpath, module, origin, board=False):
    ins, outs = parse_ports(relpath, module)
    rows = []
    for mod, lst in parse_instances(relpath, origin).items():
        total = sum(m for _, m in lst)
        label = f"{mod} ×{total}" if total > 1 else mod
        if len(lst) <= 3:
            label += "  (" + " · ".join(f"{i}" + (f"[{m}]" if m > 1 else "") for i, m in lst) + ")"
        rows.append((label, origin[mod]))
    rows.sort(key=lambda r: (r[1] == chid, r[1]))
    lh = 23
    body_h = max(len(ins), len(outs), 2 + len(rows) * 1.6 + (2 if st_present(relpath) else 0)) * lh + 40
    # 고정폭 글자 14px ≈ 9px (글꼴 대체 여유 포함): 긴 포트 이름·상태 목록·하위 모듈 이름이 상자 밖으로 나가지 않게 폭을 정한다.
    cw = 9.2
    st_names = [n.split("=")[0].strip() for n in FSM_RE.search(strip_comments(rd(relpath))).group(1).split(",")] if st_present(relpath) else []
    left = max([250] + [int(len(n + w) * cw) + 40 for n, w in ins])
    right = max([250] + [int(len(n + w) * cw) + 50 for n, w in outs])
    box = max([480, int(len(" · ".join(st_names)) * cw) + 40] + [int(len(lb) * cw) + 140 for lb, _ in rows])
    x0, y0 = left, 30
    x1 = x0 + box
    W = x1 + right
    s = [f'<svg viewBox="0 0 {W} {int(body_h+(90 if board else 70))}" role="img" aria-label="{module} 실제 포트와 하위 모듈 구조">',
         f'<rect x="{x0}" y="{y0}" width="{x1-x0}" height="{int(body_h)}" rx="10" fill="#fff" stroke="#4635b1" stroke-width="2"/>',
         f'<text x="{(x0+x1)//2}" y="{y0+24}" font-size="18" font-weight="700" text-anchor="middle">{module}</text>',
         f'<text x="{(x0+x1)//2}" y="{y0+42}" font-size="13" text-anchor="middle" fill="#555">{relpath} · 구현 도식</text>']
    st = FSM_RE.search(strip_comments(rd(relpath)))
    if st:
        names = [n.split("=")[0].strip() for n in st.group(1).split(",")]
        yy = y0 + 58 + len(rows) * lh * 1.6 + 8
        s.append(f'<text x="{x0+20}" y="{int(yy)+12}" font-size="13" fill="#555">FSM 상태 (localparam 선언 순서 · 전이는 아래 상태 전이표)</text>')
        s.append(f'<text x="{x0+20}" y="{int(yy)+34}" font-size="14" font-family="monospace">{" · ".join(names)}</text>')
    for i, (n, w) in enumerate(ins):
        y = y0 + 30 + i * lh
        s.append(f'<text x="{x0-28}" y="{y+4}" font-size="14" font-family="monospace" text-anchor="end">{n}{w}</text>')
        dash = ' stroke-dasharray="4 3"' if port_kind(n, board) in ("클록", "리셋") else ""
        s.append(f'<path d="M{x0-24} {y} H{x0}" stroke="#4635b1" stroke-width="1.5"{dash}/><path d="M{x0} {y} l-7 -4 v8 z" fill="#4635b1"/>')
    for i, (n, w) in enumerate(outs):
        y = y0 + 30 + i * lh
        s.append(f'<path d="M{x1} {y} H{x1+24}" stroke="#4635b1" stroke-width="1.5"/><path d="M{x1+24} {y} l-7 -4 v8 z" fill="#4635b1"/>')
        s.append(f'<text x="{x1+28}" y="{y+5}" font-size="14" font-family="monospace">{n}{w}</text>')
    for i, (label, org) in enumerate(rows):
        y = y0 + 58 + i * lh * 1.6
        reused = org != chid
        fill, dash = ("#f1f2ee", ' stroke-dasharray="5 3"') if reused else ("#edeafa", "")
        tag = f"{org} 재사용" if reused else "이번 장 신규"
        s.append(f'<rect x="{x0+20}" y="{int(y)}" width="{x1-x0-40}" height="28" rx="5" fill="{fill}" stroke="#4635b1"{dash}/>')
        s.append(f'<text x="{x0+32}" y="{int(y)+19}" font-size="14" font-family="monospace">{esc(label)}</text>')
        s.append(f'<text x="{x1-32}" y="{int(y)+19}" font-size="12" text-anchor="end" fill="#4635b1">{tag}</text>')
    ly = int(body_h + y0 + 26)
    s.append(f'<rect x="{x0}" y="{ly-11}" width="16" height="12" fill="#edeafa" stroke="#4635b1"/><text x="{x0+22}" y="{ly}" font-size="13">이번 장 신규</text>')
    s.append(f'<rect x="{x0+120}" y="{ly-11}" width="16" height="12" fill="#f1f2ee" stroke="#4635b1" stroke-dasharray="4 2"/><text x="{x0+142}" y="{ly}" font-size="13">이전 장 파일 재사용(수정 없음)</text>')
    s.append(f'<text x="{x0+350}" y="{ly}" font-size="13">왼쪽 input · 오른쪽 output · 점선 = 클록·리셋</text>')
    if board:
        s.append(f'<text x="{x0}" y="{ly+20}" font-size="13">이 모듈의 포트는 Basys3 외부 핀입니다 (XDC 핀 배정).</text>')
    s.append("</svg>")
    return "\n".join(s)


def port_table(c, board):
    ins, outs = parse_ports(c["top"]["file"], c["top"]["module"])
    notes = c.get("port_notes", {})
    missing = [n for n, _ in ins + outs if n not in notes]
    if missing:
        raise SystemExit(f"{c['id']}: port_notes 누락 {missing} — chapter.json에 한글 설명을 추가하세요")
    rows = "".join(f"<tr><td>{d}</td><td class=\"nw\"><code>{n}</code></td><td class=\"nw\"><code>{w or '1'}</code></td><td class=\"nw\">{port_kind(n, board)}</td><td>{notes[n]}</td></tr>"
                   for d, lst in (("input", ins), ("output", outs)) for n, w in lst)
    return f"""      <table>
        <thead><tr><th>방향</th><th>포트</th><th>폭</th><th>구분</th><th>설명</th></tr></thead>
        <tbody>{rows}</tbody>
      </table>"""


def fsm_table(c):
    f = c.get("fsm")
    if not f:
        return ""
    st = FSM_RE.search(strip_comments(rd(f["file"])))
    names = [n.split("=")[0].strip() for n in st.group(1).split(",")]
    used = {r[0] for r in f["rows"]} | {r[2] for r in f["rows"]}
    unknown = sorted(x for x in used if x not in names and x not in ("default", "(모든 상태)"))
    if unknown or not set(names) <= used:
        raise SystemExit(f"{c['id']}: fsm 표 상태명이 {f['file']} localparam과 다릅니다 {unknown or sorted(set(names) - used)}")
    figure = fsm_diagram(c, names, f) if f.get("diagram") else ""
    rows = "".join(f"<tr><td class=\"nw\"><code>{a}</code></td><td><code>{esc(b)}</code></td><td class=\"nw\"><code>{d}</code></td><td>{esc(e)}</td></tr>"
                   for a, b, d, e in f["rows"])
    return figure + f"""
      <p>상태 전이표 (<code>{f['file']}</code>의 <code>case(state)</code> 기준, 리셋 시 <code>{f['reset']}</code>):</p>
      <table>
        <thead><tr><th>현재 상태</th><th>조건</th><th>다음 상태</th><th>동작</th></tr></thead>
        <tbody>{rows}</tbody>
      </table>"""


EDITOR_URL = "https://yuul-jung.github.io/svg-flow-editor/"
FLOW = "diagrams/course_flow_00_31"
TREE = "diagrams/module_techtree_00_12"


def diagram_page(stem):
    doc = json.loads(rd(stem + ".json"))
    return doc["pages"][doc.get("activePage", 0)] if isinstance(doc.get("pages"), list) else doc


def diagram_svg(stem, uid, label):
    """내보낸 SVG가 현재 JSON에서 만들어졌는지 해시로 확인하고, 한 페이지에 여러 장 넣어도 id가 겹치지 않게 바꾼다."""
    svg = rd(stem + ".svg")
    m = re.search(r"json-sha256: ([0-9a-f]{64})", svg)
    digest = hashlib.sha256(open(os.path.join(ROOT, stem + ".json"), "rb").read()).hexdigest()
    if not m or m.group(1) != digest:
        raise SystemExit(f"{stem}.svg 가 JSON보다 오래되었습니다 — python3 tools/diagram/export_svg.py 실행")
    svg = svg.replace('id="canvas"', f'id="{uid}"', 1).replace("arrowhead-", f"{uid}-arrowhead-")
    w = re.search(r'viewBox="0 0 ([\d.]+) ', svg)
    if w:   # 큰 도면은 원본 폭의 70% 아래로 줄이지 않고 틀 안에서 가로 스크롤 (STANDARD 10.1)
        svg = svg.replace("<svg ", f'<svg style="min-width:{int(float(w.group(1)) * 0.7)}px" ', 1)
    return re.sub(r'aria-label="[^"]*"', f'aria-label="{label}" role="img"', svg, count=1).strip()


def check_techtree(stem, chs, origin):
    """테크트리 도면의 모듈·간선·×N이 실제 RTL 인스턴스 관계와 같은지 대조한다."""
    page = diagram_page(stem)
    files = {}
    for c in chs:
        if c["number"] <= 12:
            for p in c["new"]:
                if p.endswith(".v"):
                    for m in re.findall(r"^\s*module\s+(\w+)", strip_comments(rd(p)), re.M):
                        files[m] = p
    want = {}
    for m, p in files.items():
        for child, lst in parse_instances(p, origin).items():
            n = sum(x for _, x in lst)
            want[(child, m)] = f"×{n}" if n > 1 else ""
    title = {n["id"]: n["title"] for n in page["nodes"]}
    mods = {t for i, t in title.items() if not i.startswith("note")}
    if mods != set(files):
        raise SystemExit(f"{stem}.json 모듈 노드가 00~12장 RTL과 다릅니다 {sorted(mods ^ set(files))}")
    got = {(title[e["from"]], title[e["to"]]): e.get("label", "") for e in page["edges"]}
    if got != want:
        diff = sorted(set(got.items()) ^ set(want.items()))
        raise SystemExit(f"{stem}.json 간선이 RTL 인스턴스 관계와 다릅니다 {diff}")


def fsm_diagram(c, names, f):
    """svg-flow-editor JSON(원본)과 내보낸 SVG를 대조하고 안내서에 넣는다."""
    stem = f["diagram"]
    doc = json.loads(rd(stem + ".json"))
    page = doc["pages"][doc.get("activePage", 0)] if isinstance(doc.get("pages"), list) else doc
    states = {n["title"] for n in page["nodes"] if not n["id"].startswith("note")}
    if states != set(names):
        raise SystemExit(f"{c['id']}: 상태도 노드 {sorted(states ^ set(names))} 가 localparam과 다릅니다 ({stem}.json)")
    title = {n["id"]: n["title"] for n in page["nodes"]}
    drawn = {(title[e["from"]], title[e["to"]]) for e in page["edges"]}
    table = {(a, d) for a, _, d, _ in f["rows"] if a not in ("default", "(모든 상태)") and a != d}
    if drawn != table:
        raise SystemExit(f"{c['id']}: 상태도 간선과 전이표가 다릅니다 — 도면에만 {sorted(drawn - table)}, 표에만 {sorted(table - drawn)}")
    svg = diagram_svg(stem, f"{c['id']}-fsm", f"{c['top']['module']} FSM 상태도")
    return f"""
      <p>상태도 (원본 <a href="{stem}.json"><code>{stem}.json</code></a> · <a href="{EDITOR_URL}">svg-flow-editor</a>에서 <b>작업 불러오기</b>로 열어 편집 → <b>작업 저장</b> → <code>python3 tools/diagram/export_svg.py</code>):</p>
      <div class="figure-wrap">{svg.strip()}</div>"""


# ── 증거(validation/) 읽기 ───────────────────────────────────────────────────
def log_lines(path, section=None):
    """section=None: 전체, 'main': 첫 '## ' 구분 전까지, 그 외: '## <section>' 이후."""
    if not path:
        return []
    lines = rd(path).splitlines()
    if section == "main":
        out = []
        for ln in lines:
            if ln.startswith("## "):
                break
            out.append(ln)
        return out
    if section:
        for i, ln in enumerate(lines):
            if ln.strip() == f"## {section}":
                return lines[i + 1:]
        return []
    return lines


def excerpt(lines, pattern):
    out = []
    for ln in lines:
        ln = ln.rstrip().replace("**", "")
        if re.search(pattern, ln):
            out.append(re.sub(r"\| <repo>/mini_npu/validation/local_runs/\S+ \|", "| … |", ln))
    return "\n".join(out)


def sim_tool(lines):
    for ln in lines:
        m = re.search(r"Icarus Verilog version ([\d.]+)", ln)
        if m:
            return f"Icarus Verilog {m.group(1)}"
    return "도구 버전 미기록"


class Evidence:
    def __init__(self, c, by_id):
        ev = c.get("evidence", {})
        self.rtl_path = latest(ev.get("rtl_log", f"{c['id']}/validation/rtl_sim*.log"))
        self.rtl = log_lines(self.rtl_path, ev.get("section"))
        self.tool = sim_tool(log_lines(self.rtl_path))
        host_pat = ev.get("host_model_pattern", r"PYTHON_\w*SELF_TEST_PASS|PC_GOLDEN_COMPARE_PASS")
        self.host = [ln.strip() for ln in self.rtl if re.search(host_pat, ln)]
        self.host_ref = None
        if not self.host and ev.get("host_model_ref"):
            self.host_ref = ev["host_model_ref"]
            ref = by_id[self.host_ref]
            rp = latest(ref.get("evidence", {}).get("rtl_log", f"{self.host_ref}/validation/rtl_sim*.log"))
            rpat = ref.get("evidence", {}).get("host_model_pattern", host_pat)
            self.host = [ln.strip() for ln in log_lines(rp) if re.search(rpat, ln)]
        self.rtl_pass = [ln.strip() for ln in self.rtl if re.search(r"(?<!PYTHON_)\b[A-Z0-9_]*SIM_PASS\b|\| RTL_SIM_PASS \|", ln)
                         and not ln.lstrip().startswith("#")]
        self.rtl_fail = [ln for ln in self.rtl if re.search(r"_FAIL\b|\$fatal|FATAL", ln)]
        v = c.get("vivado", {"mode": "none"})
        vid = v.get("ref", c["id"]) if v.get("mode") == "via" else c["id"]
        self.viv_path = latest(f"{vid}/validation/vivado_impl_timesim_*.txt") if (v.get("mode") == "top" or (v.get("mode") == "via")) \
            else latest(f"{vid}/validation/vivado_ooc_*.txt") if v.get("mode") == "ooc" else None
        self.viv = log_lines(self.viv_path)
        self.synth = next((ln.strip() for ln in self.viv if ln.startswith("SYNTH_TIMING_")), None)
        self.tsim = next((ln.strip() for ln in self.viv if re.match(r"TIMING_SIM_(PASS|FAIL)", ln)), None)
        self.board_path = latest(f"{c['id']}/validation/board_*.md")
        self.board = self.board_path and re.search(r"\bBOARD_PASS\b", rd(self.board_path))


def short(line, n=90):
    return esc(line if len(line) <= n else line[:n] + "…")


def gates(c, e):
    g = [("pass", "HTML_PASS", f"{c['version']} · 생성기·정적 검사")]
    if e.host:
        src = f" ({int(e.host_ref[2:]):02d}장 증거)" if e.host_ref else ""
        g.append(("pass", "HOST_MODEL_PASS", short(e.host[0]) + src))
    else:
        g.append(("na", "HOST_MODEL_PASS", "해당 없음 (Python 기준 모델 없음)"))
    table = [ln for ln in e.rtl_pass if ln.startswith("|")]
    if c.get("evidence", {}).get("kind") in ("static", "host"):
        # RTL이 아닌 장(블록 설계 Tcl, PC 측정 프로그램 등): RTL 게이트는 해당 없음, 대신 한 검사 결과만 적는다.
        ev = c["evidence"]; lp = latest(ev["rtl_log"])
        pat = ev.get("gate_pattern", r"STATIC_CHECK_(PASS|FAIL)")
        hits = [ln.strip() for ln in (rd(lp).splitlines() if lp else []) if re.search(pat, ln)]
        ok = hits and all("_FAIL" not in h for h in hits)
        what = "정적 검사" if ev["kind"] == "static" else "PC 시험"
        g.append(("na", "RTL_SIM_PASS", (f"해당 없음 (RTL 시뮬레이션 대상 아님) · {what}: " + short(hits[-1], 60) + f" · {file_date(lp)}")
                  if ok else f"해당 없음 · ⚠ {what} 기록 없음"))
    elif e.rtl_pass and not e.rtl_fail:
        if table:
            head = f"회귀 결과 표 {len(table)}단계 모두 RTL_SIM_PASS"
        else:
            more = f" 외 {len(e.rtl_pass)-1}건" if len(e.rtl_pass) > 1 else ""
            head = f"{short(e.rtl_pass[0], 60)}{more}"
        g.append(("pass", "RTL_SIM_PASS", f"{head} · {e.tool} · {file_date(e.rtl_path)}"))
    elif e.rtl_path:
        g.append(("fail", "RTL_SIM_PASS", f"✗ 실패 기록 · {e.rtl_path}"))
    else:
        g.append(("todo", "RTL_SIM_PASS", "⚠ 미검증 · 시뮬레이션 증거 없음"))
    mode = c.get("vivado", {}).get("mode", "none")
    if mode == "none":
        g.append(("na", "SYNTH_TIMING_PASS", "해당 없음"))
    elif e.synth and (e.synth.startswith("SYNTH_TIMING_NOT_CHECKED") or "WNS=NA" in e.synth):
        # 제약된 레지스터 간 경로가 없으면(WNS=NA) 타이밍을 검사한 것이 아니다: PASS로 세지 않는다.
        g.append(("todo", "SYNTH_TIMING_PASS", "⚠ 미검사 · 레지스터 간 경로 없음(WNS=NA), 합성·자원만 확인 · "
                  + short(e.synth.split(" ", 1)[1], 50) + f" · {file_date(e.viv_path)}"))
    elif e.synth:
        ok = e.synth.startswith("SYNTH_TIMING_PASS")
        via = f" ({int(c['vivado']['ref'][2:]):02d}장 통합 Top)" if mode == "via" else ""
        g.append(("pass" if ok else "fail", "SYNTH_TIMING_PASS",
                  ("" if ok else "✗ ") + short(e.synth.split(" ", 1)[1], 70) + via + f" · {file_date(e.viv_path)}"))
    else:
        g.append(("todo", "SYNTH_TIMING_PASS", "⚠ 미검증 · VS Code Vivado 실행 대기 (08절)"))
    if mode == "top":
        if e.tsim:
            ok = e.tsim.startswith("TIMING_SIM_PASS")
            g.append(("pass" if ok else "fail", "TIMING_SIM_PASS", short(e.tsim, 70) + f" · {file_date(e.viv_path)}"))
        elif e.viv_path:
            g.append(("fail", "TIMING_SIM_PASS", f"✗ 통과 기록 없음 · {e.viv_path}"))
        else:
            g.append(("todo", "TIMING_SIM_PASS", "⚠ 미검증 · 배선 후 SDF 시뮬레이션 실행 대기 (8-2)"))
    if e.board:
        g.append(("pass", "BOARD_PASS", f"{e.board_path}"))
    else:
        g.append(("todo", "BOARD_PASS", "⚠ 미실시 · 현재 실물 보드 확인 불가"))
    return g


def gate_row(gs):
    items = [f'        <div class="gate {cls}">\n          <b>{name}</b>\n          <span>{note}</span>\n        </div>'
             for cls, name, note in gs]
    return '      <div class="gate-row">\n' + "\n".join(items) + "\n      </div>"


# ── HTML 조각 ────────────────────────────────────────────────────────────────
HEAD = """<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="description" content="{desc}">
<meta name="generator" content="tools/guide/build_guides.py — 직접 수정 금지, chapter.json을 고친 뒤 재생성">
<title>{title}</title>
<link rel="stylesheet" href="assets/education/site.css">
<style>
.codeblock pre{{max-height:780px;white-space:pre}}
.section svg{{width:100%;height:auto}}
.vbadge{{display:inline-block;padding:.15em .6em;border-radius:4px;font-size:.78em;font-weight:700;background:#d4edda;color:#155724;vertical-align:middle}}
.gate-row{{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:10px;margin-top:10px}}
.gate{{border:1px solid var(--line,#e0e0e0);border-radius:6px;padding:10px 14px;overflow-wrap:anywhere}}
.gate b{{display:block;font:600 11px var(--mono,monospace);letter-spacing:.04em;margin-bottom:4px}}
.gate span{{font-size:13px}}
.gate.pass{{border-color:#2d8a52;background:#f0fbf4}}
.gate.todo{{border-color:#b08900;background:#fffbe6}}
.gate.fail{{border-color:#b3261e;background:#fdeceb}}
.gate.na{{border-color:#c8c8c8;background:#f6f6f6;color:#666}}
.table-wrap{{overflow-x:auto}}
.table-wrap>table{{min-width:620px}}
.figure-wrap{{overflow-x:auto}}
.figure-wrap svg{{min-width:860px}}
.section :not(pre)>code{{overflow-wrap:anywhere}}
.codebar{{gap:8px}}
.codebar span{{min-width:0;overflow-wrap:anywhere}}
.hero p{{max-width:none}}
.access-skip{{position:absolute;left:-9999px;top:0}}
.access-skip:focus{{left:12px;top:12px;z-index:1003;background:#fff;color:#15171c;padding:6px 10px}}
.nw code{{white-space:nowrap;overflow-wrap:normal}}
</style>
</head>
<body data-chapter="{chid}">
<a class="access-skip" href="#main-content">본문 바로가기</a>
<button type="button" class="mobile-menu" id="mobile-menu" aria-controls="course-nav" aria-expanded="false">☰ 장·목차</button>
<div class="shade" id="shade"></div>
<header class="hero">
  <div class="hero-inner">
    <p class="kicker">BASYS3 · NPU 고도화판 · {numstr} <span class="vbadge">{ver}</span></p>
    <h1>{h1}</h1>
    <p>{subtitle}</p>
  </div>
</header>
<div class="wrap">
  <nav class="toc" id="course-nav" aria-label="전체 장과 절 탐색"></nav>
  <main class="content" id="main-content">
"""
FOOT = """    <div class="chapter-links" id="chapter-links"></div>
  </main>
</div>
<script>
{course}
</script>
<script defer src="assets/education/site.js"></script>
</body>
</html>
"""


def course_js(chs):
    data = {"title": SITE_TITLE, "chapters": [
        {"id": c["id"], "number": c["number"], "title": c["nav_title"], "file": fname(c)} for c in chs]}
    return "window.COURSE=" + json.dumps(data, ensure_ascii=False, indent=1) + ";"


VIVADO_FILES = re.compile(r"(\.xdc|\.tcl|run_vivado_all\.sh|run_timing_sim\.sh)$")


def code_status(path, e):
    if e is None:
        return "원본"
    if VIVADO_FILES.search(path):
        if e.synth:
            if e.synth.startswith("SYNTH_TIMING_NOT_CHECKED") or "WNS=NA" in e.synth:
                return "원본 · Vivado 합성만 (타이밍 ⚠ 미검사)"
            return "원본 · Vivado 실행 " + ("통과" if e.synth.startswith("SYNTH_TIMING_PASS") else "실패")
        return "원본 · ⚠ 미검증 (Vivado 미실행)"
    if path.endswith((".c", ".h")):           # 보드 소프트웨어: PC 컴파일·시험까지만 확인
        ok = e.rtl_pass and not e.rtl_fail
        return (f"원본 · PC 시험 통과 {file_date(e.rtl_path)} · 보드 ⚠ 미검증" if ok else "원본 · ⚠ 미검증")
    if e.rtl_pass and not e.rtl_fail:
        return f"원본 · RTL_SIM 통과 {file_date(e.rtl_path)}"
    return "원본 · ⚠ 미검증"


def code(path, e=None):
    lang = {"v": "verilog", "sv": "systemverilog", "py": "python", "sh": "bash", "tcl": "tcl", "xdc": "xdc", "c": "c", "h": "c", "html": "html", "txt": "text"}.get(path.rsplit(".", 1)[1], "text")
    return (f'      <div class="codeblock">\n        <div class="codebar"><span>{path} · {lang} · {code_status(path, e)}</span></div>\n'
            f'        <pre><code class="language-{lang}">{esc(rd(path).rstrip(chr(10)))}</code></pre>\n      </div>')


def link_to(chs, cid, anchor, label):
    c = next((x for x in chs if x["id"] == cid), None)
    return f'<a href="{fname(c)}#{anchor}">{label}</a>' if c else label


def s08_unit(c, chs, e):
    v = c.get("vivado", {"mode": "none"})
    if v["mode"] == "none":
        return "      <p>이 장은 Vivado 합성 대상이 아닙니다.</p>"
    if v["mode"] == "via":
        ref = v["ref"]
        s = f"      <p>{v['note']} → {link_to(chs, ref, 's08', f'{int(ref[2:]):02d}장 · 08')}</p>"
        if v.get("board_fragment"):          # via 장에도 보드·Vitis 절차 조각을 붙일 수 있다 (22장 이후)
            s += "\n" + rd(v["board_fragment"]).rstrip("\n")
    else:
        k, top = c["id"], c["top"]["module"]
        res = v.get("resources")
        res_row = (f'<tr><td>자원</td><td>{res} — 기대값{"" if e.synth else " · 실행 전 ⚠ 미검증"}</td><td><code>build/vivado/{k}/route_util.rpt</code></td></tr>' if res else "")
        s = f"""      <p>Vivado가 설치된 PC의 VS Code 터미널에서 이 장 모듈만 Out-of-Context(OOC)로 합성·배치·배선하고 100 MHz 타이밍을 확인합니다.</p>
      <div class="codeblock"><div class="codebar"><span>Ubuntu Terminal · Vivado 배치 (저장소 루트)</span></div>
        <pre><code>source /tools/Xilinx/Vivado/&lt;버전&gt;/settings64.sh   # 설치 경로에 맞게 변경
vivado -mode batch -nojournal -source tools/vivado/ooc_timing.tcl -tclargs {k}
# 기대: SYNTH_TIMING_PASS {k} {top} WNS=… WHS=… LUT=… FF=… DSP48E1=… RAMB=…</code></pre></div>
      <table>
        <thead><tr><th>판정 항목</th><th>기준</th><th>확인 위치</th></tr></thead>
        <tbody>
          <tr><td>Setup / Hold</td><td><code>WNS ≥ 0</code> · <code>WHS ≥ 0</code> (clk 10.000 ns)</td><td><code>build/vivado/{k}/timing_route.rpt</code></td></tr>
          {res_row}
        </tbody>
      </table>
      <p>OOC 결과는 입출력 핀 지연을 포함하지 않으므로 보드 Top 타이밍을 대신하지 않습니다. 증거 저장은 <code>bash tools/run_vivado_all.sh ooc</code>(→ <code>{k}/validation/vivado_ooc_YYYYMMDD.txt</code>). 보드 확인은 {link_to(chs, 'ch12', 's08', '12장 · 08')}에서 통합 Top으로 진행합니다.</p>"""
        for p in v.get("extra_code", []):
            s += f"\n      <p><code>{p}</code> 전체:</p>\n" + code(p, e)
    if v["mode"] == "top":
        s = rd(v["board_fragment"]).rstrip("\n")
    if e.synth:
        rec = "\n".join(x for x in (e.synth, e.tsim) if x)
        s += (f'\n      <p>실행 기록 ({file_date(e.viv_path)}, 출처 <code>{e.viv_path}</code>):</p>\n'
              f'      <div class="codeblock"><div class="codebar"><span>Vivado 실행 결과</span></div>\n'
              f'        <pre><code>{esc(rec)}</code></pre></div>')
    return s


TABLE_WRAP = '<div class="table-wrap" tabindex="0" role="region" aria-label="표 (가로 스크롤 가능)">'
FIGURE_WRAP = '<div class="figure-wrap" tabindex="0" role="region" aria-label="도면 (가로 스크롤 가능)">'


def wrap_tables(text):
    """표를 가로 스크롤 영역으로 감싸 좁은 화면에서 페이지 전체가 넘치지 않게 한다.
    스크롤 영역과 코드 박스는 키보드로 초점을 받아 화살표로 스크롤할 수 있어야 한다 (axe scrollable-region-focusable)."""
    text = re.sub(r'<div class="table-wrap">(?=<table>)', TABLE_WRAP, text)
    text = re.sub(r'(?<!aria-label="표 \(가로 스크롤 가능\)">)<table>', TABLE_WRAP + "<table>", text)
    text = re.sub(r'</table>(?!</div>)', '</table></div>', text)
    text = text.replace('<div class="figure-wrap">', FIGURE_WRAP)
    return re.sub(r"<pre(?![^>]*tabindex)(?=[ >])", '<pre tabindex="0"', text)


def section(i, title, body):
    return f'    <section class="section" id="s{i:02d}">\n      <h2><span class="num">{i:02d}</span>{title}</h2>\n{body}\n    </section>'


def build(c, chs, origin, by_id):
    k, n = c["id"], c["number"]
    e = Evidence(c, by_id)

    def org(p):
        stem = os.path.basename(p).rsplit(".", 1)[0]
        o = origin.get(stem) or (p[:4] if re.match(r"ch\d\d/", p) else "")
        return f"{int(o[2:]):02d}장" if o else ""

    keep_rows = "".join(f"<li><code>{p}</code> <small>({org(p)})</small></li>" for p in c["keep"]) or "<li>없음 (첫 장)</li>"
    new_rows = "".join(f"<li><code>{p}</code></li>" for p in c["new"])
    s00 = f"""      <p><b>목표:</b> {c['goal']}</p>
      <table>
        <thead><tr><th>구분</th><th>파일</th></tr></thead>
        <tbody>
          <tr><td>유지 (이전 장, 수정 없음)</td><td><ul>{keep_rows}</ul></td></tr>
          <tr><td>이번 장 작성</td><td><ul>{new_rows}</ul></td></tr>
        </tbody>
      </table>
      <p>전체 누적 관계: <a href="index.html#techtree">INDEX · 01 전체 테크트리</a> (00~31장 흐름 · 00~12장 모듈 재사용 도면)</p>
      <p>실습 순서: 01 구조 확인 → 02 준비 → 03 RTL 작성 → 04 테스트벤치·기준 모델 작성 → 05 시뮬레이션 → 06 결과 판정 → 08 합성·타이밍(Vivado) → 09 인계.</p>"""
    board = c.get("vivado", {}).get("mode") == "top"
    s01 = '      <div class="figure-wrap">' + svg_block(k, c["top"]["file"], c["top"]["module"], origin, board).replace("\n", "\n      ") + "</div>"
    s01 += f'\n      <p>구현 도식: 포트 이름·폭과 하위 인스턴스는 <code>{c["top"]["file"]}</code> 선언에서 자동으로 가져왔습니다.</p>\n'
    s01 += port_table(c, board) + fsm_table(c)
    prep = c.get("prep_note", "")
    s02 = f"""      <ol>
        <li>VS Code에서 저장소 루트(<code>amd_soc_npu/</code>)를 엽니다.</li>
        <li>도구를 확인합니다.</li>
      </ol>
      <div class="codeblock"><div class="codebar"><span>Ubuntu Terminal · 도구 확인</span></div>
        <pre><code>sudo apt install -y iverilog python3 ripgrep   # 처음 한 번
iverilog -V 2&gt;&amp;1 | head -1      # Icarus Verilog version 12.0 이상
python3 --version</code></pre></div>
      <ol start="3"><li>00절 '유지' 파일이 이전 장 결과 그대로 있는지 확인합니다{(' (' + prep + ')') if prep else ''}.</li></ol>"""
    s03 = "      <p>아래 파일을 경로 그대로 만들고 전체 코드를 입력합니다.</p>\n" + "\n".join(code(p, e) for p in c["new"])
    tb_note = c.get("tb_note", "기준 모델(Python)은 시험 벡터와 정답을 만듭니다.")
    s04 = f"      <p>테스트벤치는 출력을 자동 판정합니다. {tb_note}</p>\n" + "\n".join(code(p, e) for p in c["tb"] + c["ref"])
    pat = c.get("evidence", {}).get("pattern", r"_PASS|PYTHON_VECTORS|^\|")
    s05 = f"""      <div class="codeblock"><div class="codebar"><span>Ubuntu Terminal · 저장소 루트에서 실행</span></div>
        <pre><code>{esc(c['run'])}   # {esc(c.get('run_note', 'RTL 컴파일 → 시뮬레이션 → TB 자동 판정'))}</code></pre></div>
      <p>기대 출력 ({e.tool} · {file_date(e.rtl_path)} 실제 실행 로그 발췌, 출처 <code>{e.rtl_path}</code>):</p>
      <div class="codeblock"><div class="codebar"><span>기대 출력</span></div>
        <pre><code>{esc(excerpt(e.rtl, pat)) or '⚠ 실행 로그 없음'}</code></pre></div>"""
    for x in c.get("extra_runs", []):
        lp = latest(x["log"])
        s05 += f"""
      <p>{x['title']}:</p>
      <div class="codeblock"><div class="codebar"><span>Ubuntu Terminal</span></div>
        <pre><code>{esc(x['cmd'])}   # {esc(x.get('note', x['title']))}</code></pre></div>
      <div class="codeblock"><div class="codebar"><span>기대 출력 (출처 {lp})</span></div>
        <pre><code>{esc(excerpt(log_lines(lp, x.get('section')), x['pattern']))}</code></pre></div>"""
    chk = "".join(f"<tr><td><code>{a}</code></td><td>{b}</td></tr>" for a, b in c["checks"])
    s06 = f"""      <table>
        <thead><tr><th>확인 항목</th><th>의미</th></tr></thead>
        <tbody>{chk}</tbody>
      </table>
      <p><b>실패 시:</b> TB의 <code>$fatal</code> 메시지에 표시된 cycle 번호와 기대값/실제값을 확인하고, 03절 코드와 한 줄씩 대조합니다. 하나라도 실패하면 다음 장으로 넘어가지 않습니다.</p>"""
    pts = "\n".join(f"<tr><td>{a}</td><td>{b}</td></tr>" for a, b in c.get("read_points", []))
    s07 = f"""      <table>
        <thead><tr><th>위치</th><th>내용</th></tr></thead>
        <tbody>{pts}</tbody>
      </table>"""
    s08 = s08_unit(c, chs, e)
    hand = "".join(f"<tr><td><code>{a}</code></td><td>{b}</td></tr>" for a, b in c["handoff"])
    gs = {name: (cls, note) for cls, name, note in gates(c, e)}
    word = {"pass": "통과", "fail": "✗ 실패", "todo": "⚠ 대기", "na": "해당 없음"}
    prev = sorted({org(p) for p in c["keep"]} - {""}) or ["없음 (첫 장)"]
    newv = [os.path.basename(p) for p in c["new"] if p.endswith((".v", ".sv"))] or ["없음 (스크립트·제약만)"]
    vec = [os.path.basename(p) for p in c["tb"] + c["ref"]]
    synth = word[gs["SYNTH_TIMING_PASS"][0]] + (" · 타이밍 시뮬 " + word[gs["TIMING_SIM_PASS"][0]] if "TIMING_SIM_PASS" in gs else "")
    report = f"""      <p>누적 보고 (이전 결과 → 추가 RTL → 시험 벡터 → 시뮬레이션 → 합성/보드 → 인계):</p>
      <table>
        <thead><tr><th>이전 결과</th><th>추가 RTL</th><th>시험 벡터</th><th>시뮬레이션</th><th>합성 / 보드</th><th>인계</th></tr></thead>
        <tbody><tr><td>{" · ".join(prev)}</td><td>{"<br>".join(f"<code>{x}</code>" for x in newv)}</td><td>{"<br>".join(f"<code>{x}</code>" for x in vec)}</td><td>{word[gs["RTL_SIM_PASS"][0]]}</td><td>{synth} / {word[gs["BOARD_PASS"][0]] if gs["BOARD_PASS"][0] != "todo" else "미실시"}</td><td>{len(c["handoff"])}건 (아래 표)</td></tr></tbody>
      </table>"""
    s09 = report + f"""
      <table>
        <thead><tr><th>다음 장으로 넘기는 파일</th><th>사용처</th></tr></thead>
        <tbody>{hand}</tbody>
      </table>
      <p>검증 게이트 (<code>{k}/validation/</code> 증거 파일 기준으로 자동 표시):</p>
{gate_row(gates(c, e))}"""
    secs = [("이 장의 위치", s00), ("구조도", s01), ("준비", s02), ("RTL 작성", s03), ("테스트벤치·기준 모델 작성", s04),
            ("시뮬레이션 실행", s05), ("결과 판정", s06), ("코드 읽기 포인트", s07), ("합성·타이밍·보드", s08), ("검증 현황·인계", s09)]
    body = "\n".join(section(i, t, b) for i, (t, b) in enumerate(secs))
    head = HEAD.format(desc=f"Basys3 NPU {n:02d}장 실습 · {c['name']}", title=f"{n:02d}장 · {c['name']} ({c['version']})",
                       chid=k, numstr=f"{n:02d}장 실습", ver=c["version"], h1=f"제{n:02d}장 · {c['name']}", subtitle=c["goal"])
    html_out = wrap_tables(head + body + "\n" + FOOT.format(course=course_js(chs)))
    return html_out, gates(c, e)


# ── index.html · course.json · 현황표 ────────────────────────────────────────
def update_index(text, chs):
    by = {c["number"]: c for c in chs}

    def row(m):
        r, num = m.group(0), int(m.group(1))
        c = by.get(num)
        if not c:
            return r
        cells = re.findall(r"<td>(.*?)</td>", r)
        title = re.sub(r"<[^>]+>", "", cells[1])
        cells[1] = f'<a href="{fname(c)}">{title}</a>'
        cells[3] = f'<span class="badge badge-ok">{c["version"]} 완료</span>'
        if num >= 13:  # 신규 구현 장: RTL 칸을 실제 실행 로그로 판정 (00~12장은 원본에서 이전한 RTL)
            lp = latest(c["evidence"]["rtl_log"])
            kind = c["evidence"].get("kind")
            if kind in ("static", "host"):
                pat = c["evidence"].get("gate_pattern", r"STATIC_CHECK_(PASS|FAIL)")
                hits = re.findall(pat, rd(lp)) if lp else []
                ok = bool(hits) and "FAIL" not in hits
                what = "정적 검사" if kind == "static" else "PC 시험"
                cells[4] = f'<span class="badge badge-ok">{what} 통과</span>' if ok else f'<span class="badge badge-todo">{what} 대기</span>'
            else:
                ok = bool(lp) and "RTL_SIM_PASS" in rd(lp)
                cells[4] = '<span class="badge badge-ok">RTL 시뮬 통과</span>' if ok else '<span class="badge badge-todo">RTL 시뮬 대기</span>'
        return "<tr>" + "".join(f"<td>{x}</td>" for x in cells) + "</tr>"

    text = re.sub(r"<tr><td>(\d\d)</td>.*?</tr>", row, text)
    # 01 전체 테크트리 절 맨 위에 과정 도면 (svg-flow-editor 원본)
    figs = f"""<!-- diagrams:start -->
      <p>과정 도면 (원본 <a href="{FLOW}.json"><code>{FLOW}.json</code></a>, <a href="{TREE}.json"><code>{TREE}.json</code></a> · <a href="{EDITOR_URL}">svg-flow-editor</a>에서 편집 후 <code>python3 tools/diagram/export_svg.py</code>):</p>
      <div class="figure-wrap">{diagram_svg(FLOW, "course-flow", "제3부 00~31장 전체 흐름")}</div>
      <div class="figure-wrap">{diagram_svg(TREE, "module-tree", "00~12장 모듈 테크트리")}</div>
      <!-- diagrams:end -->"""
    text = re.sub(r"\n?\s*<!-- diagrams:start -->.*?<!-- diagrams:end -->", "", text, flags=re.S)
    text = re.sub(r'(<section class="section" id="techtree">\s*<h2>.*?</h2>)', lambda m: m.group(1) + "\n      " + figs, text, count=1, flags=re.S)
    if ".figure-wrap{" not in text:
        text = text.replace("</style>", ".figure-wrap{overflow-x:auto}\n.figure-wrap svg{width:100%;height:auto;min-width:860px}\n</style>", 1)
    # 장식용 칩 제거 (STANDARD 3절, 헤더 높이 160~220px)
    text = re.sub(r'\n\s*<div class="chips">.*?</div>', "", text, count=1, flags=re.S)
    if ".table-wrap{" not in text:
        text = text.replace("</style>", ".table-wrap{overflow-x:auto}\n.table-wrap>table{min-width:620px}\n.section :not(pre)>code{overflow-wrap:anywhere}\n.codebar{gap:8px}\n.codebar span{min-width:0;overflow-wrap:anywhere}\n.access-skip{position:absolute;left:-9999px;top:0}\n.access-skip:focus{left:12px;top:12px;z-index:1003;background:#fff;color:#15171c;padding:6px 10px}\n.nw code{white-space:nowrap;overflow-wrap:normal}\n</style>", 1)
    text = wrap_tables(text)
    # 책장 사진은 assets/education/hero-bookshelf.jpg (site.css) 를 쓴다. 외부 주소 덮어쓰기 제거.
    text = re.sub(r"^\.hero:before\{background-image:[^\n]*raw\.githubusercontent[^\n]*\n", "", text, flags=re.M)
    return re.sub(r"window\.COURSE=\{.*?\n\};", course_js(chs).rstrip(";") + ";", text, flags=re.S)


def update_course(text, chs):
    data = json.loads(text)
    by = {c["id"]: c for c in chs}
    for ch in data["chapters"]:
        if ch["id"] in by:
            ch["file"] = fname(by[ch["id"]])
            ch["html_status"] = "DONE"
    return json.dumps(data, ensure_ascii=False, indent=2) + "\n"


SYM = {"pass": "✅", "fail": "❌", "todo": "⏳", "na": "—"}


def status_md(chs, all_gates, course):
    cols = ["HOST_MODEL_PASS", "RTL_SIM_PASS", "SYNTH_TIMING_PASS", "TIMING_SIM_PASS", "BOARD_PASS"]
    out = ["# 학습안내서 현황 (자동 생성)", "",
           "`python3 tools/guide/build_guides.py`가 `chNN/chapter.json`과 `chNN/validation/` 증거로 만든다. 직접 수정하지 않는다.", "",
           "✅ 통과 · ❌ 실패 · ⏳ 실행 대기/미검증 · — 해당 없음", "",
           "| 장 | 제목 | 안내서 | HOST | RTL_SIM | SYNTH_TIMING | TIMING_SIM | BOARD |",
           "|---|---|---|---|---|---|---|---|"]
    have = {c["id"]: c for c in chs}
    for ch in course["chapters"]:
        c = have.get(ch["id"])
        if not c:
            out.append(f"| {ch['number']:02d} | {ch['title']} | chapter.json 대기 | | | | | |")
            continue
        g = {name: cls for cls, name, _ in all_gates[c["id"]]}
        cells = [SYM[g[x]] if x in g else "—" for x in cols]
        out.append(f"| {c['number']:02d} | {c['nav_title']} | [{fname(c)}](../{fname(c)}) | " + " | ".join(cells) + " |")
    return "\n".join(out) + "\n"


def main(check):
    chs = load_chapters()
    by_id = {c["id"]: c for c in chs}
    origin = module_origin(chs)
    check_techtree(TREE, chs, origin)
    outputs, all_gates = {}, {}
    for c in chs:
        h, g = build(c, chs, origin, by_id)
        outputs[fname(c)] = h
        all_gates[c["id"]] = g
    course_text = rd("course.json")
    outputs["course.json"] = update_course(course_text, chs)
    outputs["index.html"] = update_index(rd("index.html"), chs)
    outputs["docs/GUIDE_STATUS.md"] = status_md(chs, all_gates, json.loads(outputs["course.json"]))
    stale = []
    for c in chs:   # 같은 장의 이전 버전 파일 (버전 규칙: 이전 파일 삭제)
        for p in glob.glob(os.path.join(ROOT, f"{c['id']}_*_v*.html")):
            if os.path.basename(p) != fname(c):
                stale.append(os.path.relpath(p, ROOT))
    if check:
        diff = [p for p, t in outputs.items()
                if not os.path.exists(os.path.join(ROOT, p)) or rd(p) != t] + [f"{p} (삭제 필요)" for p in stale]
        if diff:
            print("GUIDE_OUT_OF_DATE: python3 tools/guide/build_guides.py 실행 후 커밋하세요")
            for p in diff:
                print("  -", p)
            return 1
        print(f"GUIDE_UP_TO_DATE chapters={len(chs)}")
        return 0
    for p, t in outputs.items():
        with open(os.path.join(ROOT, p), "w", encoding="utf-8") as f:
            f.write(t)
    for p in stale:
        os.remove(os.path.join(ROOT, p))
    print(f"GUIDE_BUILT chapters={len(chs)} removed={len(stale)}")
    return 0


if __name__ == "__main__":
    sys.exit(main("--check" in sys.argv))
