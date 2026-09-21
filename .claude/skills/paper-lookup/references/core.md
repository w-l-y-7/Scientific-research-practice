# CORE API

CORE 汇集了全球 15,000+ 个仓库的开放获取研究成果。它为 3700 万+ 篇论文提供**全文**，为 3.68 亿+ 篇论文提供元数据。

## 基础 URL

```
https://api.core.ac.uk/v3
```

**重要：** GET 搜索路径需要**末尾斜杠**（例如 `/v3/search/works/`，不是 `/v3/search/works`）。

## 认证

- **请求头：** `Authorization: Bearer YOUR_API_KEY`
- **查询参数：** `?api_key=YOUR_API_KEY`
- 注册地址：https://core.ac.uk/services/api

**不带认证：** 基础元数据查询可用，但拿不到全文（会返回 "Not available for public API users"）。

## 限流（基于 token）

| 用户类型 | 每日 token | 每分钟上限 |
|-----------|-------------|----------------|
| 未认证 | 100/天 | 10/分 |
| 注册个人 | 1,000/天 | 25/分 |
| 注册学术用户 | 5,000/天 | 10/分 |

简单查询消耗 1 个 token。下载和 scroll 分页消耗 3-5 个 token。

## 关键端点

### 1. 检索 works

```
GET /v3/search/works/?q={query}&limit={n}&offset={n}
```

| 参数 | 默认值 | 说明 |
|-----------|---------|-------------|
| `q` | 必填 | 检索词（支持字段查找、布尔运算符） |
| `limit` | 10 | 每页结果数（最大 100） |
| `offset` | 0 | 分页偏移量 |
| `scroll` | false | 结果超过 10,000 条时启用 scroll 分页 |
| `sort` | relevance | `relevance` 或 `recency` |

**POST 替代方式**（用于复杂查询）：
```
POST /v3/search/works
Content-Type: application/json

{"q": "machine learning", "limit": 10, "offset": 0}
```

**示例：**
```
https://api.core.ac.uk/v3/search/works/?q=CRISPR+gene+therapy&limit=10
```

### 2. 查询语言

| 运算符 | 示例 | 说明 |
|----------|---------|-------------|
| AND | `title:"AI" AND authors:"Smith"` | 两个条件都满足 |
| OR | `title:"AI" OR fullText:"Deep Learning"` | 满足任一条件 |
| Grouping | `(title:"AI" OR title:"ML") AND yearPublished>"2020"` | 优先级 |
| Field lookup | `title:"Machine Learning"` | 检索指定字段 |
| Range | `yearPublished>2018` | 数值比较 |
| Exists | `_exists_:fullText` | 字段必须存在 |
| Phrase | `title:"Attention is all you need"` | 精确短语 |

**可检索字段：** `abstract`, `arxivId`, `authors`, `contributors`, `createdDate`, `dataProviders`, `depositedDate`, `documentType`, `doi`, `fullText`, `id`, `language`, `license`, `oai`, `title`, `yearPublished`

### 3. 按 ID 获取 work

```
GET /v3/works/{id}
```

`id` 是 CORE Work ID（整数）。例如：`/v3/works/267312`

### 4. 按 ID 获取 output

```
GET /v3/outputs/{id}
```

### 5. 下载全文

```
GET /v3/outputs/{id}/download
```

返回二进制 PDF。需要认证。

```
GET /v3/works/tei/{id}
```

返回 TEI XML 格式。

### 6. 检索 outputs

```
GET /v3/search/outputs/?q={query}&limit={n}&offset={n}
```

按 DOI 检索：`q=doi:10.1038/nature12373`

## 响应格式

### 检索响应
```json
{
  "totalHits": 2281337,
  "limit": 10,
  "offset": 0,
  "scrollId": null,
  "results": [...]
}
```

### Work 对象（关键字段）
```json
{
  "id": 8848131,
  "title": "Attention Is All You Need",
  "authors": [{"name": "Ashish Vaswani"}, ...],
  "abstract": "The dominant sequence...",
  "doi": "10.48550/arXiv.1706.03762",
  "arxivId": "1706.03762",
  "yearPublished": 2017,
  "downloadUrl": "https://core.ac.uk/download/...",
  "fullText": "Full text content (when authenticated)...",
  "language": {"code": "en", "name": "English"},
  "documentType": "research",
  "citationCount": 145678,
  "dataProviders": [{"name": "arXiv"}],
  "links": [{"type": "download", "url": "..."}]
}
```

## 分页

- **标准：** `offset` + `limit`（最多 10,000 条结果）
- **Scroll：** 设置 `scroll=true`。响应包含 `scrollId`。在后续请求中用它翻到 10,000 条以后（消耗更多 token）。

## 错误处理

高负载下，API 可能返回部分分片（shard）失败的提示。这类错误是暂时的，稍等片刻后重试。
