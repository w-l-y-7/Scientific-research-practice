"""HITL 提醒 —— Claude Code 的 Stop hook。

对应 empirical study/CLAUDE.md 第七节（人在回路节点）。
教程的 Stop hook 是「会话结束时无条件打印一句：请在继续稳健性前人工审阅主表」。
**这里改成了有条件触发**，理由是 Stop 事件的实际触发时机和直觉不同：

  Stop 在「主 agent 每答完一轮」时就触发，不是「会话结束」时触发。

无条件打印的结果是：这个仓库里做**任何**事（包括改文献综述那条线的文件）
都会被提醒一次「请审阅主表」。提醒一多就没人看了，而这条提醒恰恰是最不该
被忽略的那类。**所以只在仓库状态真的处在那个卡点时才吭声。**

两个卡点，各自对应一个真实的过渡点：

  卡点一：主表已生成，稳健性还没跑
          output/tables/tab_main.tex 在，output/robustness/cells.csv 不在
          → 提醒审阅主回归，确认无误再进阶段 06（主回归错了后面全要重跑）

  卡点二：矩阵已生成，表还没出
          output/robustness/cells.csv 在，output/tables/tab_robust_appendix.tex 不在
          → 提醒审阅矩阵，确认正文挑哪几列再进阶段 07

**永远 exit 0。** Stop 事件里 exit 2 的意思是「不许停，继续干活」，那会变成一个
循环（Stop 钩子 exit 2 → 模型再跑一轮 → Stop 再触发）；已知的失败模式，
不碰。这里只做提醒，不做拦阻。

输出走两条路，因为**哪条能到人眼前在不同版本里说法不一致**：
  - stdout 明文：exit 0 时 stdout 给用户看
  - JSON 的 systemMessage：文档里写的「向用户展示消息」的字段
两条都指向用户，所以任一条生效都达到目的；万一两条都失效，代价也只是
少一句提醒，不影响任何功能。

配置文件在仓库根的 .claude/settings.json。手动自检：

    echo '{}' | .venv/Scripts/python.exe "empirical study/.claude/hooks/check_hitl_stop.py"
"""

import json
import os
import sys

# 判断卡点用的文件，相对项目根。顺序即优先级。
PROJECT_FILES = {
    "main_table": "empirical study/output/tables/tab_main.tex",
    "cells_csv": "empirical study/output/robustness/cells.csv",
    "robust_table": "empirical study/output/tables/tab_robust_appendix.tex",
}


def project_root():
    """项目根。hook 的工作目录不一定等于项目根（文档里说 handler 用
    Claude Code 的环境和当前目录），所以优先用 $CLAUDE_PROJECT_DIR。"""
    root = os.environ.get("CLAUDE_PROJECT_DIR")
    if root:
        return root.replace("\\", "/")
    return os.getcwd().replace("\\", "/")


def exists(root, rel):
    return os.path.exists(os.path.join(root, rel))


def main():
    try:
        raw = sys.stdin.buffer.read().decode("utf-8-sig", "replace")
    except (AttributeError, ValueError):
        raw = ""
    try:
        payload = json.loads(raw or "{}")
    except ValueError:
        payload = {}

    # 我们已经停过一次又被打回来的那一轮，不再吭声。
    # 本脚本不会 exit 2，所以正常情况下不会走到这里；留着是防止日后有人
    # 把 exit 改成 2 时忘了这个守卫，那就成了死循环。
    if payload.get("stop_hook_active"):
        return 0

    root = project_root()
    has = {k: exists(root, v) for k, v in PROJECT_FILES.items()}

    msg = None
    if has["main_table"] and not has["cells_csv"]:
        msg = (
            "主回归已生成，稳健性还没跑 —— 请先人工审阅 "
            "empirical study/output/tables/tab_main.tex 和 "
            "output/figures/fig_event_study.pdf。\n"
            "  确认事件研究图处理前各期系数、确认 -1 期没被当基期置零、"
            "想清楚 CS-DID 与 TWFE 的差异怎么解释。\n"
            "  主回归错了后面全要重跑，这是最贵的返工点。然后再进阶段 06。"
        )
    elif has["cells_csv"] and not has["robust_table"]:
        msg = (
            "稳健性矩阵已生成，表格还没出 —— 请先人工审阅 "
            "empirical study/output/robustness/cells.csv。\n"
            "  看有没有符号和主回归相反的格子、有没有跑不出来的格子，"
            "并决定正文展示哪 3-4 列。\n"
            "  **符号翻转或显著性消失的格子不许从附录删掉**——完整矩阵就是诚信证明。"
        )

    if msg is None:
        return 0

    print(msg)
    print(json.dumps({"systemMessage": msg}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
