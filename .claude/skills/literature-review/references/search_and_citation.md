# 数据库检索指南与引用格式

逐个数据库的检索指南（覆盖范围、语法、导出路径），后接引用格式指南。所有检索统一走 `paper-lookup` 技能——它把 18 个学术 API 的端点、参数和各自的静默失败方式都整理好了。另见 `database_strategies.md` 和 `citation_styles.md`。

## 各数据库检索指南

### Semantic Scholar

覆盖 2 亿+ 论文，全学科，带引用图谱、AI 生成的 TLDR 和论文推荐。经济学文献用 `fieldsOfStudy=Economics` 过滤。

**认证**：免费 key 走 `x-api-key` 请求头，速率 1 req/s；不带 key 走共享池，量一上来就 429。申请地址：https://www.semanticscholar.org/product/api#api-key-form

```powershell
# 相关性检索：金融科技监管，2020-2024 年的经济学文献
curl.exe -s --get "https://api.semanticscholar.org/graph/v1/paper/search" `
  --data-urlencode "query=fintech regulation" `
  --data-urlencode "fields=title,year,authors,venue,citationCount,externalIds,openAccessPdf" `
  --data-urlencode "year=2020-2024" `
  --data-urlencode "fieldsOfStudy=Economics" `
  --data-urlencode "limit=50"
```

**批量检索**（布尔查询，适合大结果集）：

```
GET /graph/v1/paper/search/bulk?query={text}&fields={fields}&sort={field}:{order}&token={token}
```

布尔运算符：`+`（AND）、`|`（OR）、`-`（NOT）、`"..."`（短语）、`*`（通配）、`()`（分组）。可排序字段如 `citationCount:desc`、`publicationDate:desc`。分页用 token，单次最多 1000 条，总量可到 1000 万篇。

```powershell
# 数字货币，分别与监管、支付相关，按被引降序
curl.exe -s --get "https://api.semanticscholar.org/graph/v1/paper/search/bulk" `
  --data-urlencode 'query="central bank digital currency"|"digital currency"+(regulation|payment)' `
  --data-urlencode "fields=title,year,citationCount,externalIds" `
  --data-urlencode "sort=citationCount:desc"
```

**按 ID 取详情**（ID 支持 `DOI:`、`ARXIV:`、`PMID:`、`PMCID:`、`CorpusId:` 等前缀）：

```powershell
curl.exe -s -H "x-api-key: $env:S2_API_KEY" `
  "https://api.semanticscholar.org/graph/v1/paper/DOI:10.1257/aer.91.5.1369?fields=title,year,abstract,citationCount,referenceCount,isOpenAccess,openAccessPdf,authors,tldr"
```

**限流与陷阱**：
- 不带 key 时经常直接返回 429：`{"message": "Too Many Requests...", "code": "429"}`。重试一次通常没用，配 key 才稳。
- `fields` 逗号分隔、中间不能有空格；不写它只拿到 `paperId` 和 `title`。
- 相关性检索每页上限 100，offset 最多翻到 1000 条。要更大的结果集换成 `/search/bulk`。
- `fieldsOfStudy` 的学科名是固定枚举，经济学写 `Economics`；本领域相关的还有 `Business`、`Political Science`、`Law`。
- 经济学论文常挂在预印本或工作论文下，`externalIds` 里的 `ArXiv`、`DOI` 字段是跨库去重的关键。

### OpenAlex

2.5 亿+ 著作、作者、机构、来源、主题，是覆盖面最广的跨学科索引。限流最高 100 req/s，按量计费、每天有 $1 免费额度；按 ID/DOI 查单条不花钱。

**认证**：建议申请免费 key（https://openalex.org/settings/api），用 `?api_key=...` 传；旧的礼貌池仍可用，加 `?mailto=you@example.com` 能拿到更好的额度。

```powershell
# 检索：金融科技监管，2020 年后、被引 >20，按被引降序
curl.exe -s "https://api.openalex.org/works?search=fintech%20regulation&filter=from_publication_date:2020-01-01,type:article,cited_by_count:%3E20&sort=cited_by_count:desc&per_page=50&select=id,doi,title,publication_year,cited_by_count,open_access"
```

**检索与过滤**：
- `search` 覆盖标题、摘要和全文，布尔运算符 `AND`/`OR`/`NOT` 必须大写；`search.exact` 关闭词干提取，`search.semantic` 走 AI 嵌入检索（beta，1 req/s，最多 50 条）。
- `filter` 是逗号分隔的 `字段:值`。常用字段：`from_publication_date`、`to_publication_date`、`publication_year`、`type`、`cited_by_count`（支持 `>100`）、`is_oa`、`has_abstract`、`authorships.author.id`、`primary_location.source.id`、`institutions.country_code`、`doi`。运算符有 `>`、`<`、`!`（取反）、`|`（同一字段内的 OR）。
- 单条查询支持 `W2741809807`、`doi:10.7717/peerj.4375`、`pmid:29456894` 和完整 DOI URL 几种写法。

**分页**：`per_page` 最大 100，`page * per_page` 不能超过 10000；再深要走游标——首次请求 `cursor=*`，之后把响应里的 `meta.next_cursor` 传回去，为 `null` 即到底。

**摘要要还原**：OpenAlex 把摘要存成 `abstract_inverted_index`（形如 `{"Despite": [0], "growing": [1], ...}`），要按位置重排才能得到文本。用 `scripts/openalex_abstract.py`，别自己手搓。错误码方面，key 无效返回 403，超过限流返回 429。

### arXiv

预印本服务器，覆盖物理、数学、计算机、定量生物、定量金融、统计和经济学。返回的是 **Atom XML，没有 JSON 选项**。经济学的三个主分类：`econ.EM`（计量经济）、`econ.GN`（一般经济）、`econ.TH`（理论）。

```powershell
# econ.GN 分类下，摘要含 "financial stability"，按提交日期倒序
curl.exe -s "https://export.arxiv.org/api/query?search_query=cat:econ.GN+AND+abs:%22financial+stability%22&max_results=20&sortBy=submittedDate&sortOrder=descending" | python .claude/skills/paper-lookup/scripts/arxiv_atom.py -
```

**语法**：
- 字段前缀：`ti:`（标题）、`au:`（作者）、`abs:`（摘要）、`co:`（评论）、`jr:`（期刊引用）、`cat:`（分类）、`rn:`（报告号）、`all:`（全字段）。
- 布尔运算：`AND`、`OR`、`ANDNOT`，括号分组，引号短语。

**限流与陷阱**：
- 限流是 **1 请求 / 3 秒**，同一时间只允许一个连接。超限返回纯文本 `Rate exceeded.`（HTTP 429），不是 XML——接了解析器的流水线会把它报成「响应损坏」。
- 日期范围必须写成 `submittedDate:[YYYYMMDDHHMM+TO+YYYYMMDDHHMM]`，方括号要做百分号编码成 `%5B`/`%5D`。把字面量 `[` 交给 `curl.exe` 会在请求发出前退出（退出码 3），抓不到任何东西，也没有状态码可查。
- 字段前缀写错不会报错：未知前缀会被静默改写成 `all:`，一次精准检索降级成全文检索。相信结果前，拿 feed 的 `<title>` 和实际发出的查询对一遍。
- 参数格式错误会伪装成一条结果：`start=notanumber` 返回 HTTP 200、`totalResults` 为 1，以及一条标题为 `Error` 的记录。把 entry 当论文之前，先查有没有 `<title>Error</title>`。
- 真正查不到时 `totalResults` 为 0、没有 entry、也没有报错。这种情况报成「arXiv 中未找到」，不要报成请求失败。
- 同一查询每天的搜索结果会缓存，24 小时内不会看到新条目。

### Crossref

DOI 注册机构，1.5 亿+ 条元数据，覆盖期刊论文、图书、会议论文、数据集和预印本。它的强项是**按已知 DOI 取权威元数据**，不适合做主题发现——`query` 是跨字段的词袋检索，主题词很容易匹配到无关记录。

**认证**：无需 key，加 `mailto=you@example.com` 进礼貌池，速率从 5 req/s 翻到 10 req/s。

```powershell
# 按 DOI 取元数据，DOI 里的 / 要编码成 %2F
curl.exe -s "https://api.crossref.org/works/10.1257%2Faer.91.5.1369?mailto=you@example.com"

# 按标题/作者/年份做已知项检索
curl.exe -s "https://api.crossref.org/works?query.bibliographic=colonial+origins+comparative+development&rows=5&mailto=you@example.com"
```

**过滤与分页**：
- `filter=name:value,...`。日期过滤用 `from-pub-date`/`until-pub-date`（接受 `YYYY`、`YYYY-MM`、`YYYY-MM-DD`）；`type` 取值如 `journal-article`、`posted-content`、`book-chapter`；布尔过滤有 `has-abstract`、`has-references`、`has-full-text`。
- `rows` 上限 1000，`offset` 上限 10000；更深用游标——首次请求 `cursor=*`，把响应里的 `next-cursor` 传回去，游标 5 分钟后失效。
- 检索字段：`query`（全字段）、`query.bibliographic`（标题+作者+ISSN+年份）、`query.author`、`query.container-title`。排序用 `sort` + `order`，如 `sort=is-referenced-by-count&order=desc`。
- 响应里 `title` 和 `container-title` 是数组，`published.date-parts` 是 `[[年, 月, 日]]`，摘要可能带 HTML 标签。收到 429 表示被临时封禁。

### 开放获取与全文

拿全文这一步由 `paper-lookup` 里的三个库分担：

- **Unpaywall** —— 给一个 DOI，判断有没有合法的免费副本。端点是 `GET /v2/{doi}?email=...`，邮箱必须是真实的，`test@example.com` 这类占位符会被 422 拒掉。看 `is_oa`，为 `true` 时取 `best_oa_location.url_for_pdf`；`oa_status` 的取值是 `gold`/`hybrid`/`bronze`/`green`/`closed`。它的 search 端点不可靠（长期返回 500），别用来检索，只做 DOI 查询。

```powershell
curl.exe -s "https://api.unpaywall.org/v2/10.1371/journal.pone.0311722?email=you@example.com"
```

- **Europe PMC** —— PubMed + PMC + 预印本合成一个索引，是唯一能跨这些语料做关键词检索、并且能在**全文内部**检索的接口。全文用 `GET /{PMCID}/fullTextXML`，论文不是开放获取时返回干净的 404（比 NCBI eFetch 那种「HTTP 200 但没有 `<body>`」好排查）。检索字段：`SRC`（`MED`/`PMC`/`PPR`）、`PUBLISHER`、`AUTH`、`TITLE`、`ABSTRACT`、`PUB_YEAR`、`HAS_FT`、`OPEN_ACCESS`、`IN_EPMC`、`DOI`、`JOURNAL`、`MESH`、`LANG`。它不需要任何认证，连邮箱都不用。

```powershell
# 开放获取 + 全文内关键词检索，取核心元数据
curl.exe -s --get "https://www.ebi.ac.uk/europepmc/webservices/rest/search" `
  --data-urlencode "query=(OPEN_ACCESS:Y AND fintech AND regulation)" `
  --data-urlencode "format=json" `
  --data-urlencode "pageSize=25" `
  --data-urlencode "resultType=core"

# 全文（JATS XML），管道给解析脚本
curl.exe -s "https://www.ebi.ac.uk/europepmc/webservices/rest/PMC7029759/fullTextXML" | python .claude/skills/paper-lookup/scripts/jats_to_text.py -
```

- **CORE** —— 全球 15000+ 仓储的开放获取全文，3700 万+ 篇。拿全文要配 `CORE_API_KEY`（请求头 `Authorization: Bearer ...`），不带认证只能拿基础元数据。GET 路径**必须带末尾斜杠**：`/v3/search/works/?q=...`。

**`paper-lookup` 还支持的其他库**（按需查阅，不做主工作流）：PubMed、PMC、bioRxiv、medRxiv、OpenCitations、PubTator3、Zenodo、Figshare、BioStudies、ROR、DOAJ。其中 PubMed、PMC、bioRxiv、medRxiv 偏生物医学，做经济学综述时一般用不上——除非主题正好落在卫生经济学这类交叉领域。

### 引文追溯

用引文网络把检索铺开，主库是 Semantic Scholar，OpenAlex 和 Europe PMC 可作补充。

1. **正向引文**（谁引用了这篇论文）：

```powershell
# 某篇论文的引用列表
curl.exe -s "https://api.semanticscholar.org/graph/v1/paper/DOI:10.1257/aer.91.5.1369/citations?fields=title,year,authors,citationCount,externalIds&limit=100"
```

   - 引用特有的字段：`contexts`（引用处的原文片段）、`intents`、`isInfluential`。想找基于开创性工作的较新研究时，`isInfluential` 能滤掉只是顺带一提的引用。
   - OpenAlex 的对应字段是 `referenced_works`（返回 OpenAlex ID 列表）。
   - Europe PMC 用 `/{source}/{id}/citations`。

2. **反向引文**（这篇论文引用了谁）：

```powershell
# 某篇论文的参考文献列表
curl.exe -s "https://api.semanticscholar.org/graph/v1/paper/DOI:10.1257/aer.91.5.1369/references?fields=title,year,authors,externalIds&limit=100"
```

   - 从纳入论文的参考文献里找被高引的奠基性工作，以及被多篇纳入研究共同引用的论文。
   - Europe PMC 用 `/{source}/{id}/references`。

## 引用格式指南

详细的排版规范见 `references/citation_styles.md`。速查：

### APA（第 7 版）
- 正文引用：(Acemoglu et al., 2001)
- 参考文献：Acemoglu, D., Johnson, S., & Robinson, J. A. (2001). The colonial origins of comparative development: An empirical investigation. *American Economic Review*, *91*(5), 1369-1401. https://doi.org/10.1257/aer.91.5.1369

### Nature
- 正文引用：上标数字^1,2^
- 参考文献：Acemoglu, D., Johnson, S. & Robinson, J. A. The colonial origins of comparative development. *Am. Econ. Rev.* **91**, 1369-1401 (2001).

### Vancouver
- 正文引用：上标数字^1,2^
- 参考文献：Acemoglu D, Johnson S, Robinson JA. The colonial origins of comparative development: an empirical investigation. Am Econ Rev. 2001;91(5):1369-401.

定稿前**务必核验引用**。用本项目的 `citation-management` 技能（DOI → 抓 BibTeX → 去重排序 → 校验），它会产出 `references.bib` 和一份校验报告；本技能自带的 `verify_citations.py` 只做单点 DOI 查询，功能重合，优先用前者。

### 优先选用高影响力论文（关键）

**始终优先选用知名作者、顶级期刊/会议的高影响力、高被引论文。**综述中质量比数量重要。

#### 引用数阈值

用引用数找出最具影响力的论文：

| 论文年龄 | 引用数阈值 | 分类 |
|-----------|-------------------|----------------|
| 0-3 年 | 20+ 次引用 | 值得关注 |
| 0-3 年 | 100+ 次引用 | 高影响力 |
| 3-7 年 | 100+ 次引用 | 重要 |
| 3-7 年 | 500+ 次引用 | 里程碑论文 |
| 7+ 年 | 500+ 次引用 | 开创性工作 |
| 7+ 年 | 1000+ 次引用 | 奠基性 |

#### 期刊与会议分级

优先选用更高层级来源的论文：

- **第 1 级（优先选用）：** American Economic Review、Econometrica、Journal of Political Economy、Quarterly Journal of Economics、Review of Economic Studies；金融方向的 Journal of Finance、Review of Financial Studies、Journal of Financial Economics
- **第 2 级（强烈倾向）：** 高影响力领域期刊（Journal of Monetary Economics、Journal of Financial Intermediation、Management Science、Journal of Public Economics 等）、机器学习/人工智能方向的顶级会议（NeurIPS、ICML）
- **第 3 级（相关时纳入）：** 受认可的领域期刊与会议
- **第 4 级（慎用）：** 影响力较低的同行评审来源
- **工作论文：** NBER、CEPR、SSRN 的工作论文更新快、被引也高，可以纳入，但要标注其未经同行评审

#### 作者声誉评估

优先选用来自以下作者的论文：
- **资深研究者**，h-index 高（成熟领域 >40）
- **知名机构的领先研究组**（Harvard、Chicago、Stanford、MIT、Oxford、LSE 等）
- **在相关领域有多篇第 1 级论文的作者**
- **公认的专业研究者**（获过奖、担任编委、学会会士）

#### 识别开创性论文

对任何主题，通过以下方式找出奠基性工作：
1. **引用数高**（5 年以上论文通常 500+）
2. **被其他纳入研究频繁引用**（出现在大量参考文献列表中）
3. **发表于第 1 级来源**（AER、Econometrica、JPE、QJE 系列）
4. **由领域先驱撰写**（常被引作某个概念的创立者）
