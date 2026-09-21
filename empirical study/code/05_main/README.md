# 阶段 05 · 主回归

对应 [CLAUDE.md](../../CLAUDE.md) 第七节第 3 条 HITL 节点、[README.md](../../README.md) 第三节阶段 5。
用 Callaway-Sant'Anna 估计量（R 的 `did::att_gt`）估渐进采纳下的处理效应，
再用双向固定效应（`fixest::feols`）作对照。

```powershell
# 在 R / RStudio 里（不是 PowerShell）。先 cd 到 empirical study/，再 source
setwd("d:/git仓库/Scientific reacher practice/empirical study")
source("code/05_main/05_main.R")
```

R 没有「脚本自己的路径」这回事，只能靠工作目录定位。脚本第 0 节的哨兵自检会拦住设错目录。

## 两条输入路线，同一套代码

`PANEL_SOURCE` 决定读哪份数据，**下游代码一行都不用改**：

| 取值 | 读什么 | 状态 |
| --- | --- | --- |
| `"mpdta"` | `did` 包自带的示例面板：县级最低工资与就业，500 县 × 2003–2007 | **现在就能跑** |
| `"panel"` | `data/processed/panel.rds`，阶段 03 产物（QCEW 真数据） | 等 QCEW 那条线跑通 |

选 `mpdta` 是因为它跟教程的例子**同一个题材、同一个数据结构**：`first.treat`
就是 `att_gt` 要的 `gvar`（0 = 从未受处理），`lemp` 是就业的对数。
拿它把方法跑通、看到真数字，不必先啃完数据拉取和清洗。

> **`mpdta` 是公开的经典数据集**，也正是 LLM 可能在预训练里见过的那一类。
> 所以第 3 节的数据指纹和 #10 的 HITL 停止点在这里尤其要紧——见下。

## 命令对照表：教程的 Stata ↔ 这里的 R

这张表就是这条 R 线的教学材料。两边做的是同一件事：

| 教程 / Stata | 这里 / R | 说明 |
| --- | --- | --- |
| `csdid y, ivar() tvar() gvar() notyet` | `did::att_gt(..., control_group = "notyettreated")` | `csdid` 本就是 R 的 `did` 移植到 Stata 的，同源 |
| `csdid ..., wboot reps(999)` | `att_gt(..., bstrap = TRUE, biters = 999)` | 乘数自助法估方差 |
| `estat simple` | `aggte(att_gt_out, type = "simple")` | 全样本汇总 ATT |
| `estat group` | `aggte(..., type = "group")` | 按处理队列聚合 |
| `estat calendar` | `aggte(..., type = "calendar")` | 按日历年聚合 |
| `estat event` | `aggte(..., type = "dynamic")` | 事件研究系数 |
| `csdid_plot` | `did::ggdid()` | 事件研究图 |
| `reghdfe y x, absorb(i t) vce(cluster id)` | `fixest::feols(y ~ x \| id + t, cluster = ~id)` | TWFE 对照 |
| — | `fixest::sunab()` | Sun-Abraham 交互加权，另一种负权重修正 |
| `esttab` | 手写 LaTeX（`writeLines`） | 少一个依赖 |
| `datasignature` | `saveRDS` + `tools::md5sum` | 数据指纹 |

**没有 Stata 也能学到的东西一样多。** 这套 R 实现和 Stata 的 `csdid` 是同一个
估计量（`csdid` 是 `did` 的移植版），系数口径一致；事件研究图、四种聚合、
TWFE 对照一个不少。

## 这份文件是模板，而且有闸门

参数区里的 `CONFIRMED` **不是 `TRUE` 就拒绝执行**。这是 HITL 闸门：
主回归规范属 CLAUDE.md 第七节第 3 条，必须研究者拍板。

闸门拦的不是「没想清楚就确认」——那个拦不住。它拦的是**未确认的裸跑**：
AI 反复迭代代码时最容易发生的事就是改了参数顺手一跑，系数变了，
而没人意识到样本或规范已经被悄悄改过。

完整参数表：

| 参数 | 待确认什么 | 影响 |
| --- | --- | --- |
| `PANEL_SOURCE` | 读示例面板还是真面板 | 见上「两条输入路线」 |
| `OUTCOME` | 结果变量 | 示例面板里是 `lemp`；QCEW 面板里是 `log_emp` |
| `GVAR` | 处理时点变量 | 示例面板里是 `first.treat`；QCEW 面板里由 `03_clean.R` 第 7b 节构造 |
| `IVAR` / `TVAR` | 个体 / 时间维度 | 示例面板里是 `countyreal` / `year` |
| `CLUSTER` | 聚类层级 | **必须与处理变量变异的层级一致**。最低工资在县级变动 → 聚类在县 |
| `CONTROLS` | 控制变量集 | `character(0)` = 基准规范 |
| `CONTROL_GROUP` | 对照组取法 | `"notyettreated"` = 用「尚未处理」的（教程推荐）；`"nevertreated"` = 用「从未处理」的 |
| `BOOTSTRAP` / `BOOT_REPS` | 方差估计 | `TRUE` + `999`。关掉就等于换了一套标准误口径，两栏不可比 |
| `MIN_OBS` | 期望样本量下界 | 守卫用，第一次跑完拿实际值回填 |
| `CONFIRMED` | 确认闸门 | 改成 `TRUE` 才能跑 |

## 产物

| 路径 | 内容 |
| --- | --- |
| `output/figures/fig_event_study.pdf` | 事件研究图 |
| `output/tables/tab_main.tex` | CS-DID 与 TWFE 并列的 LaTeX 表 |
| `output/tables/tab_main.csv` | 同一份结果的机器可读版，**阶段 06 靠它对账** |
| `logs/05_main_YYYYMMDD_HHMMSS.log` | 完整运行记录，含数据指纹 |

同一个结果写 `.tex` 和 `.csv` 两种格式看着多余，但阶段 06 的基准格必须和这里的
CS-DID 一栏对上（对不上说明两处不是同一套口径）。让 06 去解析 `.tex` 里的
`%9.4f` 太脆，一份机器可读的结果省掉这件事。

**本脚本不写 `data/processed/`。** 那片目录由 `03_clean.R` 独占写入
（CLAUDE.md 第一节），主回归只读。它只往 `output/` 和 `logs/` 写。

## 与教程写法的差异

| 教程写法 | 这里的写法 | 为什么 |
| --- | --- | --- |
| `04_main_reg.do` | `05_main.R` | 按 README.md 第二节的八阶段编号，主回归是阶段 5 |
| Stata | R | 见 [README.md](../../README.md) 第五节「计算环境」 |
| `use ".../panel_balanced.dta"` | 读 `mpdta` 或 `panel.rds` | 见上「两条输入路线」 |
| `estimates store cs_main` / `twfe_main` | 直接取 `aggte()` 的 `overall.att` | R 这边的结果对象是列表，不必走 `estimates store` |
| 直接跑 | `CONFIRMED` 闸门 | 见上 |
| `treat_indicator`（教程未交代哪来） | 直接用 `mpdta` 的 `treat` 列 | 真面板那条线由 `gvar` 和 `year` 现造 `treat_D` |

## 三个坑在这里怎么防

| 坑 | 这里怎么防 |
| --- | --- |
| 边界错位 | 造处理指示变量时用 `year >= gvar`，不用 `>`（CLAUDE.md 第九节） |
| 样本筛选错位 | 本脚本**不做任何筛选**。样本口径已在 `03_clean.R` 定死；造变量不是筛样本 |
| 聚类层级错配 | 参数区强制显式声明 `CLUSTER`，`feols` 一律写 `cluster = ~...`（`feols` 不写时的默认口径我没把握，见 `regression-spec.md` 的注；显式写就绕开了这个问题）；另见 `regression-spec.md` |

## 已知坑

**① `mpdta` 这条线能跑，QCEW 那条线不能。** `mpdta` 随 `did` 包安装，装完就有，
所以第一次跑就能看到真数字。QCEW 那条线要先有数据、先跑完 `03_clean.R`。

**② `PANEL_SOURCE = "panel"` 时，`panel.rds` 里必须有 `gvar`。** 缺了脚本会
明确报出来并指回 `03_clean.R` 第 7b 节，不会硬跑。

**③ 事件研究图的 −1 期基期陷阱。** 若把 −1 期设为基期，该期系数被机械置零，
「无预期效应」这个检验就失效了。`aggte(type = "dynamic")` 默认**不设基期**，
所有领先项都估出来——这正是要的。见 `did-checklist.md` 第 2 条。

**④ `sunab()` 对「从未受处理」的编码在不同 `fixest` 版本里要求不一样**，
有的要 `0`、有的要 `Inf`。脚本先按 `0` 跑（`mpdta` 的编码），
跑不成就打印提示、给出 `Inf` 的替代写法，并且**不影响 csdid 主结果**。

**⑤ 手写 LaTeX 表而不用 `modelsummary` / `knitr`。** `aggte()` 返回的不是
模型对象，喂给 `etable()` / `modelsummary()` 都要额外搬运；学习阶段每多一个
要装的包就多一道坎。手写 `writeLines` 零依赖，格式也看得见。

**⑥ `MIN_OBS` 的默认值 2000 是按 `mpdta` 的 2500 个观测定的。** 换成真面板
（阶段 03 产物）时必须改成那边的实际值，否则守卫会在错误的地方拦你。

## 这一节为什么停在这儿

脚本跑到第 10 节就结束了，**不往下走**。系数怎么解读、假设成不成立、
要不要进稳健性——都属于研究者。这条界线对应教程点名的训练数据泄漏风险：
LLM 可能在复述它在预训练里见过的经典结果，而不是从你这份数据里估出来的。
`mpdta` 正是公开的经典数据集，这个风险在本例里是实打实的。
界画在「**AI 跑代码、人读数字**」。

具体要你亲自做的四件事写在日志末尾：看事件研究图的处理前系数、
检查 −1 期有没有被当基期置零、判断 CS-DID 与 TWFE 的差异怎么解释、
判断这个 ATT 在经济上意味着什么。

## 下一步

`06_robust.R`（稳健性检验矩阵）已建，边界在 `config/robustness-matrix.R`。
**主回归确认无误后再动它**——主回归错了，后面所有稳健性都要重跑，
这是最贵的返工点。两个过渡点由 Stop hook 提醒（见
[../../README.md](../../README.md) 第六节）。

## 还没做的一件事

教程建议的稳健性里有一列值得单独提：**推后样本**（比如 2020–2023）。
那是 LLM 预训练截止之后的时段，如果系数在那一段仍然稳定，
说明结果不是记忆复述——这是对训练数据泄漏最直接的一个反证。

**本仓现在做不了这一列**：mpdta 只到 2007 年，而能覆盖到近年的 QCEW 那条线
还没跑通。做法是等 QCEW 面板出来之后，在矩阵里加一条样本规则即可——
改配置一行，不用动脚本。
