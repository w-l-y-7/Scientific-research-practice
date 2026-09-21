# ROR（Research Organization Registry）

研究机构的开放注册库。用它把机构署名字符串转成 ROR ID（`https://ror.org/05a0ya142`），或者查单个机构。它不是论文数据库。OpenAlex 和 Crossref 已经在 works 上*带*了 ROR ID；这个 API 是用来生成或核对 ID 本身的。

下文所有数据核实于 2026-09-10。请使用 **v2** 路由。

## 基础 URL

```
https://api.ror.org/v2
```

文档：https://ror.readme.io/docs/rest-api

## 认证

无。心跳检测：`GET https://api.ror.org/heartbeat` → `OK`。

## 限流

每 IP 每 5 分钟 2000 个请求。UTC 午夜前后流量高峰。批量匹配时，把 API 跑在本地（Docker），不要猛打公共主机。

## 标识符

ROR ID 是 `https://ror.org/` 加上九个字符（`0` + 6 个字母数字 + 2 个类校验字符），例如 `https://ror.org/05a0ya142`。路径 `/v2/organizations/05a0ya142` 可以只接受后缀。

## 关键端点

### 1. 关键词 / 标识符检索

```
GET /v2/organizations?query={text}
```

**只**检索 `names` 和 `external_ids`（GRID、ISNI、Wikidata、Crossref Funder ID）。它不检索地址、网站或关系。

不加引号的常见词会导致结果爆炸。已核实：

| `query` | `number_of_results` | 首个命中 |
|---|---|---|
| `Broad Institute` | 13016 | Broad Institute（运气好，不保证） |
| `"Broad Institute"` | 3 | Broad Institute |

在没读 `names` 和 `status` 之前，绝不要把 `items[0]` 当作匹配结果。用户给的是专有名称时，给字符串加引号（`%22…%22`）。

默认一页 20 条 active 记录。过滤和翻页见 https://ror.readme.io/docs/api-filtering 和 https://ror.readme.io/docs/api-paging。如果列表里需要 inactive / withdrawn 的机构，传 `all_status=true`。

### 2. 机构署名匹配器（非结构化字符串）

```
GET /v2/organizations?affiliation={raw affiliation}
```

最适合处理从 PDF 里直接抠出来的 "Broad Institute of MIT and Harvard, Cambridge, MA" 这类字符串。截至 2026-05-26，这个参数默认使用**单次检索（single search）**策略。

这个 JSON 和 `?query=` 的**不一样**。每一项是一个匹配包装对象：

```json
{
  "substring": "Broad Institute of MIT and Harvard, Cambridge, MA",
  "score": 1.0,
  "matching_type": "SINGLE SEARCH",
  "chosen": true,
  "organization": { "id": "https://ror.org/05a0ya142", "names": […], "status": "active" }
}
```

读取 `items[].organization` 和 `chosen`。`items[0].id` 不存在——这就是为什么幼稚的解析会在匹配成功后报出 "no ROR ID"。

已核实：10 项，首个 `chosen` 为 true，机构是 Broad Institute。

### 3. 单个机构

```
GET /v2/organizations/{ror_id_or_suffix}
```

```
GET /v2/organizations/05a0ya142
```

总是返回记录，包括 `inactive` / `withdrawn` 的。列表默认隐藏这些状态；单 id 的 GET 不会。把 ID 写进元数据前先检查 `status`。

v2 记录有 `names[]`（类型包括 ror_display、alias、acronym、label），没有顶层的 `name`。不带 `/v2` 的 `/organizations/{id}` 目前仍返回 v2 的结构；请调用 `/v2/`，这样将来默认值变了也不会在你脚下把 schema 翻掉。

## 典型工作流

1. 专有名称或 GRID/ISNI → `?query="…"`，然后检查候选列表。
2. 杂乱的机构署名行 → `?affiliation=`，保留 `chosen: true` 的行（或者你愿意为之背书的高 `score` 行）。
3. 已知 ROR ID → GET 记录，确认 `status: active`。
4. 如果用户想要这个机构的论文，就用 ROR ID 去检索 OpenAlex / Crossref。不要在 ROR 里检索论文。

## 失败模式

| 你的操作 | 会发生什么 | 怎么办 |
|---|---|---|
| 用不加引号的 `University` / `Institute` 检索 | 成千上万条命中 | 给名称加引号；不要自动挑一个 |
| 在 affiliation 响应里读 `items[0].id` | `null` | 用 `items[0].organization.id` |
| 从单 id GET 里写入了 inactive 的 ROR | 记录存在，但 `status` 不是 `active` | 读 `status` |
| 用了 v1 的字段 `name` | 缺失 | 用 `names[].value` |
