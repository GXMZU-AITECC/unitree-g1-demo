#!/usr/bin/env python3
"""仓库内链自检：Markdown / Notebook 里的相对链接必须指得到东西。

用法：
    python3 scripts/check_links.py            # 从仓库根跑
    python3 scripts/check_links.py . --verbose

退出码：0 = 全部可达；1 = 有断链（CI 与 PR 自查都用这个）。
只检查相对路径链接（图片、文档、notebook）；http(s)/mailto/纯锚点不在此列。
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

LINK = re.compile(r"\[([^\]]*)\]\(([^)\s]+)(#[^)]*)?\)")
SKIP_DIRS = {".git", "node_modules", "__pycache__", ".venv"}


def iter_docs(root: Path):
    for path in sorted(root.rglob("*")):
        if not path.is_file() or any(part in SKIP_DIRS for part in path.parts):
            continue
        if path.suffix.lower() in {".md", ".ipynb"}:
            yield path


def md_links(text: str):
    for m in LINK.finditer(text):
        yield m.group(2)


def ipynb_links(text: str):
    try:
        nb = json.loads(text)
    except json.JSONDecodeError:
        return
    for cell in nb.get("cells", []):
        for line in cell.get("source", []):
            yield from md_links(line)


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    verbose = "--verbose" in sys.argv or "-v" in sys.argv
    root = Path(args[0] if args else ".").resolve()
    broken: list[tuple[str, int, str]] = []
    total = 0

    for doc in iter_docs(root):
        text = doc.read_text(encoding="utf-8", errors="replace")
        lines = text.splitlines()
        gen = md_links(text) if doc.suffix.lower() == ".md" else ipynb_links(text)
        for target in gen:
            if target.startswith(("http://", "https://", "mailto:", "data:", "#")):
                continue
            total += 1
            path_part = target.split("#")[0]
            if not path_part:
                continue
            resolved = (doc.parent / path_part).resolve()
            if not resolved.exists():
                line_no = next((i for i, l in enumerate(lines, 1) if f"]({target}" in l), 0)
                broken.append((str(doc.relative_to(root)), line_no, target))

    print(f"checked {total} relative link(s) in {len(list(iter_docs(root)))} document(s)")
    for src, line, target in broken:
        print(f"  BROKEN  {src}:{line or '?'} -> {target}")
    if broken:
        print(f"\n{len(broken)} broken link(s). Fix the path, or delete the link.")
        return 1
    if verbose:
        print("all relative links resolve")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
