# bioRxiv API

bioRxiv 是生物学预印本服务器。API 提供预印本的元数据，包括标题、作者、摘要、DOI 和发表状态。

**重要：** bioRxiv API **没有关键词搜索**。它只支持按日期范围浏览和按 DOI 查询。要按关键词检索 bioRxiv 预印本，改用 Semantic Scholar、OpenAlex 或 CORE。

## 基础 URL

```
https://api.biorxiv.org
```

## 认证

无需认证。完全公开的 API。

## 核心端点

### 1. 内容详情 —— 按日期范围浏览

```
GET /details/biorxiv/{interval}/{cursor}/{format}
```

| 参数 | 取值 | 说明 |
|-----------|--------|-------------|
| `interval` | `YYYY-MM-DD/YYYY-MM-DD` | 日期范围（含两端）。范围要窄（1-3 天），否则容易超时。 |
| | `N`（整数） | 最近 N 篇预印本 |
| | `Nd`（整数 + "d"） | 最近 N 天 |
| `cursor` | 整数（默认 `0`） | 绝对记录偏移量。**`/details/` 每页返回 30 条，所以步长取 30** —— 见分页。 |
| `format` | `json`（默认）、`xml` | 响应格式 |

可选查询参数：`?category=neuroscience`（按分类过滤，空格用下划线代替）

**示例：**
```
https://api.biorxiv.org/details/biorxiv/2024-01-01/2024-01-31/0
https://api.biorxiv.org/details/biorxiv/5
https://api.biorxiv.org/details/biorxiv/10d
https://api.biorxiv.org/details/biorxiv/2024-01-01/2024-01-31?category=neuroscience
```

### 2. 内容详情 —— 按 DOI 查询

```
GET /details/biorxiv/{doi}/na/{format}
```

**示例：**
```
https://api.biorxiv.org/details/biorxiv/10.1101/2024.01.16.575895/na/json
```

### 3. 已发表论文链接

```
GET /pubs/biorxiv/{interval}/{cursor}
GET /pubs/biorxiv/{doi}/na
```

把预印本关联到它们正式发表的期刊版本。预印本 DOI 和发表 DOI 都接受。

### 4. 出版商过滤

```
GET /publisher/{prefix}/{interval}/{cursor}
```

按 DOI 前缀查找某出版商发表的 bioRxiv 论文。

```
https://api.biorxiv.org/publisher/10.15252/2024-01-01/2024-06-01/0
```

**陷阱：** 对很多有效的出版商前缀，这个端点都返回 `{"messages":[{"status":"no articles found"}],"collection":[]}`，上面那一个也不例外（EMBO，2026-07-27 实测）—— 而且返回 **HTTP 200**，所以空的 `collection` 和真正的无匹配根本分不出来。这里返回空结果只能算没结论，不能当作“该出版商没发过 bioRxiv 预印本”的证据。要回答“出版商 X 发表过哪些 bioRxiv 预印本”，优先用 `/pubs/`（见下），再按 `published_journal` 分组，或者到 Crossref 查 `filter=prefix:10.15252`。

## 响应格式

```json
{
  "messages": [{
    "status": "ok",
    "category": "all",
    "interval": "2024-01-01:2024-01-03",
    "funder": "all",
    "cursor": 0,
    "count": 30,
    "count_new_papers": "232",
    "total": "360"
  }],
  "collection": [{
    "title": "Paper title...",
    "authors": "Surname, A.; Surname, B.",
    "author_corresponding": "Full Name",
    "author_corresponding_institution": "Institution",
    "doi": "10.1101/2024.01.16.575895",
    "date": "2024-01-20",
    "version": "1",
    "type": "new results",
    "license": "cc_no",
    "category": "cancer biology",
    "jatsxml": "https://www.biorxiv.org/content/early/.../source.xml",
    "abstract": "Full abstract text...",
    "published": "10.1158/2159-8290.CD-24-0187",
    "server": "bioRxiv"
  }]
}
```

- `published` 若尚未在期刊发表就是 `"NA"`，已发表则是发表 DOI。
- `type` 取值：`new results`、`confirmatory results`、`contradictory results`

### `messages` 块并不统一 —— 对照前先检查

计数字段**只出现在区间查询中**。2026-07-27 实测：

| 请求 | `messages[0]` 包含 |
|---|---|
| `/details/biorxiv/2024-01-01/2024-01-03/0` | `status`、`category`、`interval`、`funder`、`cursor`、`count`、`count_new_papers`、`total` |
| `/details/biorxiv/{doi}/na/json` | 只有 `status`、`category` —— **没有计数** |
| `/details/biorxiv/5`（最近 N 篇） | 只有 `status`、`category` —— **没有计数** |
| `/pubs/biorxiv/{interval}/{cursor}` | `status`、`interval`、`cursor`、`count`、`total` |

所以技能里“先取 count、再对照”这一步，在 DOI 查询和最近 N 篇查询上无物可对。这些地方改用 `len(collection)`，并在溯源信息里注明该端点不暴露 total。

**`total` 和 `count_new_papers` 数的不是同一样东西。** 对 `2024-01-01:2024-01-03`，`total` 是 `360`，`count_new_papers` 是 `232`：`total` 数的是区间内每一条 *version*（版本）记录，`count_new_papers` 数的是首次发布的预印本去重后的条数。翻页翻到 `total` 再按 DOI 去重，落点接近 `count_new_papers` 而不是 `total` —— 要对照就对照对的那个，并说明你用的是哪个。

## 分页

**每页条数因端点而异** —— 2026-07-27 实测，而且这种差异是静默的：

| 端点 | 每页记录数 | `cursor` 步长 |
|---|---|---|
| `/details/{server}/{interval}/{cursor}` | **30** | 30 |
| `/pubs/{server}/{interval}/{cursor}` | 100 | 100 |

`cursor` 是绝对记录偏移量，不是页码，步长不对的值它照样接受、不报错：在 `/details/` 查询里用 `cursor=100` 会返回第 100-129 条记录，而且返回 **HTTP 200**。所以按 100 的步长走 `/details/`，每 100 条就会跳过第 30-99 条，表面上却像成功了。按响应实际报告的 `count` 来步进，当 `cursor + count >= total` 或 `collection` 返回空时停止。

`scripts/paginate.py --api biorxiv` 用正确的步长实现了这套遍历，并把取回的条数和 `total`、`count_new_papers` 做对照。

## 限流

没有文档化的限流规则。无需认证。请求频率要合理。

## 分类

`animal-behavior-and-cognition`, `biochemistry`, `bioengineering`, `bioinformatics`, `biophysics`, `cancer-biology`, `cell-biology`, `clinical-trials`, `developmental-biology`, `ecology`, `epidemiology`, `evolutionary-biology`, `genetics`, `genomics`, `immunology`, `microbiology`, `molecular-biology`, `neuroscience`, `paleontology`, `pathology`, `pharmacology-and-toxicology`, `physiology`, `plant-biology`, `scientific-communication-and-education`, `synthetic-biology`, `systems-biology`, `zoology`
