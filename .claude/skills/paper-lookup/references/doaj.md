# DOAJ（开放获取期刊目录）

一份经过人工筛选的*开放获取期刊*目录，以及这些期刊在 DOAJ 登记的论文。用它回答"这本期刊在 DOAJ 里吗？"或"DOAJ 收录期刊中匹配 X 的论文有哪些？"。它不是通用文献索引，也不是 Unpaywall。

Nature 不在 DOAJ。一篇论文可以是开放获取的（hybrid、bronze、green），但它所在的期刊未必被 DOAJ 收录。要问"这个 DOI 有没有免费 PDF？"，用 Unpaywall。如果你已经在 OpenAlex 上，只想问"这本期刊在 DOAJ 里吗？"这个是非题，`GET /sources/issn:{issn}` 会返回 `is_in_doaj`（PLoS ONE 的 `1932-6203` 为 `true`，Nature 的 `0028-0836` 为 `false`）——就留在 OpenAlex 上查。等你需要 APC、许可证或 `oa_start` 时再到 DOAJ。要查"CRISPR 相关的论文"，用 PubMed / OpenAlex，之后可选地限定到 DOAJ 期刊。

下文所有数据于 2026-09-10 针对 API **v4** 核验过。

## 基础 URL

```
https://doaj.org/api
```

文档（实时）：https://doaj.org/api/docs

你写的 `/api/search/...` 这类检索 URL 由 v4 提供服务；JSON 里的 `next` 链接指向 `/api/v4/search/...`。两种写法都能用。

## 认证

公共检索不需要 key。API key 是给出版商投稿用的。不要为了查一本期刊而向用户索要 DOAJ key。

## 限流

没有公布每秒上限。保持礼貌。优先用期刊 ISSN 查询，而不是翻过几万条论文命中结果。

## 查询语法

路径段*本身*就是查询（Elasticsearch query string）。DOI 里的斜杠会被自动转义。

| 目标 | 查询 |
|---|---|
| 论文标题词 | `bibjson.title:CRISPR` |
| DOI | `doi:10.3389/fpsyg.2013.00479` |
| 期刊 ISSN | `issn:1932-6203` |
| 精确期刊名 | `bibjson.title.exact:"PLoS ONE"` |
| 短名 | `title:`、`issn:`、`publisher:`、`license:`（期刊） |

`.exact` 只能用在完整字段名上，**不能**用在短别名上。

## 关键端点

### 1. 检索论文

```
GET /search/articles/{query}?page=1&pageSize=10
```

```
GET /search/articles/bibjson.title:CRISPR?pageSize=2
```

已核验：`total` 为 7777，`page` 为 1，`pageSize` 为 2，`results` 长度为 2。`next` 是
`https://doaj.org/api/v4/search/articles/bibjson.title:CRISPR?page=2&pageSize=2`。
跟着 `next` 走（或者递增 `page`），不要猜最后一页——
`last` 指向第 3889 页。

每条结果带 `id`、`created_date`、`last_updated`、`bibjson`。标识符是一个**列表**：

```json
"identifier": [
  {"id": "10.3390/v14102045", "type": "doi"},
  {"id": "1999-4915", "type": "eissn"}
]
```

挑 `type == "doi"` 的那条。不要盲目取 `identifier[0]`（它可能是 ISSN）。

### 2. 检索期刊

```
GET /search/journals/{query}?page=1&pageSize=10
```

已核验：

| 查询 | `total` | 备注 |
|---|---|---|
| `issn:0028-0836`（Nature） | 0 | 订阅制期刊。空结果就是答案。 |
| `issn:1932-6203`（PLoS ONE） | 1 | `bibjson.title` 为 `PLoS ONE`，`oa_start` 为 2006，`apc.has_apc` 为 true，上限 2477 USD |

HTTP 200 + `total: 0` + `results: []` 意味着"不是 DOAJ 期刊"，而不是服务故障。Unpaywall 仍可能找到 Nature 论文的 green 或 hybrid 副本。

期刊的 `bibjson` 包含标题、ISSN、出版商、许可证、APC 和 `oa_start`。有人问"这本期刊在 DOAJ 里是 OA 吗？"时，要引用的就是这条记录。

## 典型工作流

1. 手里有 ISSN 或期刊名 → `/search/journals/issn:{issn}`。
2. 手里有 DOI，且相信它来自 DOAJ 期刊 → `/search/articles/doi:{doi}`。
3. 如果期刊检索为空，如实说明，再去 Unpaywall 查这篇论文。
4. 不要拿翻页 `bibjson.title:CRISPR` 来替代 PubMed。

## 失败模式

| 你做了什么 | 会怎样 | 该怎么做 |
|---|---|---|
| 用了非 DOAJ 期刊的 ISSN | 200，`total: 0` | 报告"不在 DOAJ"；再试 Unpaywall |
| 把 `identifier[0]` 当成 DOI | 你可能拿到 eISSN | 过滤 `type == "doi"` |
| 把 DOAJ 当成 Unpaywall 用 | 漏掉 hybrid/green 的 OA | 论文级 OA 要查 Unpaywall |
| 只为了一个是非题就换第二个主机 | 多一次调用 | 已经在 OpenAlex 就用 `sources.is_in_doaj` |
| 短字段名 + `.exact` | 查询的含义和你想的不一样 | 用 `bibjson.title.exact` |
