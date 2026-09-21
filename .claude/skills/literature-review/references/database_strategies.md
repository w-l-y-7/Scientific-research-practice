# 文献数据库检索策略

本文档给出在多个学术数据库中系统、高效检索的完整指南，面向经济学与金融科技题材。

## 可用数据库与技能

本技能的检索统一走 **paper-lookup 技能**，它覆盖 18 个学术 API：Semantic Scholar、OpenAlex、arXiv、Crossref、Unpaywall、PubMed、Europe PMC、PMC、bioRxiv、medRxiv、DOAJ、CORE、PubTator、ROR、OpenCitations、Zenodo、Figshare、BioStudies。下面只展开经济学、金融科技最常用的几个，其余库的端点、参数和陷阱去查 `paper-lookup/references/` 下对应的文件。本文所有命令按 PowerShell 写：用 `curl.exe` 而不是 `curl`，用 `python` 而不是 `python3`。

### 核心综合库

#### Semantic Scholar
- **访问**：用 paper-lookup 技能，或 `curl.exe` 直接调 API
- **覆盖范围**：全领域 2 亿篇以上论文
- **最适合**：跨学科检索、引用图谱、有影响力的引用、论文推荐
- **认证**：不带 key 走共享限流池，经常 429；带 key 后每秒 1 次请求，放在请求头 `x-api-key`
- **检索要点**：`/paper/search` 用 `query` 纯文本，再靠 `year`、`fieldsOfStudy=Economics`、`minCitationCount`、`openAccessPdf` 这些参数收窄；布尔表达式（`+` 与、`|` 或、`-` 非、`"..."` 短语、`*` 通配）只在 `/paper/search/bulk` 端点生效
- **限流**：不配 key 频繁触发 429，是这条路最常见的失败点；另外 `fields` 参数是逗号分隔，中间不能有空格

#### OpenAlex
- **访问**：用 paper-lookup 技能，或 `curl.exe` 直接调 API
- **覆盖范围**：2.5 亿以上作品，元数据全面
- **最适合**：引用分析、作者消歧、机构研究、文献计量
- **认证**：免费 API key（`?api_key=YOUR_KEY`）最稳；不带 key 也能用，但建议带上 `?mailto=you@example.com` 进礼貌池
- **检索要点**：`/works?search=` 做全文检索，`filter=` 做字段筛选，两者可以叠用；`sort` 支持 `cited_by_count:desc`
- **限流**：最高 100 请求/秒，按用量计费，每天有 $1 免费额度；按 ID/DOI 查单个实体不计费

### 通用与预印本

#### arXiv
- **访问**：用 paper-lookup 技能，或 `curl.exe` 直接调 API；返回的是 Atom XML，没有 JSON 选项
- **覆盖范围**：预印本，涵盖物理、数学、计算机、定量金融、统计、电气工程和经济学
- **最适合**：最新未发表研究、计量与理论方法、模型类工作
- **经济学分类**：`econ.EM`（计量经济学）、`econ.GN`（一般经济学）、`econ.TH`（理论）
- **检索式写法**：`cat:econ.GN AND ti:"central bank" AND abs:"digital currency"`。字段前缀有 `ti:` `au:` `abs:` `co:` `cat:`，布尔运算符是 `AND` / `OR` / `ANDNOT`
- **限流**：每 3 秒 1 次请求，硬性限制；同一时间只允许一个连接

#### Crossref
- **访问**：用 paper-lookup 技能，或 `curl.exe` 直接调 API
- **覆盖范围**：DOI 注册数据，1.5 亿多件作品的权威元数据
- **最适合**：按 DOI 补全或核对元数据、期刊层面的检索
- **礼貌池**：URL 里带上 `mailto=you@example.com`，限流速率从 5 req/sec 翻倍到 10 req/sec，并发从 1 提到 3——几乎零成本的提速，值得每次都加
- **检索要点**：`/works?query=` 跨字段全文检索，`filter=` 收窄；标题、作者、ISSN、年份可以用 `query.bibliographic` 精确打

#### Google Scholar
- **访问**：网页抓取（慎用）或手动检索
- **覆盖范围**：全领域，覆盖全面
- **最适合**：找高被引论文、会议论文集、学位论文、工作论文
- **局限**：没有官方 API，有速率限制
- **导出**：用 "Cite" 功能导出格式化引用

### 经济学专业数据源

这几个不在 paper-lookup 的 18 个 API 之内，需要手动检索或用 WebFetch 取页面。

#### RePEc / IDEAS
- **覆盖范围**：经济学工作论文与期刊论文的聚合索引
- **最适合**：找领域内的工作论文，追踪某位作者的全部产出

#### NBER Working Papers
- **覆盖范围**：美国国家经济研究局工作论文
- **最适合**：宏观、金融、劳动经济学的前沿工作，通常早于期刊发表

#### SSRN
- **覆盖范围**：社会科学预印本，金融与法律方向尤其密集
- **最适合**：金融科技、公司金融的早期版本，核对正式发表前的差异

#### FRED（美联储经济数据）
- **覆盖范围**：宏观经济时间序列
- **最适合**：给实证工作配宏观控制变量

#### World Bank / IMF 数据
- **覆盖范围**：跨国宏观与发展指标
- **最适合**：跨国面板、金融发展指标

#### Zenodo / Figshare
- **覆盖范围**：论文的复现数据与代码
- **最适合**：核查复现包、复用他人数据

### 引用与文献管理

#### OpenCitations
- **访问**：用 paper-lookup 技能
- **覆盖范围**：开放引用数据
- **最适合**：跨库的引用追溯、开放引文计量

#### Dimensions
- **访问**：有免费档
- **覆盖范围**：论文、基金、专利、临床试验
- **最适合**：研究影响力、基金分析

---

## 检索策略框架

### 1. 定义研究问题（PICO 框架）

经济学综述里，PICO 这四个维度这样落地：

- **P**opulation（研究对象）：家庭、企业、银行还是市场？
- **I**ntervention（干预/冲击）：在检验哪一项政策、监管或技术变化？
- **C**omparison（对照）：和什么比较？未受约束的群体，还是政策前后的同一群体？
- **O**utcome（结果）：融资可得性、价格、进入退出、福利？

**示例**：「与不受该法规约束的支付机构（C）相比，监管沙盒（I）如何影响数字支付初创企业（P）的融资可得性与市场进入（O）？」

### 2. 构建检索词

#### 核心概念
从研究问题里找出 2-4 个主要概念。

**示例**：
- 概念 1：fintech、digital payment、mobile money
- 概念 2：regulatory sandbox、fintech regulation、financial supervision
- 概念 3：access to credit、financing constraints、firm entry

#### 同义词与相关词
列出替代词、缩写和相关概念。

**工具**：在 OpenAlex 用 `/works?search=` 或 topic 页看规范主题词，在 Semantic Scholar 用 `fieldsOfStudy=Economics` 限定范围，在 arXiv 直接浏览 `econ.*` 分类

#### 布尔运算符
- **AND**：缩小检索范围（两个词都必须出现）
- **OR**：扩大检索范围（任一词出现即可）
- **NOT**：排除词

**示例**：`(fintech OR "digital payment" OR "mobile money") AND ("regulatory sandbox" OR "fintech regulation") AND ("access to credit" OR "financing constraints")`

各库写法不同：OpenAlex 用大写 `AND` / `OR` / `NOT`，arXiv 用 `AND` / `OR` / `ANDNOT`，Semantic Scholar 的批量端点用 `+` / `|` / `-`。照抄某个库的布尔写法之前，先确认它认哪种。

#### 通配符与截词
- **OpenAlex**：`*` 通配（`regulat*` 匹配 regulate、regulation、regulatory），`~N` 模糊（`regulaton~1`），`"..."~N` 邻近（`"central bank"~5`）
- **Semantic Scholar 批量端点**：`*` 通配
- **arXiv**：不支持截词，只能写全词或短语

### 3. 设定纳入/排除标准

#### 纳入标准
- **时间范围**：如 2015-2026（近 10 年）
- **语言**：英语（或指定多语言）
- **出版类型**：同行评审论文、综述、工作论文、预印本
- **研究设计**：RCT、双重差分、工具变量、断点回归、结构模型、元分析
- **研究对象**：家庭、企业、银行、市场

#### 排除标准
- 样本量过小的案例研究
- 无全文的会议摘要
- 非原创研究（社论、评论、书评）
- 重复发表（工作论文与正式发表版本重复时保留后者）
- 已撤稿论文

### 4. 数据库选择策略

#### 多库并用
至少检索 3 个互补的数据库：

1. **主库**：Semantic Scholar 或 OpenAlex（跨学科，引用数据全）
2. **预印本**：arXiv 的 `econ.*` 分类，配合 NBER / SSRN
3. **补全**：Crossref（DOI 元数据）、Google Scholar（覆盖广）
4. **专业数据**：FRED、World Bank / IMF 等

#### 各库检索语法

| 数据库 | 检索参数 | 示例 |
|----------|-----------|---------|
| Semantic Scholar | `query=` 加 `year` / `fieldsOfStudy` / `minCitationCount` | `query=fintech+regulation&year=2020-2024&fieldsOfStudy=Economics` |
| Semantic Scholar（bulk） | `+` `\|` `-` `*` `()` `"..."` | `query=(digital+currency)+AND+(regulation)` |
| OpenAlex | `search=` 加 `filter=`（`field:value`） | `search=digital+currency&filter=from_publication_date:2020-01-01,type:article` |
| arXiv | `search_query=` 前缀 `ti:` `au:` `abs:` `cat:` | `search_query=cat:econ.GN+AND+ti:%22central+bank%22` |
| Crossref | `query=` / `query.bibliographic=` 加 `filter=` | `query=corporate+financing+constraints&filter=from-pub-date:2020-01-01,type:journal-article` |

---

## 检索执行工作流

### 阶段 1：预检索
1. 用宽泛的词跑一次初步检索
2. 看前 50 条结果是否相关
3. 记下常见关键词，以及 OpenAlex 的主题词、Semantic Scholar 的 `s2FieldsOfStudy`
4. 修正检索策略

### 阶段 2：全面检索
1. 在选定的所有数据库中执行修正后的检索式
2. 按标准格式导出结果（RIS、BibTeX、JSON）
3. 记录每个库的检索式和检索日期
4. 记录每个库的结果数

### 阶段 3：去重
1. 把所有结果导入同一个文件
2. 用 `search_databases.py --deduplicate` 去重
3. 按 DOI（首选）或标题（次选）识别重复
4. 保留元数据最完整的那条

### 阶段 4：筛选
1. **标题筛选**：看标题，排除明显不相关的
2. **摘要筛选**：读摘要，套用纳入/排除标准
3. **全文筛选**：取全文并审读
4. 记录每个阶段排除的原因

### 阶段 5：质量评价
1. 用合适的工具评估研究质量：
   - **随机实验（RCT）**：Cochrane RoB 2，并到 AEA RCT Registry 核对预注册
   - **观察性/准实验（双重差分、工具变量、断点回归）**：ROBINS-I 或 Newcastle-Ottawa Scale
   - **系统综述/元分析**：AMSTAR 2
   - **复现包**：核查数据与代码是否可公开获取
2. 给证据质量分级（高、中、低、极低）
3. 考虑排除质量极低的研究

---

## 检索记录模板

### 必须记录的内容
所有检索都要记录在案，以保证可复现：

```markdown
## 检索策略

### 数据库：Semantic Scholar
- **检索日期**：2026-09-16
- **时间范围**：2019-01-01 至 2026-09-16
- **检索式（批量端点）**：
  ```
  (fintech | "digital payment") + ("regulatory sandbox" | "fintech regulation")
  ```
  参数：`fields=title,year,abstract,citationCount,openAccessPdf&year=2019-2026`
- **结果**：312 篇论文
- **去重后**：240 篇论文

### 数据库：arXiv
- **检索日期**：2026-09-16
- **时间范围**：2019-01-01 至 2026-09-16
- **检索式**：
  ```
  cat:econ.GN AND abs:"digital currency" AND submittedDate:%5B201901010000+TO+202609160000%5D
  ```
- **结果**：58 篇预印本
- **去重后**：41 篇预印本

### 去重后的论文总数
- **合并结果**：281 篇不重复论文
- **标题筛选后**：198 篇论文
- **摘要筛选后**：112 篇论文
- **全文筛选后**：63 篇论文纳入综述
```

---

## 高级检索技巧

### 优先挑选高影响力论文（关键）

**始终按被引次数、发表期刊层次和作者声誉给论文排优先级。** 质量比数量重要。

#### 检索中的引用指标

用被引次数识别有影响力的工作：

| 论文年限 | 被引次数 | 分级 |
|-----------|----------------|----------------|
| 0-3 年 | 20+ | 值得关注 |
| 0-3 年 | 100+ | 高影响力 |
| 3-7 年 | 100+ | 重要 |
| 3-7 年 | 500+ | 里程碑 |
| 7 年以上 | 500+ | 奠基性 |
| 7 年以上 | 1000+ | 基础性 |

**各库的引用功能：**
- **Semantic Scholar：** `influentialCitationCount` 字段（衡量在原文基础上做出重要推进的引用）、`tldr` 一句话摘要
- **OpenAlex：** `cited_by_count` 字段，可用 `sort=cited_by_count:desc` 排序
- **Crossref：** `is-referenced-by-count` 字段
- **OpenCitations：** 开放引用图，可做跨库引用追溯

#### 按期刊质量过滤

优先选高层次期刊的论文：

**第一梯队（优先选）：**
- 综合经济学五大刊：American Economic Review、Econometrica、Journal of Political Economy、Quarterly Journal of Economics、Review of Economic Studies
- 金融三大刊：Journal of Finance、Review of Financial Studies、Journal of Financial Economics
- 交叉领域：Management Science、Journal of Monetary Economics
- 检索技巧：先用 OpenAlex 的 `/sources?search=` 查到期刊的来源 ID，再回到 works 里过滤

**第二梯队（高优先级）：**
- 高影响力领域期刊（金融科技、公司金融、货币经济方向）
- 顶级会议：AEA/ASSA 年会、NBER Summer Institute、WFA、AFA

**第三梯队（相关时纳入）：**
- 领域内有口碑的工作论文系列与期刊

**OpenAlex 期刊过滤：**
```
# 先按名称查到来源 ID
GET https://api.openalex.org/sources?search=American+Economic+Review
# 再用来源 ID 过滤 works
GET https://api.openalex.org/works?filter=primary_location.source.id:S123456789
```

**Crossref 期刊过滤：**
```
filter=issn:0002-8282,type:journal-article
```

#### 用好 "Cited by" 功能

**找有影响力的工作：**
1. 从一篇已知的关键论文入手
2. 用 Semantic Scholar 的 `/paper/{paper_id}/citations` 端点找出引用它的论文
3. 按 `citationCount` 给这些引用论文排序
4. 被引次数高的引用论文，往往指向重要的后续工作

**识别奠基性论文：**
1. 宽泛地检索你的主题
2. 记下哪些论文在参考文献里反复出现
3. 被你多个结果引用的论文，很可能是奠基性工作
4. 查 `cited_by_count` 确认其影响力

**Semantic Scholar 功能：**
- `influentialCitationCount` 展示在论文基础上做出重要推进的引用
- `tldr` 给出论文的一句话摘要
- 基于引用网络的论文推荐

### 引文追溯

#### 前向引文检索
找出引用了某篇关键论文的论文：
- 用 Semantic Scholar 的 `/paper/{paper_id}/citations` 端点（`limit` 最大 1000）
- 用 OpenAlex 按引用关系过滤 works
- 用 OpenCitations 做跨库的引用追溯
- **技巧：** 按被引次数排序，找出影响力最大的后续工作

#### 后向引文检索
审读关键论文的参考文献：
- 从纳入的论文里提取参考文献，Semantic Scholar 的 `/paper/{paper_id}/references` 或 OpenAlex 的 `referenced_works` 都能直接拿
- 检索高被引的参考文献（老论文看 500+ 次引用）
- 能发现奠基性研究
- **技巧：** 关注在多篇论文的参考文献里都出现过的条目

### 滚雪球抽样
1. 从 3-5 篇**来自第一梯队期刊**的高相关论文入手
2. 提取它们全部的参考文献
3. 看哪些参考文献被多篇论文引用
4. 审读这些重叠度高的参考文献——它们多半是奠基性工作
5. 对新发现的关键论文重复上述过程
6. 每一步都**优先挑选被引次数高的论文**

### 作者检索
跟踪领域内高产且有声望的作者：
- 用 Semantic Scholar 的 `/author/search?query={name}` 检索作者，再用 `/author/{author_id}/papers` 拉产出；作者对象自带 `hIndex`、`paperCount`
- 查作者主页（ORCID、Google Scholar）看 h-index 和发表期刊
- 看近期发表的论文和工作论文（NBER、SSRN）
- **优先选有多篇第一梯队论文**且 h-index 高（>40）的作者
- 留意公认的领域领军资深作者

### 相关论文功能
很多数据库会推荐相关论文：
- Semantic Scholar 的 `/recommendations/v1/papers/forpaper/{paper_id}` 推荐接口（`from=recent` 或 `all-cs`，`limit` 最大 500）
- OpenAlex 按 topic 与引用邻域找相近工作
- 用来发现关键词检索漏掉的论文
- **按被引次数和期刊层次过滤推荐结果**

---

## 质量控制清单

### 检索前
- [ ] 研究问题已明确
- [ ] 已确定 PICO 标准（如适用）
- [ ] 已列出检索词和同义词
- [ ] 已记录纳入/排除标准
- [ ] 已选定目标数据库（至少 3 个）
- [ ] 已确定时间范围

### 检索中
- [ ] 检索式已测试并修正
- [ ] 结果已导出，含完整元数据
- [ ] 检索参数已记录
- [ ] 已记录每个库的结果数
- [ ] 已记录检索日期

### 检索后
- [ ] 已去重
- [ ] 已按筛选流程执行
- [ ] 已记录排除原因
- [ ] 已完成质量评价
- [ ] 已用 `citation-management` 技能核验所有引用
- [ ] 综述里已写明检索方法

---

## 常见陷阱

1. **检索过窄**：漏掉相关论文
   - 对策：加入同义词、相关词和更宽泛的概念

2. **检索过宽**：得到成千上万条不相关结果
   - 对策：用 AND 加入具体概念，用字段筛选（OpenAlex 的 `filter=`、Semantic Scholar 的 `year` / `minCitationCount`）

3. **只用单个数据库**：覆盖不全
   - 对策：至少检索 3 个互补的数据库

4. **忽略预印本**：漏掉最新发现
   - 对策：纳入 arXiv 的 `econ.*` 分类，以及 NBER、SSRN 工作论文

5. **不做记录**：检索无法复现
   - 对策：记录每一条检索式、日期和结果数

6. **手工去重**：费时且易错
   - 对策：用 search_databases.py 脚本

7. **引用未核验**：DOI 失效、元数据有误
   - 对策：调用 `citation-management` 技能跑一遍（不要用本技能的 `verify_citations.py`）

8. **发表偏倚**：只纳入已发表的阳性结果
   - 对策：检索 AEA RCT Registry 和工作论文库（NBER、SSRN），把未发表结果也纳入

---

## 多库检索工作流示例

```python
# 用 paper-lookup 技能完成的工作流示例

# 1. Semantic Scholar 相关性检索
# GET https://api.semanticscholar.org/graph/v1/paper/search?query=fintech+regulation&fields=title,year,abstract,citationCount,openAccessPdf&year=2019-2024

# 2. OpenAlex 检索 + 筛选
# GET https://api.openalex.org/works?search=digital+currency&filter=from_publication_date:2019-01-01,type:article&sort=cited_by_count:desc

# 3. 在 arXiv 上检索 econ 预印本
# GET https://export.arxiv.org/api/query?search_query=cat:econ.GN+AND+abs:%22central+bank%22&max_results=50

# 4. 用 Crossref 补全 DOI 元数据
# GET https://api.crossref.org/works?query=corporate+financing+constraints&rows=20&mailto=you@example.com

# 5. 汇总并去重
# python .claude/skills/literature-review/scripts/search_databases.py sources/combined_results.json --deduplicate --format markdown --output literature_notes/candidate_papers.md

# 6. 核验所有引用：调用 citation-management 技能（不要用本技能的 verify_citations.py）

# 7. 生成最终 PDF
# python .claude/skills/literature-review/scripts/generate_pdf.py drafts/review_final.md --citation-style apa
```

---

## 资源

### OpenAlex 主题浏览
https://openalex.org/topics

### Semantic Scholar API 文档
https://api.semanticscholar.org/api-docs/

### 引用格式指南
见本技能的 references/citation_styles.md

### PRISMA 指南
系统综述与元分析首选报告条目（Preferred Reporting Items for Systematic Reviews and Meta-Analyses）：
http://www.prisma-statement.org/
