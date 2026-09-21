"""极简 BibTeX 解析器：切条目、切字段、剥外层括号。

不做的：@string 宏展开、LaTeX 反转义、跨条目引用。Crossref / Zotero 导出的
BibTeX 用这个够；手写的复杂 BibTeX 请换 bibtexparser。
"""

from __future__ import annotations

import re

_ENTRY_START = re.compile(r"@(\w+)\s*[{(]")
_SKIP_TYPES = {"comment", "preamble", "string"}


def _strip_comment_lines(text: str) -> str:
    # 只认「整行注释」。行内的 % 可能是正文（如 90% 或 URL），一律砍掉会毁内容。
    return "\n".join(
        ln for ln in text.splitlines() if not ln.lstrip().startswith("%")
    )


def _match_close(text: str, start: int) -> int:
    """text[start] 是开括号，返回配对的闭括号下标；不配对返回 -1。"""
    depth = 0
    in_quotes = False
    i = start
    while i < len(text):
        c = text[i]
        if c == "\\":
            i += 2
            continue
        if c == '"' and depth > 0:
            in_quotes = not in_quotes
        elif not in_quotes:
            if c in "{(":
                depth += 1
            elif c in "})":
                depth -= 1
                if depth == 0:
                    return i
        i += 1
    return -1


def _split_top_level(body: str) -> list[str]:
    """按顶层逗号切分；括号内和引号内的逗号不是分隔符。"""
    parts: list[str] = []
    cur: list[str] = []
    depth = 0
    in_quotes = False
    i = 0
    while i < len(body):
        c = body[i]
        if c == "\\":
            cur.append(body[i : i + 2])
            i += 2
            continue
        if c == '"' and depth == 0:
            in_quotes = not in_quotes
        if not in_quotes:
            if c in "{(":
                depth += 1
            elif c in "})":
                depth -= 1
            elif c == "," and depth == 0:
                parts.append("".join(cur))
                cur = []
                i += 1
                continue
        cur.append(c)
        i += 1
    parts.append("".join(cur))
    return parts


def unwrap(value: str) -> str:
    """剥掉最外层 {...} 或 "..."，并把折行压成单个空格。"""
    v = value.strip()
    if len(v) >= 2 and (
        (v[0] == "{" and v[-1] == "}") or (v[0] == '"' and v[-1] == '"')
    ):
        v = v[1:-1]
    return " ".join(v.split())


def parse(text: str) -> tuple[list[dict], list[dict]]:
    """解析 BibTeX。

    返回 (entries, broken)：
      entries —— [{type, key, fields, raw, line}, ...]
      broken  —— 括号不配对、没能解析完的条目 [{type, line}, ...]
    """
    text = _strip_comment_lines(text)
    entries: list[dict] = []
    broken: list[dict] = []

    for m in _ENTRY_START.finditer(text):
        etype = m.group(1).lower()
        if etype in _SKIP_TYPES:
            continue
        line = text.count("\n", 0, m.start()) + 1
        open_idx = m.end() - 1
        close_idx = _match_close(text, open_idx)
        if close_idx < 0:
            broken.append({"type": etype, "line": line})
            continue

        chunks = _split_top_level(text[open_idx + 1 : close_idx])
        fields: dict[str, str] = {}
        for chunk in chunks[1:]:
            name, sep, value = chunk.partition("=")
            if not sep:
                continue
            fields[name.strip().lower()] = unwrap(value)

        entries.append(
            {
                "type": etype,
                "key": chunks[0].strip(),
                "fields": fields,
                "raw": text[m.start() : close_idx + 1],
                "line": line,
            }
        )

    return entries, broken


def first_author_surname(author_field: str) -> str:
    """'Baek, Seungjae and Moon, Brady' -> 'baek'。取不到就给空串。"""
    first = author_field.split(" and ", 1)[0].strip()
    if not first:
        return ""
    if "," in first:
        return first.split(",", 1)[0].strip().lower()
    return first.split()[-1].lower() if first.split() else ""


def sort_key(entry: dict):
    authors = entry["fields"].get("author") or entry["fields"].get("editor") or ""
    year = entry["fields"].get("year", "")
    title = entry["fields"].get("title", "")
    return (first_author_surname(authors), year, title.lower(), entry["key"])
