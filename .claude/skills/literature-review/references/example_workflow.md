# 示例工作流

从范围界定到文档生成的完整综述实例。

## 示例工作流

金融科技 / 经济学文献综述的完整工作流（主题：数字信贷与中小企业融资约束）：

```powershell
# 1. 大纲定好后交 review-writer 代理写正文，产出 drafts/review_v1.md
#    版式参考 .claude/skills/literature-review/assets/review_template.md

# 2. 规划与界定：研究问题用 PECO 框架
#    P 中小企业（员工 < 500 人）
#    E 数字信贷可得性（数字信贷、移动支付、征信科技）
#    C 传统银行信贷，或未接入金融科技的对照组
#    O 融资约束（SA 指数、投资-现金流敏感度、贷款获批率）
#    纳入：2015-2026 年、同行评审期刊或 NBER/SSRN 工作论文、准实验或田野实验设计
#    排除：纯理论模型、没有融资约束度量、样本不是企业层面

# 3. 用 paper-lookup 技能做多库系统检索
# 每个库的完整参数与陷阱见 paper-lookup 的 references/，调用前先读

# Semantic Scholar：跨学科覆盖，带 key 走独立配额，不易撞 429
curl.exe -s -H "x-api-key: $env:S2_API_KEY" "https://api.semanticscholar.org/graph/v1/paper/search?query=fintech+digital+credit+SME+financing+constraints&fields=title,year,abstract,citationCount,authors,externalIds,openAccessPdf&limit=100&year=2015-2026" -o sources/litreview_fintech-s2.json

# OpenAlex：覆盖面最广，按被引数排序，先只要带摘要的文章
curl.exe -s "https://api.openalex.org/works?search=fintech+SME+financing+constraints&filter=from_publication_date:2015-01-01,type:article,has_abstract:true&sort=cited_by_count:desc&per_page=100&mailto=you@example.com" -o sources/litreview_fintech-openalex.json

# arXiv：经济学预印本（econ.GN 一般经济、econ.EM 计量）；返回 Atom XML，
# 不是 JSON，用 .claude/skills/paper-lookup/scripts/arxiv_atom.py 转成记录
curl.exe -s "https://export.arxiv.org/api/query?search_query=cat:econ.GN+AND+all:%22fintech%22&max_results=50" -o sources/litreview_fintech-arxiv.xml

# Crossref：按复杂检索式补权威元数据，供去重与引用核验用
curl.exe -s "https://api.crossref.org/works?query.bibliographic=fintech+SME+financing+constraints&filter=from-pub-date:2015-01-01,type:journal-article,has-abstract:true&rows=100&sort=is-referenced-by-count&order=desc&mailto=you@example.com" -o sources/litreview_fintech-crossref.json

# 4. 汇总、去重、按引用数排序
python .claude/skills/literature-review/scripts/search_databases.py sources/combined_results.json --deduplicate --rank citations --year-start 2015 --year-end 2026 --format markdown --output literature_notes/candidate_papers.md --summary

# 5. 筛选：题名 → 摘要 → 全文，每一阶段的计数都留下来，后面画 PRISMA 用
#    本例：初检 1,842 条 → 去重后 1,207 条 → 题名筛选后 318 条
#          → 全文评估 96 条 → 纳入 41 条

# 6. 提取数据：对进入全文筛选的 DOI，用 Unpaywall 查合法开放获取 PDF
curl.exe -s "https://api.unpaywall.org/v2/10.1016/j.jfineco.2021.03.007?email=you@example.com"
#    取 best_oa_location.url_for_pdf 下载；closed 的走机构订阅或馆际互借
#    任意学科全文也可用 CORE（需 CORE_API_KEY，注意搜索端点末尾的斜杠）
curl.exe -s -H "Authorization: Bearer $env:CORE_API_KEY" "https://api.core.ac.uk/v3/search/works/?q=doi:10.1016/j.jfineco.2021.03.007&limit=5"
#    按主题归类，把研究设计、识别策略、样本、效应量提进提取表

# 7. 画配图：PRISMA 流程图 + 检索统计图（都由 make_figures.py 程序化生成）
#    prisma_counts.json 的字段名见 make_figures.py 顶部的 PRISMA_FIELDS
python .claude/skills/literature-review/scripts/make_figures.py prisma --counts figures/prisma_counts.json -o figures/prisma_flow.png
python .claude/skills/literature-review/scripts/make_figures.py stats --results sources/combined_results.json -o figures/search_stats.png

# 8. 按模板结构撰写综述
#    - 引言：研究问题与 PECO 界定
#    - 方法：数据库、检索式、纳入/排除标准、PRISMA 各阶段计数
#    - 结果：按主题组织（作用渠道、企业异质性、识别策略差异）
#    - 讨论：与既往综述比较、政策含义、本综述的局限

# 9. 核验所有引用：调用 citation-management 技能，不要用本技能的 verify_citations.py
#    跑法见 .claude/skills/citation-management/SKILL.md
#    产出 citations/references.bib 和 citations/validation.json
#    覆盖 references.bib 前先备份，error 要逐条列给用户

# 查看校验报告
Get-Content citations/validation.json

# 要改就回 literature_notes/summary_table.md 改，手改 .bib 下次一跑就被覆盖

# 10. 生成规范 PDF
python .claude/skills/literature-review/scripts/generate_pdf.py drafts/review_final.md --citation-style apa --output drafts/review_final.pdf

# 11. 检查最终的 PDF 与 Markdown 输出
```
