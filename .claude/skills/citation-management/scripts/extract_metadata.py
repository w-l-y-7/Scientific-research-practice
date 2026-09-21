"""从 DOI 列表批量取 BibTeX 元数据。

用法:
    python extract_metadata.py citations/doi_list.txt -o citations/raw.bib

DOI 优先走 Crossref 的 content negotiation（对方直接返回 BibTeX，不用自己拼字段），
失败再退回 doi.org。取不到的 DOI 会集中报在最后，不会静默丢掉。
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

# DOI 允许的字符集（Crossref 官方推荐写法），末尾多余的标点由 _trim 处理
DOI_RE = re.compile(r"10\.\d{4,9}/[-._;()/:A-Za-z0-9]+")
CROSSREF = "https://api.crossref.org/works/{}/transform/application/x-bibtex"
DOI_ORG = "https://doi.org/{}"

TIMEOUT = 25
RETRY_STATUS = {429, 500, 502, 503, 504}
UA = "citation-management/1.0" + (
    f" (mailto:{os.environ['CROSSREF_MAILTO']})" if os.environ.get("CROSSREF_MAILTO") else ""
)


def _trim(doi: str) -> str:
    """剥掉从正文里粘来的尾标点。右括号只在数量不配平时才认为是标点。"""
    doi = doi.rstrip(".,;:")
    while doi.endswith(")") and doi.count("(") < doi.count(")"):
        doi = doi[:-1].rstrip(".,;:")
    return doi


def find_dois(text: str) -> list[str]:
    """抽正文里的 DOI，支持裸 DOI、https://doi.org/... 和 doi:... 三种写法。去重且大小写不敏感。"""
    found, seen = [], set()
    for m in DOI_RE.finditer(text):
        doi = _trim(m.group(0))
        low = doi.lower()
        if low not in seen:
            seen.add(low)
            found.append(doi)
    return found


def _get(url: str, accept: str) -> str:
    req = urllib.request.Request(url, headers={"Accept": accept, "User-Agent": UA})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        return resp.read().decode("utf-8", errors="replace")


def fetch_bibtex(doi: str) -> str | None:
    """取一条 BibTeX。DOI 不存在返回 None；网络问题抛异常。"""
    url = CROSSREF.format(urllib.parse.quote(doi, safe=""))
    try:
        return _get(url, "application/x-bibtex")
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        if e.code not in RETRY_STATUS:
            raise
    except urllib.error.URLError:
        pass

    # Crossref 挂了或限流，改走 doi.org 的通用内容协商
    url = DOI_ORG.format(urllib.parse.quote(doi, safe="/"))
    try:
        return _get(url, "application/x-bibtex")
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def main() -> int:
    ap = argparse.ArgumentParser(description="DOI 列表 -> BibTeX")
    ap.add_argument("doi_file", help="一行一个 DOI 的文本文件")
    ap.add_argument("-o", "--out", default="citations/raw.bib", help="输出的 .bib 路径")
    ap.add_argument("--delay", type=float, default=0.4, help="每次请求间隔秒数（默认 0.4）")
    ap.add_argument("--dois-only", action="store_true", help="只抽 DOI 写清单，不联网")
    args = ap.parse_args()

    with open(args.doi_file, encoding="utf-8") as f:
        source = f.read()

    dois = find_dois(source)
    if not dois:
        print(f"没在 {args.doi_file} 里找到任何 DOI。", file=sys.stderr)
        return 1

    if args.dois_only:
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        with open(args.out, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(dois) + "\n")
        print(f"写入 {args.out}：{len(dois)} 个 DOI")
        return 0

    print(f"找到 {len(dois)} 个 DOI，开始抓取……")
    blocks, missing, failed = [], [], []

    for i, doi in enumerate(dois, 1):
        try:
            bib = fetch_bibtex(doi)
        except urllib.error.HTTPError as e:
            failed.append((doi, f"HTTP {e.code}"))
            print(f"  [{i}/{len(dois)}] {doi}  ->  失败 HTTP {e.code}", file=sys.stderr)
            continue
        except Exception as e:  # 网络超时、DNS 等，继续跑完剩下的
            failed.append((doi, type(e).__name__))
            print(f"  [{i}/{len(dois)}] {doi}  ->  失败 {type(e).__name__}", file=sys.stderr)
            continue

        if not bib or not bib.lstrip().startswith("@"):
            missing.append(doi)
            print(f"  [{i}/{len(dois)}] {doi}  ->  查不到", file=sys.stderr)
        else:
            blocks.append(bib.strip())
            print(f"  [{i}/{len(dois)}] {doi}  ->  ok")

        if i < len(dois):
            time.sleep(args.delay)

    header = (
        "% 由 extract_metadata.py 从 Crossref 批量抓取，请勿手工编辑——\n"
        "% 要改内容请改上游，然后重跑整条流水线。\n"
    )
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        f.write(header + "\n" + "\n\n".join(blocks) + "\n")

    print(f"\n写入 {args.out}：{len(blocks)} 条")
    if missing:
        print(f"查不到（{len(missing)}）: " + ", ".join(missing))
    if failed:
        print(f"网络失败（{len(failed)}）: " + ", ".join(d for d, _ in failed))
        print("网络失败的可以稍后重跑，脚本会重新生成整个文件。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
