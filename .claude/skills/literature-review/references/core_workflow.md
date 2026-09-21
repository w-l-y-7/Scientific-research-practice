# 核心工作流

七个阶段的完整说明：选题与范围界定、系统检索、筛选与选择、数据提取与质量评估、综合与分析、引用核验、文档生成。

## 核心工作流

文献综述遵循一套结构化的多阶段工作流：

### 阶段 1：选题与范围界定

1. **确定研究问题**：经济学 / 金融科技综述用 PECO 框架（Population 研究总体、Exposure 暴露、Comparator 对照、Outcome 结局）
   - 示例："在中小企业（P）中，接入数字信贷（E）相比仅依赖传统银行信贷（C），对融资约束（O）的缓解程度如何？"

2. **界定范围与目标**：
   - 提出清晰、具体的研究问题
   - 确定综述类型（叙述性综述、系统综述、范围综述、元分析）
   - 划定边界（时间段、地域范围、研究类型）

3. **制定检索策略**：
   - 从研究问题中提取 2-4 个核心概念
   - 列出每个概念的同义词、缩写和相关词
   - 规划布尔运算符（AND、OR、NOT）组合检索词
   - 至少选择 3 个互补的数据库
   - **初步摸底时用 paper-lookup 技能**，在正式数据库检索前快速了解领域概貌

4. **设定纳入/排除标准**：
   - 日期范围（如近 10 年：2015-2024）
   - 语言（通常为英文，或指定多语言）
   - 出版类型（同行评审论文、工作论文、预印本、综述）
   - 研究设计（准实验、随机对照试验、田野实验、面板回归、元分析等）
   - 完整记录所有标准

### 阶段 2：系统文献检索

1. **多数据库检索**：

   选择适合本领域的数据库。**始终先用 paper-lookup 技能获得广泛的学术覆盖**，再用领域专用来源补充。

   **基于 API 的学术检索（paper-lookup 技能 — 从这里开始）：**
   - 用 `curl.exe` 直接打 Semantic Scholar、OpenAlex 的真实端点，覆盖跨学科的学术来源
   - 每个库的完整参数和陷阱见 paper-lookup 技能的 `references/` 目录，调用前先读
   ```powershell
   # Semantic Scholar：跨学科覆盖 2 亿+ 论文，带 key 走独立配额，不易撞 429
   curl.exe -s -H "x-api-key: $env:S2_API_KEY" `
     "https://api.semanticscholar.org/graph/v1/paper/search?query=fintech+digital+credit+SME+financing+constraints&fields=title,year,abstract,citationCount,authors,externalIds,openAccessPdf&limit=100&year=2015-2024" `
     -o sources/litreview_fintech-s2.json

   # OpenAlex：2.5 亿+ 成果，覆盖面最广，按被引数排序，只要带摘要的文章
   curl.exe -s "https://api.openalex.org/works?search=fintech+SME+financing+constraints&filter=from_publication_date:2015-01-01,type:article,has_abstract:true&sort=cited_by_count:desc&per_page=100&mailto=you@example.com" `
     -o sources/litreview_fintech-openalex.json
   ```
   - 拿到候选 DOI 后，用 Unpaywall 查合法开放获取 PDF，全文用 Europe PMC 或 CORE 取
   ```powershell
   # Unpaywall：按 DOI 查开放获取状态；email 必须是真实邮箱，占位符会被 422 拒掉
   curl.exe -s "https://api.unpaywall.org/v2/10.1016/j.jfineco.2021.03.007?email=you@example.com"
   # is_oa 为 true 时，取 best_oa_location.url_for_pdf 下载

   # CORE：任意学科全文，需要 key；注意 GET 搜索端点末尾的斜杠不能省
   curl.exe -s -H "Authorization: Bearer $env:CORE_API_KEY" "https://api.core.ac.uk/v3/search/works/?q=doi:10.1016/j.jfineco.2021.03.007&limit=5"
   ```

   **经济学与金融科技主力来源：**
   - 按 DOI 取权威元数据：用 Crossref，`GET https://api.crossref.org/works/{doi}`，DOI 里的 `/` 要编码成 `%2F`
   - 按学科收窄：Semantic Scholar 的 `fieldsOfStudy` 接受 `Economics,Business`，把检索限定在经济学与商学
   - 按机构或作者系统检索：OpenAlex 的 `filter=authorships.institutions.country_code:cn`、`filter=concepts.id:C41008148`
   - Crossref 还能按资助方检索：`filter=funder:100000001`（NSF 的 Funder Registry ID）

   **预印本与工作论文：**
   - 检索 arXiv 经济学预印本，分类看 `econ.EM`（计量经济）、`econ.GN`（一般经济）、`econ.TH`（理论）
   - arXiv 返回 Atom XML，不是 JSON；解析交给 paper-lookup 技能的 `scripts/arxiv_atom.py`
   - Semantic Scholar 和 OpenAlex 也收录 NBER、SSRN 的工作论文
   - 工作论文是否已正式发表，用 Crossref 按标题或 DOI 对照

   **paper-lookup 还覆盖哪些库（按需选用）：**
   - PubMed、PMC、Europe PMC：生物医学文献与全文，非本领域默认来源
   - bioRxiv、medRxiv：生命科学与健康科学预印本
   - CORE：全球仓储的开放获取全文
   - DOAJ：开放获取期刊名录；ROR：机构署名字符串转机构 ID
   - OpenCitations：开放引用边；Zenodo、Figshare：存缴的数据与软件

2. **记录检索参数**：
   ```markdown
   ## 检索策略

   ### 数据库：OpenAlex
   - **检索日期**：2026-09-16
   - **日期范围**：2015-01-01 至 2026-09-16
   - **检索式**：
     ```
     search=fintech SME financing constraints
     filter=from_publication_date:2015-01-01,type:article,is_oa:true
     sort=cited_by_count:desc
     ```
   - **结果数**：1,284 条论文
   ```

   每检索一个数据库就重复一次。

3. **导出并汇总结果**：
   - 从每个数据库导出 JSON 格式结果
   - 把所有结果合并到一个文件
   - 用 `scripts/search_databases.py` 做后处理：
     ```powershell
     python .claude/skills/literature-review/scripts/search_databases.py sources/combined_results.json --deduplicate --format markdown --output literature_notes/candidate_papers.md
     ```

### 阶段 3：筛选与选择

1. **去重**：
   ```powershell
   python .claude/skills/literature-review/scripts/search_databases.py sources/combined_results.json --deduplicate --output sources/unique_results.json
   ```
   - 按 DOI（首选）或标题（后备）去重
   - 记录去除的重复条目数

2. **题名筛选**：
   - 对照纳入/排除标准审查所有题名
   - 排除明显不相关的研究
   - 记录此阶段排除的数量

3. **摘要筛选**：
   - 阅读剩余研究的摘要
   - 严格执行纳入/排除标准
   - 记录排除理由

4. **全文筛选**：
   - 获取剩余研究的全文
   - 对照全部标准逐篇细审
   - 记录具体的排除理由
   - 记下最终纳入的研究数

5. **绘制 PRISMA 流程图**：
   ```
   初次检索：n = X
   ├─ 去重后：n = Y
   ├─ 题名筛选后：n = Z
   ├─ 摘要筛选后：n = A
   └─ 纳入综述：n = B
   ```

   把各阶段计数写成 `figures/prisma_counts.json`（字段名见 `scripts/make_figures.py` 顶部的 `PRISMA_FIELDS`），再画成流程图：
   ```powershell
   python .claude/skills/literature-review/scripts/make_figures.py prisma --counts figures/prisma_counts.json -o figures/prisma_flow.png
   ```

### 阶段 4：数据提取与质量评估

1. 从每篇纳入研究**提取关键数据**：
   - 研究元数据（作者、年份、期刊、DOI）
   - 研究设计与识别策略
   - 样本量与研究样本特征
   - 主要发现、效应量与统计显著性
   - 作者指出的局限性
   - 资金来源与利益冲突

2. **评估研究质量**：
   - **随机对照试验、田野实验**：用 Cochrane 偏倚风险工具（RoB 2）
   - **准实验研究（DID、IV、RDD）**：核查识别假设、平行趋势检验、工具变量外生性
   - **观察性研究**：用 Newcastle-Ottawa 量表
   - **系统综述**：用 AMSTAR 2
   - 给每篇研究评级：高质量、中等、低、极低
   - 考虑排除极低质量的研究

3. **按主题归类**：
   - 从研究中提炼 3-5 个主要主题
   - 按主题分组（同一研究可归入多个主题）
   - 记录规律、共识与争议

4. **写出大纲 `drafts/outline.md`**：
   这一步是交给 `review-writer` 代理的接口，**不能省**——代理的输入里就写死了这个文件。
   - 一个二级标题 = 一个主题
   - 每个主题四行：**覆盖文献**、**共识**、**分歧及原因**、**演进脉络**
   - 主题从文献里长出来，读完 `literature_notes/summary_table.md` 再定，不要先定主题再找文献凑
   - 确认主题之间不重叠、合起来能覆盖全部文献

### 阶段 5：综合与分析

1. **交给 `review-writer` 代理写正文**，不要在本技能里自己写：
   - 输入：`drafts/outline.md` + `literature_notes/summary_table.md` + `literature_notes/grade_assessment.md`
   - 输出：`drafts/review_v1.md`
   - 版式参考 `.claude/skills/literature-review/assets/review_template.md`
   - 写完再由 `review-checker` 代理审，产出 `drafts/review_feedback_v1.md`

2. **正文的要求**（`review-writer` 按这个写，不是逐篇研究摘要）：
   - 按主题或研究问题组织结果部分
   - 在每个主题内综合多项研究的发现
   - 比较并对照不同的方法与结果
   - 找出共识所在与争议焦点
   - 突出最强的证据

   示例结构：
   ```markdown
   #### 3.3.1 主题：数字信贷缓解融资约束的作用渠道

   纳入研究给出三条主要渠道。信息渠道方面，9 项准实验研究以征信覆盖扩张
   作为外生冲击，发现贷款获批率提升 8-15 个百分点^1-9^，对无抵押、无信用
   记录的企业效应最大^3,7,12^。相比之下，单纯扩大信贷供给（如定向再贷款）
   在信息不对称严重时效果有限^16-23^。
   ```

3. **批判性分析**：
   - 评估各研究的方法学优势与局限
   - 评价证据的质量与一致性
   - 找出知识空白与方法学空白
   - 指出需要未来研究的领域

4. **讨论部分的要求**：
   - 在更广阔的背景下解读发现
   - 讨论政策、实践或研究意义
   - 承认综述本身的局限
   - 如有可能，与既往综述比较
   - 提出具体的未来研究方向

### 阶段 6：引用核验

**关键**：定稿提交前必须核验所有引用的准确性。

1. **调用 `citation-management` 技能核验**：

   **不要用本技能的 `verify_citations.py` 重做一遍**——两套实现的结果会对不上。
   跑法见 `.claude/skills/citation-management/SKILL.md`。该技能会：
   - 从 `literature_notes/summary_table.md` 抽 DOI，抓 Crossref 元数据
   - 去重排序写成 `citations/references.bib`
   - 出 `citations/validation.json` 校验报告

   **覆盖 `references.bib` 前先备份**（该技能的红线）：
   ```powershell
   if (Test-Path citations/references.bib) { Copy-Item citations/references.bib citations/references.bib.bak -Force }
   ```

2. **检查校验报告 `citations/validation.json`**：
   - 逐条看 error。**不能因为「数量不多」就省略**，要如实列给用户
   - 核对作者姓名、标题、出版信息是否一致
   - 要改就回 `literature_notes/summary_table.md` 改——手改 `.bib` 无效，下次一跑就被覆盖

3. **统一引用格式**：
   - 选定一种引用格式并全文统一（见 `references/citation_styles.md`）
   - 常见格式：APA、Nature、Vancouver、Chicago、IEEE
   - 用核验脚本的输出正确排版引用
   - 确保正文引用与参考文献列表格式一致

### 阶段 7：文档生成

1. **生成 PDF**：
   ```powershell
   python .claude/skills/literature-review/scripts/generate_pdf.py drafts/review_final.md --citation-style apa --output drafts/review_final.pdf
   ```

   选项：
   - `--citation-style`：apa、nature、chicago、vancouver、ieee
   - `--no-toc`：关闭目录
   - `--no-numbers`：关闭章节编号
   - `--check-deps`：检查是否已安装 pandoc/xelatex

2. **检查最终输出**：
   - 检查 PDF 的格式与版式
   - 确认所有章节齐全
   - 确保引用渲染正确
   - 检查图表是否正常显示
   - 核对目录是否准确

3. **质量检查清单**：
   - [ ] 所有 DOI 均已用 `citation-management` 技能核验
   - [ ] 引用格式统一
   - [ ] 含 PRISMA 流程图（系统综述）
   - [ ] 检索方法完整记录
   - [ ] 纳入/排除标准表述清晰
   - [ ] 结果按主题组织（非逐篇罗列）
   - [ ] 完成质量评估
   - [ ] 承认局限性
   - [ ] 参考文献完整准确
   - [ ] PDF 生成无报错
