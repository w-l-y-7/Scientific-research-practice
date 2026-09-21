# PubMed (NCBI E-utilities)

PubMed 提供 3700 万篇以上生物医学与生命科学论文的引文、摘要和元数据。它**不含全文**——要全文请用 PMC。

## 基础 URL

```
https://eutils.ncbi.nlm.nih.gov/entrez/eutils/
```

## 认证

- **API key 可选**，但建议带上。不带：每秒 3 次请求。带上：每秒 10 次请求。
- 传法：`&api_key=YOUR_KEY`
- 所有请求还要带上 `&tool=your_app_name&email=your@email.com`。

## 主要端点

### 1. eSearch——检索并获取 PMID

```
GET /esearch.fcgi?db=pubmed&term={query}&retmode=json
```

| 参数 | 必填 | 默认值 | 说明 |
|-----------|----------|---------|-------------|
| `db` | 是 | -- | `pubmed` |
| `term` | 是 | -- | 检索式。支持 PubMed 语法：字段标签 `[AU]`、`[TI]`、`[TA]`、`[MH]`（MeSH），布尔 AND/OR/NOT |
| `retmax` | 否 | 20 | 返回的 PMID 上限（最多 10,000） |
| `retstart` | 否 | 0 | 分页偏移量 |
| `retmode` | 否 | `xml` | `json` 或 `xml` |
| `rettype` | 否 | `uilist` | `uilist`（ID）或 `count`（只返回计数） |
| `sort` | 否 | `relevance` | `relevance`、`pub_date`、`Author`、`JournalName` |
| `datetype` | 否 | -- | `pdat`（出版）、`mdat`（修改）、`edat`（entrez） |
| `mindate` / `maxdate` | 否 | -- | 日期范围 `YYYY/MM/DD` |
| `reldate` | 否 | -- | 最近 N 天内的条目 |
| `usehistory` | 否 | -- | 填 `y` 可把大结果集存到 History Server |

**示例：**
```
https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&term=CRISPR+gene+therapy&retmode=json&retmax=5&sort=pub_date
```

**响应：**
```json
{
  "esearchresult": {
    "count": "224107",
    "retmax": "5",
    "retstart": "0",
    "idlist": ["39984857", "39984678", "39984543", "39984210", "39983901"]
  }
}
```

### 2. eSummary——获取文档摘要

```
GET /esummary.fcgi?db=pubmed&id={pmids}&retmode=json
```

| 参数 | 必填 | 说明 |
|-----------|----------|-------------|
| `db` | 是 | `pubmed` |
| `id` | 是 | 逗号分隔的 PMID（最多 10,000 个） |
| `retmode` | 否 | `json` 或 `xml` |

**示例：**
```
https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=39984857,39984678&retmode=json
```

**响应字段：** `uid`、`pubdate`、`source`（期刊）、`authors`、`title`、`volume`、`issue`、`pages`、`fulljournalname`、`elocationid`（DOI）、`articleids`（PMC、DOI 等）、`pubtype`、`pmcrefcount`

### 3. eFetch——取回完整记录（摘要、MEDLINE）

```
GET /efetch.fcgi?db=pubmed&id={pmids}&rettype={type}&retmode={mode}
```

| rettype | retmode | 返回 |
|---------|---------|---------|
| *（省略）* | `xml` | 完整的 PubMed XML（引文 + 摘要） |
| `medline` | `text` | MEDLINE 格式 |
| `abstract` | `text` | 纯文本摘要 |
| `uilist` | `text` | PMID 列表 |

**示例——以 XML 获取摘要：**
```
https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed&id=39984857&retmode=xml
```

该 XML 包含 `<PubmedArticle>`，其中有 `<MedlineCitation>`（标题、摘要、MeSH 词、作者）和 `<PubmedData>`（论文 ID、出版历史）。

### 4. eLink——查找相关论文

```
GET /elink.fcgi?dbfrom=pubmed&db=pubmed&id={pmid}&cmd=neighbor_score&retmode=json
```

返回相关 PMID 及其相关性得分。

## 检索语法提示

- **字段标签：** `aspirin[TI]`（标题）、`Smith J[AU]`（作者）、`Nature[TA]`（期刊）、`neoplasms[MH]`（MeSH 主题词）
- **布尔：** `CRISPR AND (therapy OR treatment)`
- **日期范围：** `2020/01/01:2024/12/31[PDAT]`
- **出版类型：** `review[PT]`、`clinical trial[PT]`
- **物种：** `humans[MH]`、`mice[MH]`

## 限流

- 无 API key 时 **每秒 3 次请求**
- 有 API key 时 **每秒 10 次请求**
- 每个请求都要带 `tool` 和 `email` 参数
- 大批量任务应避开高峰时段（周一至周五 5AM–9PM ET）

## 错误格式

```json
{"error": "API rate limit exceeded", "count": "11"}
```

请求有问题返回 HTTP 400，触发限流返回 429。
