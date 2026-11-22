#!/usr/bin/env python3
"""제1부(MicroBlaze V 기본 SoC) 배포용 학습안내서 생성기.

  pip install beautifulsoup4==4.15.0 lxml       # 필요 패키지 (CI와 같은 판)
  python3 tools/part01/build_part01.py          # part01/p1_*_v02.html · part01/index.html · docs/PART01_EDIT_LOG.md 생성
  python3 tools/part01/build_part01.py --check  # 디스크와 다르거나 그림·코드·표 개수가 원본과 다르면 exit 1 (CI)

입력: part01/legacy/pages/soc/*.html, part01/chapters/11_*.html (amd_soc_rtl 이관본, 수정하지 않음)
목록: part01/course.json

원본 페이지를 공통 표준(rule_md STANDARD) 안내서로 새로 구성한다.
  - 틀: 책장 배너 · 좌측 장/절 탐색(site.js) · 이전/다음 · 코드 복사 박스 · 공통 색상
  - 절: 'SECTION NN'·분류 꼬리표·진행 위치 카드·단계 배너를 걷어내고 00 목표 + 01~ 번호 절로 정리
  - 본문: 제작·검증 메모(검증 완료/실기/계측/출처/원본/캡처 여부 등)를 문장 단위로 지우고,
          남은 '검증'은 학습 동작인 '확인'으로, 이전 장 프로젝트를 뜻하는 '원본'은 '기존'으로 바꾼다
  - 그림·표·코드는 하나도 빼지 않는다 (개수 대조, 다르면 실패)
지운 문장은 docs/PART01_EDIT_LOG.md 에 남긴다 (배포 본문 아님).
"""
from __future__ import annotations

import copy
import html
import json
import os
import re
import sys
from urllib.parse import quote, unquote, urlsplit

from bs4 import BeautifulSoup, Comment, NavigableString, Tag

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
P1 = os.path.join(ROOT, "part01")
TEXT_EXT = re.compile(r"\.(?:v|vh|sv|svh|c|h|py|tcl|xdc|sh|md|txt|json|xml|csv|log|S|hex|mem|coe|yml|yaml)$", re.I)
GITHUB_SOC = re.compile(r"^https://github\.com/Yuul-Jung/soc/blob/[^/]+/MicroBlaze_V_SoC01_41/(.+)$")


def rd(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


COURSE = json.loads(rd(os.path.join(P1, "course.json")))
CHS = COURSE["chapters"]
VER = COURSE["version"]
BY_SRC = {os.path.normpath(os.path.join(P1, c["source"])): c for c in CHS if c.get("source")}
BUNDLE = {c["bundle_of"]: c for c in CHS if c.get("bundle_of")}   # 장 → 실습 파일 묶음 쪽

# ── 문구 정리 규칙 ─────────────────────────────────────────────────────────
# 1) 낱말 바꾸기 (순서대로 적용). 그림 확대 링크·이전 장 프로젝트·공식 문서 표기를 배포용 표현으로.
REPLACE = [
    (r" — 실제 확인 화면", ""), (r" — 추정값", ""), (r"완료 당시 실제 ", "완료 후 "), (r"(을|를) 바탕으로 재구성한 ", " 기준 "),
    (r"(그림 |파형 )?출처:\s*", ""), (r"(확인 )?근거:\s*", "참고: "), (r"원문:\s*", ""), (r"(\d+쪽 )?원문 열기", "공식 문서"),
    (r"AMD (PG\d+ )?원문 ", r"AMD \1"), (r" 원문$", ""), (r"원본의 Irq", "문서의 Irq"), (r"PG\d+ 원본 그림", "PG079 그림"),
    (r"실제 (검증|확인)(한|된)? ?", r"확인\2 "), (r"보드 실행 결과:\s*", "결과: "),
    (r"확인(했|하였)습니다", "확인합니다"), (r"확인(됐|되었)습니다", "확인됩니다"), (r"확인(했|하였)다", "확인한다"),
    (r" 등 비트 위치를 원본과 대조한다", " 등 비트 위치"), (r"원문에는 ", "문서에는 "), (r"원본의 (?=Irq|$)", "문서의 "),
    (r"구조 원본은 08장", "구조는 08장"), (r"을 실기 확인", "을 보드에서 확인"),
    (r"\s*\((확인|검증) 완료\)", ""), (r" (확인|검증) 완료 →", " →"),
    (r"실제 GUI 확인", "GUI에서 확인"), (r"실기 (확인|검증) 완료", "보드에서 확인"), (r"(확인|검증) 완료", "확인"),
    (r"^(값의 )?근거$", "확인 방법"), (r"^원본$", "문서"), (r"^대조 내용$", "내용"), (r"원본 대조 내용", "참고 내용"), (r"분석 가정 기반 추정값, 실측 아님", "분석 가정 기반 추정값"),
    (r"점멸 실기 확인", "점멸 확인"),
    (r"클릭하면 원본 크기로 확대", "클릭하면 확대"), (r"이미지 클릭 시 원본 확대", "클릭하면 확대"),
    (r"원본 크기로 (열립니다|확대)", "크게 열립니다"), (r"원본 그림 크게 보기", "그림 크게 보기"),
    (r"원본 회로도 확대", "회로도 크게 보기"), (r"원본 (보기|확대)", "크게 보기"),
    (r"원문 기준:\s*", ""), (r"\s*\(원문\)", ""),
    (r"검증된 main\.c 전체 원본", "main.c 전체"), (r"main\.c 전체 원본", "main.c 전체"), (r"main\.c 원본 (소스|코드)", r"main.c 전체 \1"),
    (r"원본 C 코드 (보기|작성)", r"C 코드 \1"), (r"원본 C 예제", "C 예제"), (r"원본 전체 코드", "전체 코드"),
    (r"(아래의|SECTION \d+의) 원본 코드", r"\1 코드"), (r"내용이 동일한 원본 코드", "같은 내용의 코드"), (r"원본 코드", "전체 코드"),
    (r"실습 소스 원본", "실습 소스"), (r"Basys3 XDC — 필요한 줄만 원본에서 활성화", "Basys3 XDC — 필요한 줄만 Master XDC에서 활성화"),
    (r"(\d+장) 원본 (HW|하드웨어)", r"\1 기존 하드웨어"), (r"(\d+장) 원본 (프로젝트|폴더|XSA|C 소스)", r"\1 \2"),
    (r"(\d+장) 원본 · 보존", r"\1 · 유지"), (r"(\d+장) 원본(은|을|이|과|의)?", r"\1 프로젝트\2"),
    (r"원본 (Block Design|SoC 프로젝트|프로젝트)", r"기존 \1"), (r"원본 폴더", "이전 장 폴더"), (r"원본 소스 삭제", "소스 삭제"),
    (r"AMD 원본은", "AMD 예제는"), (r"AMD 원본 · ", "AMD · "), (r"AMD 원본 및 이전 실습", "참고 문서 · 이전 실습"),
    (r"AMD 공식 원본", "AMD 공식 문서"), (r"원본 (IP 설정 화면|주소 맵|그림|설명:|예제값)", r"\1"),
    (r"공식 매뉴얼 및 원본 근거", "참고 문서"), (r"AMD 문서 및 소스 근거", "참고 문서"), (r"공식 기술 문서와 파형 출처", "참고 문서 · 파형"),
    (r"기존 공식 쓰기·읽기 타이밍 파형 원본", "공식 쓰기·읽기 타이밍 파형"),
    (r"실제 검증 캡처 · ", ""), (r"실제 GUI (\d+)", r"GUI \1"), (r"(\d+장) 실기 성공 화면", r"\1 실행 화면"),
    (r"실기 성공 (화면|프로젝트)", r"실행 \1"), (r"실제 Echo 성공 화면", "Echo 실행 화면"),
    (r"실행 성공 화면", "실행 화면"), (r"성공 캡처", "실행 화면"),
    (r"(에서|이미) (정상 )?검증(된|한) ", r"\1 만든 "), (r"(정상 )?검증(된|한) ", ""), (r"실기 검증 및 오류 점검", "결과 확인 및 오류 점검"),
    (r"선택 참고·추가 검증", "선택 실습"), (r"선택 검증", "선택 실습"), (r"실제 Debug Watch 검증값", "Debug Watch 확인값"),
    (r"최종 검증 아님", "초기 상태"), (r"재검증", "다시 확인"), (r"검증", "확인"),
]
REPLACE = [(re.compile(a), b) for a, b in REPLACE]

# 2) 문장 지우기 — 이 문장 자체가 제작·검증 기록이면 삭제
META = re.compile("|".join([
    r"실기", r"(확인|검증) (완료|상태|범위|경계|기록)", r"정상 (확인|검증)", r"확인해야 완료",
    r"계측", r"실측", r"추정값", r"LOW confidence",
    r"캡처(가|는)? 아니", r"캡처로 (확인|검증)", r"스크린샷이 아니", r"공식 (예시|참고 도판|참고 그림)", r"재구성한", r"성공 사례", r"성공 화면이 아니",
    r"출처", r"근거", r"원본", r"원문", r"이관", r"재작성", r"GitHub",
    r"별도 (확장 )?확인 항목", r"성과로 기록", r"실행하지 않았", r"취급하지 않",
    r"확인되지 않았", r"관찰값은", r"예상값이지", r"예상값으로 표시", r"설정상 값이고", r"유도한 값", r"외부 이미지", r"PDF \d", r"기존 교재",
    r"당시 실제", r"후속 (확인|검증)한", r"이번 캡처", r"중간 캡처", r"기존 (확인|검증) 과정", r"성공 결과입니다", r"타이밍 결과가 아닙니다",
    r"아직 확인", r"확인한 결과는 아니", r"결과는 아니", r"신호가 아니", r"전력이 아닙니다", r"측정기로", r"측정하지 않", r"Watch 변수값은",
    r"성공 실측값", r"최종 캡처", r"(과|와)는 (구분|구별)", r"(은|는) 구별합니다", r"(과|와) 구별합니다", r"라고 단정", r"확인하기 전에 단정", r"수행하지 않았",
]))
# 3) 통째로 지우는 요소
DROP_SEL = ["nav.chapter-nav", "div.chapter-nav", "nav.lab-jump", "footer", "div.overview-card", "div.chapter-phase",
            "p.label-current", "p.pending", "p.source-small", "p.source-link", "div.section-top", "span.step",
            "button", "script", "style", "form"]
INTERNAL = re.compile(r"^legacy/(validation|manifests|docs)/|source_viewer\.html\?file=(validation|manifests|docs)%2F")
BLOCKS = {"p", "div", "ol", "ul", "figure", "pre", "table", "section", "details", "h3", "h4", "blockquote"}
TEXT_BLOCKS = ["h2", "h3", "h4", "p", "li", "figcaption", "summary", "th", "td", "div", "strong", "span", "b", "small"]

removed: dict[str, list[str]] = {}
SOURCES: dict[str, dict[str, str]] = {}            # 장 id → {slug: part01 기준 경로} (본문에서 링크한 실습 파일)
PAGE_CH = {c["file"]: c for c in CHS}
LANG = {".c": "C", ".h": "C", ".v": "Verilog", ".sv": "SystemVerilog", ".xdc": "XDC", ".tcl": "Tcl", ".py": "Python", ".sh": "Shell"}
broken: list[str] = []


def clean_text(s):
    for pat, rep in REPLACE:
        s = pat.sub(rep, s)
    return s


SENT = re.compile(r"(?<=[다요음함됨임]\.)\s+|(?<=니다\.)\s*|(?<=\.)\s+(?=[가-힣])|(?<=[가-힣]\.)\s+(?=[A-Z])")


def prune_sentences(el, page):
    """블록 안 문장 중 제작·검증 메모를 지운다. 태그를 품은 문장도 HTML 단위로 다룬다."""
    inner = el.decode_contents()
    if not inner.strip():
        return
    parts, buf = [], ""
    for m in re.finditer(r"<[^>]+>|[^<]+", inner):
        tok = m.group(0)
        if tok.startswith("<"):
            buf += tok
            if re.match(r"</(strong|b)>", tok):   # 굵은 꼬리표 뒤는 문장 경계로 본다
                parts.append(buf)
                buf = ""
            continue
        pieces = SENT.split(tok)
        for k, p in enumerate(pieces):
            buf += p
            if k < len(pieces) - 1:
                parts.append(buf)
                buf = ""
    parts.append(buf)
    keep, cut = [], []
    for p in parts:
        t = html.unescape(re.sub(r"<[^>]+>", "", p)).strip()
        if t and META.search(t):
            cut.append(t)
        else:
            keep.append(p)
    if cut:
        removed.setdefault(page, []).extend(cut)
        new = " ".join(x.strip() for x in keep if x.strip())
        frag = BeautifulSoup(new, "html.parser")
        el.clear()
        for ch in list(frag.contents):
            el.append(ch)


def is_leaf_block(el):
    return not any(isinstance(c, Tag) and c.name in BLOCKS | {"li", "figcaption", "h2"} for c in el.descendants)


# ── 링크 ───────────────────────────────────────────────────────────────────
def new_url(raw, src_dir, tag, page):
    u = html.unescape(raw).strip()
    g = GITHUB_SOC.match(u)
    if g and os.path.exists(os.path.join(P1, "legacy", g.group(1))):
        u = os.path.relpath(os.path.join(P1, "legacy", g.group(1)), src_dir)
    if not u or u.startswith("#") or re.match(r"^[a-z][a-z0-9+.-]*:|^//", u, re.I):
        return u
    sp = urlsplit(u)
    if not sp.path:
        return u
    tgt = os.path.normpath(os.path.join(src_dir, unquote(sp.path)))
    frag = "#" + sp.fragment if sp.fragment else ""
    if not tgt.startswith(P1 + os.sep) or not os.path.exists(tgt):
        broken.append(f"{page}: {raw}")
        return u
    if tgt in BY_SRC:
        return BY_SRC[tgt]["file"] + frag
    rel = os.path.relpath(tgt, P1).replace(os.sep, "/")
    lrel = os.path.relpath(tgt, os.path.join(P1, "legacy")).replace(os.sep, "/")
    if tag == "a" and TEXT_EXT.search(rel) and re.match(r"^(legacy/code|files)/", rel) and not sp.query:
        slug = re.sub(r"[^A-Za-z0-9]+", "_", re.sub(r"^(legacy/code|files)/", "", rel)).strip("_")
        SOURCES.setdefault(PAGE_CH[page]["id"], {}).setdefault(slug, rel)
        return f"SRC::{slug}"
    if tag == "a" and re.match(r"^(code|docs|validation)/", lrel) and TEXT_EXT.search(lrel) and not sp.query:
        return "legacy/source_viewer.html?file=" + quote(lrel, safe="") + frag
    return quote(rel, safe="/") + ("?" + sp.query if sp.query else "") + frag


# ── 페이지 변환 ─────────────────────────────────────────────────────────────
def counts(node):
    return {k: len(node.select(k)) for k in ("img", "figure", "svg", "pre", "table", "details")}


def convert(c):
    src = os.path.join(P1, c["source"])
    soup = BeautifulSoup(rd(src), "lxml")
    page = c["file"]
    hero = soup.select_one(".hero")
    main = soup.find("main")
    for x in main.find_all(string=lambda t: isinstance(t, Comment)):
        x.extract()
    for sel in DROP_SEL:
        for e in main.select(sel):
            e.decompose()
    before = counts(main)
    src_dir = os.path.dirname(src)

    # 링크 다시 계산, 내부 기록(검증 로그·manifest) 링크는 지움
    for a in main.find_all(["a", "img", "source"]):
        for attr in ("href", "src"):
            if a.get(attr):
                a[attr] = new_url(a[attr], src_dir, a.name, page)
        if a.name == "a" and a.get("href") and INTERNAL.search(a["href"]):
            removed.setdefault(page, []).append("[링크] " + a.get_text(" ", strip=True))
            a.decompose()
    for a in main.find_all("a", href=re.compile(r"^legacy/index\.html")):
        a.decompose()
    for p in main.find_all("p"):
        if p.find("a") and re.fullmatch(r"[\s·←→]*", re.sub(r"(?s)<a\b.*?</a>", "", p.decode_contents())) \
                and all(a.get("href", "").startswith("p1_") for a in p.find_all("a")) and re.search(r"[←→]", p.get_text()):
            p.decompose()
    # 그림 링크: 이미지 파일로 넘어가지 않고 쪽 안에서 확대 (아래 ZOOM 스크립트)
    IMG = re.compile(r"\.(webp|png|jpe?g|gif|svg|avif)$", re.I)
    for a in main.find_all("a"):
        href = a.get("href", "")
        if href.startswith(("http", "#")) or not IMG.search(href.split("#")[0]):
            continue
        if a.find("img"):
            a.unwrap()
        else:
            a.decompose()
    for img in main.find_all("img"):
        img["class"] = ["zoom"]
    for cap in main.find_all("figcaption"):
        for t in cap.find_all(string=True):
            t.replace_with(re.sub(r"(\s*·\s*)+$", "", str(t)))
    for img in main.find_all("img"):
        img.attrs.pop("onerror", None)
        img["loading"] = "lazy"
    for sp in main.select("span.img-fallback"):
        sp.decompose()

    # 코드: code-head 제목을 코드 박스 이름으로, codebox 껍데기 제거
    for pre in main.find_all("pre"):
        label = ""
        prev = pre.find_previous_sibling()
        if prev is not None and "code-head" in (prev.get("class") or []):
            label = prev.get_text(" ", strip=True).replace("코드 복사", "").strip()
            prev.decompose()
        label = label or pre.get("aria-label") or ""
        if not label:
            code = pre.get_text()
            label = "C" if re.search(r"#include|\bint main\b|\bu32\b", code) else (
                "XDC" if "set_property" in code or "create_clock" in code else (
                    "Tcl" if re.search(r"\b(get_files|make_wrapper|report_\w+|update_compile_order)\b", code) else "명령·출력"))
        label = clean_text(label)
        if pre.parent and "codebox" in (pre.parent.get("class") or []):
            pre.parent.unwrap()
        box = soup.new_tag("div", attrs={"class": "codeblock"})
        bar = soup.new_tag("div", attrs={"class": "codebar"})
        sp = soup.new_tag("span")
        sp.string = label
        bar.append(sp)
        pre.wrap(box)
        box.insert(0, bar)
        pre.attrs = {"tabindex": "0"}

    # 클래스 정리: 공통 구성요소로 통일
    for e in list(main.find_all(True)):
        if e.find_parent("svg") or e.name == "svg":
            continue
        cl = set(e.get("class") or [])
        name = e.name
        new = None
        if name == "figure":
            new = ["fig"]
        elif cl & {"gui-gallery", "soc10-shot-group"}:
            new = ["fig-grid"]
        elif cl & {"table-wrap", "tablewrap", "wide-code"} and name == "div" and "codeblock" not in cl:
            if e.find("table"):
                new = ["table-wrap"]
                e["tabindex"] = "0"
                e["aria-label"] = "표 (가로 스크롤 가능)"
            else:
                e.unwrap()
                continue
        elif cl & {"flow", "signal-map", "math", "bitline"}:
            new = ["flow"]
        elif cl & {"warn", "warning"}:
            new = ["callout", "warn"]
        elif cl & {"explain", "note", "ok", "key-result", "result", "lesson-check", "step-result", "goal", "lesson-goal", "gate", "success"}:
            new = ["callout"]
        elif cl & {"memory-demo", "lab-mini"}:
            new = ["cards"]
        elif cl & {"section-lead", "lesson-lead"}:
            new = ["lead"]
        elif cl & {"minor"}:
            new = ["minor"]
        elif cl & {"codeblock", "codebar", "gui-walkthrough"}:
            new = sorted(cl & {"codeblock", "codebar", "gui-walkthrough"})
        if e.name == "img":
            new = ["zoom"]
        if new:
            e["class"] = new
        else:
            e.attrs.pop("class", None)
        for k in list(e.attrs):
            if k.startswith("data-") or k in ("style", "onclick") or (k == "role" and e.get("class") != ["table-wrap"]):
                e.attrs.pop(k, None)
        if e.get("class") == ["table-wrap"]:
            e["role"] = "region"

    # 절 구성: 최상위 절만 남기고, 절 밖의 낱개 요소는 앞 절(없으면 개요)에 붙임
    sections, loose_head = [], []
    for ch in list(main.children):
        if isinstance(ch, NavigableString):
            continue
        if ch.name == "section":
            sections.append(ch)
        elif sections:
            sections[-1].append(ch.extract())
        else:
            loose_head.append(ch)

    # 문장 정리 (제목·문단·목록·그림 설명·강조 상자)
    for sec in sections + loose_head:
        for t in sec.find_all(string=True):
            if not isinstance(t, Comment) and not t.find_parent(["pre", "code", "svg", "script", "style"]):
                t.replace_with(clean_text(str(t)))
        for e in sec.find_all(["p", "li", "figcaption", "div"]):
            if e.find_parent(["pre", "svg"]):
                continue
            if e.name == "div" and "callout" not in (e.get("class") or []):
                continue
            if is_leaf_block(e):
                prune_sentences(e, page)

    # 비어버린 블록·라벨만 남은 상자 지우기
    def text_len(e):
        return len(e.get_text(" ", strip=True))
    for sec in sections + loose_head:
        for e in reversed(sec.find_all(["p", "li", "figcaption", "div", "strong", "b", "span", "small", "h3"])):
            if e.find(["img", "svg", "pre", "table", "figure"]):
                continue
            cls = e.get("class") or []
            if text_len(e) == 0 or ("callout" in cls and text_len(e) < 14):
                if text_len(e):
                    removed.setdefault(page, []).append("[짧은 상자] " + e.get_text(" ", strip=True))
                e.decompose()
        for ol in sec.find_all(["ol", "ul"]):
            if not ol.find("li"):
                ol.decompose()

    # 새 문서
    out, n = [], 0
    for sec in sections:
        h2 = sec.find("h2")
        title = h2.get_text(" ", strip=True) if h2 else "실습"
        title = re.sub(r"^\s*(SECTION|STEP)\s*\d+\s*", "", title)
        body = copy.copy(sec)
        bh = body.find("h2")
        if bh:
            bh.decompose()
        if not body.get_text(strip=True) and not body.find(["img", "svg", "pre", "table"]):
            removed.setdefault(page, []).append("[빈 절] " + title)
            continue
        n += 1
        sid = sec.get("id") or f"s{n:02d}"
        out.append(f'    <section class="section" id="{sid}">\n      <h2><span class="num">{n:02d}</span>{html.escape(title)}</h2>\n'
                   + body.decode_contents().strip() + "\n    </section>")
    desc = ""
    if hero:
        p = hero.select_one("p.hero-desc") or hero.find("p")
        desc = clean_text(p.get_text(" ", strip=True)) if p else ""
        desc = " ".join(s for s in SENT.split(desc) if s and not META.search(s))
    chips = [clean_text(x.get_text(" ", strip=True)) for x in hero.select(".chip, .chips span")] if hero else []
    chips = [x for x in chips if not META.search(x) and not re.search(r"확인|완료|기준$", x)]
    brief = [(clean_text(a.find("h2").get_text(" ", strip=True)), a.find("p")) for a in hero.select(".hero-brief article")] if hero else []
    ov = ['    <section class="section" id="overview">', '      <h2><span class="num">00</span>이 장의 목표</h2>']
    if desc:
        ov.append(f"      <p>{html.escape(desc)}</p>")
    if chips:
        ov.append('      <ul class="chips" aria-label="핵심 용어">' + "".join(f"<li>{html.escape(x)}</li>" for x in chips) + "</ul>")
    if brief:
        cards = []
        for h, p in brief:
            t = clean_text(p.get_text(" ", strip=True))
            t = " ".join(s for s in SENT.split(t) if s and not META.search(s))
            if t:
                cards.append(f"<div><b>{html.escape(h)}</b>{html.escape(t)}</div>")
        ov.append('      <div class="cards">' + "".join(cards) + "</div>")
    for e in loose_head:
        if e.get_text(strip=True) or e.find(["img", "table"]):
            ov.append("      " + str(e))
    ov.append("    </section>")
    doc = "\n".join(ov) + "\n" + "\n".join(out)
    after = counts(BeautifulSoup(doc, "html.parser"))
    return doc, before, after, desc


# ── HTML 틀 ────────────────────────────────────────────────────────────────
STYLE = """
.access-skip{position:absolute;left:-9999px;top:0}
.access-skip:focus{left:12px;top:12px;z-index:1003;background:#fff;color:#15171c;padding:6px 10px}
.vbadge{display:inline-block;padding:.15em .6em;border-radius:4px;font-size:.78em;font-weight:700;background:#d4edda;color:#155724;vertical-align:middle}
.hero p{max-width:none}
.hero h1,.section h2{overflow-wrap:anywhere}
.section :not(pre)>code{overflow-wrap:anywhere}
.section img{max-width:100%;height:auto;display:block}
.section .lead{color:var(--ink-2);font-weight:500}
.section .minor{color:var(--ink-3);font-size:.9em}
.table-wrap{overflow-x:auto;margin:12px 0}
.table-wrap th{white-space:nowrap}
.section .chips{display:flex;flex-wrap:wrap;gap:8px;margin:6px 0 14px;padding:0;list-style:none}
.chips li{border:1px solid var(--line);background:#fff;padding:3px 10px;border-radius:3px;font:500 12px "IBM Plex Mono",monospace;color:var(--ink-2);margin:0}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:12px;margin:12px 0}
.cards>div{border:1px solid var(--line);border-left:3px solid var(--accent);background:#fff;padding:12px 14px}
.cards b,.cards strong{display:block;margin-bottom:4px}
.cards small{display:block;color:var(--ink-3)}
.callout{border:1px solid #d9d3f5;border-left:4px solid var(--accent);background:#f7f5fe;padding:12px 16px;margin:14px 0}
.callout.warn{border-color:#f0d9a8;border-left-color:#b07a12;background:#fffaf0}
.callout>:first-child{margin-top:0}.callout>:last-child{margin-bottom:0}
.flow{white-space:pre-wrap;font:500 .86rem/1.7 "IBM Plex Mono",monospace;background:#fbfbf9;border:1px solid var(--line);padding:12px 16px;margin:14px 0;overflow-x:auto}
.flow code{background:none;padding:0}
.fig{margin:16px 0;border:1px solid var(--line);background:#fff;padding:10px}
.fig img,.fig svg{margin:0 auto;max-width:100%;height:auto}
.fig figcaption{font-size:.84rem;color:var(--ink-2);margin-top:8px}
.fig-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:12px;margin:14px 0}
.fig-grid .fig{margin:0}
.gui-walkthrough{border:1px solid var(--line);background:#fbfbf9;padding:12px 18px;margin:14px 0}
details{border:1px solid var(--line);background:#fff;padding:8px 14px;margin:14px 0}
summary{cursor:pointer;font-weight:600}
.codeblock pre{max-height:780px;white-space:pre}
img.zoom{cursor:zoom-in}
.zoom-view{position:fixed;inset:0;z-index:2000;background:rgba(21,23,28,.86);display:flex;align-items:center;justify-content:center;padding:24px;cursor:zoom-out}
.zoom-view img{max-width:100%;max-height:100%;background:#fff;box-shadow:0 8px 40px rgba(0,0,0,.4)}
.codebar{gap:8px}.codebar span{min-width:0;overflow-wrap:anywhere}
"""

HEAD = """<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="description" content="{meta}">
<meta name="generator" content="tools/part01/build_part01.py — 직접 수정 금지">
<title>{title}</title>
<link rel="stylesheet" href="../assets/education/site.css">
<style>{style}</style>
</head>
<body data-chapter="{chid}">
<a class="access-skip" href="#main-content">본문 바로가기</a>
<button type="button" class="mobile-menu" id="mobile-menu" aria-controls="course-nav" aria-expanded="false">☰ 장·목차</button>
<div class="shade" id="shade"></div>
<header class="hero">
  <div class="hero-inner">
    <p class="kicker">{kicker} <span class="vbadge">{ver}</span></p>
    <h1>{h1}</h1>
    <p>{desc}</p>
  </div>
</header>
<div class="wrap">
  <nav class="toc" id="course-nav" aria-label="전체 장과 절 탐색"></nav>
  <main class="content" id="main-content">
"""

FOOT = """
    <div class="chapter-links" id="chapter-links"></div>
  </main>
</div>
<script>
window.COURSE={course};
</script>
<script defer src="../assets/education/site.js"></script>
<script>
// 그림 확대: 그림을 누르면 쪽 안에서 크게 보기, 다시 누르거나 Escape로 닫기
document.addEventListener("click", (e) => {
  const img = e.target.closest("img.zoom");
  const open = document.querySelector(".zoom-view");
  if (open) { open.remove(); return; }
  if (!img) return;
  const v = document.createElement("div");
  v.className = "zoom-view";
  v.setAttribute("role", "dialog");
  v.setAttribute("aria-label", img.alt || "그림 확대");
  const big = document.createElement("img");
  big.src = img.currentSrc || img.src;
  big.alt = img.alt;
  v.append(big);
  document.body.append(v);
});
document.addEventListener("keydown", (e) => { if (e.key === "Escape") document.querySelector(".zoom-view")?.remove(); });
</script>
</body>
</html>
"""


def course_js():
    return json.dumps({"title": COURSE["title"], "chapter_select": True,
                       "chapters": [{"id": c["id"], "number": c["number"], "title": c["title"], "file": c["file"]} for c in CHS]},
                      ensure_ascii=False, indent=1)


def first_sentence(s):
    m = re.match(r"(.+?[.다])(?:\s|$)", s)
    return m.group(1) if m else s


def page_html(c, doc, desc):
    head = HEAD.format(meta=html.escape(f"Basys3 제1부 {c['number']}장 · {c['title']}"),
                       title=html.escape(f"제1부 {c['number']}장 · {c['title']} ({VER})"), style=STYLE, chid=c["id"],
                       kicker=f"BASYS3 · 제1부 MicroBlaze V 기본 SoC · {c['number']}장", ver=VER,
                       h1=html.escape(f"제1부 {c['number']}장 · {c['title']}"), desc=html.escape(first_sentence(desc)))
    return re.sub(r"/home/[A-Za-z0-9_.-]+", "~", head + doc + FOOT.replace("{course}", course_js()))


def file_block(slug, rel):
    name = os.path.basename(rel)
    code = re.sub(r"/home/[A-Za-z0-9_.-]+", "~", rd(os.path.join(P1, rel)))
    lang = LANG.get(os.path.splitext(name)[1].lower(), "텍스트")
    return (f'<div class="codeblock" id="f-{slug}"><div class="codebar"><span>{html.escape(name)} · {lang}</span></div>'
            f'<pre tabindex="0"><code>{html.escape(code)}</code></pre></div>')


def norm(s):
    return re.sub(r"\s+", "", s)


def attach_sources(c, doc):
    """본문의 실습 파일 링크(SRC::slug)를 화면 안 코드로 잇는다.
    묶음 쪽이 있는 장(11장)은 묶음 쪽으로, 나머지는 같은 쪽의 같은 코드 박스, 없으면 끝의 '실습 파일' 절로."""
    files = SOURCES.get(c["id"], {})
    if not files:
        return doc
    if c["id"] in BUNDLE:
        b = BUNDLE[c["id"]]["file"]
        soup = BeautifulSoup(doc, "html.parser")
        # 링크만 늘어놓은 문단은 파일 표로 바꿔 무엇을 여는지 분명히 한다
        for p in soup.find_all("p"):
            src = [a for a in p.find_all("a") if a.get("href", "").startswith("SRC::")]
            if len(src) < 3:
                continue
            other = [a for a in p.find_all("a") if a not in src]
            rows = "".join(
                f'<tr><td><a href="{b}#f-{a["href"][5:]}"><code>{html.escape(os.path.basename(files[a["href"][5:]]))}</code></a></td>'
                f'<td>{html.escape(re.sub(r"저장소 ", "", a.get_text(" ", strip=True)))}</td></tr>' for a in src)
            new = BeautifulSoup(
                (f'<p>{"".join(str(o) for o in other)} · 파일 전체: <a href="{b}">{html.escape(BUNDLE[c["id"]]["number"])} {html.escape(BUNDLE[c["id"]]["title"])}</a></p>' if other else "")
                + '<div class="table-wrap" tabindex="0" role="region" aria-label="표 (가로 스크롤 가능)"><table><thead><tr><th>파일</th><th>내용</th></tr></thead><tbody>'
                + rows + "</tbody></table></div>", "html.parser")
            p.replace_with(new)
        doc = str(soup)
        return re.sub(r"SRC::([A-Za-z0-9_]+)", lambda m: f"{b}#f-{m.group(1)}", doc)
    soup = BeautifulSoup(doc, "html.parser")
    extra = []
    for slug, rel in files.items():
        code = norm(rd(os.path.join(P1, rel)))
        box = next((pre.find_parent("div", class_="codeblock") for pre in soup.find_all("pre") if norm(pre.get_text()) == code), None)
        if box is not None and not box.get("id"):
            box["id"] = f"f-{slug}"
        elif box is None:
            extra.append(file_block(slug, rel))
    doc = str(soup)
    if extra:
        n = len(re.findall(r'<section class="section"', doc))
        doc += (f'\n    <section class="section" id="files">\n      <h2><span class="num">{n:02d}</span>실습 파일</h2>\n      '
                + "\n      ".join(extra) + "\n    </section>")
    return re.sub(r"SRC::([A-Za-z0-9_]+)", r"#f-\1", doc)


def bundle_html(b):
    owner = next(c for c in CHS if c["id"] == b["bundle_of"])
    files = SOURCES.get(owner["id"], {})
    secs = []
    def order(item):   # 이 장 파일(Top → XDC → C) 먼저, 이전 장 참고 파일은 뒤
        rel = item[1]
        return (rel.startswith("legacy/"), {".v": 0, ".xdc": 1, ".c": 2}.get(os.path.splitext(rel)[1], 3))
    for i, (slug, rel) in enumerate(sorted(files.items(), key=order)):
        name = os.path.basename(rel)
        m = re.match(r"legacy/code/soc(\d+)/", rel)
        title = f"{m.group(1)}장 {name} (참고)" if m else name
        lang = LANG.get(os.path.splitext(name)[1].lower(), "텍스트")
        secs.append(f'    <section class="section" id="s-{slug}">\n      <h2><span class="num">{i:02d}</span>{html.escape(title)}</h2>\n'
                    f'      <p>{lang} · {rd(os.path.join(P1, rel)).count(chr(10))}줄</p>\n      {file_block(slug, rel)}\n    </section>')
    doc = "\n".join(secs)
    head = HEAD.format(meta=html.escape(f"Basys3 제1부 {b['number']}장 · {b['title']}"), title=html.escape(f"제1부 {b['number']}장 · {b['title']} ({VER})"),
                       style=STYLE, chid=b["id"], kicker=f"BASYS3 · 제1부 MicroBlaze V 기본 SoC · {b['number']}장", ver=VER,
                       h1=html.escape(f"제1부 {b['number']}장 · {owner['title']} {b['title']}"),
                       desc=html.escape(f"{owner['number']}장 실습에 쓰는 소스·제약 파일 {len(files)}개"))
    return head + doc + FOOT.replace("{course}", course_js())


def index_html(descs):
    by = {c["id"]: c for c in CHS}
    rows = []
    for g in COURSE["groups"]:
        rows.append(f"      <h3>{html.escape(g['title'])}</h3>")
        rows.append('      <div class="table-wrap" tabindex="0" role="region" aria-label="표 (가로 스크롤 가능)"><table>')
        rows.append("        <thead><tr><th>장</th><th>제목</th><th>학습 내용</th></tr></thead><tbody>")
        for cid in g["chapters"]:
            c = by[cid]
            rows.append(f'          <tr><td>{c["number"]}</td><td><a href="{c["file"]}">{html.escape(c["title"])}</a></td><td>{html.escape(descs[cid])}</td></tr>')
        rows.append("        </tbody></table></div>")
    doc = f"""    <section class="section" id="intro">
      <h2><span class="num">00</span>학습 흐름</h2>
      <p>Basys3 위에 MicroBlaze V CPU와 Local BRAM으로 가장 작은 SoC를 만들고, AXI 주변장치를 하나씩 붙여 GPIO·UART·Timer·Interrupt를 다루는 SoC로 키웁니다. 11장에서 사용자 Top을 연결해 제1부의 SoC를 완성합니다.</p>
      <div class="flow">01~05장  MicroBlaze V · BRAM · Clock/Reset · Memory Map · AXI
   ↓
06~09장  AXI GPIO · UART Lite · Timer · Interrupt Controller   (07.1~09.1 C 코드 풀이)
   ↓
10장     GPIO · UART · Timer 통합   (10.1 C 코드 풀이)
   ↓
11장     사용자 Top과 1비트 GPIO</div>
      <p>각 장은 앞 장의 Vivado·Vitis 프로젝트를 새 이름으로 복제해 이어서 만듭니다. 앞 장 프로젝트는 그대로 둡니다.</p>
    </section>
    <section class="section" id="chapters">
      <h2><span class="num">01</span>장별 바로가기</h2>
{chr(10).join(rows)}
    </section>
    <section class="section" id="env">
      <h2><span class="num">02</span>실습 환경</h2>
      <div class="table-wrap" tabindex="0" role="region" aria-label="표 (가로 스크롤 가능)"><table>
        <thead><tr><th>항목</th><th>내용</th></tr></thead><tbody>
          <tr><td>보드</td><td>Digilent Basys3 (Artix-7 XC7A35T · 100 MHz 클록 W5 · 리셋 btnC U18)</td></tr>
          <tr><td>도구</td><td>Vivado 2024.2 · Vitis Unified IDE 2024.2 · 시리얼 터미널(moserial)</td></tr>
          <tr><td>작업 폴더</td><td><code>~/soc/hw</code> (Vivado 프로젝트) · <code>~/soc/sw</code> (Vitis Workspace)</td></tr>
          <tr><td>UART</td><td>115200 bps · 8N1</td></tr>
        </tbody></table></div>
    </section>"""
    head = HEAD.format(meta="Basys3 MicroBlaze V 기본 SoC 제1부 01~11장 학습안내서", title=html.escape(f"{COURSE['title']} ({VER})"),
                       style=STYLE, chid="p1-index", kicker="BASYS3 · PART 01 · CHAPTER 01–11", ver=VER,
                       h1="제1부 · MicroBlaze V 기본 SoC", desc="CPU·BRAM·AXI 주변장치 구축에서 사용자 Top 연결까지")
    return head + doc + FOOT.replace("{course}", course_js())


def edit_log(summary):
    out = ["# 제1부 안내서 편집 기록 (자동 생성 · 배포 본문 아님)", "",
           "`python3 tools/part01/build_part01.py`가 이관 원본(`part01/legacy/pages/soc/`, `part01/chapters/`)에서 배포용 안내서를 만들 때",
           "그림·표·코드 개수를 대조하고, 지운 제작·검증 메모를 여기에 남긴다.", "",
           "| 장 | 파일 | img | figure | svg | pre | table | details | 지운 문장 |", "|---|---|---|---|---|---|---|---|---|"]
    for c in CHS:
        if c["id"] not in summary:
            continue
        b, a = summary[c["id"]]
        out.append(f"| {c['number']} | {c['file']} | " + " | ".join(f"{b[k]}→{a[k]}" for k in b) + f" | {len(removed.get(c['file'], []))} |")
    out += ["", f"깨진 상대 링크: {len(broken)}개", ""]
    for c in CHS:
        r = removed.get(c["file"], [])
        if r:
            out += [f"## {c['number']} {c['title']}", ""] + [f"- {x}" for x in r] + [""]
    return "\n".join(out)


def main(check):
    outputs, summary, fails, descs = {}, {}, [], {}
    for c in CHS:
        if not c.get("source"):
            continue
        doc, before, after, desc = convert(c)
        doc = attach_sources(c, doc)
        summary[c["id"]] = (before, after)
        descs[c["id"]] = first_sentence(desc)
        outputs[os.path.join("part01", c["file"])] = page_html(c, doc, desc)
        for k in ("img", "svg", "pre", "table"):
            if before[k] != after[k]:
                fails.append(f"{c['file']}: {k} 개수 {before[k]} → {after[k]}")
    for b in BUNDLE.values():
        outputs[os.path.join("part01", b["file"])] = bundle_html(b)
        descs[b["id"]] = f"{b['bundle_of'][3:]}장 Top·C·XDC 파일을 한 쪽에서 보기"
    outputs[os.path.join("part01", "index.html")] = index_html(descs)
    outputs[os.path.join("docs", "PART01_EDIT_LOG.md")] = edit_log(summary)
    fails += [f"깨진 링크 {x}" for x in broken]
    keep = {c["file"] for c in CHS}
    stale = [f for f in os.listdir(P1) if re.match(r"p1_(.*_v\d+|src_.*)\.html$", f) and f not in keep]
    old_docs = [p for p in ("docs/PART01_MIGRATION.md",) if os.path.exists(os.path.join(ROOT, p))]
    if check:
        fails += [f"{p} 갱신 필요" for p, t in outputs.items()
                  if not os.path.exists(os.path.join(ROOT, p)) or rd(os.path.join(ROOT, p)) != t]
        fails += [f"{p} 삭제 필요" for p in ["part01/" + s for s in stale] + old_docs]
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
    for p in ["part01/" + s for s in stale] + old_docs:
        os.remove(os.path.join(ROOT, p))
    print(f"PART01_BUILT chapters={len(CHS)} removed_files={len(stale) + len(old_docs)} "
          f"removed_sentences={sum(map(len, removed.values()))}")
    return 0


if __name__ == "__main__":
    sys.exit(main("--check" in sys.argv))
