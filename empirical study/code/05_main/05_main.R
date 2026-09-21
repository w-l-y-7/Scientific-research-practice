#==============================================================================
# 05_main.R : 主回归 —— Callaway-Sant'Anna (did) + TWFE 对照
#
# 对应 README.md 第二节阶段 5、CLAUDE.md 第七节第 3 条 HITL 节点。
#
# 教程给的是 Stata 版（csdid / reghdfe / esttab）。这里是它的 R 版，**能真跑**：
# 两边是同一个估计量，命令一一对应，映射表见 README.md 的「命令对照表」。
# 那份 Stata 代码不在本仓——项目主语言是 R，见 README.md 第五节。
#
# 输入：示例面板 mpdta（did 包自带）—— 县级最低工资与就业，500 县 × 2003-2007
# 输出：output/figures/fig_event_study.pdf
#       output/tables/tab_main.tex
# 日志：logs/05_main_YYYYMMDD_HHMMSS.log
#
# 为什么用示例面板而不是本仓的 QCEW：QCEW 那条线要先拉数据（阶段 02）、
# 再清洗（阶段 03），两步都很重，而且本机还没有数据。示例面板让我们**直接
# 把方法跑通看到真数字**——学习阶段的重点在这里。等 QCEW 那条线跑通了，
# 把第 2 节的数据来源换掉，下面的代码一行都不用改。
#
# mpdta 是本例的巧合也是最好的选择：它正是最低工资题材，first.treat 就是
# att_gt 要的 gvar（0 = 从未受处理）。
#
# 运行方式：先 cd 到 empirical study/ 再 source("code/05_main/05_main.R")
#==============================================================================


# --- 0. 环境自检 -------------------------------------------------------------
# CLAUDE.md 第三节：R 脚本首部必须锁 R 版本。
stopifnot(getRversion() >= "4.4.0")

# 需要的外部包。缺了就把安装命令原样打出来，不猜、不让脚本半路炸在一句
# 看不懂的报错上。
needed <- c("did", "fixest", "ggplot2")
missing <- needed[!vapply(needed, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing) > 0) {
  cat("\n缺少这些 R 包：", paste(missing, collapse = ", "), "\n\n")
  cat("装它们（在 R 或 RStudio 的控制台里跑，不是在 PowerShell 里）：\n\n")
  cat('  install.packages(c(',
      paste0('"', missing, '"', collapse = ", "), '))\n\n')
  cat("did 包是从 CRAN 装的，作者是 Callaway 和 Sant'Anna 本人——\n")
  cat("它就是 Stata 那个 csdid 的源头（csdid 是把 R 的 did 移植到 Stata 的）。\n")
  stop("先装包再跑本脚本。", call. = FALSE)
}

library(did)
library(fixest)
library(ggplot2)


# --- 目录、日志 ---------------------------------------------------------------
# 假定工作目录是 empirical study/（R 没有「脚本自己的路径」，只能这样定位）。
root <- getwd()
sentinel <- file.path(root, "code", "05_main", "05_main.R")
if (!file.exists(sentinel)) {
  stop("当前工作目录不是 empirical study/（当前：", root, "）\n",
       "先 setwd() 到 empirical study/ 再 source 本文件。", call. = FALSE)
}

dir_out    <- file.path(root, "output")
dir_figs   <- file.path(dir_out, "figures")
dir_tables <- file.path(dir_out, "tables")
dir_logs   <- file.path(root, "logs")
for (d in c(dir_figs, dir_tables, dir_logs)) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

# 时间戳 + 撞名加序号（同一秒跑两次不覆盖前一次的日志）。
stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
logfile <- file.path(dir_logs, paste0("05_main_", stamp, ".log"))
k <- 2L
while (file.exists(logfile)) {
  logfile <- file.path(dir_logs, paste0("05_main_", stamp, "_", k, ".log"))
  k <- k + 1L
}

# 全流程写进日志，同时仍然打在屏幕上（split = TRUE）。结束时记得 sink()。
con <- file(logfile, open = "wt")
sink(con, split = TRUE)


# --- 1. 参数区 —— 待研究者确认 ------------------------------------------------
# 这些是主回归规范（CLAUDE.md 第七节第 3 条 HITL 节点），必须研究者拍板。
# 本文件里的取值是唯一真源：/did-estimate 技能会原样读这一段打印出来，
# 技能自己不复述任何取值——那样两边迟早对不上。

PANEL_SOURCE <- "mpdta"   # 示例面板；换成 QCEW 时改成 "panel"

OUTCOME <- "lemp"         # 结果变量：就业的对数（≠ log_emp，见下）
GVAR    <- "first.treat"  # 处理时点：首次受处理年份，0 = 从未受处理
IVAR    <- "countyreal"   # 个体维度：县
TVAR    <- "year"         # 时间维度
CLUSTER <- "countyreal"   # 聚类层级：必须与处理变量变异的层级一致
CONTROLS <- c("lpop")     # 控制变量集；character(0) = 无控制

# 对照组怎么取：notyettreated ↔ Stata csdid 的 notyet。
# nevertreated ↔ 不写 notyet（csdid 的默认）。
CONTROL_GROUP <- "notyettreated"

# 方差估计：did 用乘数自助法（multiplier bootstrap），对应 csdid 的 wboot。
BOOTSTRAP   <- TRUE
BOOT_REPS   <- 999
MIN_OBS     <- 2000L      # 样本量守卫下界（示例面板是 2500）
CONFIRMED   <- FALSE      # 确认闸门：改成 TRUE 才能跑

# 可复现。CLAUDE.md 第二节：涉及 bootstrap 必须显式设种子。
set.seed(20260417)


# --- 2. 规范摘要 + 确认闸门 ---------------------------------------------------
# 闸门拦不住「没想清楚就确认」，但能拦住**未确认的裸跑**——改了参数顺手一跑、
# 系数变了而没人察觉，是 AI 迭代代码时最容易出的事。

cat("\n", strrep("=", 72), "\n", sep = "")
cat("主回归规范摘要\n")
cat(strrep("=", 72), "\n", sep = "")
cat("  数据来源    ：", PANEL_SOURCE, "（did 包自带示例面板）\n")
cat("  结果变量    ：", OUTCOME, "\n")
cat("  处理时点    ：", GVAR, "（0 = 从未受处理）\n")
cat("  个体 / 时间 ：", IVAR, " / ", TVAR, "\n")
cat("  聚类层级    ：", CLUSTER, "\n")
cat("  控制变量    ：",
    if (length(CONTROLS) == 0) "无（基准规范）" else paste(CONTROLS, collapse = ", "), "\n")
cat("  对照组      ：", CONTROL_GROUP, "\n")
cat("  方差        ：",
    if (BOOTSTRAP) paste0("乘数自助法 reps=", BOOT_REPS) else "did 默认", "\n")
cat(strrep("=", 72), "\n", sep = "")

if (!isTRUE(CONFIRMED)) {
  cat("\n")
  cat("CONFIRMED 不是 TRUE —— 本脚本拒绝执行。\n\n")
  cat("主回归规范是 HITL 节点（CLAUDE.md 第七节第 3 条）：固定效应结构、\n")
  cat("聚类层级、控制变量取舍都是研究设计决定，不能由脚本默认。\n\n")
  cat("两件事都要做：\n")
  cat("  1. 把上面这段摘要和 .claude/rules/regression-spec.md 的默认值逐项比一遍\n")
  cat("     （走 /did-estimate 技能会自动打差异表）\n")
  cat("  2. 按 references/did-checklist.md 确认识别假设你担得起\n")
  cat("确认无误后，把参数区 CONFIRMED 改成 TRUE 再跑。\n\n")
  sink()
  close(con)
  stop("未确认，已中止。", call. = FALSE)
}


# --- 3. 读面板 + 守卫 ---------------------------------------------------------
cat("\n", strrep("=", 72), "\n", sep = "")
cat("读取面板\n")
cat(strrep("=", 72), "\n", sep = "")

if (PANEL_SOURCE == "mpdta") {
  # 用独立环境接住 data()，不依赖 source() 时的工作环境——
  # data() 默认往 parent.frame() 里塞，source(local = TRUE) 之类的情况下会找不到。
  .e <- new.env()
  data(mpdta, package = "did", envir = .e)
  panel <- .e$mpdta
  rm(.e)
} else {
  panel <- readRDS(file.path(root, "data", "processed", "panel.rds"))
}

n_obs <- nrow(panel)
n_units <- length(unique(panel[[IVAR]]))
cat("  观测数：", format(n_obs, big.mark = ","), "\n", sep = "")
cat("  县级数：", format(n_units, big.mark = ","), "\n", sep = "")
cat("  年份区间：", min(panel[[TVAR]]), " - ", max(panel[[TVAR]]), "\n", sep = "")

# 守卫一：样本量。改动让样本规模变了就当场停，而不是换个样本悄悄跑出系数。
if (n_obs < MIN_OBS) {
  sink(); close(con)
  stop("观测数 ", n_obs, " 低于守卫下界 MIN_OBS = ", MIN_OBS,
       "。样本被改动了，先查清楚。", call. = FALSE)
}

# 守卫二：主键唯一。照 CLAUDE.md 第九节，和 03_clean.R 第 8 节同一条。
key <- panel[c(IVAR, TVAR)]
if (anyDuplicated(key) > 0) {
  sink(); close(con)
  stop("主键 ", IVAR, " + ", TVAR, " 不唯一——面板没聚合干净。", call. = FALSE)
}

# 守卫三：需要的变量都在。缺了就报出实际变量名，不猜。
need_vars <- c(OUTCOME, GVAR, IVAR, TVAR, CLUSTER, CONTROLS)
absent <- setdiff(need_vars, names(panel))
if (length(absent) > 0) {
  cat("  面板里没有这些变量：", paste(absent, collapse = ", "), "\n")
  cat("  它实际有：", paste(names(panel), collapse = ", "), "\n")
  sink(); close(con)
  stop("变量缺失，已中止。", call. = FALSE)
}

# 处理指示变量。mpdta 自带 treat 列，QCEW 那条线的面板没有（它只有 gvar），
# 所以要能在缺的时候现造——**否则换成真面板时 feols 会在第 7 节炸在一句
# 「object 'treat' not found」上**，而那句话完全指不出问题在哪。
# 边界写 >= 不写 >（CLAUDE.md 第九节）；gvar > 0 让从未受处理的单元保持 0。
if (!"treat" %in% names(panel)) {
  panel$treat <- as.integer(panel[[TVAR]] >= panel[[GVAR]] & panel[[GVAR]] > 0)
  cat("  面板没有 treat 列，已按 year >= gvar 且 gvar > 0 现造。\n")
}

# 处理队列分布。主回归这边要能自己看见队列结构，不能只信上游打印过。
cat("\n  处理队列（", GVAR, " 取值）分布：\n", sep = "")
cohort_tab <- table(panel[[GVAR]][!duplicated(panel[[IVAR]])])
print(cohort_tab)

# 数据指纹。这是应对「训练数据泄漏」的具体机制，不是原则口号：
# 它把这次真正读进来的那份数据钉死。以后任何一个系数，都能追到某一次运行、
# 某一份具体的数据；而不是"模型记得的"那份经典数据的系数。
# 对 mpdta 尤其要强调——它是公开的经典数据集，正是模型可能"见过"的那类。
cat("\n  数据指纹：\n")
cat("    nrow = ", nrow(panel), "  ncol = ", ncol(panel), "\n", sep = "")
sig_tmp <- tempfile()
saveRDS(panel, sig_tmp, version = 2)
data_sig <- unname(tools::md5sum(sig_tmp))   # tools 是 base R，不额外依赖包
unlink(sig_tmp)
cat("    md5 = ", substr(data_sig, 1, 12), "\n", sep = "")


# --- 4. att_gt 主回归 ---------------------------------------------------------
# 对应 Stata 的 csdid。att_gt 就是 Callaway-Sant'Anna 的 ATT(g,t) 估计量本体，
# 按「首次处理年份」分组、每组单独和自己合适的对照组比。
#
# 注意 yname 用字符串，不是公式——这是 did 包的接口习惯，和 fixest 不同。

cat("\n", strrep("=", 72), "\n", sep = "")
cat("att_gt：分组分期 ATT(g,t)\n")
cat(strrep("=", 72), "\n", sep = "")

xformla <- if (length(CONTROLS) == 0) NULL else
  as.formula(paste("~", paste(CONTROLS, collapse = " + ")))

cs_out <- att_gt(
  yname         = OUTCOME,
  gname         = GVAR,
  idname        = IVAR,
  tname         = TVAR,
  xformla       = xformla,
  data          = panel,
  control_group = CONTROL_GROUP,   # ↔ csdid 的 notyet
  bstrap        = BOOTSTRAP,       # ↔ csdid 的 wboot
  biters        = BOOT_REPS,
  clustervars   = CLUSTER,
  print_details = FALSE
)

# 注意必须显式 print()。source() 默认 print.eval = FALSE，
# 顶层表达式算完不打印——不写 print，这一整段就只进日志不进眼睛。
cat("\n--- 分组分期估计（对应 estat group 的底层）---\n")
print(summary(cs_out))


# --- 5. 四种聚合 --------------------------------------------------------------
# 对应 Stata 连着跑的 estat simple / group / calendar / event。
# 聚合方式决定你报的是哪一个数——这是 csdid 和 TWFE 最本质的区别：
# TWFE 只给你一个隐含加权的系数，csdid 让你显式选怎么聚合。

cat("\n", strrep("=", 72), "\n", sep = "")
cat("聚合（对应 estat simple / group / calendar / event）\n")
cat(strrep("=", 72), "\n", sep = "")

agg_simple   <- aggte(cs_out, type = "simple",   na.rm = TRUE)  # ↔ estat simple
agg_group    <- aggte(cs_out, type = "group",    na.rm = TRUE)  # ↔ estat group
agg_calendar <- aggte(cs_out, type = "calendar", na.rm = TRUE)  # ↔ estat calendar
agg_dynamic  <- aggte(cs_out, type = "dynamic",  na.rm = TRUE)  # ↔ estat event

cat("\n--- simple：全样本汇总 ATT ---\n")
cat("  ATT = ", round(agg_simple$overall.att, 4),
    "   SE = ", round(agg_simple$overall.se, 4), "\n", sep = "")
cat("  95% 置信区间：[",
    round(agg_simple$overall.att - 1.96 * agg_simple$overall.se, 4), ", ",
    round(agg_simple$overall.att + 1.96 * agg_simple$overall.se, 4), "]\n", sep = "")

cat("\n--- group：按处理队列聚合 ---\n")
print(agg_group)

cat("\n--- calendar：按日历年聚合 ---\n")
print(agg_calendar)

cat("\n--- dynamic：事件研究（处理前后各期）---\n")
print(agg_dynamic)


# --- 6. 事件研究图 ------------------------------------------------------------
# 平行趋势假设**无法直接检验**，事件研究图只是间接诊断：
# 处理前各期系数接近 0 是间接支持，明显偏离 0 是否定证据。
# 见 references/did-checklist.md 第 1、2 条。

cat("\n", strrep("=", 72), "\n", sep = "")
cat("事件研究图\n")
cat(strrep("=", 72), "\n", sep = "")

p_event <- ggdid(agg_dynamic) +
  ggtitle("事件研究：最低工资调整对县级就业的影响") +
  xlab("相对处理年份") + ylab("ATT") +
  theme_minimal()

fig_path <- file.path(dir_figs, "fig_event_study.pdf")
ggsave(fig_path, plot = p_event, width = 8, height = 5, device = "pdf")
cat("  已导出：", fig_path, "\n", sep = "")

cat("\n  看图时注意 references/did-checklist.md 第 2 条的陷阱：\n")
cat("  若把 -1 期设为基期，该期系数被机械置零，\n")
cat("  「无预期效应」这个检验就失效了——要么挪基期，要么不设基期。\n")


# --- 7. TWFE 对照 + Sun-Abraham ----------------------------------------------
# 不是要替代 csdid，是要并列呈现：主回归用 csdid（方法升级），
# TWFE 放对照栏，展示「如果用传统方法，结果长这样」。
# 两者差很大时，正文要说明为什么选 csdid——这是稳健性讨论的一部分。
#
# 聚类层级与 csdid 保持一致，否则两栏的系数不可比
# （regression-spec.md 禁止事项：禁止在矩阵中悄悄改变聚类层级）。
#
# feols 不写 cluster 时到底是 iid 还是按第一个固定效应聚类，我**没有把握**
# （regression-spec.md 那段注里记了同一件事）。所以不赌默认值，一律显式写
# cluster = ~...，这样默认是哪个都不影响结果。装了 R 之后跑 ?feols 核一遍。

cat("\n", strrep("=", 72), "\n", sep = "")
cat("TWFE 对照（fixest::feols）\n")
cat(strrep("=", 72), "\n", sep = "")

twfe_fml <- as.formula(paste(OUTCOME, "~ treat |", IVAR, "+", TVAR))
twfe <- feols(twfe_fml, data = panel, cluster = as.formula(paste("~", CLUSTER)))
cat("\n--- TWFE（传统双向固定效应）---\n")
print(summary(twfe))

# Sun-Abraham 交互加权估计量：另一种针对渐进采纳负权重的修正。
# 和 csdid 并列，说明「修正负权重」不止一条路。
#
# sunab() 对「从未受处理」的编码在不同 fixest 版本里要求不一样：有的要 0，
# 有的要 Inf。mpdta 用的是 0，先按 0 跑；若报错说 cohort 里不能有 0，
# 就换成下面注释掉的那行。
sa_fml <- as.formula(paste(OUTCOME, "~ sunab(", GVAR, ", ", TVAR, ") |",
                           IVAR, "+", TVAR))
# panel$cohort_inf <- ifelse(panel[[GVAR]] == 0, Inf, panel[[GVAR]])
# sa_fml <- as.formula(paste(OUTCOME, "~ sunab(cohort_inf, ", TVAR, ") |",
#                            IVAR, "+", TVAR))
sa <- tryCatch(
  feols(sa_fml, data = panel, cluster = as.formula(paste("~", CLUSTER))),
  error = function(e) {
    cat("\n  Sun-Abraham 没跑成：", conditionMessage(e), "\n", sep = "")
    cat("  见本节注释里的 Inf 写法。这一栏是并列对照，缺了不影响 csdid 主结果。\n")
    NULL
  }
)
if (!is.null(sa)) {
  cat("\n--- Sun-Abraham 交互加权（另一种负权重修正）---\n")
  print(summary(sa))
}


# --- 8. 对照表 + 系数差 -------------------------------------------------------
# 两者差很多时要在正文说明为什么选 csdid，所以这个数字要主动算出来。
# **不填占位数字顶上**（README.md 第六节红线：跑不出来就报跑不出来）。

cat("\n", strrep("=", 72), "\n", sep = "")
cat("csdid vs TWFE 系数差\n")
cat(strrep("=", 72), "\n", sep = "")

att_cs   <- agg_simple$overall.att
se_cs    <- agg_simple$overall.se
att_twfe <- unname(coef(twfe)["treat"])
se_twfe  <- unname(coef(summary(twfe))["treat", "Std. Error"])

gap_pct <- 100 * (att_cs - att_twfe) / abs(att_twfe)

cat("\n  CS-DID (simple) ATT ：", sprintf("%9.4f", att_cs),
    "  (SE ", sprintf("%.4f", se_cs), ")\n", sep = "")
cat("  TWFE    treat 系数  ：", sprintf("%9.4f", att_twfe),
    "  (SE ", sprintf("%.4f", se_twfe), ")\n", sep = "")
cat("  差异                ：", sprintf("%9.2f", gap_pct), "%（相对 TWFE）\n", sep = "")
cat("\n  渐进采纳下两者不同是预期的——TWFE 会给已处理组负权重，\n")
cat("  CS-DID 只用尚未处理 / 从未处理的单元作对照，权重非负。\n")
cat("  差多少算大、正文怎么写，是研究者的判断，脚本不替你下结论。\n")

# LaTeX 表。手写而不用 knitr/modelsummary，是为了少依赖一个包：
# 学习阶段每多一个要装的包就多一道坎。
tex_path <- file.path(dir_tables, "tab_main.tex")
tex <- c(
  "\\begin{table}[htbp]",
  "\\centering",
  "\\caption{主回归：最低工资调整对县级就业的影响}",
  "\\begin{tabular}{lcc}",
  "\\toprule",
  " & CS-DID & TWFE \\\\",
  "\\midrule",
  sprintf("处理效应 & %9.4f & %9.4f \\\\", att_cs, att_twfe),
  sprintf("标准误   & (%9.4f) & (%9.4f) \\\\", se_cs, se_twfe),
  "\\midrule",
  sprintf("观测数   & %s & %s \\\\", format(n_obs, big.mark = ","),
          format(n_obs, big.mark = ",")),
  sprintf("县级数   & %s & %s \\\\", format(n_units, big.mark = ","),
          format(n_units, big.mark = ",")),
  "\\bottomrule",
  "\\end{tabular}",
  "\\begin{minipage}{\\linewidth}",
  "\\footnotesize 括号内为聚类在县层级的标准误。CS-DID 为 Callaway-Sant'Anna",
  "估计量的 \\texttt{simple} 聚合；TWFE 为双向固定效应。",
  "\\end{minipage}",
  "\\end{table}"
)
writeLines(tex, tex_path)
cat("\n  已导出：", tex_path, "\n", sep = "")

# 再落一份同名 .csv。同一个数字写两种格式看似多余，但阶段 06 要对账：
# 它的基准格必须和这里的 CS-DID 一栏对上，对不上说明两处不是同一套口径。
# 让 06 去解析 .tex 里的 `%9.4f` 太脆，一份机器可读的结果省掉这件事。
csv_path <- file.path(dir_tables, "tab_main.csv")
write.csv(data.frame(
  method = c("CS-DID", "TWFE"),
  att    = c(att_cs, att_twfe),
  se     = c(se_cs, se_twfe),
  n_obs  = c(n_obs, n_obs),
  n_units = c(n_units, n_units),
  data_md5 = data_sig
), csv_path, row.names = FALSE)
cat("  已导出：", csv_path, "（阶段 06 对账用）\n", sep = "")


# --- 9. 版本记录 --------------------------------------------------------------
# CLAUDE.md 第三节要求锁定依赖版本。R 的 CRAN 也没有「装旧版」的默认开关，
# 所以把实际装到的版本抄进日志，作为版本锁定的落点。

cat("\n", strrep("=", 72), "\n", sep = "")
cat("环境与版本记录（抄进 README.md 计算环境节）\n")
cat(strrep("=", 72), "\n", sep = "")
cat("  R version  : ", R.version.string, "\n", sep = "")
for (p in needed) {
  cat("  ", formatC(p, width = 10), ": ",
      as.character(utils::packageVersion(p)), "\n", sep = "")
}


# --- 10. HITL 停止点 ----------------------------------------------------------
# 到这里为止，脚本的任务是「把数字跑出来并留痕」，到此结束。
# 系数怎么解读、假设成不成立、要不要进稳健性——都属于研究者。
#
# 这条界线对应教程点名的训练数据泄漏风险：LLM 可能在复述它在预训练里
# 见过的经典结果，而不是从你这份数据里估出来的。mpdta 正是公开的经典数据集，
# 这个风险在本例里是实打实的。界画在「AI 跑代码、人读数字」。

cat("\n", strrep("=", 72), "\n", sep = "")
cat("主回归执行完毕 —— 请研究者审阅后再往下走\n")
cat(strrep("=", 72), "\n", sep = "")
cat("  观测数：", format(n_obs, big.mark = ","), "\n", sep = "")
cat("  县级数：", format(n_units, big.mark = ","), "\n", sep = "")
cat("  事件研究图：output/figures/fig_event_study.pdf\n")
cat("  系数表：output/tables/tab_main.tex\n")
cat("  日志：", logfile, "\n", sep = "")
cat("\n  要你亲自做的事：\n")
cat("    1. 看事件研究图的处理前各期系数是否接近 0（平行趋势的间接诊断）\n")
cat("    2. 检查 -1 期有没有被当基期置零（did-checklist.md 第 2 条）\n")
cat("    3. 判断 CS-DID 与 TWFE 的差异该怎么在正文里解释\n")
cat("    4. 判断这个 ATT 在经济上意味着什么\n")
cat("\n  **本脚本不解读上述任何一个数字，也不写正文措辞。**\n")
cat("  确认无误后再进阶段 06 稳健性检验——主回归错了，后面全要重跑。\n")
cat(strrep("=", 72), "\n", sep = "")

sink()
close(con)
cat("\n日志已写入：", logfile, "\n", sep = "")
