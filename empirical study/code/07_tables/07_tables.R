#==============================================================================
# 07_tables.R : 表格与图形生成
#
# 对应 README.md 第二节阶段 7。
# 教程给的是 Stata 版（esttab + csdid_plot / coefplot）。这里是它的 R 版：
#   esttab      → 手写 LaTeX（writeLines），见下面「少一个依赖」的取舍
#   csdid_plot  → did::ggdid()，在 05_main.R 里已经画过了，这里不重画
#
# **这一阶段唯一的职责是把数字搬进表格，不是算数字。**
# 表里每个数都从 output/robustness/cells.csv 和 output/tables/tab_main.csv 读，
# 一行都不许手敲（regression-spec.md 禁止事项）。
#
# 前置条件：05_main.R 和 06_robust.R 都跑过。缺哪个文件就明确报出来停下，
# 不用空表顶上——空表和「结果不显著」在版式上看不出区别。
#
# 输入：output/robustness/cells.csv（阶段 06）
#       output/tables/tab_main.csv（阶段 05）
#       config/robustness-matrix.R（对账用）
# 输出：output/tables/tab_robust_appendix.tex   完整矩阵（全部格子）
#       output/tables/tab_robust_main.tex       正文表（挑出来的几列）
#       output/figures/fig_robust_forest.pdf    稳健性森林图
# 日志：logs/07_tables_YYYYMMDD_HHMMSS.log
#
# 运行方式：先 cd 到 empirical study/ 再 source("code/07_tables/07_tables.R")
#==============================================================================


# --- 0. 环境自检 -------------------------------------------------------------
stopifnot(getRversion() >= "4.4.0")

# fixest 只在第 4 节的交叉校验里用（feols vs lm）。缺了就把那一节跳过并说明，
# 不让整张表生成失败——表的内容不依赖它。
needed <- c("ggplot2")
missing <- needed[!vapply(needed, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing) > 0) {
  cat("\n缺少这些 R 包：", paste(missing, collapse = ", "), "\n\n")
  cat('  install.packages(c(', paste0('"', missing, '"', collapse = ", "), '))\n\n')
  stop("先装包再跑本脚本。", call. = FALSE)
}
library(ggplot2)

has_fixest <- requireNamespace("fixest", quietly = TRUE)


# --- 1. 目录、日志 -----------------------------------------------------------
root <- getwd()
sentinel <- file.path(root, "code", "07_tables", "07_tables.R")
if (!file.exists(sentinel)) {
  stop("当前工作目录不是 empirical study/（当前：", root, "）\n",
       "先 setwd() 到 empirical study/ 再 source 本文件。", call. = FALSE)
}

dir_tables <- file.path(root, "output", "tables")
dir_figs   <- file.path(root, "output", "figures")
dir_logs   <- file.path(root, "logs")
for (d in c(dir_tables, dir_figs, dir_logs)) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
logfile <- file.path(dir_logs, paste0("07_tables_", stamp, ".log"))
k <- 2L
while (file.exists(logfile)) {
  logfile <- file.path(dir_logs, paste0("07_tables_", stamp, "_", k, ".log"))
  k <- k + 1L
}
con <- file(logfile, open = "wt")
sink(con, split = TRUE)


# --- 2. 参数区 —— 研究者定 ---------------------------------------------------
# 正文表展示哪几列。**这是研究者的取舍**，不是脚本的判断：完整矩阵在附录，
# 正文只挑几列讲重点（README.md 第七节）。
# 下面这组是「基准格 + 每个维度各变一次」的默认挑法，跑之前请自己看一眼——
# 挑哪几列等于决定读者看到什么，这件事不该由默认值代劳。
DISPLAY_CELLS <- c(
  "cs|lpop|full|log",          # 基准
  "cs|none|full|log",          # 变控制变量
  "cs|lpop|drop_large|log",    # 变样本
  "cs|lpop|full|level"         # 变函数形式
)

# 显著性星号。阈值照 regression-spec.md：* 0.1、** 0.05、*** 0.01。
STAR_CUT <- c(`***` = 0.01, `**` = 0.05, `*` = 0.1)


# --- 3. 读结果文件 -----------------------------------------------------------
cells_path <- file.path(root, "output", "robustness", "cells.csv")
main_path  <- file.path(dir_tables, "tab_main.csv")

if (!file.exists(cells_path)) {
  sink(); close(con)
  stop("找不到 ", cells_path, "\n先跑 06_robust.R 生成稳健性矩阵。", call. = FALSE)
}
if (!file.exists(main_path)) {
  sink(); close(con)
  stop("找不到 ", main_path, "\n先跑 05_main.R。本脚本要靠它做口径对账。",
       call. = FALSE)
}

cells <- read.csv(cells_path, stringsAsFactors = FALSE)
main  <- read.csv(main_path,  stringsAsFactors = FALSE)

cat("\n", strrep("=", 72), "\n", sep = "")
cat("读取结果文件\n")
cat(strrep("=", 72), "\n", sep = "")
cat("  稳健性矩阵：", nrow(cells), " 格（", cells_path, "）\n", sep = "")
cat("  主回归    ：", nrow(main), " 行（", main_path, "）\n", sep = "")
cat("  主回归数据指纹：", main$data_md5[1], "\n", sep = "")


# --- 4. 完整性核对 + 口径交叉校验 --------------------------------------------
# 这一步的存在理由：**表格出错最常见的方式不是数字算错，是数字对不上号**。
# 少了一格、多了一格、某格其实没跑成却被当成结果排版——这些在版式上
# 全都看不出来。所以出表之前先把「应该有几格、实际有几格」对一遍。

cat("\n", strrep("=", 72), "\n", sep = "")
cat("完整性核对\n")
cat(strrep("=", 72), "\n", sep = "")

cfg_path <- file.path(root, "config", "robustness-matrix.R")
expect_keys <- NULL
if (file.exists(cfg_path)) {
  .cfg <- new.env(parent = globalenv())
  sys.source(cfg_path, envir = .cfg)
  expect_keys <- if (isTRUE(.cfg$FULL_PRODUCT)) {
    g <- expand.grid(est = .cfg$DIMS$est, ctrl = .cfg$DIMS$ctrl,
                     sample = .cfg$DIMS$sample, outcome = .cfg$DIMS$outcome,
                     stringsAsFactors = FALSE)
    do.call(paste, c(g[c("est", "ctrl", "sample", "outcome")], sep = "|"))
  } else {
    .cfg$SELECT
  }
} else {
  cat("  ⚠ 找不到矩阵配置，跳过「应该有几格」的核对。\n")
}

got_keys <- paste(cells$est, cells$ctrl, cells$sample, cells$outcome, sep = "|")
if (!is.null(expect_keys)) {
  miss <- setdiff(expect_keys, got_keys)
  extra <- setdiff(got_keys, expect_keys)
  cat("  配置里要求：", length(expect_keys), " 格；结果文件里：",
      length(got_keys), " 格\n", sep = "")
  if (length(miss) > 0) {
    cat("  ⚠ 配置里有、结果文件里没有的格子（**这些格没跑**）：\n")
    cat(paste("      ", miss, collapse = "\n"), "\n")
  }
  if (length(extra) > 0) {
    cat("  ⚠ 结果文件里有、配置里没有的格子（配置改过了？）：\n")
    cat(paste("      ", extra, collapse = "\n"), "\n")
  }
  if (length(miss) == 0 && length(extra) == 0) {
    cat("  格子数与配置一致。\n")
  }
}

cat("\n  各状态计数：\n")
print(table(cells$status))
n_ok <- sum(cells$status == "ok")
cat("  可进表的格子：", n_ok, " / ", nrow(cells), "\n", sep = "")
if (n_ok < nrow(cells)) {
  cat("  没能进表的格子会以「—」出现在附录表里，并带一行原因说明。\n")
  cat("  **不要因为它们不好看就把行删掉**——完整矩阵本身就是诚信证明。\n")
}

# --- 交叉校验一：阶段 06 的基准格 vs 阶段 05 的主表
# 两边是同一个估计量、同一份数据、同一个聚合方式，应当给出同一个数。
# 对不上说明两处不是同一套口径——这是最容易发生、也最难从版式上看出的错。
cat("\n", strrep("=", 72), "\n", sep = "")
cat("交叉校验（这一步是给「代码错了」和「理论差异」分家的）\n")
cat(strrep("=", 72), "\n", sep = "")

if (file.exists(cfg_path)) {
  base_key <- .cfg$BASELINE_CELL
  bp <- strsplit(base_key, "|", fixed = TRUE)[[1]]
  b <- cells[cells$est == bp[1] & cells$ctrl == bp[2] &
             cells$sample == bp[3] & cells$outcome == bp[4], ]
  cs_main <- main$att[main$method == "CS-DID"]
  if (nrow(b) == 1 && b$status[1] == "ok" && length(cs_main) == 1) {
    d <- abs(b$att[1] - cs_main)
    cat("  06 基准格（", base_key, "）ATT = ", sprintf("%.6f", b$att[1]), "\n", sep = "")
    cat("  05 主表   CS-DID           ATT = ", sprintf("%.6f", cs_main), "\n", sep = "")
    cat("  差 = ", sprintf("%.6f", d), " -> ",
        if (d < 1e-6) "一致" else "**不一致，先查这里再出表**", "\n", sep = "")
    if (d >= 1e-6) {
      cat("  提示：两边都设了 set.seed(20260417)，自助法的随机数流应当一致。\n")
      cat("  不一致的常见来源是控制变量集、control_group 或样本口径被改过。\n")
    }
  } else {
    cat("  基准格 ", base_key, " 不在可用的结果里，跳过这一步对账。\n", sep = "")
  }
  # 数据指纹：两份文件读的是不是同一份面板。指纹不同，上面的对账就没有意义。
  if ("data_md5" %in% names(cells)) {
    fp_cells <- unique(cells$data_md5)
    fp_main  <- unique(main$data_md5)
    cat("  指纹：06 = ", paste(fp_cells, collapse = ","),
        "；05 = ", paste(fp_main, collapse = ","), "\n", sep = "")
    if (!any(fp_cells %in% fp_main)) {
      cat("  ⚠ 两份结果的数据指纹不同——它们读的不是同一份面板，\n")
      cat("    上面那行「差 = ...」不可比，先查数据来源。\n")
    }
  }
}

# --- 交叉校验二：同一规范、两种实现
# 教程原话：若两种工具链在同样规范下给出不同系数，基本可以锁定代码错误。
# Stata 那边是 reghdfe vs 别的实现；R 这边对应的是 feols（吸收固定效应）
# 与 lm（把固定效应展开成哑变量）。两者都是 OLS，**点估计应当逐位相同**。
#
# 只比点估计，不比标准误——feols 这里是聚类标准误、lm 是经典同方差标准误，
# 两者按构造就该不同，比它等于自找误报。
if (has_fixest) {
  cat("\n", strrep("-", 72), "\n", sep = "")
  cat("  feols vs lm（双向固定效应用两种写法估一遍，系数应当相同）\n")
  cat(strrep("-", 72), "\n", sep = "")
  PANEL_SOURCE <- "mpdta"
  if (PANEL_SOURCE == "mpdta") {
    .e <- new.env(); data(mpdta, package = "did", envir = .e)
    pnl <- .e$mpdta; rm(.e)
  } else {
    pnl <- readRDS(file.path(root, "data", "processed", "panel.rds"))
  }
  IVAR <- "countyreal"; TVAR <- "year"; GVAR <- "first.treat"
  if (!"treat" %in% names(pnl)) {
    pnl$treat <- as.integer(pnl[[TVAR]] >= pnl[[GVAR]] & pnl[[GVAR]] > 0)
  }
  f_abs <- fixest::feols(lemp ~ treat | countyreal + year, data = pnl,
                         cluster = ~countyreal)
  f_lm  <- lm(lemp ~ treat + factor(countyreal) + factor(year), data = pnl)
  b_abs <- unname(coef(f_abs)["treat"])
  b_lm  <- unname(coef(f_lm)["treat"])
  cat("    feols（| 吸收）    ：", sprintf("%.8f", b_abs), "\n", sep = "")
  cat("    lm（哑变量展开）   ：", sprintf("%.8f", b_lm), "\n", sep = "")
  cat("    差                 ：", sprintf("%.2e", abs(b_abs - b_lm)), "\n", sep = "")
  cat("    ", if (abs(b_abs - b_lm) < 1e-8) {
    "一致——两处口径相同，可以往下走。"
  } else {
    "**不一致。** 先查两件事：fixest 默认会丢掉单例组（fixef.rm），\n      而 lm 不会；以及两边样本量是否相同。"
  }, "\n", sep = "")
} else {
  cat("\n  （没装 fixest，跳过 feols vs lm 的交叉校验。）\n")
}


# --- 5. 出表用的格式化函数 ---------------------------------------------------
# 星号跟着 p 值走。p 值本身不进表（期刊惯例是只留星号），但判定留在这里，
# 别处不要各写一遍。
star_of <- function(p) {
  if (is.na(p)) return("")
  if (p < STAR_CUT[["***"]]) return("***")
  if (p < STAR_CUT[["**"]])  return("**")
  if (p < STAR_CUT[["*"]])   return("*")
  ""
}
# 用正态近似从点估计和标准误反推 p。cs 格的自助法标准误、twfe 格的聚类标准误
# 都是渐近正态的，这个近似在样本量下站得住；**但它是近似，不是原始 p 值**。
# 若日后要精确 p 值，得从各估计量的结果对象里直接取。
p_of <- function(att, se) {
  if (is.na(att) || is.na(se) || se <= 0) return(NA_real_)
  2 * stats::pnorm(-abs(att / se))
}

fmt_est <- function(att, se) {
  if (is.na(att)) return("—")
  paste0(sprintf("%.3f", att), star_of(p_of(att, se)))
}
fmt_se <- function(se) {
  if (is.na(se)) return("")
  paste0("(", sprintf("%.3f", se), ")")
}


# --- 6. 附录表：完整矩阵 -----------------------------------------------------
# 全部格子都进附录，包括没跑成的。**这是本阶段最重要的一条纪律**：
# 稳健性检验最大的诱惑是只报告支持主结论的列；完整的矩阵本身就是诚信证明
# （README.md 第七节红线）。

cells$est_label <- c(twfe = "TWFE", cs = "CS-DID", sa = "Sun-Abraham",
                     sdid = "SDID")[cells$est]
cells$est_label[is.na(cells$est_label)] <- cells$est[is.na(cells$est_label)]
cells$ctrl_label <- c(none = "无控制", lpop = "+ lpop")[cells$ctrl]
cells$ctrl_label[is.na(cells$ctrl_label)] <- cells$ctrl[is.na(cells$ctrl_label)]

# 排序：估计量分组、组内按样本和结果变量。排序只为好读，不影响任何数字。
ord <- order(match(cells$est, c("twfe", "cs", "sa", "sdid")),
             match(cells$sample, c("full", "drop_large", "drop_last")),
             match(cells$outcome, c("log", "level", "ihs")))
cells <- cells[ord, ]

app <- c(
  "\\begin{table}[htbp]",
  "\\centering",
  "\\caption{稳健性检验矩阵：全部格子}",
  "\\small",
  "\\begin{tabular}{llllrrrr}",
  "\\toprule",
  "估计量 & 控制变量 & 样本 & 结果变量 & 系数 & 标准误 & 观测数 & 单元数 \\\\",
  "\\midrule"
)
for (i in seq_len(nrow(cells))) {
  r <- cells[i, ]
  app <- c(app, sprintf("%s & %s & %s & %s & %s & %s & %s & %s \\\\",
                        r$est_label, r$ctrl_label,
                        c(full = "全样本", drop_large = "排除大单元",
                          drop_last = "排除末期")[r$sample],
                        c(log = "对数", level = "水平值",
                          ihs = "IHS")[r$outcome],
                        fmt_est(r$att, r$se), fmt_se(r$se),
                        ifelse(is.na(r$n_obs), "—",
                               format(r$n_obs, big.mark = ",")),
                        ifelse(is.na(r$n_units), "—",
                               format(r$n_units, big.mark = ","))))
}
app <- c(app, "\\bottomrule", "\\end{tabular}")
app <- c(app,
  "\\begin{minipage}{\\linewidth}",
  "\\footnotesize 括号内为聚类标准误。``—'' 表示该格未产出估计值，原因见表下说明。",
  "星号：$^{*}$ 0.1、$^{**}$ 0.05、$^{***}$ 0.01。",
  "\\end{minipage}")
# 没跑成的格子逐条列在表下。不列的话，附录表里的一排「—」看上去像是
# 「跑了但没结果」，和「根本没跑」分不开。
bad <- cells[cells$status != "ok", ]
if (nrow(bad) > 0) {
  app <- c(app,
    "\\vspace{0.5em}",
    "\\begin{minipage}{\\linewidth}",
    "\\footnotesize \\textbf{未产出估计值的格子：}",
    paste0(sprintf("\\textit{%s}：%s。", bad$cell_id, bad$note), collapse = " "),
    "\\end{minipage}")
}
app <- c(app, "\\end{table}")

app_path <- file.path(dir_tables, "tab_robust_appendix.tex")
writeLines(app, app_path)
cat("\n  已导出：", app_path, "（", nrow(cells), " 行，含 ",
    nrow(bad), " 个未产出的格子）\n", sep = "")


# --- 7. 正文表：挑出来的几列 ------------------------------------------------
cat("\n", strrep("=", 72), "\n", sep = "")
cat("正文表（DISPLAY_CELLS 指定的列）\n")
cat(strrep("=", 72), "\n", sep = "")

disp <- cells[paste(cells$est, cells$ctrl, cells$sample, cells$outcome,
                    sep = "|") %in% DISPLAY_CELLS, ]
not_found <- setdiff(DISPLAY_CELLS,
                     paste(cells$est, cells$ctrl, cells$sample, cells$outcome,
                           sep = "|"))
if (length(not_found) > 0) {
  cat("  ⚠ 参数区 DISPLAY_CELLS 里这些格在结果文件中找不到：\n")
  cat(paste("      ", not_found, collapse = "\n"), "\n")
}
cat("  实际进正文表的列数：", nrow(disp), "\n", sep = "")

if (nrow(disp) > 0) {
  mn <- c(
    "\\begin{table}[htbp]",
    "\\centering",
    "\\caption{稳健性检验：主回归结果在不同规范下的表现}",
    "\\begin{tabular}{l" , paste(rep("c", nrow(disp)), collapse = ""), "}",
    "\\toprule",
    paste(c("", paste0("(", seq_len(nrow(disp)), ")")), collapse = " & "),
    "\\\\",
    "\\midrule",
    paste(c("处理效应", fmt_est(disp$att, disp$se)), collapse = " & "), "\\\\",
    paste(c("", fmt_se(disp$se)), collapse = " & "), "\\\\",
    "\\midrule",
    paste(c("估计量", disp$est_label), collapse = " & "), "\\\\",
    paste(c("控制变量", disp$ctrl_label), collapse = " & "), "\\\\",
    paste(c("样本", c(full = "全样本", drop_large = "排除大单元",
                      drop_last = "排除末期")[disp$sample]), collapse = " & "), "\\\\",
    paste(c("结果变量", c(log = "对数", level = "水平值",
                          ihs = "IHS")[disp$outcome]), collapse = " & "), "\\\\",
    paste(c("观测数", format(disp$n_obs, big.mark = ",")), collapse = " & "), "\\\\",
    "\\bottomrule",
    "\\end{tabular}",
    "\\begin{minipage}{\\linewidth}",
    "\\footnotesize 括号内为聚类标准误。星号：$^{*}$ 0.1、$^{**}$ 0.05、$^{***}$ 0.01。",
    "完整矩阵见附录表。",
    "\\end{minipage}",
    "\\end{table}"
  )
  mn_path <- file.path(dir_tables, "tab_robust_main.tex")
  writeLines(mn, mn_path)
  cat("  已导出：", mn_path, "\n", sep = "")
  cat("\n  **挑哪几列就是决定读者看到什么。** 参数区那组是默认挑法，\n")
  cat("  出正文前请自己看一眼，不满意就改 DISPLAY_CELLS 重跑本脚本。\n")
}


# --- 8. 稳健性森林图 ---------------------------------------------------------
# 一个格子一个点、一条 95% 置信区间，横轴是 ATT，纵轴是格子。
# 主回归的基准格单独标出来——图上第一眼该看到的是「各格有没有跑偏」。
#
# 真正该盯的是**跨过 0 的那些格**和**符号相反的那些格**。图只是把它们
# 摆到一起，判断仍然是人做。

cat("\n", strrep("=", 72), "\n", sep = "")
cat("稳健性森林图\n")
cat(strrep("=", 72), "\n", sep = "")

plot_df <- cells[cells$status == "ok" & !is.na(cells$att), ]
if (nrow(plot_df) >= 2) {
  plot_df$key <- paste(plot_df$est, plot_df$ctrl, plot_df$sample,
                       plot_df$outcome, sep = "|")
  plot_df$label <- paste0(plot_df$est_label, " | ",
                          c(full = "全样本", drop_large = "排大",
                            drop_last = "排末期")[plot_df$sample], " | ",
                          c(log = "对数", level = "水平", ihs = "IHS")[plot_df$outcome],
                          ifelse(plot_df$ctrl == "none", " | 无控制", ""))
  # 基准格排最上面，其余保持附录表的顺序
  plot_df <- plot_df[order(plot_df$key != .cfg$BASELINE_CELL), ]
  plot_df$label <- factor(plot_df$label, levels = rev(plot_df$label))
  plot_df$is_base <- plot_df$key == .cfg$BASELINE_CELL

  main_cs <- main$att[main$method == "CS-DID"][1]

  p_forest <- ggplot(plot_df, aes(x = att, y = label)) +
    geom_vline(xintercept = 0, linetype = "dashed", colour = "grey50") +
    geom_vline(xintercept = main_cs, linetype = "dotted", colour = "steelblue") +
    geom_errorbarh(aes(xmin = ci_lo, xmax = ci_hi), height = 0.15,
                   colour = "grey30") +
    geom_point(aes(colour = is_base), size = 2.2) +
    scale_colour_manual(values = c(`TRUE` = "firebrick", `FALSE` = "grey20"),
                        labels = c(`TRUE` = "基准格", `FALSE` = "其余格子"),
                        name = NULL) +
    labs(title = "稳健性检验矩阵：各格 ATT 与 95% 置信区间",
         subtitle = "实线为 0，点线为阶段 05 主回归的 CS-DID 估计",
         x = "ATT", y = NULL) +
    theme_minimal(base_size = 10)

  fig_path <- file.path(dir_figs, "fig_robust_forest.pdf")
  ggsave(fig_path, plot = p_forest,
         width = 9, height = max(3.5, 0.32 * nrow(plot_df) + 2),
         device = "pdf")
  cat("  已导出：", fig_path, "（", nrow(plot_df), " 格）\n", sep = "")
} else {
  cat("  可用格子少于 2 个，不出图。\n")
}

cat("\n", strrep("=", 72), "\n", sep = "")
cat("表格图形已生成 —— 请研究者审阅后再进阶段 08\n")
cat(strrep("=", 72), "\n", sep = "")
cat("\n  要你亲自做的事：\n")
cat("    1. 正文表挑的那几列是不是你想让读者看到的\n")
cat("    2. 森林图上有没有跨过 0、或符号和主回归相反的格子\n")
cat("    3. 它们在附录里保留，正文里怎么说明可能原因\n")
cat("\n  **本脚本不解读上述任何一个数字，也不写正文措辞。**\n")
cat(strrep("=", 72), "\n", sep = "")

sink()
close(con)
cat("\n日志已写入：", logfile, "\n", sep = "")
