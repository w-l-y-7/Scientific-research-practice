# Unpaywall API

Unpaywall 告诉你一篇学术论文是否存在合法的免费副本。给一个 DOI，它返回开放获取状态、PDF 链接和位置详情。

## 基础 URL

```
https://api.unpaywall.org/v2
```

## 认证

不需要 API key。你**必须**把**邮箱地址**作为查询参数带上：`?email=you@example.com`

**重要：** 用真实邮箱地址。Unpaywall 会以 HTTP 422 拒绝 `test@example.com` 这类占位符邮箱。

## 限流

每天 100000 次调用。用量更大就下载数据库快照。

## 关键端点

### 1. DOI 查询

```
GET /v2/{doi}?email=you@example.com
```

**示例：**
```
https://api.unpaywall.org/v2/10.1038/nature12373?email=you@example.com
```

### 2. 检索（不可靠）

```
GET /v2/search?query={text}&email=you@example.com
```

**警告：** 截至 2026 年 3 月，search 端点一直返回 HTTP 500 错误。它可能已被弃用，或者时好时坏。改用 DOI 查询——先用 PubMed/OpenAlex/Semantic Scholar 找到论文，再逐个 DOI 检查 OA 状态。

| 参数 | 说明 |
|-----------|-------------|
| `query` | 检索文本。支持引号短语、`OR`、`-` 取反 |
| `is_oa` | `true` 或 `false`——按 OA 状态过滤 |
| `page` | 页码（从 1 开始），每页 50 条结果 |

## 响应格式

### DOI 查询响应
```json
{
  "doi": "10.1038/nature12373",
  "doi_url": "https://doi.org/10.1038/nature12373",
  "title": "Nanometre-scale thermometry in a living cell",
  "year": 2013,
  "published_date": "2013-07-31",
  "genre": "journal-article",
  "publisher": "Springer Nature",
  "is_oa": true,
  "oa_status": "green",
  "best_oa_location": {
    "url": "https://dash.harvard.edu/bitstream/1/...",
    "url_for_pdf": "https://dash.harvard.edu/bitstream/1/...pdf",
    "url_for_landing_page": "https://dash.harvard.edu/handle/...",
    "host_type": "repository",
    "version": "acceptedVersion",
    "license": "cc-by",
    "is_best": true,
    "oa_date": "2016-01-01"
  },
  "first_oa_location": {...},
  "oa_locations": [...],
  "has_repository_copy": true,
  "journal_name": "Nature",
  "journal_issns": "0028-0836,1476-4687",
  "journal_issn_l": "0028-0836",
  "journal_is_oa": false,
  "journal_is_in_doaj": false,
  "z_authors": [
    {"raw_author_name": "G. Kucsko", "author_position": "first"},
    {"raw_author_name": "P. C. Maurer", "author_position": "middle"}
  ]
}
```

### OA 状态取值
| 状态 | 含义 |
|--------|---------|
| `gold` | 发表在完全 OA 的期刊上 |
| `hybrid` | 订阅制期刊中的 OA 论文（出版商托管） |
| `bronze` | 在出版商网站上可免费阅读，但没有 OA 许可证 |
| `green` | 可通过仓储获取（例如机构仓储、预印本） |
| `closed` | 找不到合法的免费副本 |

### OA 位置字段
| 字段 | 说明 |
|-------|-------------|
| `url` | 最佳 URL（有 PDF 就优先给 PDF，否则给落地页） |
| `url_for_pdf` | PDF 直链（没有 PDF 时为 null） |
| `url_for_landing_page` | 落地页 URL |
| `host_type` | `publisher` 或 `repository` |
| `version` | `submittedVersion`、`acceptedVersion`、`publishedVersion` |
| `license` | 例如 `cc-by`、`cc-by-nc`、`implied-oa`，或 null |
| `is_best` | 是否就是 `best_oa_location` |
| `oa_date` | 该位置首次可用的时间 |

### 检索响应
```json
{
  "results": [
    {
      "response": {...},
      "score": 42.5,
      "snippet": "...text with <b>highlighted</b> matches..."
    }
  ]
}
```

## 典型工作流

1. 你手里有一个 DOI，来自 PubMed、Crossref 或其他来源
2. 用这个 DOI 调用 Unpaywall
3. 看 `is_oa`——如果为 true，用 `best_oa_location.url_for_pdf` 拿免费 PDF
4. 看 `oa_status`，判断是哪一种 OA
5. 如果为 closed，`oa_locations` 会是空的——这篇论文需要订阅才能看
