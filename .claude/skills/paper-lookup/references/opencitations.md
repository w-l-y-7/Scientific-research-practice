# OpenCitations

开放引用数据（谁引用了谁），以引用/被引 PID 的开放列表形式提供。当你需要一条开放许可的引用边、一个可引用的计数，或者一个 Open Citation Identifier (OCI) 时用它。它不是论文检索工具，Index 端点上也不返回标题。

做文献检索请用 PubMed、OpenAlex 或 Semantic Scholar。要*带标题和摘要的引用图谱*，从 Semantic Scholar 或 OpenAlex 入手，把 OpenCitations 当作开放数据校验用。当你手里已经有 `{source}/{id}` 对时，Europe PMC 的 `/citations` 是生物医学领域的替代方案。

下文所有数据于 2026-09-10 核验过。

## 基础 URL

```
https://api.opencitations.net/index/v2    # 引用边和计数
https://api.opencitations.net/meta/v1     # PID 的书目元数据
```

Index v2 是当前版本（v2.2.0，2025-04-15）。Meta 在 **v1**——`meta/v2/...` 会返回 HTTP 404。

## 认证

可选。公共调用不需要 token。用量更大时，可向 OpenCitations 申请访问 token，并发送 `Authorization: <token>`。不要为此新增 `.env` key；不带 key 直接调用即可。

## 限流

没有公布每秒上限。串行发请求。先调 `/citation-count`，再调 `/citations`——列表端点会在单个响应体里返回**全部**入引，没有分页参数。

## 标识符前缀（必填）

Index v2 的 ID 必须是 `doi:`、`pmid:` 或 `omid:`。裸 DOI 会返回 HTTP 400：

```
GET /index/v2/citation-count/10.1038/nature12373
  -> 400  the value '10.1038/nature12373' is not valid for parameter 'id'
          Example: /index/v2/citation-count/doi:10.1108/jd-12-2013-0166

GET /index/v2/citation-count/doi:10.1038/nature12373
  -> 200  [{"count": "1806"}]
```

## 关键端点

### 1. 入引计数

```
GET /index/v2/citation-count/{id}
```

永远是一个单元素 JSON 数组。`count` 是**字符串**，不是整数。

| 查询 | HTTP | 响应体 |
|---|---|---|
| `doi:10.1038/nature12373` | 200 | `[{"count": "1806"}]` |
| `pmid:23803767` | 200 | `[{"count": "94"}]` |
| `doi:10.9999/not-a-real-doi` | 200 | `[{"count": "0"}]` |

作品不存在时返回 HTTP 200 加 `"0"`，而不是 404。不要把 200 当成"这个 DOI 在索引里"。

### 2. 出参参考文献计数

```
GET /index/v2/reference-count/{id}
```

结构与 citation-count 相同。

### 3. 入引 / 出参参考文献

```
GET /index/v2/citations/{id}
GET /index/v2/references/{id}
```

每项：

| 字段 | 含义 |
|---|---|
| `oci` | Open Citation Identifier (`citingOmidsuffix-citedOmidsuffix`) |
| `citing` / `cited` | 空格分隔的 PID，每个都带前缀（`doi:`、`pmid:`、`omid:`、`openalex:`） |
| `creation` | 引用作品的 ISO 日期 |
| `timespan` | 被引与引用作品出版之间的 XSD 时长（`P6Y0M1D`） |
| `journal_sc` / `author_sc` | `"yes"` / `"no"` 自引标志 |

在 `doi:10.1038/nature12373` 的 `/references` 上核验过：30 行。第一个 `citing` 是
`omid:br/06120344846 doi:10.1038/nature12373 openalex:W2159974629 pmid:23903748`。
把 `doi:` 那一段解析出来；不要把整串当成一个 DOI。

在 `doi:10.1186/1756-8722-6-59` 的 `/citations` 上核验过：单个响应里 217 行。
对 `nature12373` 来说计数是 1806——除非用户要完整集合，否则不要拉整个列表。

### 4. 按 OCI 取单条引用

```
GET /index/v2/citation/{oci}
```

`oci` 是两段数字的形式，不带 `oci:` 前缀。

### 5. 元数据（标题、作者）

```
GET /meta/v1/metadata/{id}
```

同样是 `doi:` / `pmid:` / `omid:` 前缀。返回 `id`（空格分隔的 PID）、`title`、`author`（分号分隔，可能含 ORCID + OMID）。当你从 Index 拿到一条引用边、需要人类可读的标签时用它。

## 典型工作流

1. 你有一个 DOI 或 PMID。
2. 先调 `citation-count`。如果结果是 `"0"`，只能说 OpenCitations 没有它的入引记录——不能说这篇论文在所有地方都无人引用。
3. 需要短列表就用 `/references` 或 `/citations`。从每个 `citing`/`cited` 字符串里抽出 `doi:` 那一段。
4. 用 Meta、Crossref 或 Semantic Scholar 补齐标题。不要凭 OCI 自己编。

## 失败模式

| 你做了什么 | 会怎样 | 该怎么做 |
|---|---|---|
| 裸 DOI，没有 `doi:` 前缀 | HTTP 400 | 补上前缀方案 |
| 未知 DOI | HTTP 200，`count: "0"` | 报告存在空白；改试 Semantic Scholar |
| 把 `citing` 当成一个 DOI 解析 | 你存下的是 `omid:br/… doi:10.… pmid:…` | 按空格切分；保留 `doi:` 那段的值 |
| 对高被引作品调 `/citations` | 数 MB 的 JSON，没有分页 | 先计数；限定拉取范围 |
| `meta/v2/...` | HTTP 404 HTML | 改用 `meta/v1` |
