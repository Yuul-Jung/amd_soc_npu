#!/usr/bin/env python3
"""제1부(MicroBlaze V 기본 SoC) 안내서 생성기.

  python3 tools/part01/build_part01.py          # part01/p1_*_v01.html · part01/index.html · docs/PART01_MIGRATION.md 생성
  python3 tools/part01/build_part01.py --check  # 디스크 내용과 다르거나 그림·코드 개수가 어긋나면 exit 1 (CI)

입력은 amd_soc_rtl에서 이관한 원본 페이지(part01/legacy/pages/soc/*.html, part01/chapters/11_*.html)이고
목록·제목은 part01/course.json 이 정한다. 원본은 고치지 않는다.

변환 내용 (rule_md STANDARD 2~4·10.3):
  - 상단: 어두운 격자 배너 → 공통 책장 사진 배너(assets/education/site.css)
  - 좌측: 장 선택 상자 → 공통 좌측 장·절 탐색(site.js, window.COURSE), 이전/다음/INDEX
  - 본문: 원본 <main> 내용을 그대로 옮기고, 원본 장별 스타일은 .p1-body 아래로 범위를 한정해 유지
  - 배너 요약 카드(hero-brief)·칩은 지우지 않고 '00 이 장의 개요' 절로 옮김
  - 코드: <pre>를 공통 코드 박스(.codeblock/.codebar, 복사 버튼)로 감쌈
  - 링크: 상대 경로를 part01/ 기준으로 다시 계산, 제1부 장끼리는 새 파일로 연결,
          code/docs/validation 텍스트 파일은 원본과 같이 UTF-8 소스 보기(legacy/source_viewer.html)로 연결
  - 개인 경로(/home/<사용자>)는 ~ 로 바꿈
그림(img·figure·svg)·표·코드·절 개수는 원본과 같아야 하며, 다르면 실패한다.
"""
from __future__ import annotations

import html
import json
import os
import re
import sys
from urllib.parse import quote, unquote, urlsplit

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
P1 = os.path.join(ROOT, "part01")
TEXT_EXT = re.compile(r"\.(?:v|vh|sv|svh|c|h|py|tcl|xdc|sh|md|txt|json|xml|csv|log|S|hex|mem|coe|yml|yaml)$", re.I)
GITHUB_SOC = re.compile(r"^https://github\.com/Yuul-Jung/soc/blob/[^/]+/MicroBlaze_V_SoC01_41/(.+)$")


def rd(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


COURSE = json.loads(rd(os.path.join(P1, "course.json")))
CHS = COURSE["chapters"]
BY_SRC = {os.path.normpath(os.path.join(P1, c["source"])): c for c in CHS}


# ── CSS 범위 한정 ──────────────────────────────────────────────────────────
# 원본 장 스타일 중 상단·좌측·하단 틀(공통 틀로 대체됨)은 버리고, 나머지는 .p1-body 안에서만 적용한다.
LAYOUT = re.compile(
    r"\.(?:topbar|topbar-inner|top-inner|breadcrumb|brand|hero|hero-[\w-]+|chip|chips|wrap|flow-nav|nav-[\w-]+|"
    r"timeline|reader-[\w-]+|site-footer|skip-link|chapter-nav|version-badge|section-group|meta)(?![\w-])")
DROP_DECL = re.compile(r"^\s*(?:margin|background|background-color|font|font-family)\s*:", re.I)


def split_top(s, sep=","):
    out, depth, cur = [], 0, ""
    for ch in s:
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        if ch == sep and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    out.append(cur)
    return out


def scope_selector(sel):
    s = sel.strip()
    if not s or LAYOUT.search(s):
        return None
    if re.match(r"^\*(?:::?[\w-]+)?$", s):
        return None
    if s in (":root", "html", "body", "main"):
        return ".p1-body"
    m = re.match(r"^(?:html|body|main|:root)(?![\w-])\s*(.*)$", s)
    if m:
        return (".p1-body " + m.group(1)).strip() if not m.group(1).startswith((">", "+", "~")) else ".p1-body" + m.group(1)
    return ".p1-body " + s


def scope_css(css):
    css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)
    out, i, n = [], 0, len(css)
    while i < n:
        j = css.find("{", i)
        k = css.find(";", i)
        if j < 0:
            break
        if 0 <= k < j and css[i:k].strip().startswith("@"):  # @import · @charset
            i = k + 1
            continue
        prelude = css[i:j].strip()
        depth, p = 1, j + 1
        while p < n and depth:
            depth += {"{": 1, "}": -1}.get(css[p], 0)
            p += 1
        body = css[j + 1:p - 1]
        i = p
        if prelude.startswith(("@media", "@supports")):
            inner = scope_css(body)
            if inner.strip():
                out.append(prelude + "{" + inner + "}")
        elif prelude.startswith("@"):
            out.append(prelude + "{" + body + "}")
        else:
            sels = [x for x in (scope_selector(s) for s in split_top(prelude)) if x]
            if not sels:
                continue
            if ".p1-body" in sels and all(x == ".p1-body" for x in sels):
                body = ";".join(d for d in body.split(";") if d.strip() and not DROP_DECL.match(d))
                if not body.strip():
                    continue
            out.append(",".join(sels) + "{" + body.strip() + "}")
    return "\n".join(out)


# ── 링크 다시 계산 ─────────────────────────────────────────────────────────
broken: list[str] = []


def new_url(raw, src_dir, tag, page):
    u = html.unescape(raw).strip()
    g = GITHUB_SOC.match(u)
    if g and os.path.exists(os.path.join(P1, "legacy", g.group(1))):
        u = os.path.relpath(os.path.join(P1, "legacy", g.group(1)), src_dir)
    if not u or u.startswith("#") or re.match(r"^[a-z][a-z0-9+.-]*:|^//", u, re.I):
        return raw
    sp = urlsplit(u)
    if not sp.path:
        return raw
    tgt = os.path.normpath(os.path.join(src_dir, unquote(sp.path)))
    frag = "#" + sp.fragment if sp.fragment else ""
    qs = "?" + sp.query if sp.query else ""
    if not tgt.startswith(P1 + os.sep) or not os.path.exists(tgt):
        broken.append(f"{page}: {raw}")
        return raw
    if tgt in BY_SRC:
        return html.escape(BY_SRC[tgt]["file"] + frag, quote=True)
    rel = os.path.relpath(tgt, P1).replace(os.sep, "/")
    lrel = os.path.relpath(tgt, os.path.join(P1, "legacy")).replace(os.sep, "/")
    if tag == "a" and re.match(r"^(code|docs|validation)/", lrel) and TEXT_EXT.search(lrel) and not qs:
        return html.escape("legacy/source_viewer.html?file=" + quote(lrel, safe="") + frag, quote=True)
    return html.escape(quote(rel, safe="/") + qs + frag, quote=True)


def rewrite_links(fragment, src_dir, page):
    def tag(m):
        t, name = m.group(0), m.group(1).lower()
        if name == "a" and re.search(r"\sdownload(?:[\s=>])", t):
            name = "a-download"
        t = re.sub(r'(\s(?:href|src|poster)\s*=\s*")([^"]*)(")',
                   lambda a: a.group(1) + new_url(a.group(2), src_dir, name, page) + a.group(3), t)
        t = re.sub(r'(\ssrcset\s*=\s*")([^"]*)(")',
                   lambda a: a.group(1) + ", ".join(
                       " ".join([new_url(p.split()[0], src_dir, "img", page)] + p.split()[1:])
                       for p in a.group(2).split(",") if p.strip()) + a.group(3), t)
        return t
    return re.sub(r"<([a-zA-Z][\w-]*)\b[^>]*>", tag, fragment)


# ── 코드 박스 ──────────────────────────────────────────────────────────────
def wrap_pre(body):
    def one(m):
        head, pre = m.group(1), m.group(2)
        label = ""
        if head:
            label = re.sub(r"<[^>]+>", "", re.search(r"<strong>(.*?)</strong>", head, re.S).group(1)).strip()
        if not label:
            a = re.search(r'aria-label="([^"]*)"', pre[:300])
            label = html.unescape(a.group(1)) if a else ""
        if not label:
            label = "코드"
        return ('<div class="codeblock"><div class="codebar"><span>' + html.escape(label) + "</span></div>"
                + pre + "</div>")
    return re.sub(r'(<div class="code-head">.*?</div>)?\s*(<pre\b.*?</pre>)', one, body, flags=re.S)


# ── 원본 페이지 분해 ───────────────────────────────────────────────────────
def text_of(s):
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", "", s or ""))).strip()


def first_sentence(s):
    """배너에는 첫 문장만 (헤더 높이 160~220px, STANDARD 2절). 전체 문장은 00 이 장의 개요 절에 둔다."""
    m = re.match(r"(.+?[.다])(?:\s|$)", s)
    return m.group(1) if m else s


def first(pat, s, flags=re.S):
    m = re.search(pat, s, flags)
    return m.group(1) if m else ""


def counts(s):
    return {k: len(re.findall(p, s)) for k, p in
            (("img", r"<img\b"), ("figure", r"<figure\b"), ("svg", r"<svg\b"), ("pre", r"<pre\b"),
             ("table", r"<table\b"), ("section", r"<section\b"), ("details", r"<details\b"))}


def parse(src_html):
    hero = first(r'<(?:header|section) class="hero">(.*?)</(?:header|section)>\s*<div class="wrap">', src_html)
    main = first(r"<main\b[^>]*>(.*)</main>", src_html)
    style = "\n".join(re.findall(r"<style[^>]*>(.*?)</style>", src_html, re.S))
    kicker = text_of(first(r'<p class="hero-kicker">(.*?)</p>', hero) or first(r"<small>(.*?)</small>", hero))
    desc = first(r'<p class="hero-desc">(.*?)</p>', hero) or first(r"<p>(.*?)</p>", hero)
    chips = [text_of(x) for x in re.findall(r'<span class="(?:chip|version-badge)">(.*?)</span>', hero)]
    if not chips:
        chips = [text_of(x) for x in re.findall(r"<span>(.*?)</span>", first(r'<div class="chips">(.*?)</div>', hero))]
    brief = re.findall(r"<article>\s*<h2>(.*?)</h2>\s*<p>(.*?)</p>\s*</article>", hero, re.S)
    return dict(main=main, style=style, kicker=kicker, desc=desc.strip(), chips=chips, brief=brief)


HEAD = """<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="description" content="{meta}">
<meta name="generator" content="tools/part01/build_part01.py — 직접 수정 금지, 원본(part01/legacy·chapters) 또는 생성기를 고친 뒤 재생성">
<title>{title}</title>
<link rel="stylesheet" href="../assets/education/site.css">
<style>
/* 공통 틀 보조 */
.access-skip{{position:absolute;left:-9999px;top:0}}
.access-skip:focus{{left:12px;top:12px;z-index:1003;background:#fff;color:#15171c;padding:6px 10px}}
.vbadge{{display:inline-block;padding:.15em .6em;border-radius:4px;font-size:.78em;font-weight:700;background:#d4edda;color:#155724;vertical-align:middle}}
.hero p{{max-width:none}}
.p1-overview .chips{{display:flex;flex-wrap:wrap;gap:8px;margin:6px 0 14px;padding:0;list-style:none}}
.p1-overview .chips li{{border:1px solid var(--line);background:#fff;padding:3px 10px;border-radius:3px;font:500 12px "IBM Plex Mono",monospace;color:var(--ink-2)}}
.p1-overview .brief{{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px}}
.p1-overview .brief div{{border:1px solid var(--line);border-left:3px solid var(--accent);background:#fff;padding:12px 14px}}
.p1-overview .brief b{{display:block;margin-bottom:4px}}
.section :not(pre)>code{{overflow-wrap:anywhere}}
.p1-body .codeblock{{margin:14px 0 18px}}
.p1-body .codeblock pre{{margin:0;max-height:780px;white-space:pre;border:0;border-left:0}}
.p1-body img{{max-width:100%;height:auto}}
.table-wrap,.p1-body .tablewrap{{overflow-x:auto}}
.p1-body section[id]{{scroll-margin-top:16px}}
/* 원본 장 스타일 (.p1-body 범위 한정) */
{css}
</style>
</head>
<body data-chapter="{chid}">
<a class="access-skip" href="#main-content">본문 바로가기</a>
<button type="button" class="mobile-menu" id="mobile-menu" aria-controls="course-nav" aria-expanded="false">☰ 장·목차</button>
<div class="shade" id="shade"></div>
<header class="hero">
  <div class="hero-inner">
    <p class="kicker">BASYS3 · 제1부 MicroBlaze V 기본 SoC · {num}장 <span class="vbadge">{ver}</span></p>
    <h1>제1부 {num}장 · {h1}</h1>
    <p>{desc}</p>
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
window.COURSE={course};
</script>
<script defer src="../assets/education/site.js"></script>
</body>
</html>
"""


def course_js():
    return json.dumps({"title": COURSE["title"],
                       "chapters": [{"id": c["id"], "number": c["number"], "title": c["title"], "file": c["file"]} for c in CHS]},
                      ensure_ascii=False, indent=1)


def sanitize(s):
    return re.sub(r"/home/[A-Za-z0-9_.-]+", "~", s)


def build_page(c):
    src = os.path.join(P1, c["source"])
    p = parse(rd(src))
    main = p["main"]
    main = re.sub(r'<nav class="chapter-nav">.*?</nav>', "", main, flags=re.S)
    main = re.sub(r'<footer class="footer">.*?</footer>', "", main, flags=re.S)
    before = counts(main)
    main = wrap_pre(main)
    main = re.sub(r'<button[^>]*onclick="copyCode[^"]*"[^>]*>.*?</button>', "", main, flags=re.S)
    main = rewrite_links(main, os.path.dirname(src), c["file"])
    main = sanitize(main)
    after = counts(main)
    ov = ['    <section class="section p1-overview" id="p1-overview">',
          '      <h2><span class="num">00</span>이 장의 개요</h2>',
          f'      <p>{rewrite_links(p["desc"], os.path.dirname(src), c["file"])}</p>']
    if p["chips"]:
        ov.append('      <ul class="chips" aria-label="핵심 용어">' + "".join(f"<li>{html.escape(x)}</li>" for x in p["chips"]) + "</ul>")
    if p["brief"]:
        ov.append('      <div class="brief">' + "".join(f"<div><b>{text_of(h)}</b>{b.strip()}</div>" for h, b in p["brief"]) + "</div>")
    ov.append(f'      <p>원본: <a href="{html.escape(quote(c["source"], safe="/"))}"><code>part01/{c["source"]}</code></a> (이관 원본 보존본)</p>')
    ov.append("    </section>")
    css = scope_css(p["style"])
    head = HEAD.format(meta=html.escape(f"Basys3 제1부 {c['number']}장 · {c['title']}"),
                       title=html.escape(f"제1부 {c['number']}장 · {c['title']} ({COURSE['version']})"),
                       css=css, chid=c["id"], num=c["number"], ver=COURSE["version"],
                       h1=html.escape(c["title"]), desc=html.escape(first_sentence(text_of(p["desc"]))))
    out = head + "\n".join(ov) + '\n    <div class="p1-body">\n' + main.strip() + "\n    </div>\n" + FOOT.format(course=course_js())
    return sanitize(out), before, after, len(p["brief"]), len(p["chips"])


# ── 제1부 INDEX ───────────────────────────────────────────────────────────
def build_index(summary):
    by = {c["id"]: c for c in CHS}
    rows = []
    for g in COURSE["groups"]:
        rows.append(f'      <h3>{html.escape(g["title"])}</h3>')
        rows.append('      <div class="table-wrap" tabindex="0" role="region" aria-label="표 (가로 스크롤 가능)"><table>')
        rows.append("        <thead><tr><th>장</th><th>제목</th><th>개요</th><th>그림</th><th>코드</th></tr></thead><tbody>")
        for cid in g["chapters"]:
            c = by[cid]
            s = summary[cid]
            rows.append(f'          <tr><td>{c["number"]}</td><td><a href="{c["file"]}">{html.escape(c["title"])}</a></td>'
                        f'<td>{html.escape(s["desc"])}</td><td>{s["after"]["img"] + s["after"]["svg"]}</td><td>{s["after"]["pre"]}</td></tr>')
        rows.append("        </tbody></table></div>")
    body = f"""    <section class="section" id="intro">
      <h2><span class="num">00</span>학습 흐름</h2>
      <p>01~05장에서 MicroBlaze V·BRAM·Clock/Reset·Memory Map·AXI 구조를 익히고, 06~10장에서 AXI GPIO·UART Lite·Timer·Interrupt Controller를 하나씩 붙여 통합합니다. 11장에서 사용자 Top을 연결해 제2부(주변장치 IP)와 제3부(소형 NPU)의 출발점이 되는 SoC를 완성합니다. 07.1~10.1장은 각 장의 C 코드를 한 줄씩 풀이합니다.</p>
      <p>01~05장 · 프로세서·메모리·버스 → 06~09장 · GPIO·UART·Timer·Interrupt → 10장 · 통합 → 11장 · 사용자 Top → <a href="../index.html">제3부 · 소형 NPU (00~31장)</a></p>
    </section>
    <section class="section" id="chapters">
      <h2><span class="num">01</span>장별 바로가기</h2>
{chr(10).join(rows)}
    </section>
    <section class="section" id="sources">
      <h2><span class="num">02</span>원본 자료 · 검증 기록</h2>
      <ul>
        <li><a href="legacy/00_overview/START_HERE.html">공통 사양·실습 순서 (원본)</a></li>
        <li><a href="legacy/validation/verification.html">장별 검증 결과 (원본)</a></li>
        <li><a href="legacy/peripheral_schematic_atlas.html">주변장치 회로 도감 (원본)</a></li>
        <li><a href="legacy/index.html">원본 41장 전체 목록 (이관 당시 그대로)</a></li>
        <li><a href="legacy/source_viewer.html?file=EDITORIAL_GUIDELINES.md">원본 교재 제작·검증 지침</a></li>
        <li><a href="files/p1_11/verification_record.md">11장 검증 기록</a> · <a href="files/p1_11/basys3_soc11_top.v">11장 Top</a> · <a href="files/p1_11/basys3_soc11_top.xdc">11장 XDC</a> · <a href="files/p1_11/main_soc11.c">11장 C</a></li>
        <li><a href="../docs/PART01_MIGRATION.md">제1부 이관·변환 점검 기록</a></li>
        <li>제2부(사용자 AXI IP·주변장치) 원본: <a href="https://github.com/Yuul-Jung/amd_soc_rtl/tree/main/part02_1" target="_blank" rel="noopener">amd_soc_rtl/part02_1</a> (비공개 저장소)</li>
      </ul>
    </section>
    <section class="section" id="rules">
      <h2><span class="num">03</span>검증 원칙</h2>
      <ul>
        <li>본문·그림·코드는 원본(<code>{COURSE["source"]}</code>)을 그대로 옮기고 화면 틀만 공통 표준으로 바꿨습니다. 각 장의 그림·표·코드 개수는 원본과 같음을 생성기가 확인합니다.</li>
        <li>원본에 기록된 GUI 캡처·실행 결과만 표시합니다. 이 이관으로 Vivado·Vitis·보드를 다시 실행하지 않았습니다(⚠ 미검증).</li>
        <li>안내서는 <code>python3 tools/part01/build_part01.py</code>로 만들며 직접 수정하지 않습니다.</li>
      </ul>
    </section>
"""
    head = HEAD.format(meta="Basys3 MicroBlaze V 기본 SoC 제1부 01~11장 학습안내서",
                       title=html.escape(f"{COURSE['title']} ({COURSE['version']})"), css=".table-wrap th{white-space:nowrap}", chid="p1-index",
                       num="01~11", ver=COURSE["version"], h1="MicroBlaze V 기본 SoC",
                       desc="CPU·BRAM·AXI 주변장치 구축에서 사용자 Top 연결까지 — 제2부·제3부의 선수 과정")
    head = head.replace("<p class=\"kicker\">BASYS3 · 제1부 MicroBlaze V 기본 SoC · 01~11장", "<p class=\"kicker\">BASYS3 · PART 01 · CHAPTER 01–11")
    head = head.replace("<h1>제1부 01~11장 · ", "<h1>제1부 · ")
    return head + body + FOOT.format(course=course_js())


def report(summary):
    out = ["# 제1부 이관·변환 점검 기록 (자동 생성)", "",
           f"원본: `{COURSE['source']}` → `part01/` (원본 파일은 그대로 보존, 개인 경로만 `~`로 치환).",
           "생성: `python3 tools/part01/build_part01.py` — 직접 수정하지 않는다.", "",
           "## 장별 요소 개수 (원본 <main> → 새 안내서 본문)", "",
           "그림 누락 방지를 위해 img·figure·svg·pre·table·section·details 개수가 같아야 생성기가 통과한다.", "",
           "| 장 | 새 파일 | img | figure | svg | pre | table | section | details | 개요 카드 | 판정 |",
           "|---|---|---|---|---|---|---|---|---|---|---|"]
    for c in CHS:
        s = summary[c["id"]]
        b, a = s["before"], s["after"]
        cell = lambda k: f"{b[k]}→{a[k]}"
        ok = "통과" if b == a else "실패"
        out.append(f"| {c['number']} | [{c['file']}](../part01/{c['file']}) | " + " | ".join(cell(k) for k in b) + f" | {s['brief']} | {ok} |")
    out += ["", "## 링크", "",
            f"- 깨진 상대 링크: {len(broken)}개" + ("" if not broken else "\n" + "\n".join(f"  - `{x}`" for x in broken)),
            "- 제1부 장끼리의 링크는 새 안내서로, `code/`·`docs/`·`validation/` 텍스트 파일은 원본과 같이 UTF-8 소스 보기로 연결.",
            "- `github.com/Yuul-Jung/soc/blob/…/MicroBlaze_V_SoC01_41/…` 링크는 이관본(`part01/legacy/…`)으로 바꿈.", "",
            "- 보존본 안의 알려진 깨짐 1건: `part01/legacy/pages/soc/ch01_microblaze_bram_v01.html`(amd_soc_rtl의 01장 시범판)은 "
            "amd_soc_rtl 최상위 `assets/education/site-theme.css`를 가리켜 이 저장소에서는 공통 스타일 없이 보인다. "
            "새 안내서 `p1_01_microblaze_bram_v01.html`이 대체하므로 원본은 고치지 않았다.", "",
            "## 미검증", "",
            "- ⚠ 미검증: 원본 GUI 캡처 이미지 안의 화면 글자(창 제목의 사용자 경로 등)는 자동 점검 대상이 아님.",
            "- ⚠ 미검증: Vivado·Vitis·보드 재실행 없음 — 원본 기록만 옮김.", ""]
    return "\n".join(out)


def main(check):
    outputs, summary, fails = {}, {}, []
    for c in CHS:
        page, before, after, nb, nc = build_page(c)
        outputs[os.path.join("part01", c["file"])] = page
        src_desc = parse(rd(os.path.join(P1, c["source"])))["desc"]
        summary[c["id"]] = dict(before=before, after=after, brief=nb, chips=nc, desc=text_of(src_desc))
        if before != after:
            fails.append(f"{c['file']}: 요소 개수 불일치 {before} → {after}")
    outputs[os.path.join("part01", "index.html")] = build_index(summary)
    outputs[os.path.join("docs", "PART01_MIGRATION.md")] = report(summary)
    fails += [f"깨진 링크 {x}" for x in broken]
    keep = {c["file"] for c in CHS}
    stale = [f for f in os.listdir(P1) if re.match(r"p1_.*_v\d+\.html$", f) and f not in keep]
    if check:
        fails += [f"{p} 갱신 필요" for p, t in outputs.items() if not os.path.exists(os.path.join(ROOT, p)) or rd(os.path.join(ROOT, p)) != t]
        fails += [f"part01/{p} 삭제 필요" for p in stale]
    if fails:
        print("PART01_FAIL")
        for x in fails:
            print("  -", x)
        return 1
    if check:
        print(f"PART01_UP_TO_DATE chapters={len(CHS)}")
        return 0
    for p, t in outputs.items():
        with open(os.path.join(ROOT, p), "w", encoding="utf-8") as f:
            f.write(t)
    for p in stale:
        os.remove(os.path.join(P1, p))
    print(f"PART01_BUILT chapters={len(CHS)} removed={len(stale)}")
    return 0


if __name__ == "__main__":
    sys.exit(main("--check" in sys.argv))
