#==============================================================================
# 03_clean.R : QCEW 年度 zip -> 州-年面板
#
# 输入：data/raw/qcew/zip/YYYY_annual_singlefile.zip   （阶段 02 产物，只读）
#       data/external/state_min_wage.dta / .rds        （可选；缺则不建 gvar）
# 输出：data/processed/panel.rds
# 日志：logs/03_clean_YYYYMMDD_HHMMSS.log
#
# 这是一份模板。「参数区」里的每一项都是研究设计决定（CLAUDE.md 第七节第 2 条
# 把样本规则列为 HITL 节点），留空时脚本会主动中止，不会按某个默认值默默跑完。
# 「机械部分」不用改。
#
# 依赖：只用 base R + utils（unzip / read.csv）。不额外装包——清洗是整条流水线的
# 入口，入口少一个依赖就少一个别人复现不出来的理由。
#
# 与常见教程写法的三点不同：
#   1. 原始数据不是现成的 .dta。阶段 02 只留年度 zip、解压出的 CSV 默认删掉，
#      所以这里要自己逐年解包再读。
#   2. QCEW 的 area_fips 带前导零（01001 是阿拉巴马州奥陶加县）。R 这边反而省事：
#      全部列先按字符读进来，前导零天生就保住了，不用像 Stata 那样指定 stringcols。
#   3. 列名不硬编码。本仓从没真下载过数据，表头没核对过；脚本读表头自查，
#      缺列就把该年的实际表头整个打出来再中止，不赌。
#
# 另外本脚本负责构造 did 包要的 gvar（首次受处理年份，从未受处理=0）。理由见
# 第 7b 节开头——处理定义必须和样本定义定在同一处，否则下游各脚本各建一次，
# 迟早建出不一样的。
#
# 运行方式：先 setwd() 到 empirical study/，再
#           source("code/03_clean/03_clean.R")
#           （R 也没有「脚本自己的路径」这回事，只能靠工作目录定位；第 0 节自检会拦住）
#
# ⚠ 这份脚本一行都没跑过：本机没有 QCEW 数据，也从没下载过。守卫写全了、
#   逻辑按清洗流程逐节排开，但**未在真实数据上验证**。第一次真跑会慢（见 README 已知坑③）。
#==============================================================================

stopifnot(getRversion() >= "4.4.0")

set.seed(20260417)   # CLAUDE.md 第二节：全项目统一种子


#------------------------------------------------------------------------------
# 0. 定位、日志
#------------------------------------------------------------------------------

ROOT <- getwd()

# R 不知道自己被放在哪，只能假设工作目录正确。用一个哨兵文件自检。
if (!file.exists(file.path(ROOT, "code", "03_clean", "03_clean.R"))) {
  stop("当前工作目录不是 empirical study/（当前：", ROOT, "）\n",
       "先 setwd() 到 empirical study/ 再 source 本文件。", call. = FALSE)
}

RAW     <- file.path(ROOT, "data", "raw", "qcew")
ZIPDIR  <- file.path(RAW, "zip")
PROC    <- file.path(ROOT, "data", "processed")
EXT     <- file.path(ROOT, "data", "external")
LOGDIR  <- file.path(ROOT, "logs")
SCRATCH <- file.path(PROC, "_scratch")

dir.create(PROC, recursive = TRUE, showWarnings = FALSE)
dir.create(LOGDIR, recursive = TRUE, showWarnings = FALSE)

# 时间戳。同一秒内跑两次会撞名，撞了就加序号——日志被悄悄覆盖就丢了运行痕迹。
stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
logfile <- file.path(LOGDIR, paste0("03_clean_", stamp, ".log"))
suffix <- 2L
while (file.exists(logfile)) {
  logfile <- file.path(LOGDIR, paste0("03_clean_", stamp, "_", suffix, ".log"))
  suffix <- suffix + 1L
}

con <- file(logfile, open = "wt")
sink(con, split = TRUE)

cat(strrep("=", 78), "\n", sep = "")
cat("03_clean.R   ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n", sep = "")
cat("工作目录：", ROOT, "\n", sep = "")
cat(strrep("=", 78), "\n", sep = "")


#------------------------------------------------------------------------------
# 1. 参数区 —— 待研究者确认，留空（NA）则中止
#
#    每项都影响最终样本。改任何一项都要重跑，并重新记「剔除多少观测」。
#    代码列（own_code / industry_code / agglvl_code）的取值，第一次跑时
#    脚本会在首年打印出实际出现的值，照那个填，不要凭记忆写。
#------------------------------------------------------------------------------

# *** 待确认 ①：保留哪些所有制 ***
# QCEW 的 own_code：1=联邦 2=州 3=地方 5=私营。
# 例：只要私营填 "5"；私营加地方政府填 c("5", "3")。
KEEP_OWN <- NA_character_

# *** 待确认 ②：行业范围 ***
# 例：只要全部行业合计，填合计那一行的 industry_code。可填多个。
KEEP_IND <- NA_character_

# *** 待确认 ③：地区层级 ***
# QCEW 的 agglvl_code 区分全国 / 州 / 县 / 大都市区。填州级那个码。
KEEP_AGG <- NA_character_

# *** 待确认 ④：同州同年多行时怎么聚合 ***
# "sum"  = 就业加总（例：把县加总成州）
# "mean" = 取平均
# 注意：平均工资（pay）是比率，永远取平均，不跟着这项走。
AGG_MODE <- NA_character_

# *** 待确认 ⑤：异常值 ***
# 缩尾百分位，如 0.01 表示上下各缩 1%。留 NA 则不缩尾。
WINSOR_P <- NA_real_
# 超几倍标准差标旗。**只标旗、不删除**，删不删由研究者看完清单决定。
OUTLIER_SD <- NA_real_

# *** 待确认 ⑥：面板平衡 ***
# 留 NA = 保留非平衡面板（只报告哪些州年份不全）
# 填数字 n = 剔除不足 n 年的州
PANEL_MIN_YEARS <- NA_integer_

# *** 待确认 ⑦：期望样本量下界（末尾守卫用）***
# 第一次跑完把日志里的实际观测数写死在这里。之后 AI 改代码一旦让样本规模变了，
# 脚本会在落盘之前中止，错误不会沉进 data/processed/。
MIN_OBS <- NA_integer_

# *** 待确认 ⑧：处理旗标变量名（第 7b 节用）***
# 外部文件里标记「该州该年受政策约束」的 0/1 变量名。
# 政策阈值怎么折算成 0/1 是研究设计决定（CLAUDE.md 第七节第 1 条），
# 本脚本不替你判阈值，只接受已经折好的干净 0/1。外部文件不在时不填也行。
TREAT_VAR <- NA_character_

# *** 待确认 ⑨：外部文件没覆盖到的州怎么算（第 7b 节用）***
# "0" = 报错停下。外部文件本该覆盖全部州，缺了说明它有问题。
# "1" = 视为「从未受处理」，gvar 记 0。
#       **填 1 等于宣布一个识别假设**：「没出现在外部文件里的州 = 从未调整最低工资」。
#       只有外部文件本身只是一张「受处理州清单」时才该填 1。
UNMATCHED_NEVER <- "0"

# 年份区间。与阶段 02 实际拉下来的区间保持一致。
Y0 <- 2000L
Y1 <- 2019L

# 需要从 QCEW 原始文件里取的列。列名取自 QCEW 公布的表结构，
# 但本仓没真下载过数据，**没核对过**——所以不硬编码列序，读表头自查。
VAR_EMP <- "annual_avg_emplvl"
VAR_PAY <- "avg_annual_pay"

KEYS   <- c("area_fips", "own_code", "industry_code", "agglvl_code")
NEEDED <- c(KEYS, VAR_EMP, VAR_PAY)
NCODE  <- c("own_code", "industry_code", "agglvl_code")

# 参数填齐了没有。留 NA 就停下，不猜。
required_params <- list(KEEP_OWN = KEEP_OWN, KEEP_IND = KEEP_IND,
                        KEEP_AGG = KEEP_AGG, AGG_MODE = AGG_MODE,
                        MIN_OBS = MIN_OBS)
missing_param <- names(required_params)[vapply(required_params, function(x)
  length(x) == 0 || all(is.na(x)), logical(1))]
if (length(missing_param) > 0) {
  cat("\n参数区还有没填的：", paste(missing_param, collapse = ", "), "\n", sep = "")
  cat("这些是研究设计决定（CLAUDE.md 第七节第 2 条），要研究者拍板，脚本不替你选。\n")
  cat("填好上面「参数区」再重跑。\n")
  sink(); close(con)
  stop("参数未填齐，已中止。", call. = FALSE)
}

if (!AGG_MODE %in% c("sum", "mean")) {
  cat("\nAGG_MODE 只能是 \"sum\" 或 \"mean\"，现在是 \"", AGG_MODE, "\"\n", sep = "")
  sink(); close(con)
  stop("AGG_MODE 取值非法。", call. = FALSE)
}


#------------------------------------------------------------------------------
# 2. 两个小程序
#------------------------------------------------------------------------------

# 报损。README.md 第六节红线：清洗和回归都要报损失，
# 每一步剔掉多少、占多少，逐条记。
# 用法：n1 <- report_loss("步骤说明", n0); n1 <- nrow(df)
report_loss <- function(step, n0, n1) {
  if (n0 > 0) {
    d <- n0 - n1
    pct <- 100 * d / n0
    cat(sprintf("  [报损] %s：%s -> %s，剔除 %s（%5.2f%%）\n",
                step, format(n0, big.mark = ","), format(n1, big.mark = ","),
                format(d, big.mark = ","), pct))
  } else {
    cat(sprintf("  [报损] %s：%s 行（无起点可比）\n",
                step, format(n1, big.mark = ",")))
  }
  invisible(n1)
}

# 按代码变量筛选。把「报损 + 筛完为 0 时把实际取值打出来」收在一处，
# 免得三个筛选各写一遍、漏掉诊断。
# 用法：df <- keep_matching(df, "own_code", KEEP_OWN, "按所有制筛选 own_code")
keep_matching <- function(df, var, values, step) {
  n0 <- nrow(df)
  hit <- as.character(df[[var]]) %in% as.character(values)
  out <- df[hit, , drop = FALSE]
  report_loss(step, n0, nrow(out))
  if (nrow(out) == 0) {
    actual <- sort(unique(as.character(df[[var]])))
    if (length(actual) > 40) actual <- c(actual[1:40], "...")
    cat("  ↑ 筛完剩 0 行。参数填的是 {", paste(values, collapse = ", "),
        "}，该年 ", var, " 的实际取值是：", paste(actual, collapse = " "), "\n", sep = "")
  }
  out
}


#------------------------------------------------------------------------------
# 3. 逐年解包 -> 读入 -> 筛选 -> 追加
#------------------------------------------------------------------------------

nper <- Y1 - Y0 + 1L
acc <- NULL

cat("\n", strrep("=", 78), "\n", sep = "")
cat("逐年读入\n")
cat(strrep("=", 78), "\n", sep = "")

for (y in Y0:Y1) {

  zfile <- file.path(ZIPDIR, paste0(y, "_annual_singlefile.zip"))
  if (!file.exists(zfile)) {
    cat("\n缺少 ", y, " 年的压缩包：", zfile, "\n", sep = "")
    cat("先跑阶段 02：code/02_fetch/02_fetch.py --years ", y, "\n", sep = "")
    sink(); close(con)
    stop("压缩包缺失，已中止。", call. = FALSE)
  }

  cat("\n-- ", y, " --\n", sep = "")

  # 解到 data/processed/_scratch/，不往 data/raw/ 里写（那边写入后即只读）
  dir.create(SCRATCH, recursive = TRUE, showWarnings = FALSE)

  # utils::unzip 是 base R，不需要额外装包。unzip() 的返回值是解出来的文件名，
  # 正是我们下一步要的东西——比 Stata 那边再 dir 一次更直接。
  extracted <- tryCatch(
    unzip(zfile, exdir = SCRATCH, overwrite = TRUE),
    error = function(e) {
      cat("解包失败：", conditionMessage(e), "\n", sep = "")
      NULL
    }
  )
  if (is.null(extracted)) {
    sink(); close(con)
    stop("解包失败，已中止。", call. = FALSE)
  }

  # 找出解出来的 CSV。若压缩包把 CSV 套在子目录里，这里会找不到——
  # 那就把实际解出的东西打出来，不猜。
  csvs <- extracted[grepl("\\.csv$", extracted, ignore.case = TRUE)]
  if (length(csvs) == 0) {
    cat(y, " 年解包后没找到 CSV。实际解出：\n", sep = "")
    print(basename(extracted))
    sink(); close(con)
    stop("没找到 CSV，已中止。", call. = FALSE)
  }
  if (length(csvs) > 1) {
    cat("  注意：解出 ", length(csvs), " 个 CSV，只读第一个\n", sep = "")
  }
  csv <- csvs[1]

  #---- 读表头自查列名 ----
  # 只读第一行，不解析那 500MB。
  hdr_line <- readLines(csv, n = 1, warn = FALSE)
  hdr_line <- sub("^﻿", "", hdr_line)   # 抹掉可能的 UTF-8 BOM
  hdr <- strsplit(gsub('"', "", hdr_line), ",", fixed = TRUE)[[1]]
  ncol_hdr <- length(hdr)

  miss <- setdiff(NEEDED, hdr)
  if (length(miss) > 0) {
    cat("\n", y, " 年的文件里没有这些列：", paste(miss, collapse = ", "), "\n", sep = "")
    cat("该年实际表头（", ncol_hdr, " 列）：\n", sep = "")
    cat(paste(hdr, collapse = " "), "\n")
    cat("\n早期年份的布局可能和近年版不同（见 code/02_fetch/README.md 已知坑③）。\n")
    cat("确认后改「参数区」的 VAR_EMP / VAR_PAY / KEYS。\n")
    sink(); close(con)
    stop("列名对不上，已中止。", call. = FALSE)
  }
  cat("  表头 OK：", ncol_hdr, " 列，需要的 ", length(NEEDED), " 列都在\n", sep = "")

  #---- 导入 ----
  # 关键：全部列按字符读入。Stata 那边要靠 stringcols() 指定哪一列不能数字化，
  # R 这里反过来——先全当字符，再显式转换需要当数字的列。前导零因此在读入这步
  # 就不可能丢（area_fips 的 01001 不会变成 1001）。
  raw_df <- read.csv(csv, colClasses = "character", check.names = FALSE,
                     stringsAsFactors = FALSE)
  # 有的年份表头带 UTF-8 BOM，会让第一列的名字变成 "﻿area_fips"，
  # 之后按名字取列会全部取不到，而且报错信息看不出是 BOM 干的。
  names(raw_df)[1] <- sub("^﻿", "", names(raw_df)[1])
  cat("  读入 ", format(nrow(raw_df), big.mark = ","), " 行，",
      ncol(raw_df), " 列\n", sep = "")

  # 复核一遍：读进来之后 area_fips 还得带前导零。
  if (!any(grepl("^0", raw_df$area_fips))) {
    cat("  警告：area_fips 里没有任何以 0 开头的值。要么这一年真的没有 0 开头的",
        "县码（不可能），要么前导零已经丢了。先查清楚。\n")
  }

  #---- 首年探查：把代码列的实际取值打出来，供研究者填参数区 ----
  if (y == Y0) {
    cat("  首年探查（照这个填参数区的代码）：\n")
    for (v in NCODE) {
      vals <- sort(unique(raw_df[[v]]))
      if (length(vals) <= 40) {
        cat("    ", v, "（", length(vals), " 个）：",
            paste(vals, collapse = " "), "\n", sep = "")
      } else {
        cat("    ", v, "：", length(vals), " 个取值，太长不列；跑 table() 看\n", sep = "")
      }
    }
  }

  #---- 年份自校验 ----
  if ("year" %in% names(raw_df)) {
    yvals <- suppressWarnings(as.integer(raw_df$year))
    if (any(!is.na(yvals)) &&
        (min(yvals, na.rm = TRUE) != y || max(yvals, na.rm = TRUE) != y)) {
      cat(y, " 年的包里 year 列是 ", min(yvals, na.rm = TRUE), "-",
          max(yvals, na.rm = TRUE), "，和包名对不上\n", sep = "")
      sink(); close(con)
      stop("年份对不上，已中止。", call. = FALSE)
    }
    df <- raw_df
  } else {
    cat("  包里没有 year 列，按包名年份生成\n")
    df <- raw_df
    df$year <- as.character(y)
  }

  #---- 结果变量转数值 ----
  for (v in c(VAR_EMP, VAR_PAY)) {
    df[[v]] <- suppressWarnings(as.numeric(df[[v]]))
  }

  #---- 统一列名，保证逐年 rbind 时列一致 ----
  names(df)[names(df) == VAR_EMP] <- "emp"
  names(df)[names(df) == VAR_PAY] <- "pay"

  #---- 州码 ----
  # area_fips 前两位是州 FIPS。全国码（US000 之类）切出来不是数字，
  # as.integer 后为 NA——这类行没州码，下面单独剔除并报损。
  df$state_id <- suppressWarnings(as.integer(substr(df$area_fips, 1, 2)))

  keep_cols <- c("area_fips", "own_code", "industry_code", "agglvl_code",
                 "year", "emp", "pay", "state_id")
  df <- df[, keep_cols, drop = FALSE]
  df$year <- as.integer(df$year)

  #---- 筛选，每条都报损 ----
  df <- keep_matching(df, "own_code", KEEP_OWN, "按所有制筛选 own_code")
  if (nrow(df) == 0) {
    cat(y, " 年按所有制筛完没有数据，参数区 KEEP_OWN 填错了。\n", sep = "")
    sink(); close(con)
    stop("筛选后为空，已中止。", call. = FALSE)
  }

  df <- keep_matching(df, "industry_code", KEEP_IND, "按行业筛选 industry_code")
  if (nrow(df) == 0) {
    cat(y, " 年按行业筛完没有数据，参数区 KEEP_IND 填错了。\n", sep = "")
    sink(); close(con)
    stop("筛选后为空，已中止。", call. = FALSE)
  }

  df <- keep_matching(df, "agglvl_code", KEEP_AGG, "按地区层级筛选 agglvl_code")
  if (nrow(df) == 0) {
    cat(y, " 年按地区层级筛完没有数据，参数区 KEEP_AGG 填错了。\n", sep = "")
    sink(); close(con)
    stop("筛选后为空，已中止。", call. = FALSE)
  }

  # 没有州码的行在这里退场。单独报一次，不混在别的筛选里。
  n0 <- nrow(df)
  df <- df[!is.na(df$state_id), , drop = FALSE]
  report_loss("剔除没有州码的行（全国/跨州口径）", n0, nrow(df))

  cat("  ", y, " 年入库 ", format(nrow(df), big.mark = ","), " 行\n", sep = "")

  acc <- if (is.null(acc)) df else rbind(acc, df)

  # 清掉这一年的解压产物。临时目录在 data/processed/ 下，已被 .gitignore 覆盖。
  unlink(extracted[file.exists(extracted)])
}

cat("\n逐年读入完成，合计 ", format(nrow(acc), big.mark = ","), " 行\n", sep = "")
unlink(SCRATCH, recursive = TRUE)


#------------------------------------------------------------------------------
# 4. 聚合到州-年
#
#    若 KEEP_AGG 已经选定州级口径，每年每州只有一行，这一步是空转；
#    若保留的是县级，这一步才是把县加总成州。
#------------------------------------------------------------------------------

cat("\n", strrep("=", 78), "\n", sep = "")
cat("聚合到州-年\n")
cat(strrep("=", 78), "\n", sep = "")

n0 <- nrow(acc)
# 工资是比率，永远取平均；就业按 AGG_MODE 走。
# 注意 pay 是不加权的简单平均——若研究者要按就业加权，得改这里并说明。
agg_fun <- if (AGG_MODE == "sum") sum else mean
emp_agg <- aggregate(acc$emp, by = list(state_id = acc$state_id, year = acc$year),
                     FUN = agg_fun, na.rm = TRUE)
pay_agg <- aggregate(acc$pay, by = list(state_id = acc$state_id, year = acc$year),
                     FUN = mean, na.rm = TRUE)
names(emp_agg)[3] <- "emp"
names(pay_agg)[3] <- "pay"
panel <- merge(emp_agg, pay_agg, by = c("state_id", "year"), all = TRUE)
report_loss(paste0("collapse 到州-年（", AGG_MODE, "）"), n0, nrow(panel))

panel$log_emp <- log(panel$emp)


#------------------------------------------------------------------------------
# 5. 缺失与面板平衡 —— 只报告，不删除
#    照教程「每步缺失检查、面板检查只报告不删除，保留研究者的决定权」
#------------------------------------------------------------------------------

cat("\n", strrep("=", 78), "\n", sep = "")
cat("缺失与面板平衡（只报告）\n")
cat(strrep("=", 78), "\n", sep = "")

for (v in c("emp", "pay", "log_emp")) {
  cat("  ", v, "  缺失 ", format(sum(is.na(panel[[v]])), big.mark = ","),
      " 行\n", sep = "")
}

# 面板平衡：先列出年份不足的州，删不删由 PANEL_MIN_YEARS 决定
n_years_tab <- table(panel$state_id)
panel$n_years <- as.integer(n_years_tab[as.character(panel$state_id)])

short_states <- names(n_years_tab)[n_years_tab < nper]
cat("\n  年份不足 ", nper, " 年的州：",
    format(length(short_states), big.mark = ","), " 个\n", sep = "")
if (length(short_states) > 0) {
  print(data.frame(state_id = short_states,
                   n_years = as.integer(n_years_tab[short_states])),
        row.names = FALSE)
}

if (!is.na(PANEL_MIN_YEARS)) {
  n0 <- nrow(panel)
  panel <- panel[panel$n_years >= PANEL_MIN_YEARS, , drop = FALSE]
  report_loss(paste0("剔除年份不足 ", PANEL_MIN_YEARS, " 年的州"), n0, nrow(panel))
} else {
  cat("  PANEL_MIN_YEARS 留空，保留非平衡面板\n")
}
panel$n_years <- NULL


#------------------------------------------------------------------------------
# 6. 异常值 —— 缩尾按参数，标旗只标不删
#------------------------------------------------------------------------------

cat("\n", strrep("=", 78), "\n", sep = "")
cat("异常值\n")
cat(strrep("=", 78), "\n", sep = "")

if (!is.na(WINSOR_P)) {
  # quantile(type = 7) 是 R 的默认分位数算法，和 Stata 的 _pctile 口径不同。
  # 差别只在边缘情形，但既然口径不同就该说明——**这里没有对齐 Stata**。
  plo <- WINSOR_P
  phi <- 1 - WINSOR_P
  qs <- quantile(panel$log_emp, probs = c(plo, phi), na.rm = TRUE, type = 7)
  lo <- qs[[1]]; hi <- qs[[2]]
  cat(sprintf("  缩尾区间：[%9.4f, %9.4f]\n", lo, hi))
  nlow <- sum(panel$log_emp < lo, na.rm = TRUE)
  nhigh <- sum(panel$log_emp > hi, na.rm = TRUE)
  panel$log_emp[!is.na(panel$log_emp) & panel$log_emp < lo] <- lo
  panel$log_emp[!is.na(panel$log_emp) & panel$log_emp > hi] <- hi
  cat(sprintf("  缩尾改动：下侧 %s 行，上侧 %s 行\n",
              format(nlow, big.mark = ","), format(nhigh, big.mark = ",")))
  cat("  （缩尾不改变观测数，所以不报损；下面守卫的样本量仍应等于缩尾前）\n")
} else {
  cat("  WINSOR_P 留空，不缩尾\n")
}

if (!is.na(OUTLIER_SD)) {
  m <- mean(panel$log_emp, na.rm = TRUE)
  s <- sd(panel$log_emp, na.rm = TRUE)
  panel$outlier_flag <- as.integer(!is.na(panel$log_emp) &
                                     abs(panel$log_emp - m) > OUTLIER_SD * s)
  cat("  超 ", OUTLIER_SD, " 倍标准差的观测：",
      format(sum(panel$outlier_flag), big.mark = ","), " 行（只标旗，未删除）\n", sep = "")
  print(table(panel$outlier_flag, useNA = "ifany"))
  cat("  要删除请研究者明确指示；脚本不自己删。\n")
} else {
  cat("  OUTLIER_SD 留空，不标旗\n")
}


#------------------------------------------------------------------------------
# 7. 合并 data/external/
#
#    外部数据还没进库，所以用 file.exists 包住——不能变成硬依赖。
#    合并是 1:1，键 state_id + year。
#
#    **面板当 master。** 这一点和多数示例写法相反，值得说清楚。R 这边用
#    all.x = TRUE（左连接），语义上天然就是「面板当 master」，比 Stata 的
#    _merge 好读——不存在「_merge 的 2 到底是哪一边」这种必须记住的问题。
#------------------------------------------------------------------------------

cat("\n", strrep("=", 78), "\n", sep = "")
cat("合并外部数据\n")
cat(strrep("=", 78), "\n", sep = "")

ext_rds <- file.path(EXT, "state_min_wage.rds")
ext_dta <- file.path(EXT, "state_min_wage.dta")
has_ext <- file.exists(ext_rds) || file.exists(ext_dta)

if (has_ext) {
  ext_df <- if (file.exists(ext_rds)) {
    readRDS(ext_rds)
  } else {
    # .dta 不是 base R 能读的格式。要么用 haven::read_dta，要么在外部整理阶段
    # 存成 .rds。这里明确报出来，不假装能读。
    cat("  找到 ", ext_dta, "，但 base R 读不了 .dta。\n", sep = "")
    cat("  两条路：装 haven 包（haven::read_dta），或把外部文件另存成 "
        , ext_rds, "。\n", sep = "")
    sink(); close(con)
    stop("外部文件格式需要转换，已中止。", call. = FALSE)
  }

  # 键唯一性：1:1 合并的前提。不唯一就在这里停，不让 merge 悄悄展开成笛卡尔积。
  if (anyDuplicated(ext_df[, c("state_id", "year")]) > 0) {
    cat("  外部文件在 state_id + year 上不唯一，1:1 合并会被展开。先压到唯一键。\n")
    sink(); close(con)
    stop("外部文件主键不唯一，已中止。", call. = FALSE)
  }

  # 面板当 master = all.x = TRUE。只在外部文件里出现的行自动不进结果，
  # 先数出来报损（连的是「不是面板单位」那些行）。
  panel_keys <- paste(panel$state_id, panel$year)
  ext_keys   <- paste(ext_df$state_id, ext_df$year)
  n_ext_only <- sum(!ext_keys %in% panel_keys)

  # 变量名撞车检查（Stata 的 merge 会因此报错，R 会加 .x/.y 后缀静默改名）。
  clash <- setdiff(intersect(names(panel), names(ext_df)), c("state_id", "year"))
  if (length(clash) > 0) {
    cat("  外部文件和面板有同名变量：", paste(clash, collapse = ", "), "\n", sep = "")
    cat("  合并后 R 会给它们加 .x / .y 后缀，容易看错。先在外部整理阶段改名。\n")
    sink(); close(con)
    stop("变量名撞车，已中止。", call. = FALSE)
  }

  n0 <- nrow(panel)
  panel <- merge(panel, ext_df, by = c("state_id", "year"), all.x = TRUE)
  cat("  合并后 ", format(nrow(panel), big.mark = ","), " 行\n", sep = "")
  report_loss("剔除只在外部文件出现的州-年（不是面板单位）",
              n0 + n_ext_only, nrow(panel))
  cat("  只保留面板里有的州-年；外部文件没覆盖到的州-年，旗标此时是 NA（见第 7b 节）。\n")
} else {
  cat("  ", ext_rds, " 不在，跳过合并与 gvar 构建（外部数据还没有，不算错误）\n", sep = "")
  cat("  → panel.rds 里不会出现 gvar；阶段 05 会因此拒绝运行，\n")
  cat("    直到补上外部文件并重跑本脚本。\n")
}


#------------------------------------------------------------------------------
# 7b. 构造 gvar —— did 包要的「首次受处理年份」，从未受处理编码 0
#
#    为什么放在这里、而不是放在 05_main.R 里现算：
#    gvar 是处理定义，和样本定义是同一类东西（CLAUDE.md 第七节第 1、2 条）。
#    放在 03 里定死一次，下游 05/06/07/08 一律读 panel.rds 里的同名变量。
#    若放到下游各算各的，稳健性检验按队列切样本、表格按队列分组时，
#    四处就可能用四种口径，而且没人看得出来——正是第九节要防的那类错。
#
#    外部文件不在时整块跳过：03 不能因为一个可选依赖而失败。
#------------------------------------------------------------------------------

if (has_ext) {

  cat("\n", strrep("=", 78), "\n", sep = "")
  cat("构造处理时点 gvar\n")
  cat(strrep("=", 78), "\n", sep = "")

  # 这一步才需要 TREAT_VAR，所以检查放在这里，不放在 §1 那段统一检查里
  # （外部文件不在时不该因为没填它而中止）。
  if (is.na(TREAT_VAR) || !nzchar(TREAT_VAR)) {
    cat("\n外部文件已存在，但参数区 ⑧ TREAT_VAR 没填。\n")
    cat("它是外部文件里标记「该州该年受政策约束」的 0/1 变量名。\n")
    cat("先看清楚那一列叫什么再填——填错了不会报错，只会把处理时点算错。\n")
    cat("外部文件实际有哪些变量：", paste(names(ext_df), collapse = ", "), "\n", sep = "")
    sink(); close(con)
    stop("TREAT_VAR 未填，已中止。", call. = FALSE)
  }

  #--- 守卫 A：旗标变量得在，且是数值型 ---
  if (!TREAT_VAR %in% names(panel)) {
    cat("  外部文件里找不到叫 ", TREAT_VAR, " 的变量。面板实际有：\n", sep = "")
    cat("  ", paste(names(panel), collapse = ", "), "\n", sep = "")
    sink(); close(con)
    stop("旗标变量不存在，已中止。", call. = FALSE)
  }
  if (!is.numeric(panel[[TREAT_VAR]])) {
    cat("  ", TREAT_VAR, " 不是数值型。先在外部整理阶段折成 0/1 数值。\n", sep = "")
    sink(); close(con)
    stop("旗标不是数值型，已中止。", call. = FALSE)
  }

  flag <- panel[[TREAT_VAR]]

  #--- 守卫 B：旗标缺失 ---
  # 外部文件没覆盖到、只在面板里的那些州-年，此刻旗标是 NA。
  # 这不是技术瑕疵，是「这个州到底算不算从未受处理」的识别假设，必须显式决定。
  # 放着不管最危险：did 会把 NA 当未处理，处理时点就悄悄错了。
  nmiss <- sum(is.na(flag))
  if (nmiss > 0) {
    if (UNMATCHED_NEVER == "1") {
      cat("  外部文件没覆盖到的州-年 ", format(nmiss, big.mark = ","),
          " 个，按 UNMATCHED_NEVER=1 记为从未受处理。\n", sep = "")
      flag[is.na(flag)] <- 0
      panel[[TREAT_VAR]] <- flag
    } else {
      cat("  旗标 ", TREAT_VAR, " 有 ", format(nmiss, big.mark = ","),
          " 个缺失（外部文件没覆盖到这些州-年）。\n", sep = "")
      cat("  缺失会被 did 当成「未处理」，把处理时点算错，而且不报错。两条路：\n")
      cat("    a) 补全外部文件后重跑；\n")
      cat("    b) 若外部文件本就只是一张「受处理州清单」，在参数区 ⑨ 设\n")
      cat("       UNMATCHED_NEVER \"1\"，明确宣布「未出现的州 = 从未受处理」这个假设。\n")
      sink(); close(con)
      stop("旗标有缺失，已中止。", call. = FALSE)
    }
  }

  #--- 守卫 C：旗标必须是干净的 0/1 ---
  # 出现别的值说明「政策阈值折算成 0/1」这步没做干净。阈值是研究设计决定，不该在这里判。
  tvals <- sort(unique(flag))
  bad <- tvals[!(tvals %in% c(0, 1))]
  if (length(bad) > 0) {
    cat("  旗标 ", TREAT_VAR, " 出现 0/1 之外的取值：",
        paste(bad, collapse = " "), "\n", sep = "")
    cat("  政策阈值要在外部整理阶段折算成 0/1，脚本不替你选阈值。\n")
    sink(); close(con)
    stop("旗标取值非法，已中止。", call. = FALSE)
  }

  #--- 构造 ---
  # 每州取「旗标=1 的最早年份」。从未为 1 的州记 0。
  treat_year <- ifelse(flag == 1, panel$year, NA_real_)
  first_treat <- tapply(treat_year, panel$state_id, function(z) {
    if (all(is.na(z))) NA_real_ else min(z, na.rm = TRUE)
  })
  panel$gvar <- as.numeric(first_treat[as.character(panel$state_id)])
  panel$gvar[is.na(panel$gvar)] <- 0

  #--- 守卫 D：gvar 在同州各年必须一致 ---
  # 它是州层面的常数。不一致说明构造逻辑错了。
  spread <- tapply(panel$gvar, panel$state_id, function(z) length(unique(z)))
  if (any(spread != 1)) {
    cat("  同州的 gvar 不一致。gvar 是州层面常数，不一致说明逻辑错了。\n")
    sink(); close(con)
    stop("gvar 非同州常数，已中止。", call. = FALSE)
  }

  #--- 守卫 E：取值合法 ---
  badg <- panel$gvar[!(panel$gvar == 0 | (panel$gvar >= Y0 & panel$gvar <= Y1))]
  if (length(badg) > 0) {
    cat("  gvar 有落在 {0} ∪ [", Y0, ", ", Y1, "] 之外的取值：",
        paste(sort(unique(badg)), collapse = " "), "\n", sep = "")
    sink(); close(con)
    stop("gvar 取值越界，已中止。", call. = FALSE)
  }

  #--- 守卫 F：政策一经开始不得回退 ---
  # did / Callaway-Sant'Anna 假设处理是「吸收态」：开始了就一直在。
  # 中途出现旗标=0 的年份要查清楚，是政策真撤了、还是数据填漏了。
  nback <- sum(panel$gvar > 0 & panel$year > panel$gvar & flag == 0, na.rm = TRUE)
  if (nback > 0) {
    cat("  有 ", nback, " 个州-年：gvar 之后又出现旗标=0（政策暂停或回退）。\n", sep = "")
    cat("  Callaway-Sant'Anna 假设处理一旦开始不撤销，先把这些年份的政策状态查清楚。\n")
    sink(); close(con)
    stop("政策出现回退，已中止。", call. = FALSE)
  }

  #--- 诊断：did::att_gt 跑不跑得动 ---
  # 估计量按「队列」（同一首次处理年份的州）分组估计 ATT(g,t)。
  # 队列太少、或某个队列只有一两个州，估出来的 ATT 不可信；全在同一年受处理
  # 则连对照都没有。这些都不该等到跑完回归才发现。
  state_lvl <- panel[!duplicated(panel$state_id), ]
  cohorts <- sort(unique(state_lvl$gvar[state_lvl$gvar > 0]))
  ncohorts <- length(cohorts)
  never <- sum(state_lvl$gvar == 0)
  ntreat <- sum(state_lvl$gvar > 0)

  cat("\n  处理队列数（按首次受处理年份）：", ncohorts, "\n", sep = "")
  cat("  受处理的州：", ntreat, " 个\n", sep = "")
  cat("  从未受处理的州：", never, " 个（did 的默认对照组）\n", sep = "")
  cat("  各队列州数：\n")
  print(table(state_lvl$gvar))

  # 单州队列：ATT 建立在单个州上，换个州结论就变，不能直接写进正文。
  for (g in cohorts) {
    if (sum(state_lvl$gvar == g) == 1) {
      cat("  ⚠ 队列 gvar=", g, " 只有 1 个州。单州队列的 ATT 不可信，\n", sep = "")
      cat("    并入相邻队列或换估计量后再报。\n")
    }
  }

  # 首年即受处理：没有处理前期，事件研究图画不出 pre-period，估计量会丢弃这批州。
  nfirst <- sum(state_lvl$gvar == Y0)
  if (nfirst > 0) {
    cat("  注意：gvar==", Y0, "（区间首年即受处理）的州 ", nfirst, " 个，\n", sep = "")
    cat("        没有处理前期，事件研究会丢掉它们。\n")
  }

  #--- 守卫 G：至少要有可比组 ---
  if (ntreat == 0) {
    cat("  没有任何州受处理，gvar 全是 0。要么旗标填错了，要么区间选错了。\n")
    sink(); close(con)
    stop("没有处理组，已中止。", call. = FALSE)
  }
  if (never == 0 && ncohorts <= 1) {
    cat("  所有受处理的州都在同一年受处理，且没有从未受处理的州——\n")
    cat("  没有任何可比组，估不出 ATT。这种设计要么换估计量，要么换数据。\n")
    sink(); close(con)
    stop("没有可比组，已中止。", call. = FALSE)
  }
  if (never == 0) {
    cat("  没有从未受处理的州，只能靠「尚未处理」的州作对照")
    cat("（att_gt 的 control_group = \"notyettreated\"）。\n")
    cat("  这是有代价的：早期队列的对照里混着后期队列，正文里要说明。\n")
  }
  if (ncohorts <= 1) {
    cat("  只有 1 个处理队列 + 有从未受处理组 = 经典两期 DID。\n")
    cat("  估计量能跑，但它在渐进采纳下的优势用不上；要清楚自己在跑的是哪种设计。\n")
  }

  cat("  gvar 已写入面板。\n")
} else {
  cat("\n  gvar 未构建（外部文件缺）。panel.rds 里不会有这个变量。\n")
}


#------------------------------------------------------------------------------
# 8. 末尾守卫 —— 写在落盘之前
#
#    作用：AI 反复迭代时，只要某次改动让观测数变了、关键变量有了缺失、
#    或主键不唯一，脚本就在这里中断，错误不会沉进 data/processed/。
#    比事后发现系数奇怪再回溯便宜得多。
#------------------------------------------------------------------------------

cat("\n", strrep("=", 78), "\n", sep = "")
cat("末尾守卫\n")
cat(strrep("=", 78), "\n", sep = "")

# 守卫一：样本量
final_n <- nrow(panel)
cat("  最终观测数：", format(final_n, big.mark = ","), "\n", sep = "")
if (final_n < MIN_OBS) {
  cat("  观测数低于 MIN_OBS = ", MIN_OBS, "，样本被改动了，先查清楚。\n", sep = "")
  sink(); close(con)
  stop("样本量守卫未通过，已中止。", call. = FALSE)
}

# 守卫二：主键唯一
if (anyDuplicated(panel[, c("state_id", "year")]) > 0) {
  cat("  主键 state_id + year 不唯一，说明聚合没做干净。先查清楚再往下走。\n")
  dup <- panel[duplicated(panel[, c("state_id", "year")]) |
                 duplicated(panel[, c("state_id", "year")], fromLast = TRUE), ]
  print(head(dup[order(dup$state_id, dup$year), c("state_id", "year")], 20),
        row.names = FALSE)
  sink(); close(con)
  stop("主键不唯一，已中止。", call. = FALSE)
}

# 守卫三：关键变量无缺失，且是有限值
#
# 查 is.finite 而不只查 is.na，是因为上面 collapse 那步用的是 sum(na.rm = TRUE)：
# 某个州-年全是缺失时它会返回 0，而 log(0) 是 -Inf —— 那不是 NA，is.na() 抓不到，
# 却会让后面所有回归系数变成 NaN。这类「看着有值、其实是坏的」正是守卫要拦的。
nmiss_le <- sum(is.na(panel$log_emp))
nbad_le  <- sum(!is.na(panel$log_emp) & !is.finite(panel$log_emp))
if (nmiss_le > 0) {
  cat("  log_emp 有 ", nmiss_le, " 个缺失。缺失怎么处理是研究设计问题\n", sep = "")
  cat("  （CLAUDE.md 第七节第 2 条），先在参数区定好规则再来。\n")
  sink(); close(con)
  stop("关键变量有缺失，已中止。", call. = FALSE)
}
if (nbad_le > 0) {
  cat("  log_emp 有 ", nbad_le, " 个非有限值（-Inf / Inf / NaN）。\n", sep = "")
  cat("  通常是某个州-年的 emp 全是缺失或为 0，collapse 时被 sum(na.rm=TRUE) 变成了 0，\n")
  cat("  取对数就成了 -Inf。先查清这些州-年，不要直接往下跑。\n")
  bad_rows <- panel[!is.na(panel$log_emp) & !is.finite(panel$log_emp), ]
  print(utils::head(bad_rows[, c("state_id", "year", "emp", "log_emp")], 20),
        row.names = FALSE)
  sink(); close(con)
  stop("关键变量有非有限值，已中止。", call. = FALSE)
}

# 年份覆盖面。少一年就意味着面板短一截，必须显式确认。
ymin <- min(panel$year); ymax <- max(panel$year)
cat("  年份区间：", ymin, " - ", ymax, "（预期 ", Y0, " - ", Y1, "）\n", sep = "")
if (ymin != Y0 || ymax != Y1) {
  cat("  年份区间和预期对不上，先查清楚。\n")
  sink(); close(con)
  stop("年份覆盖面守卫未通过，已中止。", call. = FALSE)
}

# 面板完整度提示。守卫不拦这个——非平衡面板是研究者的选择，
# 但至少要让人看见缺口有多大。51 是 50 州 + 华盛顿特区，按 QCEW 的州级口径。
full <- 51L * nper
cat("  州 x 年：", format(final_n, big.mark = ","), " 个观测；满面板需要 ",
    format(full, big.mark = ","), " 个\n", sep = "")
if (final_n < full) {
  cat("  （不足满面板，非平衡。要平衡面板请设 PANEL_MIN_YEARS）\n")
}


#------------------------------------------------------------------------------
# 9. 落盘
#------------------------------------------------------------------------------

panel <- panel[order(panel$state_id, panel$year), ]
saveRDS(panel, file.path(PROC, "panel.rds"))

nstates <- length(unique(panel$state_id))

cat("\n", strrep("=", 78), "\n", sep = "")
cat("完成\n")
cat("  观测数：", format(final_n, big.mark = ","), "\n", sep = "")
cat("  州数：", format(nstates, big.mark = ","), "\n", sep = "")
if (has_ext) {
  cat("  gvar：已写入（did / att_gt 可用）\n")
} else {
  cat("  gvar：未构建（外部文件 data/external/state_min_wage 缺）\n")
  cat("        阶段 05 主回归会因此拒绝运行；补上外部文件后重跑本脚本即可。\n")
}
cat("  产物：", file.path(PROC, "panel.rds"), "\n", sep = "")
cat("  日志：", logfile, "\n", sep = "")
cat(strrep("=", 78), "\n", sep = "")
cat("下一步：把上面的「最终观测数」写进参数区的 MIN_OBS，之后重跑就会自动守卫。\n")

sink()
close(con)
cat("\n日志已写入：", logfile, "\n", sep = "")
