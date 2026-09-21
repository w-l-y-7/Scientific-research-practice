# Semantic Scholar API

Semantic Scholar 索引了 2 亿以上的论文，覆盖所有学科，并提供 AI 功能：引用上下文、有影响力的引用、TLDR 和论文推荐。

## 基础 URL

```
https://api.semanticscholar.org/graph/v1       (学术图谱)
https://api.semanticscholar.org/recommendations/v1  (推荐)
```

## 认证

- **不带 key：** 共享限流池（经常触发 429 错误）。能用，但不可靠。
- **带 key：** 每个 key 每秒 1 次请求（可申请更高额度）。
- 请求头：`x-api-key: YOUR_KEY`
- 免费申请 key：https://www.semanticscholar.org/product/api#api-key-form

## `fields` 参数

几乎所有端点都接受 `fields` —— 一个逗号分隔（不能有空格）的字段列表，指定要包含哪些字段。不带它的话，只能拿到 `paperId` + `title`。

**论文字段：**
`paperId`、`corpusId`、`externalIds`、`url`、`title`、`abstract`、`venue`、`publicationVenue`、`year`、`referenceCount`、`citationCount`、`influentialCitationCount`、`isOpenAccess`、`openAccessPdf`、`fieldsOfStudy`、`s2FieldsOfStudy`、`publicationTypes`、`publicationDate`、`journal`、`authors`、`citations`、`references`、`tldr`、`embedding`

**作者字段：**
`authorId`、`externalIds`、`url`、`name`、`affiliations`、`homepage`、`paperCount`、`citationCount`、`hIndex`、`papers`

## 论文 ID 格式

`{paper_id}` 参数接受：
- `649def34f8be52c8b66281af98ae884c09aef38b`（S2 hash）
- `CorpusId:215416146`
- `DOI:10.1038/s41586-021-03819-2`
- `ARXIV:2005.14165`
- `PMID:19872477`
- `PMCID:2323736`
- `ACL:W12-3903`

## 主要端点

### 1. 论文检索（相关性）

```
GET /graph/v1/paper/search?query={text}&fields={fields}&offset={n}&limit={n}
```

| 参数 | 默认值 | 说明 |
|-----------|---------|-------------|
| `query` | 必填 | 纯文本检索 |
| `fields` | paperId,title | 逗号分隔 |
| `offset` | 0 | 分页起点 |
| `limit` | 100 | 最大 100 |
| `year` | -- | `2019` 或 `2016-2020` |
| `publicationDateOrYear` | -- | `YYYY-MM-DD:YYYY-MM-DD` |
| `fieldsOfStudy` | -- | 例如 `Computer Science,Medicine` |
| `publicationTypes` | -- | 例如 `JournalArticle,Conference` |
| `openAccessPdf` | -- | 筛选出 OA 论文 |
| `minCitationCount` | -- | 最低引用数 |
| `venue` | -- | 逗号分隔的期刊/会议 |

通过 offset 最多能访问 **1,000 条结果**。

**示例：**
```
https://api.semanticscholar.org/graph/v1/paper/search?query=CRISPR+gene+therapy&fields=title,year,abstract,citationCount,authors,openAccessPdf&limit=10&year=2023-2024
```

### 2. 论文批量检索（布尔查询，大结果集）

```
GET /graph/v1/paper/search/bulk?query={text}&fields={fields}&sort={field}:{order}&token={token}
```

- 支持布尔运算符：`+`（AND）、`|`（OR）、`-`（NOT）、`"..."`（短语）、`*`（通配符）、`()`（分组）
- 基于 token 的分页（最多 1000 万篇论文）
- 每次调用最多返回 1,000 条
- 可排序：`citationCount:desc`、`publicationDate:desc`、`paperId:asc`

### 3. 论文详情（按 ID）

```
GET /graph/v1/paper/{paper_id}?fields={fields}
```

**示例：**
```
https://api.semanticscholar.org/graph/v1/paper/DOI:10.1038/s41586-021-03819-2?fields=title,year,abstract,citationCount,referenceCount,isOpenAccess,openAccessPdf,authors,tldr
```

**响应：**
```json
{
  "paperId": "dc32a984b651256a8ec282be52310e6bd33d9815",
  "title": "Highly accurate protein structure prediction with AlphaFold",
  "year": 2021,
  "citationCount": 34260,
  "isOpenAccess": true,
  "openAccessPdf": {"url": "https://...pdf", "status": "HYBRID"},
  "tldr": {"text": "This work develops AlphaFold, a system that..."},
  "authors": [{"authorId": "47921134", "name": "J. Jumper"}, ...]
}
```

### 4. 论文引用

```
GET /graph/v1/paper/{paper_id}/citations?fields={fields}&offset={n}&limit={n}
```

返回引用这篇论文的论文。`limit` 最大 1000。

引用特有的字段：`contexts`、`intents`、`isInfluential`

### 5. 论文参考文献

```
GET /graph/v1/paper/{paper_id}/references?fields={fields}&offset={n}&limit={n}
```

返回这篇论文引用的论文。分页方式与引用相同。

### 6. 论文标题匹配

```
GET /graph/v1/paper/search/match?query={exact title}&fields={fields}
```

返回单个最佳匹配，带 `matchScore`。无匹配时返回 404。

### 7. 作者检索

```
GET /graph/v1/author/search?query={name}&fields={fields}&offset={n}&limit={n}
```

### 8. 作者详情

```
GET /graph/v1/author/{author_id}?fields={fields}
```

### 9. 作者的论文

```
GET /graph/v1/author/{author_id}/papers?fields={fields}&offset={n}&limit={n}
```

### 10. 论文推荐

```
GET /recommendations/v1/papers/forpaper/{paper_id}?fields={fields}&limit={n}&from={pool}
```

`from`：`recent`（默认）或 `all-cs`。`limit` 最大 500。

### 11. 多论文推荐（POST）

```
POST /recommendations/v1/papers/
Content-Type: application/json

{
  "positivePaperIds": ["paperId1", "paperId2"],
  "negativePaperIds": ["paperId3"]
}
```

### 12. 论文批量查询（POST）

```
POST /graph/v1/paper/batch?fields={fields}
Content-Type: application/json

{"ids": ["DOI:10.1038/nature12373", "ARXIV:2005.14165"]}
```

每次请求最多 500 个 ID。

## 分页

| 端点 | 每页上限 | 总量上限 | 方式 |
|----------|-------------|-----------|--------|
| 相关性检索 | 100 | 1,000 | offset/next |
| 批量检索 | 1,000 | 10,000,000 | token |
| 引用/参考文献 | 1,000 | 全部 | offset/next |
| 作者检索 | 1,000 | -- | offset/next |

## 出版物类型

`Review`, `JournalArticle`, `CaseReport`, `ClinicalTrial`, `Conference`, `Dataset`, `Editorial`, `LettersAndComments`, `MetaAnalysis`, `News`, `Study`, `Book`, `BookSection`

## 学科领域

`Computer Science`, `Medicine`, `Chemistry`, `Biology`, `Materials Science`, `Physics`, `Geology`, `Psychology`, `Art`, `History`, `Geography`, `Sociology`, `Business`, `Political Science`, `Economics`, `Philosophy`, `Mathematics`, `Engineering`, `Environmental Science`, `Agricultural and Food Sciences`, `Education`, `Law`, `Linguistics`

## 错误格式

```json
{"message": "Too Many Requests", "code": "429"}
```

未找到返回 HTTP 404，限流返回 429。
