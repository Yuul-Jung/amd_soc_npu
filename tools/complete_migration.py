#!/usr/bin/env python3
"""Copy complete Part 01 legacy and Part 02 source trees without modifying source repositories.

Example:
  python3 tools/complete_migration.py --soc ../soc --amd ../amd_soc
  python3 tools/complete_migration.py --soc ../soc --amd ../amd_soc --apply --commit

Requires local Git clones with source commits available. The default mode is read-only.
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

SOC_REF = "33e6a7da5fbbf0de7e698a556db42b8eac74abd7"
AMD_MAIN_REF = "c506461e4ab0842c68e8afcaaaf605afea170463"
AMD_WORK_REF = "8068ec462793b55e1d201b5b8c08096c43c5e7e7"
SOURCE_PREFIX = "MicroBlaze_V_SoC01_41/"

def git(repo, *args):
    return subprocess.check_output(["git", "-C", str(repo), *args])

def sha_blob(data):
    hdr = b"blob " + str(len(data)).encode() + b"\x00"
    return hashlib.sha1(hdr + data).hexdigest()

def ls(repo, revision):
    for entry in git(repo, "ls-tree", "-r", "-z", revision).split(b"\x00"):
        if not entry:
            continue
        metadata, filename = entry.split(b"\t", 1)
        mode, kind, sha = metadata.decode().split()
        if kind == "blob":
            yield mode, sha, filename.decode("utf-8")

def map_soc(path):
    if path.startswith(SOURCE_PREFIX):
        return "part01/legacy/" + path[len(SOURCE_PREFIX):]
    return None

def map_main(path):
    if path.startswith("part02_v2/"):
        return "part02_1/" + path[len("part02_v2/"):]
    m = re.fullmatch(r"part02/chapters/P2_(0[1-9])_Lesson_\d+/(.+)", path)
    if m:
        return f"part02_1/ch{m[1]}/{m[2]}"
    if path.startswith("part02/P2_10_Lesson_20261106/"):
        return "part02_1/ch10/" + path.split("part02/P2_10_Lesson_20261106/", 1)[1]
    if path == "part02/chapters/P2_00_SoC_Overview.html":
        return "part02_1/P2_00_SoC_Overview.html"
    if path.startswith("part02/assets/"):
        return "part02_1/legacy_assets/" + path[len("part02/assets/"):]
    if path.startswith("part02/docs/"):
        return "part02_1/docs/" + path[len("part02/docs/"):]
    if path.startswith("part02/tests/"):
        return "part02_1/tests/" + path[len("part02/tests/"):]
    if path == "part02/README.md":
        return "part02_1/SOURCE_README.md"
    if path.startswith("rule_md/"):
        return path
    return None

def map_work(path):
    m = re.fullmatch(r"part02/chapters/P2_(1[1-9]|20)_Lesson/(.+)", path)
    if m:
        return f"part02_2/ch{m[1]}/{m[2]}"
    if path.startswith("part02/chapters/P2_11_20_Guide/"):
        return "part02_2/guide/" + path.split("P2_11_20_Guide/", 1)[1]
    if path.startswith("part02/docs/"):
        return "part02_2/docs/" + path[len("part02/docs/"):]
    if path.startswith("part02/tests/"):
        return "part02_2/tests/" + path[len("part02/tests/"):]
    if path.startswith(".github/workflows/p2-"):
        return "migration/source_workflows/" + path[len(".github/workflows/"):]
    return None

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--soc", type=Path, required=True, help="local soc clone")
    parser.add_argument("--amd", type=Path, required=True, help="local amd_soc clone")
    parser.add_argument("--dest", type=Path, default=Path("."), help="amd_soc_rtl clone")
    parser.add_argument("--apply", action="store_true", help="write missing files")
    parser.add_argument("--commit", action="store_true", help="commit verified changes")
    args = parser.parse_args()
    if args.commit and not args.apply:
        parser.error("--commit requires --apply")
    dest = args.dest.resolve()
    repos = [(args.soc.resolve(), SOC_REF, map_soc),
             (args.amd.resolve(), AMD_MAIN_REF, map_main),
             (args.amd.resolve(), AMD_WORK_REF, map_work)]
    git(dest, "rev-parse", "--is-inside-work-tree")
    for repo, ref, _ in repos:
        git(repo, "cat-file", "-e", ref + "^{commit}")

    # Read all desired paths first, before creating any destination files.
    entries = {}
    for repo, ref, mapper in repos:
        for mode, sha, source_path in ls(repo, ref):
            target_path = mapper(source_path)
            if target_path is None:
                continue
            if mode not in ("100644", "100755"):
                raise RuntimeError("unsupported source mode: " + source_path)
            if target_path in entries:
                prev = entries[target_path]
                if prev["blob_sha"] != sha:
                    raise RuntimeError("source path collision: " + target_path)
                continue
            entries[target_path] = {
                "repo": str(repo), "source_ref": ref,
                "source_path": source_path, "path": target_path,
                "blob_sha": sha, "mode": mode
            }

    pending = []
    conflicts = []
    for item in entries.values():
        target = dest / item["path"]
        if not target.resolve().is_relative_to(dest) or target.is_symlink():
            raise RuntimeError("unsafe destination: " + str(target))
        if target.exists():
            if not target.is_file() or sha_blob(target.read_bytes()) != item["blob_sha"]:
                conflicts.append(item["path"])
            continue
        pending.append(item)

    print(f"files_expected={len(entries)} existing_valid={len(entries)-len(pending)-len(conflicts)} "
          f"missing={len(pending)} conflicts={len(conflicts)}")
    if conflicts:
        print("Conflicting files (no overwrite performed):", *conflicts, sep="\n", file=sys.stderr)
        return 2
    if not args.apply:
        print("DRY RUN: no files changed. Run again with --apply --commit to copy.")
        return 0

    for item in pending:
        raw = git(item["repo"], "cat-file", "blob", item["blob_sha"])
        if sha_blob(raw) != item["blob_sha"]:
            raise RuntimeError("source hash mismatch: " + item["source_path"])
        path = dest / item["path"]
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(raw)
        if item["mode"] == "100755":
            path.chmod(path.stat().st_mode | 0o111)

    for item in entries.values():
        path = dest / item["path"]
        if not path.is_file() or sha_blob(path.read_bytes()) != item["blob_sha"]:
            raise RuntimeError("destination hash mismatch: " + item["path"])

    # Switch Part 01 main contents from GitHub blob links to self-contained local pages.
    index = dest / "part01" / "index.html"
    old_link = ("https://github.com/Yuul-Jung/soc/blob/main/"
                "MicroBlaze_V_SoC01_41/pages/soc/")
    updated = index.read_text(encoding="utf-8").replace(old_link, "legacy/pages/soc/")
    if updated == index.read_text(encoding="utf-8") and old_link in index.read_text(encoding="utf-8"):
        raise RuntimeError("failed to rewrite part01 local links")
    index.write_text(updated, encoding="utf-8")

    manifest = [
        {key: item[key] for key in ("path", "source_ref", "source_path", "blob_sha", "mode")}
        for item in sorted(entries.values(), key=lambda x: x["path"])
    ]
    manifest_path = dest / "migration" / "SOURCE_MANIFEST.json"
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                             encoding="utf-8")

    if args.commit:
        git(dest, "add", "--", "part01/index.html", "part01/legacy",
            "part02_1", "part02_2", "rule_md", "migration")
        git(dest, "commit", "-m", "migrate: copy complete Part 01 and Part 02 archives with SHA verification")

    print(f"PASS: {len(entries)} source blobs match destination; copied {len(pending)} files.")
    print("STATIC SOURCE COPY ONLY; HTML browser tests and RTL/Vivado/Vitis/board checks NOT_RUN.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
