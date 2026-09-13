"""从财报 PDF 抽取表格，每页存一个 CSV。

用法:
    python extract_tables.py 财报.pdf          # 只留看起来像表格的
    python extract_tables.py 财报.pdf --all    # 全都导出，不过滤
"""

import csv
import sys
from pathlib import Path

import pdfplumber

# 无边框表格要靠 text 策略才认得出来
TEXT_STRATEGY = {"vertical_strategy": "text", "horizontal_strategy": "text"}

# text 策略很激进，会把正文误判成表格。实测：真表格的单元格均长 9~14，
# 被误判的正文是 39~53。所以用均长卡一道，阈值按自己的文档调。
MIN_COLS = 2        # 只有一列的"表格"一定是正文
MAX_AVG_CELL = 30   # 单元格平均超过这么多字符，基本是正文


def clean(cell):
    if cell is None:
        return ""
    return " ".join(cell.split())


def looks_like_table(rows):
    if len(rows) < 2:
        return False
    cols = max(len(r) for r in rows)
    if cols < MIN_COLS:
        return False
    cells = [c for r in rows for c in r if c]
    if not cells:
        return False
    return sum(len(c) for c in cells) / len(cells) <= MAX_AVG_CELL


def find_tables(page, keep_all=False):
    """先试有线策略；抽不出像样的表格，再退到 text 策略。

    注意不能写成「lines 非空就不试 text」——有线策略常返回一堆
    一行一列的垃圾，会挡掉真正该用 text 策略抽的表。
    """
    for strategy, settings in (("lines", None), ("text", TEXT_STRATEGY)):
        tables = page.extract_tables(settings) if settings else page.extract_tables()
        if keep_all:
            if tables:
                return tables, strategy
        elif any(looks_like_table(t) for t in tables):
            return tables, strategy
    return [], "none"


def main(pdf_path, keep_all=False):
    out_dir = Path(pdf_path).with_suffix("")
    out_dir.mkdir(exist_ok=True)

    kept = skipped = 0
    with pdfplumber.open(pdf_path) as pdf:
        for page in pdf.pages:
            tables, strategy = find_tables(page, keep_all)
            i = 1
            for rows in tables:
                if not keep_all and not looks_like_table(rows):
                    skipped += 1
                    continue
                name = out_dir / f"p{page.page_number}_t{i}.csv"
                with open(name, "w", newline="", encoding="utf-8-sig") as f:
                    csv.writer(f).writerows([[clean(c) for c in row] for row in rows])
                i += 1
                kept += 1
                print(f"{name}  {len(rows)} 行 x {max(len(r) for r in rows)} 列  [{strategy}]")

    print(f"\n导出 {kept} 个 -> {out_dir}/")
    if skipped:
        print(f"跳过 {skipped} 个疑似正文（要全部导出加 --all）")


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        sys.exit(__doc__)
    main(args[0], keep_all="--all" in sys.argv)
