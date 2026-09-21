"""校验 .bib，把问题写成 JSON 报告。

用法:
    python validate_citations.py citations/references.bib -o citations/validation.json

只做「不用联网就能查」的检查：字段完整性、DOI 格式、年份、作者写法、
LaTeX 特殊字符转义。DOI 能不能真解析出来，得另外联网核。
退出码 0 = 没有 error，1 = 有 error（可直接拿去做流水线的门禁）。
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import bibparse  # noqa: E402

DOI_RE = re.compile(r"^10\.\d{4,9}/\S+$")
YEAR_RE = re.compile(r"^\d{4}$")

REQUIRED = {
    "article": ["author", "title", "journal", "year"],
    "inproceedings": ["author", "title", "booktitle", "year"],
    "incollection": ["author", "title", "booktitle", "publisher", "year"],
    "inbook": ["author", "title", "publisher", "year"],
    "book": ["title", "publisher", "year"],
    "phdthesis": ["author", "title", "school", "year"],
    "mastersthesis": ["author", "title", "school", "year"],
    "techreport": ["author", "title", "institution", "year"],
    "unpublished": ["author", "title", "year"],
    "misc": ["title", "year"],
    "online": ["title", "year"],
}
DEFAULT_REQUIRED = ["author", "title", "year"]

# 这些字段里出现未转义的 & % _ # 会让 LaTeX 编译失败
TEX_SENSITIVE_FIELDS = ("title", "booktitle", "journal", "publisher", "school", "institution")
SPECIAL_CHARS = "&%_#"
# Crossref 会把 & 输出成 &amp;。它不会让编译失败，但会被原样渲染出来，得单独报
HTML_ENTITY = re.compile(r"&(?:[a-zA-Z]+|#\d+);")


def _issue(sev, code, entry, message, field=None):
    return {
        "severity": sev,
        "code": code,
        "entry": entry,
        "field": field,
        "message": message,
    }


def _unescaped(text: str, ch: str) -> bool:
    return any(c == ch and (i == 0 or text[i - 1] != "\\") for i, c in enumerate(text))


def check_entry(entry: dict, issues: list[dict], this_year: int) -> None:
    key = entry["key"] or "(无 key)"
    fields = entry["fields"]
    etype = entry["type"]

    if not entry["key"]:
        issues.append(_issue("error", "missing_key", key, f"@{etype} 缺 citation key"))

    required = REQUIRED.get(etype)
    if required is None:
        issues.append(_issue("warning", "unknown_type", key, f"没见过的条目类型 @{etype}，按通用规则检查"))
        required = DEFAULT_REQUIRED
    for name in required:
        if not fields.get(name):
            issues.append(_issue("error", "missing_field", key, f"@{etype} 缺必需字段 {name}", name))

    if etype == "book" and not (fields.get("author") or fields.get("editor")):
        issues.append(_issue("error", "missing_field", key, "@book 至少要有 author 或 editor", "author"))

    doi = fields.get("doi", "")
    if not doi:
        issues.append(_issue("warning", "no_doi", key, "没有 doi，无法据此去重和核对"))
    elif not DOI_RE.match(doi):
        issues.append(_issue("error", "bad_doi", key, f"DOI 格式不对：{doi}", "doi"))

    year = fields.get("year", "")
    if year and not YEAR_RE.match(year):
        issues.append(_issue("error", "bad_year", key, f"year 不是四位数字：{year}", "year"))
    elif year:
        y = int(year)
        if not 1900 <= y <= this_year + 1:
            issues.append(_issue("warning", "odd_year", key, f"year={y} 看着不正常", "year"))

    author = fields.get("author", "")
    if author:
        if "&" in author:
            issues.append(_issue("warning", "bad_author", key, "作者用 & 分隔了，BibTeX 要求用 and", "author"))
        if "et al" in author.lower():
            issues.append(_issue("warning", "bad_author", key, "作者里写了 et al.，应该列全作者", "author"))
        if any(not seg.strip() for seg in author.split(" and ")):
            issues.append(_issue("error", "bad_author", key, "作者列表里有空的作者名（多了一个 and？）", "author"))
        # 连着两个 and 时 split 不会产生空段，得单独认
        if re.search(r"\band\s+and\b", author, re.IGNORECASE):
            issues.append(_issue("error", "bad_author", key, "作者列表里连着两个 and，中间少了作者名", "author"))

    for name in TEX_SENSITIVE_FIELDS:
        value = fields.get(name, "")

        entity = HTML_ENTITY.search(value)
        if entity:
            issues.append(
                _issue(
                    "warning",
                    "html_entity",
                    key,
                    f"{name} 里有 HTML 实体 {entity.group(0)}：BibTeX 不认，会原样渲染出来。& 要写成 \\&",
                    name,
                )
            )

        # 先挖掉 HTML 实体，再找裸的 &，否则 &amp; 会被误报成编译错误
        probe = HTML_ENTITY.sub("", value)
        for ch in SPECIAL_CHARS:
            if _unescaped(probe, ch):
                issues.append(
                    _issue("warning", "unescaped_special", key, f"{name} 里有未转义的 {ch}，LaTeX 会编译报错", name)
                )
                break


def main() -> int:
    ap = argparse.ArgumentParser(description="校验 BibTeX 并输出 JSON 报告")
    ap.add_argument("src", help="要校验的 .bib")
    ap.add_argument("-o", "--out", default="citations/validation.json", help="JSON 报告路径")
    args = ap.parse_args()

    src = Path(args.src)
    text = src.read_text(encoding="utf-8")
    entries, broken = bibparse.parse(text)
    this_year = dt.date.today().year

    issues: list[dict] = []
    for b in broken:
        issues.append(_issue("error", "unparsed", f"(第{b['line']}行)", f"@{b['type']} 括号不配对，整条没能解析"))

    key_counts = Counter(e["key"] for e in entries if e["key"])
    for k, n in key_counts.items():
        if n > 1:
            issues.append(_issue("error", "duplicate_key", k, f"citation key 出现了 {n} 次，LaTeX 引用会指向错的一篇"))

    for e in entries:
        check_entry(e, issues, this_year)

    errors = sum(1 for i in issues if i["severity"] == "error")
    warnings = len(issues) - errors
    report = {
        "source": src.as_posix(),
        "generated": dt.datetime.now().isoformat(timespec="seconds"),
        "summary": {
            "entries": len(entries),
            "errors": errors,
            "warnings": warnings,
            "ok": errors == 0,
        },
        "by_type": dict(Counter(e["type"] for e in entries)),
        "issues": issues,
    }

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"校验 {src}：{len(entries)} 条，{errors} 个 error，{warnings} 个 warning")
    if issues:
        print()
        for i in issues:
            where = f"{i['entry']}" + (f".{i['field']}" if i["field"] else "")
            print(f"  [{i['severity']:7}] {where}: {i['message']}")
    else:
        print("没有发现问题。")
    print(f"\n报告写入 {out_path}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
