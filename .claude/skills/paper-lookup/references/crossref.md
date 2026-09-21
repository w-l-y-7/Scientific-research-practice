# Crossref API

Crossref 是学术内容的 DOI 注册机构，为 1.5 亿多件作品提供元数据，涵盖期刊论文、图书、会议论文、数据集和预印本。

## 基础 URL

```
https://api.crossref.org
```

## 认证

无需认证。加上 `mailto=you@example.com` 就能进入 **polite pool**（礼貌池），限流速率翻倍。

## 限流

| 池 | 速率 | 并发 |
|------|------|-------------|
| 公共（无 mailto） | 5 req/sec | 1 并发 |
| 礼貌池（带 mailto） | 10 req/sec | 3 并发 |

收到 HTTP 429 表示被临时封禁。

## 关键端点

### 1. 检索作品

```
GET /works?query={text}&rows={n}&mailto=you@example.com
```

| 参数 | 默认值 | 说明 |
|-----------|---------|-------------|
| `query` | -- | 跨所有字段的全文检索 |
| `query.author` | -- | 检索作者姓名 |
| `query.bibliographic` | -- | 检索标题、作者、ISSN、年份 |
| `query.affiliation` | -- | 检索机构署名 |
| `query.container-title` | -- | 检索期刊名 |
| `filter` | -- | 逗号分隔的 `name:value` 对 |
| `sort` | `score` | `score`、`published`、`issued`、`deposited`、`updated`、`is-referenced-by-count`、`references-count` |
| `order` | `desc` | `asc` 或 `desc` |
| `rows` | 20 | 每页条数（上限 1000） |
| `offset` | 0 | 跳过 N 条结果（上限 10000） |
| `cursor` | -- | 用 `*` 开启基于游标的深度分页 |
| `select` | -- | 逗号分隔的字段名，指定要返回的字段 |
| `facet` | -- | 分面计数，例如 `type-name:10` |
| `sample` | -- | 随机返回 N 条（上限 100） |

**示例：**
```
https://api.crossref.org/works?query=CRISPR+gene+therapy&filter=from-pub-date:2024-01-01,type:journal-article,has-abstract:true&rows=5&sort=published&order=desc&mailto=you@example.com
```

### 2. 按 DOI 获取作品

```
GET /works/{doi}?mailto=you@example.com
```

DOI 需要 URL 编码：`10.1038/nature12373` 变成 `10.1038%2Fnature12373`

**示例：**
```
https://api.crossref.org/works/10.1038%2Fnature12373?mailto=you@example.com
```

### 3. 期刊

```
GET /journals?query={name}&rows={n}
GET /journals/{issn}
GET /journals/{issn}/works?query={text}&rows={n}
```

### 4. 资助机构

```
GET /funders?query={name}
GET /funders/{id}
GET /funders/{id}/works?rows={n}
```

资助机构 ID 来自 Funder Registry（例如 NSF 是 `100000001`）。

### 5. 成员（出版商）

```
GET /members?query={name}
GET /members/{id}/works?rows={n}
```

## 关键过滤器

### 日期过滤器（接受 `YYYY`、`YYYY-MM`、`YYYY-MM-DD`）
| 过滤器 | 说明 |
|--------|-------------|
| `from-pub-date` / `until-pub-date` | 出版日期 |
| `from-print-pub-date` / `until-print-pub-date` | 印刷版出版日期 |
| `from-online-pub-date` / `until-online-pub-date` | 在线出版日期 |
| `from-posted-date` / `until-posted-date` | 发布日（预印本） |

### 布尔过滤器
| 过滤器 | 说明 |
|--------|-------------|
| `has-abstract` | 有摘要 |
| `has-orcid` | 有 ORCID ID |
| `has-funder` | 有资助机构信息 |
| `has-full-text` | 有全文链接 |
| `has-references` | 有参考文献列表 |
| `has-license` | 有许可证信息 |

### 取值过滤器
| 过滤器 | 说明 |
|--------|-------------|
| `type` | `journal-article`、`posted-content`、`book-chapter`、`proceedings-article` 等 |
| `issn` | 期刊 ISSN |
| `doi` | 指定 DOI |
| `orcid` | 贡献者的 ORCID |
| `funder` | Funder Registry ID |
| `member` | Crossref 成员 ID |
| `prefix` | DOI 前缀 |
| `license.url` | 许可证 URL |
| `update-type` | `correction`、`retraction` |

**语法：** `filter=name1:value1,name2:value2`

## 分页

### 基于偏移量（上限 10000）
```
/works?query=cancer&rows=100&offset=200
```

### 基于游标（无上限）
1. 第一个请求：`?cursor=*&rows=100`
2. 响应里带 `next-cursor`
3. 下一个请求：`?cursor={next-cursor-value}&rows=100`
4. 游标 5 分钟后失效

## 响应格式

### 列表响应
```json
{
  "status": "ok",
  "message-type": "work-list",
  "message": {
    "total-results": 2779116,
    "items-per-page": 20,
    "next-cursor": "...",
    "items": [...]
  }
}
```

### 作品对象（关键字段）
```json
{
  "DOI": "10.1038/nature12373",
  "title": ["Nanometre-scale thermometry in a living cell"],
  "author": [{"given": "G.", "family": "Kucsko", "sequence": "first"}],
  "publisher": "Springer Science and Business Media LLC",
  "type": "journal-article",
  "published": {"date-parts": [[2013, 7, 31]]},
  "container-title": ["Nature"],
  "ISSN": ["0028-0836", "1476-4687"],
  "volume": "500",
  "issue": "7460",
  "page": "54-58",
  "is-referenced-by-count": 1745,
  "references-count": 30,
  "abstract": "<p>Abstract text with HTML tags...</p>",
  "license": [{"URL": "...", "content-version": "vor"}],
  "link": [{"URL": "...", "content-type": "application/pdf"}],
  "reference": [{"key": "...", "doi-asserted-by": "crossref", "DOI": "..."}],
  "subject": ["Multidisciplinary"],
  "language": "en"
}
```

注意：`title` 和 `container-title` 是数组。`published.date-parts` 是 `[[year, month, day]]`。摘要可能含 HTML 标签。
