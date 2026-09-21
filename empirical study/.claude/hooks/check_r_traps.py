"""R 质量门禁 —— Claude Code 的 PreToolUse / PostToolUse hook。

对应 empirical study/CLAUDE.md 第九节、第十节。同一个脚本挂两个事件，
行为由 stdin 里的 hook_event_name 决定：

  PreToolUse   只管一件事——**缺随机种子就拦住**（见下面 ⑤）。
  PostToolUse  文件已经落盘，把四类写法提示回灌给模型（①②③④）。

两类事件的分工不是随意分的，是**能力**决定的：Edit 的 tool_input 里只有
改动片段（old_string / new_string），没有整份文件，所以「看整块」的检查在
PreToolUse 做不了；PostToolUse 时文件已落盘，读磁盘拿到的是真正的成品。

关于「拦截」与「提示」的分界（本项目的规定）：

  拦截的只有一条——**缺随机种子**。它的检查是客观的（有没有 set.seed 是
  事实），没有合法例外（涉及随机数的脚本不设种子就是错的），而且漏掉的
  后果是**静默的**：每次跑出来的数不一样，但看上去一切正常。
  这三条同时成立才值得拦。

  其余四条只提示。它们是判断问题（`feols` 的 cluster 可能确实写在别处、
  稳健标准误可能是有意为之的稳健性列），拦了会误伤，人都学会忽略提示了。

PostToolUse 的提示走 exit 2 把 stderr 回灌给模型——**那次写入已经完成了，
回灌不了任何东西**，只是让写代码的模型自己看见。区别于 PreToolUse 的
exit 2：那个是真的挡住不写。

配置文件在仓库根的 .claude/settings.json。手动自检（不用经过 Claude Code），
注意事件名要写对，两个分支行为不同：

    # 走 PreToolUse 分支：有 bstrap 但没 set.seed，应当 exit 2
    '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"empirical study/code/06_robust/06_robust.R","content":"att_gt(bstrap = TRUE)"}}' | .venv/Scripts/python.exe "empirical study/.claude/hooks/check_r_traps.py"

    # 走 PostToolUse 分支：读磁盘上的文件，应当 exit 2 并提示裸的 year >
    '{"hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"file_path":"empirical study/code/05_main/05_main.R"}}' | .venv/Scripts/python.exe "empirical study/.claude/hooks/check_r_traps.py"
"""

import json
import os
import re
import sys

# 只管这条线的 .R 文件。根目录文献综述那条线没有 .R，写了也不该被这里管。
WATCH_DIR = "empirical study"

# ② 的豁免名单。这两个文件「筛选样本」正是本职，不该被提示：
#   03_clean.R   清洗就是筛样本（CLAUDE.md 第九节：所有筛选集中在这里）
#   06_robust.R  稳健性矩阵的样本维度就是要一遍遍重切样本
# 别处出现 filter()/subset() 才提示。豁免放在文件名单上，不放宽提示措辞——
# 措辞一软，真正该看的那次也会被划过去。
FILTER_OK = {"03_clean.R", "06_robust.R"}

# ⑤ 涉及随机数的调用。**只认明确开启随机的那几种写法**，不认 `bstrap = BOOTSTRAP`
#    这类间接写法（值在参数区里，看不出来是 TRUE 还是 FALSE）。
#    宁漏勿误——这条会真的挡住写入，误报一次就得让人绕路。
#    `bstrap\s*=\s*TRUE` 而不是 `bstrap`：显式写了 `bstrap = FALSE` 的脚本
#    是确定性的，不该被拦。
RE_RANDOM = re.compile(
    r"\bbstrap\s*=\s*TRUE\b"
    r"|\bbiters\s*="
    r"|\b(?:sample|runif|rnorm|rbinom|rpois|rgeom|replicate)\s*\("
    r"|\bboot\s*\("
    r"|\bsynthdid"
    r"|\bboottest\b"
    r"|\bfwildclusterboot\b",
    re.IGNORECASE,
)
RE_SEED = re.compile(r"\bset\.seed\s*\(")

# ① 裸的 < / > 比年份。`(?!=)` 让 >= 和 <= 不命中；\b 让 base_year 这类
#    更长的变量名不命中（year 前面是下划线，不是词边界）。
RE_BOUNDARY = re.compile(r"\b(?:year|yq)\b\s*[<>](?!=)\s*-?\d")
# ② filter() / subset() 当样本筛选用。
#    不拦 df[cond, ] 这种下标写法——它在 R 里太常见，当筛选用和当下标用
#    分不出来，一律报等于天天误报。宁可漏报，不要让人学会忽略这个提示。
RE_FILTER = re.compile(r"(?:^|[^\w.$])(?:dplyr::)?(?:filter|subset)\s*\(")
# ③ 异方差稳健标准误的各种写法。
#    fixest: vcov = "hetero" / se = "hetero"
#    sandwich: vcovHC / vcovHAC
#    HC0..HC3 出现在任何地方都值得看一眼
RE_ROBUST = re.compile(
    r"""(?:vcov|se)\s*=\s*["'](?:hetero|white|HC\d?)["']"""
    r"""|vcovHC|vcovHAC|["']HC[0-3]["']""",
    re.IGNORECASE,
)
# ④ 固定效应回归。要看整个文件有没有 cluster。
RE_FEOLS = re.compile(r"\bfeols\s*\(")
RE_CLUSTER = re.compile(r"\bcluster\s*=")


def targeted(path):
    """这个文件要不要看：.R 后缀，且在 empirical study/ 下。"""
    if not path.lower().endswith(".r"):
        return False
    parts = path.replace("\\", "/").split("/")
    return WATCH_DIR in parts


def abs_path(path):
    """把 hook 传来的路径变成能打开的绝对路径。
    相对路径按项目根解析——hook 的工作目录不一定等于项目根，
    靠 $CLAUDE_PROJECT_DIR 兜一道。
    """
    p = path.replace("\\", "/")
    if re.match(r"^[A-Za-z]:/", p) or p.startswith("/"):
        return p
    base = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    return os.path.join(base.replace("\\", "/"), p)


def code_part(line):
    """去掉注释再匹配。
    整行 `#` 开头、以及行尾的 `#` 注释都剔掉——
    注释里写「不要用 year > 2009」不该被当成违规。
    """
    s = line.strip()
    if s.startswith("#"):
        return ""
    return line.split("#", 1)[0]


def read_file(path):
    """读磁盘上的文件，读不到返回 None。
    用 utf-8-sig 吃掉可能的 BOM——带 BOM 的话第一行会多一个看不见的字符，
    行号和首行的匹配都会偏。读不到不是错误（可能是新建文件），返回 None。
    """
    try:
        with open(abs_path(path), "rb") as fh:
            return fh.read().decode("utf-8-sig", "replace")
    except OSError:
        return None


def apply_edits(tool_name, tool_input, original):
    """还原「这次写入之后」的文件内容。
    Write：content 就是整份新文件，不必读盘。
    Edit / MultiEdit：拿着磁盘上的旧内容，把 old_string 换成 new_string。
    还原不了（文件读不到、或 old_string 对不上）返回 None——
    **调用方必须把 None 当成「信息不足」，不能当成「没问题」而放行拦截逻辑。**
    """
    if tool_name == "Write":
        c = tool_input.get("content")
        return c if isinstance(c, str) else None
    if original is None:
        return None

    edits = []
    if tool_name in ("MultiEdit", "MultiEditTool"):
        edits = [e for e in (tool_input.get("edits") or []) if isinstance(e, dict)]
    else:
        edits = [tool_input]

    text = original
    for e in edits:
        old = e.get("old_string")
        new = e.get("new_string")
        if new is None:
            new = e.get("new_str")
        if not isinstance(old, str) or not isinstance(new, str):
            return None
        if old == "":
            return None
        if e.get("replace_all"):
            if old not in text:
                return None
            text = text.replace(old, new)
        else:
            if old not in text:
                return None          # 对不上说明磁盘内容和我以为的不一样，别猜
            text = text.replace(old, new, 1)
    return text


def fragments_of(tool_input):
    """把这次写入的片段全取出来（拿不到整份文件时的退路）。
    Write 看 content，Edit 看 new_string，MultiEdit 逐个编辑看 new_string——
    漏掉一种就会漏报。"""
    out = []
    for key in ("content", "new_string", "new_str"):
        v = tool_input.get(key)
        if isinstance(v, str):
            out.append(v)
    edits = tool_input.get("edits")
    if isinstance(edits, list):
        for e in edits:
            if isinstance(e, dict):
                for key in ("new_string", "new_str"):
                    if isinstance(e.get(key), str):
                        out.append(e[key])
    return out


def scan_advisory(text, base):
    """①②③④ 四条提示，扫整份文本。返回 [(行号, 提示), ...]。
    `base` 是文件名，留着以后按文件放行用。
    """
    hits = []
    for i, line in enumerate(text.splitlines(), 1):
        code = code_part(line)
        if not code:
            continue
        if RE_BOUNDARY.search(code):
            hits.append((i, "裸的 `year >` / `year <` —— 边界一律写 `>=` / `<=`"
                            "（CLAUDE.md 第九节）"))
        if RE_FILTER.search(code) and base not in FILTER_OK:
            hits.append((i, "`filter()` / `subset()` —— 样本筛选集中在 03_clean.R。"
                            "确需在此筛选，把剔掉多少观测记进日志"
                            "（CLAUDE.md 第九节）"))
        if RE_ROBUST.search(code):
            hits.append((i, "异方差稳健标准误 —— regression-spec.md 禁用默认稳健标准误，"
                            "须显式声明聚类，如 `cluster = ~state_id`"))
    # ④ 整份文件级别
    if RE_FEOLS.search(text) and not RE_CLUSTER.search(text):
        hits.append((0, "这份文件里有 `feols(` 但全文没出现 `cluster = ` —— "
                        "固定效应（`| id + year`）和标准误是两回事，"
                        "不写 cluster 时 feols 给的是另一套口径的标准误，"
                        "而且不报错、不警告"))
    return hits


def seed_verdict(text):
    """⑤ 缺随机种子。返回 (要不要拦, 说明)。
    text 是「写入之后」的整份内容；text 为 None 表示信息不足——
    这时**不拦**。拦错的代价是挡住一次正常写入，漏掉的代价是下一次有人
    主动写 seed；两者相比，漏比误伤便宜。
    """
    if text is None:
        return False, ""
    if not RE_RANDOM.search(text):
        return False, ""
    if RE_SEED.search(text):
        return False, ""
    return True, (
        "缺少 `set.seed(...)`：这份 .R 里有涉及随机数的调用"
        "（bstrap / biters / sample / runif / boot 等），但全文找不到 set.seed。\n"
        "  CLAUDE.md 第二节：涉及 bootstrap、随机抽样、模拟的命令必须在使用前显式设置种子。\n"
        "  漏掉的后果是**静默的**——每次跑出来的数不一样，而结果看上去一切正常。\n"
        "  加一行：`set.seed(20260417)`（全项目统一基准种子）。"
    )


def main():
    # 走 sys.stdin.buffer 而不是 sys.stdin：管道输入可能带 UTF-8 BOM
    # （实测 PowerShell 5.1 的管道就会塞一个），带 BOM 的 JSON 解析会直接失败。
    # 这里用 utf-8-sig 解码把 BOM 吃掉，避免「静默跳过」——守看着在守、其实没守，
    # 是这类工具最坏的失败方式。
    try:
        raw = sys.stdin.buffer.read().decode("utf-8-sig", "replace")
    except (AttributeError, ValueError):
        raw = ""

    try:
        payload = json.loads(raw or "{}")
    except ValueError:
        # 读不懂就当没这回事，不能因为 hook 报错挡住人写文件。
        # 但要吭一声，否则坏了没人知道——只是吭在 stderr，且仍然 exit 0。
        print("check_r_traps: 读不懂 stdin 传来的 JSON，已跳过检查",
              file=sys.stderr)
        return 0

    event = (payload.get("hook_event_name") or "PreToolUse").strip()
    tool_name = (payload.get("tool_name") or "Write").strip()
    tool_input = payload.get("tool_input") or {}
    path = tool_input.get("file_path") or ""
    if not targeted(path):
        return 0

    base = os.path.basename(path.replace("\\", "/"))

    if event == "PreToolUse":
        # 只有一件事可做：拦缺种子。还原不出整份内容就放行（见 seed_verdict）。
        text = apply_edits(tool_name, tool_input, read_file(path))
        block, why = seed_verdict(text)
        if block:
            print(f"⛔ 拦住写入：{path}", file=sys.stderr)
            print(f"  {why}", file=sys.stderr)
            return 2
        return 0

    # PostToolUse：文件已经写完，从磁盘读成品再提示。
    # 读不到就退回片段——片段少一些上下文，但总比什么都不说不着。
    disk = read_file(path)
    if disk is not None:
        hits = scan_advisory(disk, base)
    else:
        hits = []
        for frag in fragments_of(tool_input):
            hits.extend(scan_advisory(frag, base))

    if not hits:
        return 0

    print(f"⚠ R 陷阱提示：{path}", file=sys.stderr)
    for lineno, msg in hits:
        where = f"  行 {lineno}：" if lineno else "  整份文件："
        print(f"{where}{msg}", file=sys.stderr)
    print("  （只提示，未拦截——那次写入已经完成了。判断权在你。）",
          file=sys.stderr)
    # exit 2 在 PostToolUse 里的意思是「把这段话回灌给模型」，不是撤销写入。
    return 2


if __name__ == "__main__":
    sys.exit(main())
