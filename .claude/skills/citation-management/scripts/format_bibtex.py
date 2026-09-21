"""raw.bib 去重 + 排序 -> references.bib。

用法:
    python format_bibtex.py citations/raw.bib -o citations/references.bib

去重看「是不是同一篇文献」，依次比 DOI、标题；citation key 只作最后兜底。
同一篇被不同来源重复抓进来时，保留字段更全的那条（丢字段比丢条目可惜）。
排序按 第一作者姓 -> 年份 -> 标题。
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bibparse  # noqa: E402

_NON_ALNUM = re.compile(r"[^a-z0-9]")


def _norm_title(title: str) -> str:
    """标题比对用：去掉大小写、标点、LaTeX 外壳的差异。"""
    return _NON_ALNUM.sub("", title.lower())


def _dedupe_key(entry: dict) -> tuple[str, str]:
    fields = entry["fields"]
    doi = fields.get("doi", "").strip().lower()
    if doi:
        return ("doi", doi)
    title = _norm_title(fields.get("title", ""))
    if title:
        return ("title", title)
    return ("key", entry["key"].lower())


def main() -> int:
    ap = argparse.ArgumentParser(description="BibTeX 去重排序")
    ap.add_argument("src", help="输入 .bib（通常是 raw.bib）")
    ap.add_argument("-o", "--out", default="citations/references.bib", help="输出 .bib 路径")
    args = ap.parse_args()

    text = Path(args.src).read_text(encoding="utf-8")
    entries, broken = bibparse.parse(text)
    if not entries:
        print(f"{args.src} 里没有解析到任何条目，什么都没写。", file=sys.stderr)
        return 1

    kept: dict[tuple[str, str], dict] = {}
    dropped: list[tuple[str, str]] = []
    for e in entries:
        k = _dedupe_key(e)
        prev = kept.get(k)
        if prev is None:
            kept[k] = e
        elif len(e["fields"]) > len(prev["fields"]):
            dropped.append((prev["key"], e["key"]))
            kept[k] = e
        else:
            dropped.append((e["key"], prev["key"]))

    ordered = sorted(kept.values(), key=bibparse.sort_key)

    # key 撞车：不同文献恰好重名，加后缀区分，否则 LaTeX 引用会指向错的那篇
    used: dict[str, int] = {}
    for e in ordered:
        base = e["key"]
        new_key = base
        while new_key in used:
            used[base] = used.get(base, 0) + 1
            n = used[base]
            new_key = f"{base}{chr(ord('a') + n - 1)}" if n <= 26 else f"{base}{n}"
        if new_key != base:
            print(f"注意：citation key 重复，{base} -> {new_key}", file=sys.stderr)
            e["key"] = new_key
        used[new_key] = 0

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(
            f"% 由 format_bibtex.py 从 {Path(args.src).as_posix()} 去重排序生成，请勿手工编辑。\n"
            f"% 共 {len(ordered)} 条（输入 {len(entries)} 条，去重 {len(dropped)} 条）。\n\n"
        )
        f.write("\n\n".join(e["raw"] for e in ordered) + "\n")

    print(f"写入 {out_path}：{len(entries)} 条 -> {len(ordered)} 条")
    for loser, winner in dropped:
        print(f"  去掉重复 {loser}（保留 {winner}）")
    if broken:
        print(f"跳过 {len(broken)} 个括号不配对的条目：")
        for b in broken:
            print(f"  第 {b['line']} 行 @{b['type']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
