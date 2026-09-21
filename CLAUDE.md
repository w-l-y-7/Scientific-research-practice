# 项目规则

文献综述项目。把一批论文变成一份**引用经核验、证据经分级、按主题组织**的综述。

主题方向：**金融科技**。具体题目待定——`literature_notes/summary_table.md` 还是空表，
主题要从文献里长出来，录进去再定。

## 目录

| 目录 | 存什么 | 谁写 |
| --- | --- | --- |
| `papers/` | PDF 原文，只读 | 人放的 |
| `extracts/` | PDF 转出的 Markdown / CSV，只读 | `extract_tables.py`、markitdown、pymupdf4llm |
| `sources/` | 各库检索的原始结果 JSON | 检索脚本 |
| `figures/` | PRISMA 流程图、检索统计图 | `make_figures.py` |
| `literature_notes/` | 检索记录、候选文献、结构化摘要、GRADE 分级 | 人 + 技能 |
| `citations/` | BibTeX 和校验报告 | 脚本，**不要手改** |
| `drafts/` | 大纲、初稿、审阅意见、终稿 | `review-writer` / `review-checker` 代理 |
| `empirical study/` | **另一条线**：实证研究的数据、代码、产物、正文 | 脚本 + 人，见该目录 README |

**不要在仓库里再套一层子目录。** 代理和技能里写的都是仓库根目录下的相对路径
（`drafts/outline.md`、`literature_notes/summary_table.md`），加一层全断。

唯一例外是 `empirical study/`：那是**另一条独立的线**——自己跑数据的实证研究，
不是读论文的综述，两边不共享目录和脚本。它有自己的八阶段流水线、目录约定和红线，
见 `empirical study/README.md`。综述那条线的技能和代理不碰它，它的路径也不受上面这条规则约束。

但反过来有个例外：`method-advisor` 和 `did-estimate` 两个技能**服务的是 `empirical study/`
那条线，定义却放在仓库根**。这不是笔误——Claude Code 只从**项目根**发现技能，
放别处加载不到（和 `.claude/settings.json` 必须放根是完全同一个原因，见
`empirical study/README.md` 第六节）。它们内部写的路径一律是 `empirical study/...` 开头的。

## 流水线

顺序不能颠倒，每一步的输入是上一步的输出：

| # | 阶段 | 产出 | 用什么 |
| --- | --- | --- | --- |
| 1 | 检索 | `literature_notes/zotero_results.md`、`external_results.md` | `paper-lookup`、Zotero MCP |
| 2 | 筛选 | `literature_notes/candidate_papers.md` | 人 |
| 3 | 录笔记 | `literature_notes/summary_table.md` | **人** |
| 4 | 引用核验 | `citations/` | `citation-management` |
| 5 | 证据分级 | `literature_notes/grade_assessment.md` | `grade-assessment` |
| 6 | 定大纲 | `drafts/outline.md` | 人 |
| 7 | 写正文 | `drafts/review_v1.md` | `review-writer` 代理 |
| 8 | 审阅 | `drafts/review_feedback_v1.md` | `review-checker` 代理 |
| 9 | 定稿 | `drafts/review_final.md` | 人 |

第 3 步是唯一的瓶颈入口，前面没做完后面全卡着。

## 红线

- **`literature_notes/summary_table.md` 是唯一人工输入端。** 要改作者名、补页码、加文献，
  改这个文件然后重跑流水线。改别处下次一跑就被覆盖。
- **`citations/` 下的四个文件全是机器生成的**（`doi_list.txt`、`raw.bib`、`references.bib`、
  `validation.json`），手改无效。
- **覆盖 `references.bib` 前必须先备份。**
  ```powershell
  if (Test-Path citations/references.bib) { Copy-Item citations/references.bib citations/references.bib.bak -Force }
  ```
  不能靠「看着像流水线产物」来判断——手工整理的版本被覆盖就找不回来了。
- **不编造 DOI、作者、页码。** 查不到就报「查不到」，让它缺着。
- **校验出 error 要如实列出来**，不能因为「数量不多」就省略。
- **低等级证据写成「证据有限」，不要写成「已证实」。** 措辞强度跟着 GRADE 等级走。
- **综述按主题组织，不要逐篇罗列。** 每段综合 3-5 篇，讲共识、分歧和演进。

## 环境

- Shell 是 **PowerShell 5.1**。`&&` 和 `||` 不可用——用 `;`，或 `A; if ($?) { B }`。
- **`curl` 是 `Invoke-WebRequest` 的别名**，要调真 curl 必须写 `curl.exe`。
- pdfplumber 装在 `.venv` 里，用前先激活：
  ```powershell
  .\.venv\Scripts\activate
  ```

## PDF 工具

按用途选，完整说明见 [PDF处理工具使用说明.md](PDF处理工具使用说明.md)：

| 用途 | 工具 | 协议 |
| --- | --- | --- |
| 读正文（论文、研报、年报） | `pymupdf4llm` | **AGPL ⚠** |
| 转 docx / pptx / xlsx | `markitdown` | MIT |
| 抽表格、抠数字 | `pdfplumber` + text 策略 | MIT |

**`pymupdf4llm` 是 AGPL**，涉及交付代码或商用前先看说明文档第七节。
替代方案是 MIT 的 markitdown，代价是词间空格会丢。

## 代理与技能

| 名字 | 类型 | 干什么 | 服务哪条线 |
| --- | --- | --- | --- |
| `literature-review` | 技能 | 七阶段全流程，从检索到成文 | 综述 |
| `paper-lookup` | 技能 | 18 个学术 API 检索 | 综述 |
| `citation-management` | 技能 | DOI → BibTeX → 校验报告 | 综述 |
| `grade-assessment` | 技能 | 按 GRADE 逐篇分级 | 综述 |
| `review-writer` | 代理 | 按主题写综述正文 | 综述 |
| `review-checker` | 代理 | 审初稿，出审阅意见 | 综述 |
| `method-advisor` | 技能 | 把研究问题映射到方法假设检查单，给建议不替你决定 | **实证** |
| `did-estimate` | 技能 | 跑阶段 05 主回归：前置检查 → 停下等你确认 → 执行 → 交产物 | **实证** |
| `estimator-agent` | 代理 | 跑阶段 06 稳健性矩阵，核对格子有无遗漏，交回状态和失败原因 | **实证** |
| `robustness-reviewer` | 代理 | 对抗式审阅阶段 06/07：格子漏没漏、口径一不一致、维度有没有真的生效 | **实证** |

技能和代理的分工：技能跑在当前对话里，中途能插手确认；代理是独立上下文，
只交结果回来。所以需要人把关的环节（检索、筛选、分级、主回归规范）用技能，
自成一体的环节（成文）用代理。

后四个服务实证那条线，但**定义必须放根目录**——Claude Code 只从项目根发现技能和代理。
它们读写的都是 `empirical study/` 下的路径。

那两个代理的出现理由是**上下文隔离**：审阅必须在另一个上下文里做，
否则会退化成复述（「我刚才是这么算的，所以没问题」）。
而需要人中途拍板的环节不能交给代理——代理跑完才交结果回来，没法暂停等人，
所以那些环节（阶段 5 主回归规范、阶段 6 矩阵边界）留在技能和配置闸门里。
