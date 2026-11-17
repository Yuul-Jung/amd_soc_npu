#!/usr/bin/env python3
"""Two-source, byte-preserving Part 02 importer (review before committing).
Usage: python3 tools/import_remaining.py --source ../amd_soc --dest . --apply
       python3 tools/import_remaining.py --source ../amd_soc --dest . --apply --commit
Requires the source Git repository containing both pinned commits.
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

MAIN = "c506461e4ab0842c68e8afcaaaf605afea170463"
SECOND = "8068ec462793b55e1d201b5b8c08096c43c5e7e7"

def git(repo, *args):
    return subprocess.check_output(["git", "-C", str(repo), *args])

def git_sha(data):
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\\0" + data).hexdigest()

def source_entries(repo, revision):
    raw = git(repo, "ls-tree", "-r", "-z", revision)
    for record in raw.split(b"\\0"):
        if not record:
            continue
        metadata, filename = record.split(b"\\t", 1)
        mode, kind, sha = metadata.decode().split()
        if kind == "blob":
            yield (mode, sha, filename.decode("utf-8"))

def map_main(path):
    if path.startswith("part02_v2/"):
        return "part02_1/" + path[len("part02_v2/"):]
    match = re.match(r"part02/chapters/P2_(0[1-9])_Lesson_\\d+/(.*)", path)
    if match:
        return "part02_1/ch" + match.group(1) + "/" + match.group(2)
    if path.startswith("part02/P2_10_Lesson_20261106/"):
        return "part02_1/ch10/" + path.split("part02/P2_10_Lesson_20261106/", 1)[1]
    if path == "part02/chapters/P2_00_SoC_Overview.html":
        return "part02_1/P2_00_SoC_Overview.html"
    if path.startswith("part02/assets/"):
        return "part02_1/legacy_assets/" + path[len("part02/assets/"):]
    if path.startswith("rule_md/"):
        return path
    return None

def map_second(path):
    match = re.match(r"part02/chapters/P2_(1[1-9]|20)_Lesson/(.*)", path)
    if match:
        return "part02_2/ch" + match.group(1) + "/" + match.group(2)
    if path.startswith("part02/chapters/P2_11_20_Guide/"):
        return "part02_2/guide/" + path[len("part02/chapters/P2_11_20_Guide/"):]
    if path.startswith("part02/docs/"):
        return "part02_2/docs/" + path[len("part02/docs/"):]
    if path.startswith("part02/tests/"):
        return "part02_2/tests/" + path[len("part02/tests/"):]
    if path.startswith(".github/workflows/p2-"):
        return "migration/source_workflows/" + path[len(".github/workflows/"):]
    return None

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--source", required=True, type=Path, help="original amd_soc checkout")
    ap.add_argument("--dest", default=Path("."), type=Path, help="amd_soc_rtl checkout")
    ap.add_argument("--apply", action="store_true", help="copy files; default audit only")
    ap.add_argument("--commit", action="store_true", help="commit verified copied files")
    args = ap.parse_args()
    if args.commit and not args.apply:
        ap.error("--commit requires --apply")
    source, dest = args.source.resolve(), args.dest.resolve()
    if source == dest:
        ap.error("source and destination must differ")
    for ref in (MAIN, SECOND):
        git(source, "cat-file", "-e", ref + "^{commit}")
    manifest, conflicts, pending = [], [], []
    for revision, mapper in ((MAIN, map_main), (SECOND, map_second)):
        for mode, sha, old_path in source_entries(source, revision):
            new_path = mapper(old_path)
            if not new_path:
                continue
            data = git(source, "cat-file", "blob", sha)
            if git_sha(data) != sha:
                raise RuntimeError("source blob hash mismatch: " + old_path)
            target = dest / new_path
            if not target.resolve().is_relative_to(dest):
                raise RuntimeError("path escape: " + new_path)
            status = "identical" if target.is_file() and target.read_bytes() == data else (
                "CONFLICT" if target.exists() else "pending")
            if status == "CONFLICT":
                conflicts.append(new_path)
            elif status == "pending":
                pending.append((target, data, mode))
            manifest.append(dict(source_revision=revision, source_path=old_path,
                                 destination_path=new_path, blob_sha=sha, status=status))
    if conflicts:
        print("Refusing to overwrite differing files:", *conflicts, sep="\\n", file=sys.stderr)
        return 2
    if args.apply:
        for target, data, mode in pending:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            if mode == "100755":
                target.chmod(target.stat().st_mode | 0o111)
        for item in manifest:
            target = dest / item["destination_path"]
            if not target.is_file() or git_sha(target.read_bytes()) != item["blob_sha"]:
                raise RuntimeError("destination verification failure: " + str(target))
        manifest_path = dest / "migration" / "SOURCE_MANIFEST.json"
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\\n",
                                 encoding="utf-8")
        if args.commit:
            git(dest, "add", "-A", "--", "part02_1", "part02_2", "rule_md", "migration")
            git(dest, "commit", "-m", "migrate: complete binary-safe Part 02 source snapshots")
    print(json.dumps(dict(total=len(manifest), already_identical=len(manifest)-len(pending),
                          copied=len(pending) if args.apply else 0,
                          pending=0 if args.apply else len(pending),
                          conflicts=len(conflicts)), ensure_ascii=False))
    return 0

if __name__ == "__main__":
    sys.exit(main())
