# Scientific Reacher Practice

两条独立的线，各有各的流水线，不共享目录和脚本：

| 线 | 干什么 | 目录 | 规则 |
| --- | --- | --- | --- |
| **文献综述** | 把一批论文变成一份**引用经核验、证据经分级、按主题组织**的综述 | 仓库根 | [CLAUDE.md](CLAUDE.md) |
| **实证研究** | 自己跑数据，从识别策略走到复现包 | `empirical study/` | [empirical study/CLAUDE.md](empirical%20study/CLAUDE.md) |

综述线方向是 **金融科技**，具体题目待定——`literature_notes/summary_table.md` 还是空表，
**主题要从文献里长出来**，录进去再定。

实证线另有一条**学术诚信清单**（研究者必须亲自做的五个判断、投稿前自检、复现包还差哪几项）：
[empirical study/README.md](empirical%20study/README.md) 第八节，
细则见 [academic-integrity.md](empirical%20study/references/academic-integrity.md)。
**综述线自己的红线在** [CLAUDE.md](CLAUDE.md)（引用核验、不编造 DOI、措辞跟着 GRADE 走）。

> **⚠️ 现在跑不了完整流水线。** R 及 R 包未安装，实证线的阶段 03–08（全是 `.R`）
> 一行都没跑过；`.venv` 里也还没有 matplotlib。已装、未装、装上了要补什么，
> 见[第六节](#六环境与依赖)。**装完环境后这一节要回来改。**

---

## 一、目录结构

### 仓库根

| 目录 / 文件 | 存什么 | 谁写 |
| --- | --- | --- |
| `papers/` | PDF 原文，只读 | 人放的 |
| `extracts/` | PDF 转出的 Markdown / CSV，只读 | `extract_tables.py`、markitdown、pymupdf4llm |
| `sources/` | 各库检索的原始结果 JSON | 检索脚本 |
| `figures/` | PRISMA 流程图、检索统计图 | `make_figures.py` |
| `literature_notes/` | 检索记录、候选文献、结构化摘要、GRADE 分级 | 人 + 技能 |
| `citations/` | BibTeX 和校验报告 | 脚本，**不要手改** |
| `drafts/` | 大纲、初稿、审阅意见、终稿 | 人 + `review-writer` / `review-checker` |
| `empirical study/` | **另一条线**，见下 | 脚本 + 人 |
| `.claude/settings.json` | 挂 `empirical study/.claude/hooks/` 的两个 hook。**必须放根** | 人 |
| `.claude/skills/` | 七个技能的定义与脚本 | — |
| `.claude/agents/` | 四个代理的定义 | — |
| `.venv/` | Python 3.14.3 环境，已装 pdfplumber | — |
| `extract_tables.py` | PDF 抽表格脚本（从仓库根调用） | 人 |
| `requirements.txt` | `.venv` 的依赖清单 | 人 |
| `CLAUDE.md` | 项目规则，Claude Code 每次会话自动读 | 人 |
| `PDF处理工具使用说明.md` | 三件 PDF 工具的完整用法与踩坑记录 | 人 |

**不要在仓库里再套一层子目录。** 技能和代理里写的都是仓库根目录下的相对路径
（`drafts/outline.md`、`literature_notes/summary_table.md`），加一层全断。

### `empirical study/`（另一条线，不受上一条约束）

```
empirical study/
├── CLAUDE.md         规则：路径、种子、版本、命名、披露、HITL、提交、AI 边界
├── README.md         八阶段流水线、目录约定、计算环境、规则基座
├── config/
│   └── robustness-matrix.R   阶段 6 的矩阵边界（HITL 产物，不是代码）
├── data/
│   ├── raw/          原始数据，只读，禁止写入（现为空）
│   ├── processed/    03_clean.R 独占写入（现为空）
│   └── external/     外部整理数据，进版本库
├── code/
│   ├── 01_identify/  阶段 1 的决策记录（目录空）
│   ├── 02_fetch/     02_fetch.py ← 唯一的 Python，已跑过（见第七节）
│   ├── 03_clean/     03_clean.R
│   ├── 04_describe/  （目录空）
│   ├── 05_main/      05_main.R
│   ├── 06_robust/    06_robust.R
│   ├── 07_tables/    07_tables.R
│   └── 08_replication/ （目录空）
├── output/
│   ├── tables/  figures/  robustness/   全空，只有 .gitkeep
├── logs/             每次运行留痕，带时间戳（现有 3 份，都是阶段 02 的探测日志）
├── paper/            正文（空）
├── references/       方法卡、AI 披露模板
└── .claude/
    ├── rules/        回归规范默认值
    └── hooks/        写 .R 时的自动检查
```

`data/raw/`、`data/processed/`、`output/` 里的内容**不进版本库**，根 `.gitignore`
按 `目录/*` 加 `!目录/.gitkeep` 的写法排除，骨架留住、内容物挡在外面。
`data/external/` 和 `config/` 例外，要进——前者是外部整理数据，后者是研究者的决定。

`code/02_fetch/`、`03_clean/`、`05_main/`、`06_robust/`、`07_tables/` 各有一份 `README.md`，
写该阶段的跑法、产物和已知坑。

---

## 二、综述流水线（九步，顺序不能颠倒）

每一步的输入是上一步的输出。第 3 步是唯一的瓶颈入口，前面没做完后面全卡着。

| # | 阶段 | 产出 | 用什么 |
| --- | --- | --- | --- |
| 1 | 检索 | `literature_notes/zotero_results.md`、`external_results.md` | `paper-lookup` 技能、Zotero MCP |
| 2 | 筛选 | `literature_notes/candidate_papers.md` | 人 |
| 3 | 录笔记 | `literature_notes/summary_table.md` | **人** |
| 4 | 引用核验 | `citations/` | `citation-management` 技能 |
| 5 | 证据分级 | `literature_notes/grade_assessment.md` | `grade-assessment` 技能 |
| 6 | 定大纲 | `drafts/outline.md` | 人 |
| 7 | 写正文 | `drafts/review_v1.md` | `review-writer` 代理 |
| 8 | 审阅 | `drafts/review_feedback_v1.md` | `review-checker` 代理 |
| 9 | 定稿 | `drafts/review_final.md` | 人 |

### 各步骤具体怎么跑

**第 1 步 · 检索**

先在本地 Zotero 库里搜，再补外部数据库。两边分开记，不要混在一起。

```
在 Zotero 库中搜索数字支付、智能投顾、区块链金融相关文献，
命中的条目用 zotero_item_metadata 补全字段，记录到 literature_notes/zotero_results.md
```

外部库走 `paper-lookup`。它一个技能覆盖 **18 个学术 API**——但不要 18 个全撒一遍，
金融科技起步查这四个就够：

| 库 | 为什么 |
| --- | --- |
| Semantic Scholar | 覆盖面广，能按引用数排序，让有影响力的先冒出来 |
| OpenAlex | 元数据全，作者消歧做得好 |
| arXiv（`econ.GN` / `econ.EM`） | 预印本更新快，正式发表要等一两年 |
| Crossref | DOI 和正式发表记录以此为准 |

```
用 paper-lookup 在 Semantic Scholar 搜索 "digital payment adoption household finance"
2020-2026 的论文，限定 Economics 领域，结果存到 sources/，摘要记入 literature_notes/external_results.md
```

**每个库的端点和限流规则先读一遍再调**：`.claude/skills/paper-lookup/references/<库名>.md`。
这些 API 会在 HTTP 200 的情况下返回错误答案（arXiv 参数写错会返回一条标题叫 `Error` 的记录、
Semantic Scholar 不配 key 频繁 429），参考文件里写了每个库特有的静默失败方式。

**第 2 步 · 筛选**

```
把 zotero_results.md 和 external_results.md 合并，按 DOI 去重，
按纳入排除标准筛，写进 literature_notes/candidate_papers.md，
每个阶段的计数都要留，PRISMA 图要用
```

**筛选之前先把标准写下来**，不要边筛边改标准。排除理由要分条记，只记总数在 PRISMA
报告规范里是不合格的。

**第 3 步 · 录笔记（唯一的瓶颈）**

人手动填 `literature_notes/summary_table.md`。**只要 DOI 写对，其余字段由 Crossref 自动补全**，
标题写个大概就行——抽 DOI 用的是正则，不看格式。DOI 支持裸写、带链接、带前缀三种写法。

**第 4 步 · 引用核验**

```
跑一下引用流水线
```

或者手动四步：

```powershell
# 1) 抽 DOI
python .claude/skills/citation-management/scripts/extract_metadata.py literature_notes/summary_table.md --dois-only -o citations/doi_list.txt

# 2) 抓元数据（Crossref 内容协商，对方直接返回 BibTeX）
python .claude/skills/citation-management/scripts/extract_metadata.py citations/doi_list.txt -o citations/raw.bib

# 3) 去重排序 —— 会覆盖 references.bib，先备份
if (Test-Path citations/references.bib) { Copy-Item citations/references.bib citations/references.bib.bak -Force }
python .claude/skills/citation-management/scripts/format_bibtex.py citations/raw.bib -o citations/references.bib

# 4) 校验
python .claude/skills/citation-management/scripts/validate_citations.py citations/references.bib -o citations/validation.json
```

校验出 error 要挨条看，`validation.json` 里 `missing_field` / `bad_doi` / `duplicate_key` 是 error，
`no_doi` / `odd_year` / `unescaped_special` 是 warning。

**第 5 步 · 证据分级**

```
跑一下证据分级
```

按 GRADE 框架逐篇评级。做法是「**识别策略定起始等级，样本 / 稳健性 / 一致性三个维度做调整**」：

| 识别策略 | 起始等级 |
| --- | --- |
| RCT / 随机田野实验、自然实验 | 高 |
| RDD / DID / IV | 中（依赖不可检验的假设，这是方法特性不是缺陷） |
| 匹配 / 面板固定效应 | 低 |
| OLS / 相关性 / 描述统计 | 极低 |

金融科技实证研究里 DID 和 IV 是主力，所以大量论文会落在「中」档起评。

**关键规则：信息缺失不等于降级。** 摘要几乎不写样本量和稳健性检验，如果把「摘要没提」
当成「没做」来处理，结果是每篇都降一级、整张表全是极低——那是噪声不是评价。
摘要没提到的，写「摘要未提及」，不降级。

**第 6 步 · 定大纲**

人写 `drafts/outline.md`。一个二级标题 = 一个主题，每个主题下面四行：
覆盖文献、共识、分歧及原因、演进脉络。

**主题从文献里长出来**，先读完 `summary_table.md` 再定，别先写主题再去找文献凑。

**第 7 步 · 写正文**

```
让 review-writer 按 drafts/outline.md 写综述正文，输出到 drafts/review_v1.md
```

代理读三份输入：大纲 + 摘要表 + GRADE 分级。**措辞强度跟着 GRADE 等级走**——
低等级证据写成「证据有限」，不要写成「已证实」。

**第 8 步 · 审阅**

```
让 review-checker 检查 drafts/review_v1.md，出审阅意见到 drafts/review_feedback_v1.md
```

五个维度：引用准确性、覆盖完整性、综合深度、逻辑连贯性、研究空白。
**只提意见、不改正文**——改不改、怎么改由人决定。

**第 9 步 · 定稿**

人把改好的正文写进 `drafts/review_final.md`。定稿后 `review_v1.md` 冻结，
后续修改只动终稿文件。

---

## 三、技能与代理

**分工原则**：技能跑在当前对话里，中途能插手确认；代理是独立上下文，只交结果回来。
所以需要人把关的环节（检索、筛选、分级、主回归规范）用技能，
自成一体的环节（成文、跑矩阵）用代理。

### 技能（`.claude/skills/`，共七个）

| 名字 | 干什么 | 服务哪条线 | 怎么触发 |
| --- | --- | --- | --- |
| `literature-review` | 七阶段全流程，从选题界定到成文。含 PRISMA 流程图脚本 | 综述 | `/literature-review` 或「做个文献综述」 |
| `paper-lookup` | 18 个学术 API 检索，附各库的限流规则和陷阱 | 综述 | 「找几篇关于 X 的论文」「查一下这个 DOI」 |
| `citation-management` | DOI → BibTeX → 校验报告 | 综述 | 「跑一下引用流水线」「整理引用」 |
| `grade-assessment` | 按 GRADE 逐篇分级 | 综述 | 「跑一下证据分级」「这些论文证据够不够硬」 |
| `git-save` | 扫垃圾 → 写 `.gitignore` → add / commit / push | 通用 | 「保存一下」「推上去」 |
| `method-advisor` | 把研究问题映射到方法假设检查单，给建议但**不替你决定** | **实证** | 「用什么方法」「该用 IV 还是 DID」 |
| `did-estimate` | 跑阶段 05 主回归：前置检查 → 停下等确认 → 执行 → 交产物 | **实证** | 「跑主回归」「跑一下 att_gt」「进阶段 05」 |

### 代理（`.claude/agents/`，共四个）

| 名字 | 干什么 | 输入 | 输出 |
| --- | --- | --- | --- |
| `review-writer` | 按主题写综述正文 | 大纲 + 摘要表 + GRADE | `drafts/review_v1.md` |
| `review-checker` | 审初稿，出审阅意见 | 初稿 + 摘要表 + GRADE | `drafts/review_feedback_v1.md` |
| `estimator-agent` | 跑阶段 06 稳健性矩阵，核对格子有无遗漏 | `config/robustness-matrix.R` | 状态 + 失败原文 |
| `robustness-reviewer` | 对抗式审阅阶段 06/07 的产物 | `cells.csv` + 配置 + 表 | 审阅意见（**只读，不写文件**） |

后两个服务实证线。`estimator-agent` 只跑不改——**尤其不许翻 `MATRIX_CONFIRMED` 那道闸门**；
`robustness-reviewer` 刻意是另一个上下文，看不到写表时的思路，才会去逐格对账而不是复述
「我刚才是这么算的」。分工细节见 `empirical study/CLAUDE.md` 第十二节。

### 为什么后四个的定义要放根目录

Claude Code **只从项目根发现**技能和代理。`method-advisor`、`did-estimate`
和上面两个代理服务的都是 `empirical study/` 那条线，但如果放进
`empirical study/.claude/`，它们根本不会被加载——所以定义在根，
`empirical study/.claude/` 里只留 hook 脚本和规则文件，由根 `.claude/settings.json` 挂上。
同一个原因，`.claude/settings.json` 也必须放根。

### 技能附带的脚本

脚本一律**从仓库根目录调用，路径写全**——不要写 `scripts/x.py`，那是相对技能目录的，
从仓库根跑不起来。

```powershell
# PRISMA 2020 流程图
python .claude/skills/literature-review/scripts/make_figures.py prisma --counts figures/prisma_counts.json -o figures/prisma_flow.png

# 各库贡献 + 年份分布
python .claude/skills/literature-review/scripts/make_figures.py stats --results sources/combined_results.json -o figures/search_stats.png
```

`counts.json` 的字段名是固定的（`identified_databases`、`screened`、`included` 等 11 个）。
名字写错脚本会报错并列出可用字段，**不会静默按 0 处理**——数字画错比画不出来危险得多。

其他脚本：

| 脚本 | 用途 | 依赖 |
| --- | --- | --- |
| `literature-review/scripts/search_databases.py` | 检索结果去重、排序、按年份过滤、导出 | 标准库 |
| `literature-review/scripts/make_figures.py` | PRISMA 流程图、检索统计图 | **matplotlib（未装）** |
| `literature-review/scripts/generate_pdf.py` | Markdown → PDF（pandoc + xelatex），`--check-deps` 检查依赖 | pandoc ✓、xelatex ✓ |
| `grade-assessment/scripts/fetch_abstracts.py` | 按 DOI 从 Crossref 批量抓摘要 | 标准库 |
| `citation-management/scripts/*.py` | 四个脚本，对应引用流水线四步 | 标准库 |
| `paper-lookup/scripts/*.py` | 四个脚本，配合各库的参考文件用 | 标准库 |

---

## 四、PDF 工具链

完整说明见 [PDF处理工具使用说明.md](PDF处理工具使用说明.md)，那里面所有命令都在本机实测过。

**按用途选工具**：

| 用途 | 工具 | 协议 | 状态 |
| --- | --- | --- | --- |
| 读正文（论文、研报、年报） | `pymupdf4llm` | **AGPL ⚠** | 已装（uv 全局工具） |
| 转 docx / pptx / xlsx | `markitdown` | MIT | 已装（uv 全局工具） |
| 抽表格、抠数字 | `pdfplumber` + text 策略 | MIT | 已装（`.venv` 里，0.11.10） |

```powershell
# PDF → Markdown，保留标题层级和空格
pymupdf4llm 研报.pdf --out ./out

# 批量转办公格式
Get-ChildItem *.pdf | ForEach-Object { markitdown $_.Name -o ($_.BaseName + ".md") }

# 抽表格（先激活环境）
.\.venv\Scripts\activate
python extract_tables.py 财报.pdf          # 只留看起来像表格的
python extract_tables.py 财报.pdf --all    # 全都导出，不过滤
```

**三个必须知道的坑**：

1. **无边框表格默认抽不出来。** pdfplumber 默认用「有线」策略，但很多财报表格根本没有线。
   要加 `{"vertical_strategy": "text", "horizontal_strategy": "text"}`。`extract_tables.py`
   已经两个策略都试了。
2. **markitdown 转 PDF 会丢词间空格**（`guide planning decisions` → `guideplanningdecisions`），
   数字和专有名词会连成一片，**不适合拿来核对财报数据**。读正文用 pymupdf4llm。
3. **扫描件和部分中文 PDF 没有文本层**，抽出来是乱码。这不是代码问题，得另找 OCR 工具。

**`extract_tables.py` 的过滤是启发式的，会漏也会误留，务必人工过一遍。**
实测一篇 8 页论文：13 个候选筛到 5 个，抽查 3 个只有 1 个是真表格。
阈值（`MIN_COLS` / `MAX_AVG_CELL`）是按那篇论文定的，**换一批文档要重新校准**。

**协议提醒**：`pymupdf4llm`（含底层 `pymupdf`）是 **AGPL-3.0**。自己写作业、读文献没问题；
**代码要交付给公司、或把成果开源到 GitHub 之前先看说明文档第七节**。
替代方案是 MIT 的 markitdown，代价是词间空格会丢——也就是说，这套流程里真正不可替代的
是 pdfplumber，而它是 MIT。

---

## 五、红线

### 两条线通用

- **不编造数字、DOI、作者、页码。** 查不到就报「查不到」，让它缺着，也不拿近似值顶上。
- **表和图全部脚本生成。** 手工调过的数字下次重跑就对不上，对不上就等于没有。
- **每次运行留日志。** 时间戳、输入文件名、输出文件名、观测数，缺一样就没法复现。

### 综述线

- **`literature_notes/summary_table.md` 是唯一人工输入端。** 要改作者名、补页码、加文献，
  改这个文件然后重跑流水线。改别处下次一跑就被覆盖。
- **`citations/` 下的四个文件全是机器生成的**（`doi_list.txt`、`raw.bib`、`references.bib`、
  `validation.json`），手改无效。
- **覆盖 `references.bib` 前必须先备份。** 不能靠「看着像流水线产物」来判断——手工整理的
  版本被覆盖就找不回来了：
  ```powershell
  if (Test-Path citations/references.bib) { Copy-Item citations/references.bib citations/references.bib.bak -Force }
  ```
- **校验出 error 要如实列出来**，不能因为「数量不多」就省略。
- **低等级证据写成「证据有限」，不要写成「已证实」。** 措辞强度跟着 GRADE 等级走。
- **综述按主题组织，不要逐篇罗列。** 每段综合 3-5 篇，讲共识、分歧和演进。

### 实证线

完整版见 [empirical study/README.md](empirical%20study/README.md) 第七节。

- **原始数据只读。** 清洗结果另存，绝不覆盖 `data/raw/`。
- **四处由人定稿才往下走**：样本规则、模型规范、矩阵边界、结论措辞。
  AI 给出方案和代价，决定权在研究者。
- **AI 只跑代码、不读数字。** 系数解读、假设判断、稳健性结论由研究者撰写；
  每个结果都要能追到数据指纹（`saveRDS` + `tools::md5sum`）。
- **稳健性矩阵完整进附录，符号翻转的格子不许删。** 跑不成的格子也要有行并写明原因。
  正文可以只展示 3-4 列，但要说明为什么这么挑。
- **结论措辞跟着识别策略走。** DID / IV 写成「在某某假设下，估计结果支持……」，
  不写成「已证明」。

---

## 六、环境与依赖

**Shell 是 PowerShell 5.1**，注意两个坑：

- **`&&` 和 `||` 不可用**——用 `;`，或 `A; if ($?) { B }`
- **`curl` 是 `Invoke-WebRequest` 的别名**——要调真 curl 必须写 `curl.exe`

### 装了没有（2026-09-21 核对）

| 需要什么 | 干什么用 | 现状 |
| --- | --- | --- |
| Python 3.14.3（`.venv`） | 全部技能脚本、PDF 抽表 | ✅ |
| `pdfplumber` 0.11.10 | `extract_tables.py` 抽表格 | ✅ |
| `pandoc` | `generate_pdf.py` 出 PDF | ✅ |
| `xelatex`（MiKTeX） | `generate_pdf.py` 中文排版 | ✅ |
| `markitdown` / `pymupdf4llm` | PDF → Markdown / Office 格式 | ✅（uv 全局工具） |
| **`matplotlib`** | `make_figures.py` 画 PRISMA 图和统计图 | ❌ **没装** |
| **R（≥ 4.4.0）** | 实证线阶段 03、05、06、07 的所有 `.R` | ❌ **没装** |
| **R 包 `did` `fixest` `ggplot2`** | 阶段 05 主回归必需 | ❌ 没装（跟着 R 一起） |
| QCEW 数据出口 | 实证线阶段 02 拉数据 | ⚠️ 直连 403，需挂代理 |

**所以现在能跑到哪一步**：综述线的第 1–5 步和第 7–9 步都能跑（脚本全是标准库），
只有画 PRISMA 图那一步缺 matplotlib。实证线**一行 R 都没跑过**，
阶段 02 的 Python 拉取脚本能跑但直连数据源被 403 挡住。

### 补环境

```powershell
# 1) 补 matplotlib（PRISMA 图要用；装完把版本写进 requirements.txt）
.\.venv\Scripts\activate
uv pip install matplotlib

# 2) 装 R：https://cran.r-project.org/bin/windows/base/
#    RStudio Desktop 可选但强烈建议：https://posit.co/download/rstudio-desktop/
#    装完在 R 里核对：R.version.string 应显示 4.4.0 或更高

# 3) 装阶段 05 必需的三个 R 包
Rscript -e "install.packages(c('did','fixest','ggplot2'))"
```

R 包第二档（`haven`、`fwildclusterboot`、`sandwich` + `lmtest`、`ivreg`、
`rdrobust` / `rddensity` / `rdplot`）**现在不装也行**，用到哪个装哪个，
清单和用途见 [empirical study/README.md](empirical%20study/README.md) 第五节。

**装完 R 之后要回来改两处**（都是刻意留的待办，不要跳过）：

1. **本节表格**：把 ❌ 改成 ✅，并记下实际装到的版本。
2. **`.claude/rules/regression-spec.md`**：那里有一条关于 `feols` 不写 `cluster` 时
   默认口径的**待核实项**，明写着「本机还没装 R，这个仓库里一行 R 都没跑过。
   等装好 R，跑 `?feols` 看 `vcov` 一节……核完把这段删掉」。
   装好后核实并删掉那段。**不管默认是哪个，本项目的规定都是显式写 `cluster = ~...`**。

R 包版本由 `empirical study/README.md` 第五节记录：跑完 `05_main.R` 后脚本会把
`R.version.string` 和 `packageVersion()` 打进日志，抄进那一节即可。

### Python 环境

`requirements.txt` 现在只锁了 pdfplumber。**要加依赖先改这个文件再装**，
不要在会话里临时 `pip install`（规则见 [empirical study/CLAUDE.md](empirical%20study/CLAUDE.md) 第三节）。
换机器重建：

```powershell
uv venv .venv
uv pip install -r requirements.txt
```

`literature-review` 技能出 PDF 还依赖 `pandoc` 和 `xelatex`（MiKTeX），检查一遍：

```powershell
python .claude/skills/literature-review/scripts/generate_pdf.py --check-deps
```

---

## 七、当前状态

**两条线都还没真正跑起来。** 综述线的内容文件全是空模板，实证线只跑过阶段 02 的
探测（且没拉到数据）。另外 R 没装，实证线阶段 03 起走不动，见第六节。

### 综述线

| 文件 | 状态 |
| --- | --- |
| `literature_notes/zotero_results.md` | 未跑（空模板） |
| `literature_notes/external_results.md` | 未跑（空模板） |
| `literature_notes/candidate_papers.md` | 纳入排除标准待填 |
| `literature_notes/summary_table.md` | **空表，待录入——瓶颈在这** |
| `citations/doi_list.txt` | 空 |
| `citations/raw.bib` | 未生成 |
| `citations/references.bib` | 空（有一份 717 字节的 `.bak` 备份） |
| `citations/validation.json` | 未生成 |
| `literature_notes/grade_assessment.md` | 未跑（等 summary_table 有文献） |
| `drafts/outline.md` | 主题待定 |
| `drafts/review_v1.md` | 未生成（三个前置依赖没一个就位） |
| `drafts/review_feedback_v1.md` | 未跑 |
| `drafts/review_final.md` | 未定稿 |

`papers/`、`extracts/`、`figures/`、`sources/` 四个目录只有 `.gitkeep`，等第一批 PDF 进来。

**下一步**：从第 1 步检索开始——Zotero MCP 和 `paper-lookup` 都不需要额外依赖，现在就能跑。

### 实证线

| 阶段 | 状态 |
| --- | --- |
| 01 研究问题与识别假设 | 目录空，**这个 HITL 节点还没做，后面七步都得等它** |
| 02 数据拉取 | 脚本已写好，跑过 3 次；**`data/raw/` 里一个数据文件都没有** |
| 03 数据清洗 | `03_clean.R` 已建，**没跑过**（要 R） |
| 04 描述统计 | 目录空 |
| 05 主回归 | `05_main.R` 已建，**没跑过**（要 R） |
| 06 稳健性矩阵 | `06_robust.R` + `config/robustness-matrix.R` 已建，**没跑过**（要 R） |
| 07 表格图形 | `07_tables.R` 已建，**没跑过**（要 R） |
| 08 复现包 | 目录空 |

阶段 02 的三份日志（`logs/02_fetch_*.log`）全是 `--check` 探测，没有真下载：

- `02_fetch_20260920_212229`（2019 单年）→ **403 Forbidden**
- `02_fetch_20260920_213259`（2019 单年）→ HTTP 200，74.8 MB
- `02_fetch_20260920_213831`（2000-2019 全区间）→ **20 年全部 403**

中间那份通了是因为挂了代理，换回直连立刻又是 403。**这是网络出口问题，不是脚本问题**，
排查方式和已知坑见 [empirical study/code/02_fetch/README.md](empirical%20study/code/02_fetch/README.md)。
