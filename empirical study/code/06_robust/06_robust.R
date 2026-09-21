#==============================================================================
# 06_robust.R : 稳健性检验矩阵 —— 按配置逐格执行
#
# 对应 README.md 第二节阶段 6、CLAUDE.md 第七节第 4 条 HITL 节点。
# 教程给的是 Stata 版（每个格子生成一个临时 .do，用 stata-mp 批量跑）。
# 这里是它的 R 版，**有一处结构性差异**，见 06_robust/README.md 的对照表：
#
#   教程：每格一个临时 do 文件 → 调用 stata-mp -b do tmp_cell_XX.do
#   这里：一个脚本内循环 → R 有真正的循环和 tryCatch，不需要文件周转
#
# 每格一个临时文件是 Stata 分批执行模型的产物，不是设计选择。R 里用循环 +
# tryCatch 能拿到同样的隔离（一格炸了不影响其他格），而且不用管临时文件的
# 清理和命名冲突。**隔离靠 tryCatch，不靠文件。**
#
# 输入：config/robustness-matrix.R（矩阵边界，HITL 产物）
#       示例面板 mpdta 或 data/processed/panel.rds
# 输出：output/robustness/cells.csv   逐格结果，每跑完一格就落盘一次
# 日志：logs/06_robust_YYYYMMDD_HHMMSS.log
#
# **本脚本不评判结果。** 哪个格子稳、哪个翻了、正文怎么写，是研究者的事。
# 脚本只负责把每格的数字算出来、把失败原因记下来、把数据指纹留上。
#
# 运行方式：先 cd 到 empirical study/ 再 source("code/06_robust/06_robust.R")
#==============================================================================


# --- 0. 环境自检 -------------------------------------------------------------
stopifnot(getRversion() >= "4.4.0")

# 比 05_main.R 少一个 ggplot2——这里只出数字，不出图，图留给 07_tables.R。
needed <- c("did", "fixest")
missing <- needed[!vapply(needed, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing) > 0) {
  cat("\n缺少这些 R 包：", paste(missing, collapse = ", "), "\n\n")
  cat("装它们（在 R / RStudio 控制台里跑）：\n\n")
  cat('  install.packages(c(', paste0('"', missing, '"', collapse = ", "), '))\n\n')
  stop("先装包再跑本脚本。", call. = FALSE)
}

library(did)
library(fixest)


# --- 1. 目录、日志 -----------------------------------------------------------
root <- getwd()
sentinel <- file.path(root, "code", "06_robust", "06_robust.R")
if (!file.exists(sentinel)) {
  stop("当前工作目录不是 empirical study/（当前：", root, "）\n",
       "先 setwd() 到 empirical study/ 再 source 本文件。", call. = FALSE)
}

cfg_path <- file.path(root, "config", "robustness-matrix.R")
if (!file.exists(cfg_path)) {
  stop("找不到矩阵配置 ", cfg_path, "。阶段 06 的一切以它为准，缺了不能跑。",
       call. = FALSE)
}

dir_robust <- file.path(root, "output", "robustness")
dir_logs   <- file.path(root, "logs")
for (d in c(dir_robust, dir_logs)) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
logfile <- file.path(dir_logs, paste0("06_robust_", stamp, ".log"))
k <- 2L
while (file.exists(logfile)) {
  logfile <- file.path(dir_logs, paste0("06_robust_", stamp, "_", k, ".log"))
  k <- k + 1L
}
con <- file(logfile, open = "wt")
sink(con, split = TRUE)


# --- 2. 载入矩阵配置 + 校验 + 闸门 -------------------------------------------
# 配置用独立环境接住，不撒进本脚本的全局环境。理由同 05_main.R 处理
# data() 的那一处：source() 默认往 parent.frame() 塞，接住才不依赖调用方式。
.cfg <- new.env(parent = globalenv())
sys.source(cfg_path, envir = .cfg)

need_cfg <- c("MATRIX_CONFIRMED", "DIMS", "CONTROLS", "SAMPLES",
              "OUTCOMES", "OUTCOME_COL", "SELECT", "BASELINE_CELL",
              "FULL_PRODUCT", "SDID_NOTE")
absent <- setdiff(need_cfg, ls(.cfg))
if (length(absent) > 0) {
  cat("配置里缺这些项：", paste(absent, collapse = ", "), "\n")
  sink(); close(con)
  stop("矩阵配置不完整，已中止。", call. = FALSE)
}

MATRIX_CONFIRMED <- .cfg$MATRIX_CONFIRMED
DIMS       <- .cfg$DIMS
CONTROLS   <- .cfg$CONTROLS
SAMPLES    <- .cfg$SAMPLES
OUTCOMES   <- .cfg$OUTCOMES
OUTCOME_COL <- .cfg$OUTCOME_COL
BASELINE_CELL <- .cfg$BASELINE_CELL
FULL_PRODUCT  <- .cfg$FULL_PRODUCT

cat("\n", strrep("=", 72), "\n", sep = "")
cat("稳健性矩阵边界（来自 config/robustness-matrix.R）\n")
cat(strrep("=", 72), "\n", sep = "")
cat("  估计量    ：", paste(DIMS$est, collapse = " / "), "\n")
cat("  控制变量集：", paste(DIMS$ctrl, collapse = " / "), "\n")
cat("  样本范围  ：", paste(DIMS$sample, collapse = " / "), "\n")
cat("  结果变量  ：", paste(DIMS$outcome, collapse = " / "), "\n")
cat("  格子数    ：",
    if (isTRUE(FULL_PRODUCT)) {
      paste0("跑满笛卡尔积 = ", prod(vapply(DIMS, length, integer(1))), " 格")
    } else {
      paste0("SELECT 指定 = ", length(.cfg$SELECT), " 格")
    }, "\n")
cat("  基准格    ：", BASELINE_CELL, "（要与阶段 05 对账）\n")
cat("  SDID      ：", .cfg$SDID_NOTE, "\n")
cat(strrep("=", 72), "\n", sep = "")

# 校验 SELECT 里每一条。**写错的格子必须当场报出来**——静默少跑一格，
# 汇总表就会少一列，而且没人看得出是漏了还是本来就没打算跑。
if (!isTRUE(FULL_PRODUCT)) {
  bad <- character(0)
  for (i in seq_along(.cfg$SELECT)) {
    parts <- strsplit(.cfg$SELECT[i], "|", fixed = TRUE)[[1]]
    if (length(parts) != 4L) {
      bad <- c(bad, sprintf("  第 %d 条「%s」：不是四段（应写成 估计量|控制集|样本|结果变量）",
                            i, .cfg$SELECT[i]))
      next
    }
    for (j in 1:4) {
      dim_name <- c("est", "ctrl", "sample", "outcome")[j]
      if (!parts[j] %in% DIMS[[dim_name]]) {
        bad <- c(bad, sprintf("  第 %d 条「%s」：%s 不认识「%s」，可选 %s",
                              i, .cfg$SELECT[i], dim_name, parts[j],
                              paste(DIMS[[dim_name]], collapse = " / ")))
      }
    }
  }
  if (length(bad) > 0) {
    cat("\nSELECT 里有写错的条目：\n")
    cat(paste(bad, collapse = "\n"), "\n")
    sink(); close(con)
    stop("矩阵配置有错，已中止。", call. = FALSE)
  }
}

# 闸门。和 05_main.R 的 CONFIRMED 同一个机制。
if (!isTRUE(MATRIX_CONFIRMED)) {
  cat("\n")
  cat("MATRIX_CONFIRMED 不是 TRUE —— 本脚本拒绝执行。\n\n")
  cat("矩阵边界是 HITL 节点（CLAUDE.md 第七节第 4 条）：换哪些估计量、\n")
  cat("切哪几刀样本、试到什么程度算够，都靠研究者划，脚本不替你决定。\n\n")
  cat("三件事都要做：\n")
  cat("  1. 对着上面这段边界，确认 DIMS / SELECT 就是你要的范围\n")
  cat("  2. 确认 references/did-checklist.md 里那些假设你都担得起\n")
  cat("  3. 想清楚「稳健性做到哪种程度可以收手」——这是本阶段唯一的判断\n")
  cat("确认无误后，把 config/robustness-matrix.R 里 MATRIX_CONFIRMED 改成 TRUE。\n\n")
  sink(); close(con)
  stop("矩阵边界未确认，已中止。", call. = FALSE)
}


# --- 3. 读面板 + 基础守卫 -----------------------------------------------------
PANEL_SOURCE <- "mpdta"   # 与 05_main.R 保持同一个开关；换 QCEW 时一起改

OUTCOME <- "lemp"; GVAR <- "first.treat"
IVAR <- "countyreal"; TVAR <- "year"; CLUSTER <- "countyreal"

cat("\n", strrep("=", 72), "\n", sep = "")
cat("读取面板\n")
cat(strrep("=", 72), "\n", sep = "")

if (PANEL_SOURCE == "mpdta") {
  .e <- new.env()
  data(mpdta, package = "did", envir = .e)
  base_panel <- .e$mpdta
  rm(.e)
} else {
  base_panel <- readRDS(file.path(root, "data", "processed", "panel.rds"))
}

absent <- setdiff(c(OUTCOME, GVAR, IVAR, TVAR, CLUSTER), names(base_panel))
if (length(absent) > 0) {
  cat("  面板里没有这些变量：", paste(absent, collapse = ", "), "\n")
  cat("  它实际有：", paste(names(base_panel), collapse = ", "), "\n")
  sink(); close(con)
  stop("变量缺失，已中止。", call. = FALSE)
}
if (anyDuplicated(base_panel[c(IVAR, TVAR)]) > 0) {
  sink(); close(con)
  stop("主键 ", IVAR, " + ", TVAR, " 不唯一——面板没聚合干净。", call. = FALSE)
}

# 处理指示变量。从 gvar 和 year 现造，**不用面板里可能已有的同名列**——
# 一个约定贯穿所有格子，避免「这格用的是源数据的 treat、那格用的是造的」。
# 边界写 >= 不写 >（CLAUDE.md 第九节）；gvar > 0 让从未受处理的单元保持 0。
treat_D <- as.integer(base_panel[[TVAR]] >= base_panel[[GVAR]] &
                        base_panel[[GVAR]] > 0)
base_panel$treat_D <- treat_D

# 如果源数据自带 treat 列，和现造的核一遍。对不上要说出来——
# 对不上意味着两种处理定义不一致，而后面所有 TWFE 格子都建立在这个定义上。
if ("treat" %in% names(base_panel)) {
  n_mismatch <- sum(base_panel$treat != treat_D, na.rm = TRUE)
  cat("  处理变量核对：现造的 treat_D 与源数据 treat 列不一致的观测 = ",
      n_mismatch, "\n", sep = "")
  if (n_mismatch > 0) {
    cat("  ⚠ 两者不一致。本脚本一律用现造的 treat_D（定义统一），\n")
    cat("    但这个差异要你自己判断是哪种处理定义，别当没看见。\n")
  }
}

cat("  观测数：", format(nrow(base_panel), big.mark = ","), "\n", sep = "")
cat("  县级数：", format(length(unique(base_panel[[IVAR]])), big.mark = ","), "\n", sep = "")
cat("  年份区间：", min(base_panel[[TVAR]]), " - ", max(base_panel[[TVAR]]), "\n", sep = "")

# 数据指纹。整份面板一个指纹（不是逐格算）——各格都是它切出来的子集，
# 指纹钉住母本，加上每格的样本量，就能还原出这一格读的是哪份数据。
cat("\n  数据指纹（母本面板）：\n")
sig_tmp <- tempfile()
saveRDS(base_panel, sig_tmp, version = 2)
data_sig <- substr(unname(tools::md5sum(sig_tmp)), 1, 12)
unlink(sig_tmp)
cat("    md5 = ", data_sig, "\n", sep = "")


# --- 4. 派生辅助列 -----------------------------------------------------------
# 样本规则里用到的量先算好，理由：**规则共用一套口径**，而且阈值是按整份
# 面板定的，不随每个格子的子样本漂。阈值要是跟着子样本走，「切样本」和
# 「改阈值」两个维度就混在一起了，看不出是哪一刀起的作用。

base_panel$lpop_p90 <- as.numeric(stats::quantile(base_panel$lpop, 0.90,
                                                  na.rm = TRUE))

cat("\n  派生辅助列：lpop_p90 = ",
    sprintf("%.3f", base_panel$lpop_p90[1]), "\n", sep = "")


# --- 5. 逐格执行 -------------------------------------------------------------
# 一个格子 = (估计量, 控制集, 样本, 结果变量) 四元组。run_cell() 只算数，
# 不判断；失败不抛出，而是把原因写成 status = "error" 的一行记下来。
#
# **失败也要留一行。** 悄悄少一格，汇总表就少一列，而且事后无从分辨
# 「这格跑了但结果不好看」和「这格根本没跑」。稳定性由 reviewer-agent 判断，
# 脚本的职责是保证「跑过什么、没跑成什么」全都看得见。

run_cell <- function(cell_id, est, ctrl, smp, oc, seed_i) {
  # 每个格子一个独立种子：重跑单独一格能复现出同一个数，且格与格之间
  # 不共享随机数流（CLAUDE.md 第二节的基准种子 + 序号约定）。
  set.seed(seed_i)

  mk <- function(status, note = "", att = NA_real_, se = NA_real_,
                 n_obs = NA_integer_, n_units = NA_integer_,
                 n_treated = NA_integer_) {
    data.frame(
      cell_id = cell_id, est = est, ctrl = ctrl, sample = smp,
      outcome = oc, status = status,
      att = att, se = se,
      ci_lo = if (is.na(att) || is.na(se)) NA_real_ else att - 1.96 * se,
      ci_hi = if (is.na(att) || is.na(se)) NA_real_ else att + 1.96 * se,
      n_obs = n_obs, n_units = n_units, n_treated_units = n_treated,
      cluster = CLUSTER, seed = seed_i, data_md5 = data_sig,
      note = note,
      stringsAsFactors = FALSE
    )
  }

  # --- 切样本。这是全项目唯一允许重新切样本的地方（CLAUDE.md 第九节），
  #     每刀都要报损。
  keep <- eval(SAMPLES[[smp]], envir = base_panel)
  # quote(TRUE) 是「不切」最自然的写法，但长度 1 的逻辑值在 `[` 里会循环，
  # 语义上是「全留」却容易被读成别的意思。在一处摊平，别处就不必猜。
  if (is.logical(keep) && length(keep) == 1L) keep <- rep(keep, nrow(base_panel))
  if (!is.logical(keep) || length(keep) != nrow(base_panel)) {
    return(mk("error", sprintf("样本规则 %s 没算出长度正确的逻辑向量（得到 %s 长度 %d）",
                               smp, class(keep)[1], length(keep))))
  }
  keep[is.na(keep)] <- FALSE
  sub <- base_panel[keep, , drop = FALSE]
  n0 <- nrow(base_panel); n1 <- nrow(sub)
  cat(sprintf("    [报损] %s：%d -> %d（剔 %d，%.2f%%）\n",
              smp, n0, n1, n0 - n1, 100 * (n0 - n1) / n0))

  if (n1 == 0) return(mk("error", sprintf("样本规则 %s 切完剩 0 行", smp)))

  n_units   <- length(unique(sub[[IVAR]]))
  n_treated <- length(unique(sub[[IVAR]][sub$treat_D == 1]))
  if (n_units < 2) {
    return(mk("error", sprintf("切完只剩 %d 个单元，估不出处理效应", n_units),
              n_obs = n1, n_units = n_units, n_treated = n_treated))
  }

  # --- 造结果变量。att_gt 的 yname 要字符串、feols 的公式要名字，
  #     所以每个格子先落成一列再回归。
  y <- eval(OUTCOMES[[oc]], envir = sub)
  if (!is.numeric(y) || length(y) != n1) {
    return(mk("error", sprintf("结果变量 %s 没算出长度正确的数值向量", oc),
              n_obs = n1, n_units = n_units, n_treated = n_treated))
  }
  sub[[OUTCOME_COL]] <- y
  n_bad <- sum(!is.finite(sub[[OUTCOME_COL]]))   # 查 is.finite 不查 is.na：
  if (n_bad > 0) {                               # -Inf 不是 NA，is.na 抓不到，
    return(mk("error",                        # 却会让系数变成 NaN
              sprintf("结果变量 %s 里有 %d 个非有限值（Inf/-Inf/NaN）",
                      oc, n_bad),
              n_obs = n1, n_units = n_units, n_treated = n_treated))
  }

  ctrls <- CONTROLS[[ctrl]]
  xfml <- if (length(ctrls) == 0) NULL else
    as.formula(paste("~", paste(ctrls, collapse = " + ")))

  # --- 分估计量
  if (est == "cs") {
    fit <- att_gt(
      yname = OUTCOME_COL, gname = GVAR, idname = IVAR, tname = TVAR,
      xformla = xfml, data = sub,
      control_group = "notyettreated",
      bstrap = TRUE, biters = 999, clustervars = CLUSTER,
      print_details = FALSE
    )
    agg <- aggte(fit, type = "simple", na.rm = TRUE)
    return(mk("ok", "", agg$overall.att, agg$overall.se, n1, n_units, n_treated))
  }

  if (est == "twfe") {
    f <- as.formula(paste(OUTCOME_COL, "~ treat_D |", IVAR, "+", TVAR))
    fit <- feols(f, data = sub, cluster = as.formula(paste("~", CLUSTER)))
    ct <- summary(fit)$coeftable
    return(mk("ok", "", unname(ct["treat_D", "Estimate"]),
              unname(ct["treat_D", "Std. Error"]), n1, n_units, n_treated))
  }

  if (est == "sa") {
    # Sun-Abraham 交互加权：另一种针对渐进采纳负权重的修正。
    # sunab() 对「从未受处理」的编码在不同 fixest 版本里要求不一样（0 或 Inf），
    # 照 05_main.R 第 7 节的做法：先按 0 跑，报错再换 Inf。
    f <- as.formula(paste(OUTCOME_COL, "~ sunab(", GVAR, ", ", TVAR, ") |",
                          IVAR, "+", TVAR))
    fit <- tryCatch(
      feols(f, data = sub, cluster = as.formula(paste("~", CLUSTER))),
      error = function(e) e
    )
    if (inherits(fit, "error")) {
      sub$cohort_inf <- ifelse(sub[[GVAR]] == 0, Inf, sub[[GVAR]])
      f <- as.formula(paste(OUTCOME_COL, "~ sunab(cohort_inf, ", TVAR, ") |",
                            IVAR, "+", TVAR))
      fit <- tryCatch(
        feols(f, data = sub, cluster = as.formula(paste("~", CLUSTER))),
        error = function(e) e
      )
    }
    if (inherits(fit, "error")) {
      return(mk("error", paste("sunab 两种编码都没跑通：", conditionMessage(fit)),
                n_obs = n1, n_units = n_units, n_treated = n_treated))
    }
    # sunab 出来的是各期系数，要汇总成一个数才进得了矩阵。
    # summary(fit, agg = "att") 这个接口**我没核实过**（本机没装 R），
    # 跑不通就如实记成 error，不拿别的数顶上。
    sm <- tryCatch(summary(fit, agg = "att"), error = function(e) e)
    if (inherits(sm, "error") || is.null(sm$coeftable)) {
      return(mk("error",
                "summary(fit, agg='att') 没跑通，Sun-Abraham 的汇总接口待核",
                n_obs = n1, n_units = n_units, n_treated = n_treated))
    }
    ct <- sm$coeftable
    return(mk("ok", "", unname(ct[1, "Estimate"]),
              unname(ct[1, "Std. Error"]), n1, n_units, n_treated))
  }

  if (est == "sdid") {
    # 教程这一档没实现，理由写在配置的 SDID_NOTE 里。**记录，不静默跳过。**
    return(mk("not_implemented", "SDID 未实现：synthdid 接口未核实",
              n_obs = n1, n_units = n_units, n_treated = n_treated))
  }

  mk("error", paste("不认识的估计量：", est), n_obs = n1, n_units = n_units,
     n_treated = n_treated)
}

# --- 组装格子清单
if (isTRUE(FULL_PRODUCT)) {
  grid <- expand.grid(est = DIMS$est, ctrl = DIMS$ctrl,
                      sample = DIMS$sample, outcome = DIMS$outcome,
                      stringsAsFactors = FALSE)
  cell_keys <- do.call(paste, c(grid[c("est", "ctrl", "sample", "outcome")],
                                sep = "|"))
} else {
  cell_keys <- .cfg$SELECT
}

cat("\n", strrep("=", 72), "\n", sep = "")
cat("逐格执行：共 ", length(cell_keys), " 格\n", sep = "")
cat(strrep("=", 72), "\n", sep = "")

cells_path <- file.path(dir_robust, "cells.csv")
rows <- list()

for (i in seq_along(cell_keys)) {
  parts <- strsplit(cell_keys[i], "|", fixed = TRUE)[[1]]
  cell_id <- sprintf("cell_%02d", i)
  cat("\n-- ", cell_id, "  ", cell_keys[i], " ", strrep("-", 30), "\n", sep = "")

  # 每格一次 tryCatch：一格炸了不影响后面的格。这是「隔离」的落点——
  # 教程靠每格一个独立进程，这里靠 tryCatch，效果一样而不用管临时文件。
  res <- tryCatch(
    run_cell(cell_id, parts[1], parts[2], parts[3], parts[4],
             seed_i = 20260417L + i),
    error = function(e) {
      data.frame(
        cell_id = cell_id, est = parts[1], ctrl = parts[2],
        sample = parts[3], outcome = parts[4], status = "error",
        att = NA_real_, se = NA_real_, ci_lo = NA_real_, ci_hi = NA_real_,
        n_obs = NA_integer_, n_units = NA_integer_,
        n_treated_units = NA_integer_, cluster = CLUSTER, seed = 20260417L + i,
        data_md5 = data_sig,
        note = paste("未捕获的异常：", conditionMessage(e)),
        stringsAsFactors = FALSE
      )
    }
  )

  if (res$status == "ok") {
    cat("    ATT = ", sprintf("%.4f", res$att),
        "  SE = ", sprintf("%.4f", res$se),
        "  N = ", res$n_obs, "\n", sep = "")
  } else {
    cat("    [", res$status, "] ", res$note, "\n", sep = "")
  }

  rows[[i]] <- res
  # 每跑完一格就把累积结果落盘。中途崩了，已经跑完的格子还在文件里，
  # 不用从头再来。
  write.csv(do.call(rbind, rows), cells_path, row.names = FALSE)
}


# --- 6. 收尾汇总 -------------------------------------------------------------
cat("\n", strrep("=", 72), "\n", sep = "")
cat("矩阵执行完毕\n")
cat(strrep("=", 72), "\n", sep = "")

all_cells <- do.call(rbind, rows)
n_ok    <- sum(all_cells$status == "ok")
n_err   <- sum(all_cells$status == "error")
n_skip  <- sum(all_cells$status == "not_implemented")

cat("  成功    ：", n_ok, " 格\n", sep = "")
cat("  失败    ：", n_err, " 格\n", sep = "")
cat("  未实现  ：", n_skip, " 格\n", sep = "")
cat("  结果文件：", cells_path, "\n", sep = "")
cat("  日志    ：", logfile, "\n", sep = "")

if (n_err > 0) {
  cat("\n  失败的格子（**逐条列出来，不因为数量少就省略**）：\n")
  for (j in which(all_cells$status == "error")) {
    cat("    ", all_cells$cell_id[j], " ", all_cells$est[j], "|",
        all_cells$ctrl[j], "|", all_cells$sample[j], "|",
        all_cells$outcome[j], "：", all_cells$note[j], "\n", sep = "")
  }
}

# 基准格自检：它在 SELECT 里吗？没在的话这一阶段和阶段 05 就没有对账点。
if (!BASELINE_CELL %in% cell_keys) {
  cat("\n  ⚠ 基准格 ", BASELINE_CELL, " 不在本次的格子清单里。\n", sep = "")
  cat("    这意味着这批结果没有一个能对上阶段 05 的主回归——\n")
  cat("    对不上就无从判断这里的代码和 05_main.R 是不是同一套口径。\n")
} else {
  b <- all_cells[all_cells$est == strsplit(BASELINE_CELL, "|", fixed = TRUE)[[1]][1] &
                 all_cells$ctrl == strsplit(BASELINE_CELL, "|", fixed = TRUE)[[1]][2] &
                 all_cells$sample == strsplit(BASELINE_CELL, "|", fixed = TRUE)[[1]][3] &
                 all_cells$outcome == strsplit(BASELINE_CELL, "|", fixed = TRUE)[[1]][4], ]
  if (nrow(b) == 1 && b$status[1] == "ok") {
    cat("\n  基准格（", BASELINE_CELL, "）：ATT = ", sprintf("%.4f", b$att[1]),
        "  SE = ", sprintf("%.4f", b$se[1]), "\n", sep = "")
    cat("    要和 output/tables/tab_main.csv 里的 CS-DID 一栏对上。\n")
    cat("    对不上说明 06 和 05 不是同一套口径，先查这个再往下走。\n")
  }
}


# --- 7. HITL 停止点 ----------------------------------------------------------
# 到这里为止，脚本的任务是「把每格的数字跑出来并留痕」，到此结束。
# 哪些格子稳、变的是哪一维度、正文怎么写——都属于研究者。

cat("\n", strrep("=", 72), "\n", sep = "")
cat("矩阵已生成 —— 请研究者审阅后再进阶段 07\n")
cat(strrep("=", 72), "\n", sep = "")
cat("\n  要你亲自做的事：\n")
cat("    1. 看有没有哪个格子的符号和主回归相反、或显著性没了\n")
cat("    2. 变的是哪一维度——控制变量？样本？函数形式？\n")
cat("    3. 决定正文展示哪 3-4 列、附录放多少\n")
cat("    4. 跑不出来的格子怎么处理（补实现，还是如实说明做不了）\n")
cat("\n  **符号翻转或显著性消失的格子，不许从附录里删掉。**\n")
cat("  完整矩阵本身就是诚信证明（README.md 第七节红线）。\n")
cat("\n  **本脚本不解读上述任何一个数字，也不写正文措辞。**\n")
cat(strrep("=", 72), "\n", sep = "")

sink()
close(con)
cat("\n日志已写入：", logfile, "\n", sep = "")
