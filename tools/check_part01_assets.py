#!/usr/bin/env python3
"""Audit first-part course HTML for missing local resources.

Usage: python3 tools/check_part01_assets.py
Exit status: 0 if all referenced files exist, 1 if references are missing.
Checks only the 14 distributed original chapter pages (SoC 01-10 and supplements).
No network access or dependencies required.
"""
from __future__ import annotations

import argparse
import sys
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit

PROJECT_ROOT = Path(__file__).resolve().parents[1]
HTML_DIR = Path("part01/legacy/pages/soc")


class ResourceParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.references = []

    def handle_starttag(self, tag, attrs):
        for name, value in attrs:
            if name in ("href", "src") and value:
                self.references.append((tag, name, value))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--root", type=Path, default=PROJECT_ROOT)
    ap.add_argument("--list", action="store_true", help="show each missing file")
    args = ap.parse_args()
    root = args.root.resolve()
    pages_dir = root / HTML_DIR
    if not pages_dir.is_dir():
        print(f"ERROR: no chapter directory: {pages_dir}", file=sys.stderr)
        return 2
    pages = sorted(
        p for p in pages_dir.glob("*.html")
        if p.name.startswith(tuple(f"{x:02d}_" for x in range(1, 11)))
    )
    if len(pages) != 14:
        print(f"ERROR: expected 14 original 01-10 HTML pages, found {len(pages)}", file=sys.stderr)
        return 2
    counts = Counter()
    missing = Counter()
    for page in pages:
        parser = ResourceParser()
        parser.feed(page.read_text(encoding="utf-8"))
        for tag, attr, raw in parser.references:
            u = urlsplit(raw)
            if u.scheme or u.netloc or raw.startswith("#") or raw.startswith("//"):
                continue
            if not u.path:
                continue
            destination = (page.parent / unquote(u.path)).resolve()
            if not destination.is_relative_to(root):
                print(f"ERROR: path escapes repository: {page} -> {raw}", file=sys.stderr)
                return 2
            counts["checked"] += 1
            if destination.is_file():
                counts["valid"] += 1
            else:
                counts["missing"] += 1
                missing[str(destination.relative_to(root))] += 1

    print(f"pages={len(pages)} local_references={counts['checked']} "
          f"valid={counts['valid']} broken={counts['missing']} "
          f"unique_missing={len(missing)}")
    if args.list:
        for target, uses in sorted(missing.items()):
            print(f"{uses:>3}  {target}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
