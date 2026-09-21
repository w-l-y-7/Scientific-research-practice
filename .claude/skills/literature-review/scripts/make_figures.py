"""用 matplotlib 画文献综述需要的图。

上游技能原本靠 OpenRouter 调 AI 生图，那条路在本机走不通（缺 generate_schematic_ai.py，
也没有 API key）。这里改成程序化画图：不联网、不要密钥、同一份输入永远得到同一张图，
这对「可复现」这个要求反而更合适——综述里的流程图本来就该由数字决定，不该每次长得不一样。

两种图：

    python make_figures.py prisma --counts counts.json -o figures/prisma.png
    python make_figures.py stats  --results results.json -o figures/stats.png

counts.json 的字段见 PRISMA_FIELDS；漏填的按 0 处理，但**不会**替你猜。
results.json 就是 search_databases.py 处理的那种检索结果数组。
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

import matplotlib

matplotlib.use("Agg")  # 无显示环境也要能出图

# PowerShell 5.1 的 `Out-File -Encoding utf8` 默认带 BOM，用 utf-8 读会直接报错。
# utf-8-sig 对带 BOM 和不带 BOM 的文件都能读，Windows 上必须用它。
JSON_ENCODING = "utf-8-sig"

import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch

# 中文字体：按 Windows 常见字体依次试，都没有就退回默认并警告（默认字体画中文会是方框）
CJK_FONTS = ["Microsoft YaHei", "SimHei", "SimSun", "Noto Sans CJK SC", "Source Han Sans SC"]
plt.rcParams["axes.unicode_minus"] = False

# Okabe-Ito 色板，对色盲友好
BLUE, ORANGE, GREEN, VERMILLION = "#0072B2", "#E69F00", "#009E73", "#D55E00"
SKY, GREY = "#56B4E9", "#666666"


def use_cjk_font() -> bool:
    """把 matplotlib 字体设成能画中文的。返回是否找到了中文字体。"""
    from matplotlib import font_manager

    available = {f.name for f in font_manager.fontManager.ttflist}
    for name in CJK_FONTS:
        if name in available:
            plt.rcParams["font.sans-serif"] = [name]
            return True
    return False


# PRISMA 2020 主流程需要的计数。字段名和论文里那张图的格子一一对应
PRISMA_FIELDS = {
    "identified_databases": "数据库检索到的记录",
    "identified_registers": "其他来源（预印本、引文追溯等）",
    "removed_duplicates": "剔除重复记录",
    "removed_ineligible": "自动工具标记为不合格",
    "screened": "进入标题/摘要筛选",
    "screened_excluded": "标题/摘要阶段排除",
    "sought": "索取全文",
    "not_retrieved": "未获取到全文",
    "assessed": "全文评估",
    "assessed_excluded": "全文阶段排除",
    "included": "纳入综述的研究",
}


def box(ax, x, y, w, h, text, *, face=SKY, edge=BLUE, fontsize=9, weight="normal"):
    """画一个圆角框，文字居中。"""
    ax.add_patch(
        FancyBboxPatch(
            (x, y), w, h,
            boxstyle="round,pad=0.02,rounding_size=0.12",
            linewidth=1.2, edgecolor=edge, facecolor=face, zorder=2,
        )
    )
    ax.text(x + w / 2, y + h / 2, text, ha="center", va="center",
            fontsize=fontsize, color="#1a1a1a", zorder=3, weight=weight)


def arrow(ax, x1, y1, x2, y2, *, color=BLUE, style="-|>", lw=1.2):
    """从 (x1,y1) 到 (x2,y2) 画一个箭头。"""
    ax.add_patch(
        FancyArrowPatch(
            (x1, y1), (x2, y2), arrowstyle=style, mutation_scale=12,
            linewidth=lw, color=color, zorder=1, shrinkA=0, shrinkB=0,
        )
    )


def label(n: int | str) -> str:
    """统一括号计数写法。"""
    return f"(n = {n})"


def draw_prisma(counts: dict, out: Path, title: str) -> None:
    """画 PRISMA 2020 流程图。

    刻意只画主流程（识别 → 筛选 → 索取 → 评估 → 纳入）加右侧的排除框。
    真实综述里排除原因往往要分条列，这里用 `assessed_excluded_reasons` 字段支持，
    传一个 {原因: 条数} 的字典即可。
    """
    for key in PRISMA_FIELDS:
        counts.setdefault(key, 0)
    reasons = counts.get("assessed_excluded_reasons") or {}

    fig, ax = plt.subplots(figsize=(11, 13))
    ax.set_xlim(0, 11)
    ax.set_ylim(0, 15)
    ax.axis("off")

    W, H = 4.6, 1.15          # 主流程框尺寸
    MAIN_X = 0.5              # 主流程左边界
    SIDE_X = 6.4              # 排除框左边界
    SIDE_W = 4.2

    rows = [
        13.4, 11.5, 9.6, 7.7, 5.6, 3.4, 1.5
    ]

    # 识别
    box(ax, MAIN_X, rows[0], W, H,
        f"{PRISMA_FIELDS['identified_databases']}\n{label(counts['identified_databases'])}",
        face=SKY, weight="bold")
    box(ax, MAIN_X + W + 0.3, rows[0], W * 0.75, H,
        f"{PRISMA_FIELDS['identified_registers']}\n{label(counts['identified_registers'])}",
        face="#DCE9F5")

    # 剔除重复
    box(ax, SIDE_X, rows[1], SIDE_W, H,
        f"{PRISMA_FIELDS['removed_duplicates']}\n{label(counts['removed_duplicates'])}\n"
        f"{PRISMA_FIELDS['removed_ineligible']} {label(counts['removed_ineligible'])}",
        face="#FDEBD0", edge=ORANGE)
    arrow(ax, MAIN_X + W / 2, rows[0], MAIN_X + W, rows[1] + H / 2, color=ORANGE)
    arrow(ax, SIDE_X, rows[1] + H / 2, MAIN_X + W, rows[1] + H / 2, color=ORANGE)

    # 筛选
    box(ax, MAIN_X, rows[2], W, H,
        f"{PRISMA_FIELDS['screened']}\n{label(counts['screened'])}", weight="bold")
    arrow(ax, MAIN_X + W / 2, rows[1], MAIN_X + W / 2, rows[2] + H)

    box(ax, SIDE_X, rows[2], SIDE_W, H,
        f"{PRISMA_FIELDS['screened_excluded']}\n{label(counts['screened_excluded'])}",
        face="#FDEBD0", edge=ORANGE)
    arrow(ax, MAIN_X + W, rows[2] + H / 2, SIDE_X, rows[2] + H / 2, color=ORANGE)

    # 索取全文
    box(ax, MAIN_X, rows[3], W, H,
        f"{PRISMA_FIELDS['sought']}\n{label(counts['sought'])}")
    arrow(ax, MAIN_X + W / 2, rows[2], MAIN_X + W / 2, rows[3] + H)

    box(ax, SIDE_X, rows[3], SIDE_W, H,
        f"{PRISMA_FIELDS['not_retrieved']}\n{label(counts['not_retrieved'])}",
        face="#FDEBD0", edge=ORANGE)
    arrow(ax, MAIN_X + W, rows[3] + H / 2, SIDE_X, rows[3] + H / 2, color=ORANGE)

    # 全文评估
    box(ax, MAIN_X, rows[4], W, H,
        f"{PRISMA_FIELDS['assessed']}\n{label(counts['assessed'])}")
    arrow(ax, MAIN_X + W / 2, rows[3], MAIN_X + W / 2, rows[4] + H)

    reason_lines = "\n".join(f"  · {k} {label(v)}" for k, v in reasons.items())
    excluded_text = f"{PRISMA_FIELDS['assessed_excluded']} {label(counts['assessed_excluded'])}"
    if reason_lines:
        excluded_text += "\n" + reason_lines
    box(ax, SIDE_X, rows[4] - 0.5, SIDE_W, H + 0.5,
        excluded_text, face="#FDEBD0", edge=ORANGE, fontsize=8)
    arrow(ax, MAIN_X + W, rows[4] + H / 2, SIDE_X, rows[4] + H / 2, color=ORANGE)

    # 纳入
    box(ax, MAIN_X, rows[6], W, H,
        f"{PRISMA_FIELDS['included']}\n{label(counts['included'])}",
        face="#D5F0E3", edge=GREEN, weight="bold")
    arrow(ax, MAIN_X + W / 2, rows[4], MAIN_X + W / 2, rows[6] + H, color=GREEN, lw=1.6)

    ax.set_title(title, fontsize=14, weight="bold", pad=14)

    # 左侧环节名，帮助读者对齐 PRISMA 的四个阶段
    for y, name in [(rows[0] + H / 2, "识别"), (rows[2] + H / 2, "筛选"),
                    (rows[3] + H / 2, "索取"), (rows[4] + H / 2, "评估"),
                    (rows[6] + H / 2, "纳入")]:
        ax.text(0.1, y, name, ha="right", va="center", fontsize=10,
                color=GREY, rotation=90, weight="bold")

    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out, dpi=300, bbox_inches="tight", facecolor="white")
    plt.close(fig)


def draw_stats(results: list[dict], out: Path, title: str) -> None:
    """画检索统计：各库贡献了多少条、以及年份分布。"""
    fig, axes = plt.subplots(1, 2, figsize=(13, 5.5))

    # 左：各来源条数
    sources = Counter(r.get("source") or "未知来源" for r in results)
    names = [k for k, _ in sources.most_common()]
    values = [v for _, v in sources.most_common()]
    axes[0].barh(names[::-1], values[::-1], color=BLUE, height=0.6)
    axes[0].set_xlabel("记录数")
    axes[0].set_title("各数据库贡献的记录数", fontsize=11, weight="bold")
    for i, v in enumerate(values[::-1]):
        axes[0].text(v, i, f" {v}", va="center", fontsize=9, color=GREY)
    axes[0].grid(axis="x", alpha=0.25, linestyle=":")
    axes[0].set_axisbelow(True)

    # 右：年份分布
    years = [str(r["year"]) for r in results if r.get("year")]
    if years:
        yc = Counter(years)
        keys = sorted(yc)
        axes[1].bar(keys, [yc[k] for k in keys], color=GREEN, width=0.65)
        axes[1].set_xlabel("发表年份")
        axes[1].set_ylabel("记录数")
        axes[1].set_title("文献年份分布", fontsize=11, weight="bold")
        if len(keys) > 12:
            axes[1].tick_params(axis="x", rotation=90, labelsize=8)
        axes[1].grid(axis="y", alpha=0.25, linestyle=":")
        axes[1].set_axisbelow(True)
    else:
        axes[1].text(0.5, 0.5, "结果里没有年份字段", ha="center", va="center",
                     color=GREY, transform=axes[1].transAxes)
        axes[1].axis("off")

    fig.suptitle(f"{title}（共 {len(results)} 条记录）", fontsize=13, weight="bold")
    fig.tight_layout()

    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out, dpi=300, bbox_inches="tight", facecolor="white")
    plt.close(fig)


def main() -> int:
    ap = argparse.ArgumentParser(
        description="用 matplotlib 画文献综述配图（PRISMA 流程图 / 检索统计图）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""示例:
  python make_figures.py prisma --counts counts.json -o figures/prisma.png
  python make_figures.py stats  --results results.json -o figures/stats.png
""",
    )
    sub = ap.add_subparsers(dest="kind", required=True)

    p1 = sub.add_parser("prisma", help="画 PRISMA 2020 流程图")
    p1.add_argument("--counts", required=True,
                    help="计数 JSON，字段见脚本顶部的 PRISMA_FIELDS")
    p1.add_argument("-o", "--output", default="figures/prisma.png")
    p1.add_argument("--title", default="PRISMA 文献筛选流程")

    p2 = sub.add_parser("stats", help="画各库贡献和年份分布")
    p2.add_argument("--results", required=True, help="检索结果 JSON 数组")
    p2.add_argument("-o", "--output", default="figures/stats.png")
    p2.add_argument("--title", default="检索结果概览")

    args = ap.parse_args()

    if not use_cjk_font():
        print("警告：没找到中文字体，中文会显示成方框。"
              "装上 Microsoft YaHei / SimHei 之类的中文字体即可。", file=sys.stderr)

    out = Path(args.output)

    if args.kind == "prisma":
        counts = json.loads(Path(args.counts).read_text(encoding=JSON_ENCODING))
        if not isinstance(counts, dict):
            print("counts.json 顶层必须是对象。", file=sys.stderr)
            return 1
        unknown = set(counts) - set(PRISMA_FIELDS) - {"assessed_excluded_reasons"}
        if unknown:
            # 字段名写错时静默按 0 处理最坑人，这里直接报出来
            print(f"counts.json 里有不认识的字段: {', '.join(sorted(unknown))}", file=sys.stderr)
            print(f"可用字段: {', '.join(PRISMA_FIELDS)}", file=sys.stderr)
            return 1
        draw_prisma(counts, out, args.title)
        print(f"PRISMA 流程图已写入 {out}")
        return 0

    results = json.loads(Path(args.results).read_text(encoding=JSON_ENCODING))
    if not isinstance(results, list):
        print("results.json 顶层必须是数组。", file=sys.stderr)
        return 1
    if not results:
        print("results.json 是空的，没东西可画。", file=sys.stderr)
        return 1
    draw_stats(results, out, args.title)
    print(f"统计图已写入 {out}（基于 {len(results)} 条记录）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
