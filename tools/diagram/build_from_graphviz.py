#!/usr/bin/env python3
"""Graphviz 자동 배치 SVG(대각선·곡선 연결)를 flowchart 규칙(rule_md common/flowchart-rules.md 4·14절)에 맞춘
svg-flow-editor 도면으로 다시 그린다.

  python3 tools/diagram/build_from_graphviz.py part02            # partNN/diagrams/*.json(원본)·*.svg(산출물)
  python3 tools/diagram/build_from_graphviz.py part02 --check    # 원본에서 다시 만든 JSON이 디스크와 다르면 exit 1

- 노드·연결·문구·채움색은 원본 Graphviz SVG(학습자가 보던 그림)에서 그대로 가져온다. 새 노드·연결을 만들지 않는다.
- 배치: Graphviz 순위(rank)를 그대로 쓰고, 같은 순위 안의 순서도 유지한다. 방향(LR/TD)은 원본 Mermaid 머리말을 따른다.
- 연결: 수평·수직 직각 경로만 쓴다. 마름모는 상·하·좌·우 꼭짓점에서만 나가고 들어온다.
  분기 2개 → 아래(주 흐름)·옆, 3개 → 좌·하·우, 4개 이상 → 아래 꼭짓점 한 줄기에서 갈라짐(14절 예외: 가독성 우선).
  되돌아가는 연결은 도면 바깥 통로(loopRight/loopLeft, 통로마다 다른 x)로 돌린다.
- SVG는 svg-flow-editor(GitHub Pages)를 Playwright로 열어 불러오기 → 도면 품질 검사(inspectDiagramQuality) 0건 →
  선이 도형을 관통하지 않는지 추가 검사 → 라벨 자리 배치(export_svg.py와 같은 규칙) → svgString() 순서로 만든다.
JSON을 편집기에서 고친 뒤에는 tools/diagram/export_svg.py로 SVG만 다시 내보낸다 (이 스크립트를 다시 돌리면 JSON이 원본에서 재생성된다).
"""
from __future__ import annotations

import hashlib
import html
import json
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from export_svg import PLACE_LABELS  # noqa: E402  (라벨 배치 규칙 공유)

EDITOR = "https://yuul-jung.github.io/svg-flow-editor/"
STROKE = "#4635B1"
FONT_MAIN, FONT_SUB = 18, 15


def rd(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


# ── Graphviz SVG 읽기 ─────────────────────────────────────────────────────
def nums(d):
    return [float(x) for x in re.findall(r"-?\d+(?:\.\d+)?", d)]


def parse_gv(path):
    t = rd(path)
    nodes, edges = {}, []
    for body in re.findall(r'<g id="node\d+" class="node">(.*?)</g>', t, re.S):
        nid = html.unescape(re.search(r"<title>(.*?)</title>", body).group(1))
        shape = re.search(r'<(path|polygon|ellipse)[^>]*?(?:\sd="([^"]+)"|\spoints="([^"]+)")', body)
        fill = (re.search(r'fill="([^"]+)"', body) or [None, "#ffffff"])[1]
        v = nums(shape.group(2) or shape.group(3) or "")
        xs, ys = v[0::2], v[1::2]
        l, r, tp, b = min(xs), max(xs), min(ys), max(ys)
        cx, cy = (l + r) / 2, (tp + b) / 2
        # 마름모: 가장 왼쪽 점이 세로 가운데에 있다
        left_pts = [ys[i] for i in range(len(xs)) if abs(xs[i] - l) < 1.5]
        diamond = bool(left_pts) and all(abs(y - cy) < (b - tp) * 0.2 for y in left_pts)
        lines = [html.unescape(x) for x in re.findall(r"<text[^>]*>(.*?)</text>", body, re.S)]
        nodes[nid] = dict(id=nid, cx=cx, cy=cy, lines=lines, diamond=diamond, fill=fill if fill != "none" else "#ffffff")
    for body in re.findall(r'<g id="edge\d+" class="edge">(.*?)</g>', t, re.S):
        a, b = html.unescape(re.search(r"<title>(.*?)</title>", body).group(1)).split("->")
        label = " ".join(html.unescape(x) for x in re.findall(r"<text[^>]*>(.*?)</text>", body, re.S)).strip()
        edges.append(dict(a=a.strip(), b=b.strip(), label=label))
    return nodes, edges


def direction(svg_path):
    mmd = os.path.splitext(svg_path)[0] + ".mmd"
    if os.path.exists(mmd):
        m = re.search(r"flowchart\s+(LR|RL|TD|TB|BT)", rd(mmd))
        if m:
            return "LR" if m.group(1) in ("LR", "RL") else "TB"
    return None


def gv_direction(nodes, edges):
    """학습자가 보던 Graphviz 그림의 실제 흐름 방향 (연결의 가로·세로 이동량 합 비교)."""
    # Graphviz는 같은 순위 노드를 한 줄(같은 y 또는 같은 x)에 놓는다 → 줄 수가 적은 축이 순위 축
    ys = {round(n["cy"] / 6) for n in nodes.values()}
    xs = {round(n["cx"] / 6) for n in nodes.values()}
    return "TB" if len(ys) < len(xs) else "LR"


# ── 배치 ──────────────────────────────────────────────────────────────────
def cluster(vals, tol):
    """좌표를 순위로 묶는다 (Graphviz는 같은 순위 노드를 같은 좌표에 둔다)."""
    out, cur = [], None
    for v in sorted(set(vals)):
        if cur is None or v - cur > tol:
            out.append(v)
        cur = v
    return lambda v: min(range(len(out)), key=lambda i: abs(out[i] - v))


# 배치 후보: (같은 순위 안 순서 기준, 교차 축 배율). 품질 검사를 처음 통과한 후보를 diagrams.json에 기록한다.
_ORDER = [("gv", 1.35), ("parent", 1.35), ("gv", 1.0), ("parent", 1.0), ("child", 1.35), ("gv", 1.9), ("parent", 1.9), ("child", 1.0)]
# 방향: 1 = 원본 Mermaid 머리말(없으면 Graphviz 줄 배치) 방향, 2 = 반대 방향 (먼저 1을 모두 시도)
VARIANTS = [(1, h, sc) for h, sc in _ORDER] + [(2, h, sc) for h, sc in _ORDER]
VARIANT = VARIANTS[0]
RANK_OVERRIDE: dict = {}


def layout(nodes, edges, sizes, mode):
    """mode: 'TB' 또는 'LR'. 순위 축(main)·교차 축(cross)으로 계산한 뒤 좌표로 바꾼다."""
    main = (lambda n: n["cy"]) if mode == "TB" else (lambda n: n["cx"])
    cross = (lambda n: n["cx"]) if mode == "TB" else (lambda n: n["cy"])
    rank_of = cluster([main(n) for n in nodes.values()], 12)
    gv_rank = {k: rank_of(main(n)) for k, n in nodes.items()}
    # 순위: Graphviz 순위 순서로 앞선 노드에서 오는 연결만 앞방향으로 보고 최장 경로로 다시 매긴다
    # (자식은 언제나 부모 바로 다음 순위 이후 → 형제 분기가 같은 순위에 모인다)
    order = sorted(nodes, key=lambda k: (gv_rank[k], cross(nodes[k])))
    pos = {k: i for i, k in enumerate(order)}
    rank = dict(gv_rank)
    for k in order:
        for e in edges:
            if e["b"] == k and pos[e["a"]] < pos[k]:
                rank[k] = max(rank[k], rank[e["a"]] + 1)
    rank.update(RANK_OVERRIDE)      # diagrams.json "ranks": 자동 순위로 선이 도형을 지나는 경우만 사람이 정한 순위
    for k, n in nodes.items():
        n["rank"] = rank[k]
    ranks = sorted({n["rank"] for n in nodes.values()})
    # main 축 크기: TB이면 높이, LR이면 너비 / cross 축 크기는 반대
    msz = lambda n: sizes[n["id"]][1] if mode == "TB" else sizes[n["id"]][0]
    csz = lambda n: sizes[n["id"]][0] if mode == "TB" else sizes[n["id"]][1]
    gap_main = 118 if mode == "TB" else 150
    gap_cross = 46 if mode == "TB" else 40
    pos_main, cur = {}, 150 if mode == "TB" else 60
    for r in ranks:
        mem = [n for n in nodes.values() if n["rank"] == r]
        span = max(msz(n) for n in mem)
        pos_main[r] = cur + span / 2
        cur += span + gap_main
    # cross: Graphviz 순서를 유지하고 비율을 살리되 겹치지 않게 민다
    allc = [cross(n) for n in nodes.values()]
    lo = min(allc)
    _, how, scale = VARIANT
    for r in ranks:
        mem = [n for n in nodes.values() if n["rank"] == r]
        if how == "gv" or r == ranks[0]:
            mem.sort(key=cross)
        else:   # 무게중심: 이미 놓인 부모(또는 Graphviz 기준 자식)의 평균 위치
            def bary(n):
                if how == "parent":
                    ps = [nodes[e["a"]] for e in edges if e["b"] == n["id"] and nodes[e["a"]]["rank"] < r and "c" in nodes[e["a"]]]
                    return (sum(p["c"] for p in ps) / len(ps) / scale + lo) if ps else cross(n)
                cs = [nodes[e["b"]] for e in edges if e["a"] == n["id"]]
                return sum(cross(c) for c in cs) / len(cs) if cs else cross(n)
            mem.sort(key=lambda n: (bary(n), cross(n)))
        edge_ = -1e9
        for n in mem:
            want = (cross(n) - lo) * scale
            c = max(want, edge_ + gap_cross + csz(n) / 2)
            n["c"] = c
            edge_ = c + csz(n) / 2
    # 곧게 펴기: 부모 하나·자식 하나로 이어진 줄은 같은 줄(교차 축 좌표)에 맞춘다 (계단 모양 방지)
    fparents = {k: [e["a"] for e in edges if e["b"] == k and nodes[e["a"]]["rank"] < nodes[k]["rank"]] for k in nodes}
    fchildren = {k: [e["b"] for e in edges if e["a"] == k and nodes[e["b"]]["rank"] > nodes[k]["rank"]] for k in nodes}
    for r in ranks:
        for n in sorted([n for n in nodes.values() if n["rank"] == r], key=lambda n: n["c"]):
            ps = fparents[n["id"]]
            if len(ps) == 1 and len(fchildren[ps[0]]) == 1:
                want = nodes[ps[0]]["c"]
                others = [o for o in nodes.values() if o["rank"] == r and o is not n]
                if all(abs(want - o["c"]) >= (csz(n) + csz(o)) / 2 + gap_cross for o in others):
                    n["c"] = want
    for n in nodes.values():
        n["m"] = pos_main[n["rank"]]
    # 좌표 정리: cross 최소 여백
    minc = min(n["c"] - csz(n) / 2 for n in nodes.values())
    off = (90 if mode == "TB" else 150) - minc
    for n in nodes.values():
        n["c"] += off
        n["x"], n["y"] = (n["c"], n["m"]) if mode == "TB" else (n["m"], n["c"])
    return cur


# 포트 이름: TB 기준 → LR로 바꿀 때 축을 바꾼다
TB2LR = {"top": "left", "bottom": "right", "left": "top", "right": "bottom"}


def route(nodes, edges, mode):
    P = (lambda p: p) if mode == "TB" else (lambda p: TB2LR[p])
    out, used = [], {}
    fwd = {}
    for i, e in enumerate(edges):
        a, b = nodes[e["a"]], nodes[e["b"]]
        if b["rank"] > a["rank"]:
            fwd.setdefault(e["a"], []).append(i)
    side = {}
    for a, idx in fwd.items():
        na = nodes[a]
        idx.sort(key=lambda i: nodes[edges[i]["b"]]["c"])
        if not na["diamond"] or len(idx) == 1 or len(idx) >= 4:
            for i in idx:
                side[i] = "bottom"
        elif len(idx) == 2:
            d = [nodes[edges[i]["b"]]["c"] - na["c"] for i in idx]
            main_i = min(range(2), key=lambda k: abs(d[k]))
            other = 1 - main_i
            side[idx[main_i]] = "bottom"
            side[idx[other]] = "right" if d[other] > 0 else "left"
            if side[idx[other]] in ("right", "left") and abs(d[other]) < 1:
                side[idx[other]] = "right"
        else:
            for i, s in zip(idx, ("left", "bottom", "right")):
                side[i] = s
    lane_r = lane_l = 0
    maxc = max(n["c"] + 0 for n in nodes.values())
    for i, e in enumerate(edges):
        a, b = nodes[e["a"]], nodes[e["b"]]
        ed = dict(id=f"e{i + 1}", **{"from": e["a"], "to": e["b"]}, label=e["label"], route="auto",
                  strokeColor=STROKE, strokeWidth=2.4, arrowSize=13, labelFont=14)
        if b["rank"] > a["rank"]:
            fp = side[i]
            ed["fp"], ed["tp"] = P(fp), P("top")
        else:   # 되돌아가는 연결 · 같은 순위 연결: 바깥 통로
            if mode == "TB":
                use_left = used.get((e["a"], "right")) or used.get((e["b"], "right"))
                if use_left:
                    lane_l += 1
                    ed.update(fp="left", tp="left", route="loopLeft")
                else:
                    lane_r += 1
                    ed.update(fp="right", tp="right", route="loopRight", laneX=0)
                    ed["_lane"] = lane_r
            else:   # LR: 아래쪽 통로로 돌아간다 (bendPoints, 직각 2회)
                lane_r += 1
                ed.update(fp="bottom", tp="bottom")
                ed["_lowlane"] = lane_r
        used[(e["a"], ed["fp"])] = True
        out.append(ed)
    return out


def channel_routes(nodes, sizes, eds, mode):
    """순위 사이 통로(channel)에 꺾임을 모아, 같은 순위 쌍을 잇는 선들이 한 줄기로 합쳐지고 갈라지게 한다.
    긴 연결(순위 2개 이상 건너뜀)은 도형을 관통하지 않는 통로를 고른다."""
    TB = mode == "TB"
    lo = lambda n: (n["y"] - sizes[n["id"]][1] / 2) if TB else (n["x"] - sizes[n["id"]][0] / 2)
    hi = lambda n: (n["y"] + sizes[n["id"]][1] / 2) if TB else (n["x"] + sizes[n["id"]][0] / 2)
    ranks = sorted({n["rank"] for n in nodes.values()})
    chan = {}
    for r0, r1 in zip(ranks, ranks[1:]):
        a = max(hi(n) for n in nodes.values() if n["rank"] == r0)
        b = min(lo(n) for n in nodes.values() if n["rank"] == r1)
        chan[r1] = round(a + min(34, (b - a) / 3))   # r1 순위 앞 통로: 앞 순위 가까이 (뒤쪽 내림 구간에 라벨 자리)
    rects = {n["id"]: (n["x"] - sizes[n["id"]][0] / 2 - 4, n["x"] + sizes[n["id"]][0] / 2 + 4,
                       n["y"] - sizes[n["id"]][1] / 2 - 4, n["y"] + sizes[n["id"]][1] / 2 + 4) for n in nodes.values()}

    def clear(pts, skip):
        for (x1, y1), (x2, y2) in zip(pts, pts[1:]):
            l, r, t, b = min(x1, x2), max(x1, x2), min(y1, y2), max(y1, y2)
            for k, (L, R, T, B) in rects.items():
                if k in skip:
                    continue
                if l < R and r > L and t < B and b > T:
                    return False
        return True

    for ed in eds:
        if ed.get("route") != "auto" or ed.get("bendPoints"):
            continue
        a, b = nodes[ed["from"]], nodes[ed["to"]]
        straight = ("bottom", "top") if TB else ("right", "left")
        if (ed["fp"], ed["tp"]) != straight or b["rank"] <= a["rank"]:
            continue
        s = (a["x"], a["y"] + sizes[a["id"]][1] / 2) if TB else (a["x"] + sizes[a["id"]][0] / 2, a["y"])
        t = (b["x"], b["y"] - sizes[b["id"]][1] / 2) if TB else (b["x"] - sizes[b["id"]][0] / 2, b["y"])
        if (TB and abs(s[0] - t[0]) < 1) or (not TB and abs(s[1] - t[1]) < 1):
            continue
        cands = [chan[b["rank"]]]
        nxt = [r for r in ranks if r > a["rank"]][0]
        if chan[nxt] != cands[0]:
            cands.append(chan[nxt])
        cands += [chan[r] for r in ranks if a["rank"] < r < b["rank"] and chan[r] not in cands]
        done = False
        for c in cands:
            bends = [[round(s[0]), c], [round(t[0]), c]] if TB else [[c, round(s[1])], [c, round(t[1])]]
            if clear([s] + bends + [t], {a["id"], b["id"]}):
                ed["bendPoints"] = bends
                done = True
                break
        if not done:
            ed["_needlane"] = True


# ── 브라우저(편집기)에서 크기 재기·검사·내보내기 ─────────────────────────
SEG_THROUGH = r"""() => {
  const bad = [];
  const rects = scene.nodes.map(n => ({id: n.id, l: n.x - n.w/2 + 2, r: n.x + n.w/2 - 2, t: n.y - n.h/2 + 2, b: n.y + n.h/2 - 2}));
  for (const e of scene.edges) {
    const p = edgePath(e) || [];
    for (let i = 1; i < p.length; i++) {
      const [x1, y1] = p[i-1], [x2, y2] = p[i];
      const l = Math.min(x1, x2), r = Math.max(x1, x2), t = Math.min(y1, y2), b = Math.max(y1, y2);
      for (const q of rects) {
        if (q.id === e.from || q.id === e.to) continue;
        if (l < q.r && r > q.l && t < q.b && b > q.t) bad.push('선이 도형 관통: ' + e.id + ' → ' + q.id);
      }
    }
  }
  return bad;
}"""


def build(pg, svg_path, out_base, title, mode_hint):
    nodes, edges = parse_gv(svg_path)
    mode = mode_hint or direction(svg_path) or gv_direction(nodes, edges)
    if VARIANT[0] == 2:
        mode = "LR" if mode == "TB" else "TB"
    sizes = {}
    for n in nodes.values():
        main_t, sub_t = n["lines"][0] if n["lines"] else n["id"], " · ".join(n["lines"][1:])
        n["title"], n["sub"] = main_t, sub_t
        w1 = pg.evaluate("([t,f,w])=>measureFlowText(t,f,w)", [main_t, FONT_MAIN, "700"])
        w2 = pg.evaluate("([t,f,w])=>measureFlowText(t,f,w)", [sub_t, FONT_SUB, "400"]) if sub_t else 0
        tw = max(w1, w2)
        if n["diamond"]:
            sizes[n["id"]] = (round(tw * 1.55 + 70), 104 if sub_t else 92)
        else:
            sizes[n["id"]] = (round(max(tw + 36, 150)), 76 if sub_t else 56)
    end = layout(nodes, edges, sizes, mode)
    eds = route(nodes, edges, mode)
    W = round(max(n["x"] + sizes[n["id"]][0] / 2 for n in nodes.values()) + 90)
    H = round(max(n["y"] + sizes[n["id"]][1] / 2 for n in nodes.values()) + 70)
    # 통로 좌표
    for ed in eds:
        if "_lane" in ed:
            ed["laneX"] = W - 40 + ed.pop("_lane") * 34
        if "_lowlane" in ed:
            k = ed.pop("_lowlane")
            a, b = nodes[ed["from"]], nodes[ed["to"]]
            y = H - 20 + k * 30
            ed["bendPoints"] = [[round(a["x"]), y], [round(b["x"]), y]]
    channel_routes(nodes, sizes, eds, mode)
    for ed in eds:
        if ed.pop("_needlane", False):    # 막힌 긴 연결: 도면 바깥 통로로 (TB: 오른쪽, LR: 아래쪽)
            if mode == "TB":
                k = 1 + sum(1 for x in eds if x.get("route") == "loopRight")
                ed.update(fp="right", tp="right", route="loopRight", laneX=W - 40 + k * 34)
            else:
                k = 1 + sum(1 for x in eds if x.get("_low"))
                a, b = nodes[ed["from"]], nodes[ed["to"]]
                y = H - 20 + k * 30
                ed.update(fp="bottom", tp="bottom", bendPoints=[[round(a["x"]), y], [round(b["x"]), y]], _low=True)
    for ed in eds:
        ed.pop("_low", None)
    lanes_r = [ed["laneX"] for ed in eds if ed.get("route") == "loopRight"]
    if lanes_r:
        W = max(W, max(lanes_r) + 40)
    lowl = [ed["bendPoints"][0][1] for ed in eds if ed.get("bendPoints")]
    if lowl:
        H = max(H, max(lowl) + 36)
    scene = {
        "version": 3, "pageTitle": title, "title": title,
        "subtitle": "",
        "width": W, "height": H + 10,
        "headings": {"title": {"x": W / 2, "y": 44, "w": W - 80, "h": 50, "size": 26, "align": "left", "autoFit": True},
                     "subtitle": {"x": W / 2, "y": 90, "w": W - 80, "h": 30, "size": 15, "align": "left", "autoFit": True}},
        "settings": {"fontMain": FONT_MAIN, "fontSub": FONT_SUB, "stroke": 2.4, "gap": 40, "pad": 8, "padY": 5, "defaultPreset": "navy"},
        "nodes": [dict(id=n["id"], type="diamond" if n["diamond"] else "rect", x=round(n["x"]), y=round(n["y"]),
                       w=sizes[n["id"]][0], h=sizes[n["id"]][1], title=n["title"], sub=n["sub"], fill=n["fill"],
                       autoFit=False, textAlign="center", strokeColor="#1F3A5F", strokeWidth=2.2,
                       textColor="#172439", subTextColor="#273e5e", fontMain=FONT_MAIN, fontSub=FONT_SUB)
                  for n in nodes.values()],
        "edges": eds,
    }
    # 도면 위쪽 머리글 아래부터 시작하도록 y 보정 (TB는 150부터, LR은 cross 축 시작 150)
    js = json.dumps(scene, ensure_ascii=False, indent=1) + "\n"
    with open(out_base + ".json", "w", encoding="utf-8") as f:
        f.write(js)
    return js


def export(pg, json_path):
    pg.goto(EDITOR)
    pg.wait_for_function("typeof svgString==='function' && typeof inspectDiagramQuality==='function'")
    pg.set_input_files("#loadJSON", json_path)
    pg.wait_for_function("document.getElementById('fileStatus').textContent.includes('불러오기 완료')", timeout=10000)
    probs = pg.evaluate("inspectDiagramQuality().map(x=>x.message)") + pg.evaluate(SEG_THROUGH)
    if probs:
        return probs, None
    lab = pg.evaluate(PLACE_LABELS)
    if lab:
        return lab, None
    svg = pg.evaluate("svgString()")
    if svg.startswith("<?xml"):
        svg = svg.split("?>", 1)[1].lstrip()
    svg = re.sub(r'<rect[^>]*class="heading-hit"[^>]*/>', "", svg)   # 편집기 제목 클릭 영역 (CSS로만 투명)
    digest = hashlib.sha256(open(json_path, "rb").read()).hexdigest()
    rel = os.path.relpath(json_path, ROOT)
    svg = svg.replace(">", f"><!-- 원본: {rel} · json-sha256: {digest} · 생성: svg-flow-editor · 직접 수정 금지 -->", 1)
    return [], svg


def main():
    global VARIANT
    part = next((a for a in sys.argv[1:] if not a.startswith("-")), "part02")
    check = "--check" in sys.argv
    conf = json.loads(rd(os.path.join(ROOT, part, "diagrams.json")))
    from playwright.sync_api import sync_playwright
    fails = []
    with sync_playwright() as pw:
        b = pw.chromium.launch()
        pg = b.new_page(viewport={"width": 1600, "height": 1000})
        pg.on("dialog", lambda d: d.accept())
        pg.goto(EDITOR)
        pg.wait_for_function("typeof measureFlowText==='function'")
        for d in conf["diagrams"]:
            src = os.path.join(ROOT, part, d["source"])
            base = os.path.join(ROOT, part, "diagrams", d["name"])
            os.makedirs(os.path.dirname(base), exist_ok=True)
            old = rd(base + ".json") if os.path.exists(base + ".json") else None
            pg.goto(EDITOR)
            pg.wait_for_function("typeof measureFlowText==='function'")
            RANK_OVERRIDE.clear()
            RANK_OVERRIDE.update(d.get("ranks", {}))
            tries = [VARIANTS[d["variant"]]] if check and "variant" in d else VARIANTS
            # 후보마다 품질 검사를 하고, 통과한 후보 중 되돌림 연결 수 → 도면 넓이가 가장 작은 것을 고른다
            best = None
            for VARIANT in tries:
                pg.goto(EDITOR)
                pg.wait_for_function("typeof measureFlowText==='function'")
                js = build(pg, src, base, d["title"], d.get("mode"))
                if check:
                    break
                probs, svg = export(pg, base + ".json")
                if probs:
                    continue
                sc = json.loads(js)
                back = sum(1 for e in sc["edges"] if e.get("route", "auto") != "auto" or e["fp"] == e["tp"])
                score = (back, sc["width"] * sc["height"])
                if best is None or score < best[0]:
                    best = (score, VARIANT, js, svg)
            if not check and best:
                _, VARIANT, js, svg = best
                d["variant"] = VARIANTS.index(VARIANT)
                with open(base + ".json", "w", encoding="utf-8") as f:
                    f.write(js)
                probs = []
            if check:
                if old != js:
                    fails.append(f"{d['name']}.json 갱신 필요")
                    with open(base + ".json", "w", encoding="utf-8") as f:
                        f.write(old or "")
                continue
            if probs:
                fails.append(d["name"] + ": " + "; ".join(probs[:6]))
                continue
            with open(base + ".svg", "w", encoding="utf-8") as f:
                f.write(svg.rstrip() + "\n")
            print("DIAGRAM_PASS", d["name"])
        b.close()
    if not check:
        with open(os.path.join(ROOT, part, "diagrams.json"), "w", encoding="utf-8") as f:
            f.write(json.dumps(conf, ensure_ascii=False, indent=1) + "\n")
    for x in fails:
        print("DIAGRAM_FAIL", x)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
