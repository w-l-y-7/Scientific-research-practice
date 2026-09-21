"""从 DOI 列表批量取标题、摘要和期刊信息，供 GRADE 评价使用。

用法:
    python fetch_abstracts.py literature_notes/summary_table.md -o literature_notes/raw_abstracts.json

走 Crossref 的 REST 接口（不是 content negotiation），因为只有 JSON 里带 abstract 字段。
取不到摘要的条目**仍然写进结果**，摘要留空——GRADE 评价需要知道「哪些论文拿不到摘要」，
这比静默丢掉一条更容易发现。

摘要覆盖率是个硬约束：金融和经济的期刊里，Elsevier、Springer、Wiley 系大多存了摘要，
IEEE、部分学会期刊和很多工作论文没有。跑完看末尾的统计，低到离谱是正常的，不代表脚本坏了。
"""

from __future__ import annotations

import argparse
import html
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

# 与 citation-management 用同一套 DOI 规则，保证两个技能抽出来的 DOI 一致
DOI_RE = re.compile(r"10\.\d{4,9}/[-._;()/:A-Za-z0-9]+")
CROSSREF_API = "https://api.crossref.org/works/{}"

TIMEOUT = 25
RETRY_STATUS = {429, 500, 502, 503, 504}
MAX_RETRY = 3
UA = "grade-assessment/1.0" + (
    f" (mailto:{os.environ['CROSSREF_MAILTO']})" if os.environ.get("CROSSREF_MAILTO") else ""
)

# Crossref 的摘要字段是 JATS XML 片段，不去掉标签会污染后面的阅读
TAG_RE = re.compile(r"<[^>]+>")
WS_RE = re.compile(r"\s+")
# 剥完标签后开头会残留 <jats:title>Abstract</jats:title> 里的那个词，单独除掉
LEAD_LABEL_RE = re.compile(r"^(abstract|summary|摘要)\b[:\s]*", re.IGNORECASE)


def _trim(doi: str) -> str:
    """剥掉从正文里粘来的尾标点。右括号只在数量不配平时才认为是标点。"""
    doi = doi.rstrip(".,;:")
    while doi.endswith(")") and doi.count("(") < doi.count(")"):
        doi = doi[:-1].rstrip(".,;:")
    return doi


def find_dois(text: str) -> list[str]:
    """抽正文里的 DOI，支持裸写、https://doi.org/...、doi:... 三种写法。去重且大小写不敏感。"""
    found, seen = [], set()
    for m in DOI_RE.finditer(text):
        doi = _trim(m.group(0))
        low = doi.lower()
        if low not in seen:
            seen.add(low)
            found.append(doi)
    return found


def clean_abstract(raw: str | None) -> str:
    """把 JATS 片段压成纯文本。

    Crossref 返回的摘要长这样：'<jats:p>We study ...</jats:p>'，还可能带
    '<jats:italic>' 之类的行内标签和 '&amp;' 这类实体。直接拿去读会看到一堆尖括号，
    所以先剥标签再还原实体。剥完剩下的多余空白压成单个空格。
    """
    if not raw:
        return ""
    text = TAG_RE.sub(" ", raw)
    text = html.unescape(text)
    text = WS_RE.sub(" ", text).strip()
    return LEAD_LABEL_RE.sub("", text).strip()


def _first_author(item: dict) -> str:
    """取第一作者姓氏。没有作者时返回空串，不编一个出来。"""
    authors = item.get("author") or []
    if not authors:
        return ""
    first = authors[0]
    return (first.get("family") or first.get("name") or "").strip()


def _year(item: dict) -> str:
    """按发表、在线、创建的顺序找年份，找不到返回空串。"""
    for key in ("published-print", "published-online", "published", "created", "issued"):
        parts = (item.get(key) or {}).get("date-parts") or []
        if parts and parts[0] and parts[0][0]:
            return str(parts[0][0])
    return ""


def _get_json(doi: str) -> dict | None:
    """取一条 Crossref 记录。DOI 不存在返回 None；网络问题抛异常。"""
    url = CROSSREF_API.format(urllib.parse.quote(doi, safe=""))
    req = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": UA})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        return json.loads(resp.read().decode("utf-8", errors="replace"))


def fetch_record(doi: str) -> dict | None:
    """取一条记录并整理成扁平结构，带 429 退避重试。"""
    last_error = None
    for attempt in range(MAX_RETRY):
        try:
            payload = _get_json(doi)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            if e.code in RETRY_STATUS and attempt < MAX_RETRY - 1:
                last_error = e
                time.sleep(2 ** attempt)
                continue
            raise
        except urllib.error.URLError as e:
            if attempt < MAX_RETRY - 1:
                last_error = e
                time.sleep(2 ** attempt)
                continue
            raise
        else:
            item = (payload or {}).get("message") or {}
            titles = item.get("title") or []
            venues = item.get("container-title") or []
            return {
                "doi": doi,
                "title": WS_RE.sub(" ", titles[0]).strip() if titles else "",
                "abstract": clean_abstract(item.get("abstract")),
                "venue": venues[0].strip() if venues else "",
                "year": _year(item),
                "first_author": _first_author(item),
                "type": (item.get("type") or "").strip(),
                "cited_by": item.get("is-referenced-by-count"),
            }
    raise last_error if last_error else RuntimeError("unreachable")


def main() -> int:
    ap = argparse.ArgumentParser(description="DOI 列表 -> 标题/摘要/期刊 JSON")
    ap.add_argument("doi_file", help="含 DOI 的文件，通常是 literature_notes/summary_table.md")
    ap.add_argument("-o", "--out", default="literature_notes/raw_abstracts.json", help="输出 JSON 路径")
    ap.add_argument("--delay", type=float, default=0.5, help="每次请求间隔秒数（默认 0.5）")
    args = ap.parse_args()

    with open(args.doi_file, encoding="utf-8") as f:
        source = f.read()

    dois = find_dois(source)
    if not dois:
        print(f"没在 {args.doi_file} 里找到任何 DOI。", file=sys.stderr)
        print("GRADE 评价无从下手——先把文献录进表里，别自己编。", file=sys.stderr)
        return 1

    print(f"找到 {len(dois)} 个 DOI，开始抓取……")
    records, missing, failed = [], [], []

    for i, doi in enumerate(dois, 1):
        try:
            rec = fetch_record(doi)
        except urllib.error.HTTPError as e:
            failed.append((doi, f"HTTP {e.code}"))
            print(f"  [{i}/{len(dois)}] {doi}  ->  失败 HTTP {e.code}", file=sys.stderr)
            continue
        except Exception as e:  # 超时、DNS 等，跳过这条继续跑完剩下的
            failed.append((doi, type(e).__name__))
            print(f"  [{i}/{len(dois)}] {doi}  ->  失败 {type(e).__name__}", file=sys.stderr)
            continue

        if rec is None:
            missing.append(doi)
            print(f"  [{i}/{len(dois)}] {doi}  ->  Crossref 查不到", file=sys.stderr)
        else:
            records.append(rec)
            flag = "有摘要" if rec["abstract"] else "无摘要"
            print(f"  [{i}/{len(dois)}] {doi}  ->  {flag}")

        if i < len(dois):
            time.sleep(args.delay)

    with_abstract = sum(1 for r in records if r["abstract"])
    payload = {
        "source": args.doi_file,
        "counts": {
            "total_dois": len(dois),
            "fetched": len(records),
            "with_abstract": with_abstract,
            "without_abstract": len(records) - with_abstract,
            "not_found": len(missing),
            "failed": len(failed),
        },
        "records": records,
        "not_found": missing,
        "failed": [{"doi": d, "error": e} for d, e in failed],
    }

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)

    print(f"\n写入 {args.out}")
    print(f"  取到 {len(records)} 条，其中 {with_abstract} 条带摘要")
    if len(records) - with_abstract:
        print(f"  {len(records) - with_abstract} 条没有摘要 —— 这些论文只能按标题和期刊评，等级的可信度会低")
    if missing:
        print(f"  Crossref 查不到（{len(missing)}）: " + ", ".join(missing))
    if failed:
        print(f"  网络失败（{len(failed)}）: " + ", ".join(d for d, _ in failed))
        print("  网络失败的重跑本脚本即可，整个文件会重写。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
