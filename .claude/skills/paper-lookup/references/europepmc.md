# Europe PMC API

Europe PMC 是一个统一的检索面，覆盖 PubMed 摘要、PMC 全文、**预印本**（bioRxiv、
medRxiv、Research Square、SSRN 等）、专利、NHS 指南和学位论文。它是本技能里唯一能同时
*跨*这些语料库做关键词检索的 API。

当其他 API 做不到下面这些事时，就求助于它：

- **对 bioRxiv/medRxiv 预印本做关键词检索。** 这些预印本服务器自己的 API 完全没有关键词
  检索（见 `references/biorxiv.md`）。Europe PMC 收录它们，并用 `SRC:"PPR"` 过滤。
- **在全文内部检索**，而不只是标题和摘要，结果限制过滤器（`HAS_FT:Y`、`OPEN_ACCESS:Y`）
  在服务端生效。
- **诚实失败的全文。** 当论文不是开放获取时，`fullTextXML` 返回干净的 **404**，
  而 NCBI eFetch 返回带元数据、没有 `<body>` 的 HTTP 200（见 `references/pmc.md`
  的陷阱章节）。

下面所有数据均于 2026-07-27 验证。

## 基础 URL

```
https://www.ebi.ac.uk/europepmc/webservices/rest
```

## 认证

不需要。没有 key，没有 email 参数，也不用注册。

## 限流

没有公布每秒限制。Europe PMC 要求合理使用，并建议大批量遍历时用 `cursorMark`
分页，而不是很深的 `page` 偏移量。并发要保持低，长时间遍历要串行。

## 主要端点

### 1. 检索

```
GET /search?query={query}&format=json&pageSize={n}&resultType={type}
```

| 参数 | 默认值 | 说明 |
|---|---|---|
| `query` | 必填 | 见下面的查询语言。要做 URL 编码。 |
| `format` | `xml` | `json`、`xml` 或 `dc` |
| `resultType` | `lite` | `idlist`（只有 ID）、`lite`（核心书目信息）、`core`（增加摘要、全文链接、MeSH、资助信息） |
| `pageSize` | 25 | 上限 **1,000**。超出会被拒绝，而不是被截断——见下面的错误形态。 |
| `cursorMark` | `*` | 深分页——用这个，不要用 `page` |
| `page` | 1 | 从 1 开始。只适合浅分页。 |
| `sort` | relevance | `CITED desc`、`P_PDATE_D desc`（出版日期）、`TITLE asc`——注意方向词前是**空格**，不是冒号 |

**示例**——关于 CRISPR 的预印本：

```powershell
curl.exe -s --get "https://www.ebi.ac.uk/europepmc/webservices/rest/search" --data-urlencode 'query=CRISPR AND SRC:"PPR"' --data-urlencode 'format=json' --data-urlencode 'pageSize=2' --data-urlencode 'resultType=lite'
```

返回 `hitCount` 13341，`resultList.result[]` 各项的 `id` 形如 `PPR1283561`，
`source` 为 `PPR`。

**响应外层结构：**

```json
{
  "version": "6.9",
  "hitCount": 13341,
  "nextCursorMark": "AoIIQExCVyg1NTg2NjE3NQ==",
  "nextPageUrl": "https://www.ebi.ac.uk/europepmc/webservices/rest/search?...",
  "request": {"queryString": "CRISPR AND SRC:\"PPR\"", "resultType": "lite", "cursorMark": "*", "pageSize": 2},
  "resultList": {"result": [...]}
}
```

回显的 `request.queryString` 是**解析后**的查询——把它和你发出的查询做对比，
以便在信任 `hitCount` 之前发现被改写或被截断的查询。

**错误会以 HTTP 200 返回，且没有 `resultList`。** `pageSize=1001` 返回：

```json
{"errCode": 404, "errMsg": "Invalid page size provided. Valid size is between 1 and 1000"}
```

注意 `errCode` 是 404，却*在 200 响应里*。在索引结果之前要检查 `errCode` / `resultList`
是否存在——HTTP 状态码和异常都不会告诉你出错。

### 2. 全文 XML

```
GET /{PMCID}/fullTextXML
```

```
https://www.ebi.ac.uk/europepmc/webservices/rest/PMC7029759/fullTextXML
```

返回 JATS `<article>`（不像 eFetch 那样包在 `<pmc-articleset>` 里）。把它管道传给
`scripts/jats_to_text.py`，该脚本两种外层包装都能处理。

**404 表示不是开放获取**——在 PMC1500000 上验证过，正是 eFetch 返回 200 但没有 `<body>`
的那篇论文。这里的 404 是诚实的答案，所以当你需要*确定*全文是否存在时，优先用这个端点。

### 3. 引文与参考文献

```
GET /{source}/{id}/citations?format=json&pageSize={n}&page={n}
GET /{source}/{id}/references?format=json&pageSize={n}&page={n}
```

`source` 是语料库代码：`MED`（PubMed）、`PMC`、`PPR`（预印本）、`PAT`（专利）、`AGR`、`CBA`、
`CTX`、`ETH`、`HIR`、`NBK`。

```
https://www.ebi.ac.uk/europepmc/webservices/rest/MED/32117569/citations?format=json&pageSize=1
```

返回 `hitCount` 以及 `citationList.citation[]`（或 `referenceList.reference[]`）。
两者都用各自语料库专属的键来包列表，所以要按端点分别解析，不要假定都是 `resultList`。

### 4. 文本挖掘词与补充文件

```
GET /{source}/{id}/textMinedTerms/{semanticType}?format=json
GET /{source}/{id}/supplementaryFiles
```

两者都是**按论文可选**的，论文没有时返回 **404**。这里的 404 表示“这篇论文没有这类数据”，
不是请求有问题——不要把它当成故障，也不要重试。

在 MED/32117569 上验证过：`resultType=core` 报告 `hasSuppl: "N"`，而 `supplementaryFiles`
返回 404，两者一致。先用一次 `core` 检索读出 `hasSuppl`，若为 `"N"` 就跳过这次调用；
`textMinedTerms` 没有对应的预检查，它对同一篇论文也返回 404。

## 查询语言

字段前缀词，用 `AND` / `OR` / `NOT`（大写）组合，支持引号短语和括号。

| 字段 | 匹配 | 示例 |
|---|---|---|
| `SRC` | 语料库 | `SRC:"PPR"`（预印本）、`SRC:"MED"`、`SRC:"PMC"` |
| `PUBLISHER` | 预印本服务器或出版商 | `PUBLISHER:"bioRxiv"`、`PUBLISHER:"medRxiv"` |
| `AUTH` | 作者姓名 | `AUTH:"Doudna J"` |
| `TITLE` | 标题 | `TITLE:"gene editing"` |
| `ABSTRACT` | 摘要 | `ABSTRACT:organoid` |
| `PUB_YEAR` | 出版年份 | `PUB_YEAR:2023`、`PUB_YEAR:[2020 TO 2024]` |
| `HAS_FT` | 已索引全文 | `HAS_FT:Y` |
| `OPEN_ACCESS` | 开放获取 | `OPEN_ACCESS:Y` |
| `IN_EPMC` | 全文托管在 Europe PMC | `IN_EPMC:Y` |
| `DOI` | DOI | `DOI:"10.1038/nature12373"` |
| `EXT_ID` | PMID | `EXT_ID:32117569` |
| `JOURNAL` | 期刊名 | `JOURNAL:"Nature"` |
| `MESH` | MeSH 词 | `MESH:"CRISPR-Cas Systems"` |
| `LANG` | 语言 | `LANG:eng` |

没有前缀的裸词会同时检索标题、摘要和全文。

**补齐预印本缺口的模式：**

```powershell
curl.exe -s --get "https://www.ebi.ac.uk/europepmc/webservices/rest/search" --data-urlencode 'query=(SRC:"PPR" AND PUBLISHER:"bioRxiv" AND "organoid")' --data-urlencode 'format=json&pageSize=2&resultType=lite'
```

`hitCount` 1972，每条命中结果的 `bookOrReportDetails.publisher` 都确认是 `bioRxiv`。
从这些结果里取出 `doi`（`10.1101/...` 形式的预印本 DOI），交给 bioRxiv API 获取
预印本专属元数据，比如已发表版本链接。

## 结果对象（resultType=core，关键字段）

```json
{
  "id": "37917583",
  "source": "MED",
  "pmid": "37917583",
  "pmcid": "PMC10680139",
  "doi": "10.1016/j.celrep.2023.113339",
  "title": "...",
  "authorString": "Smith J, Jones A.",
  "journalInfo": {"volume": "42", "journal": {"title": "Cell reports"}},
  "pubYear": "2023",
  "abstractText": "...",
  "isOpenAccess": "Y",
  "inEPMC": "Y",
  "hasPDF": "Y",
  "hasSuppl": "Y",
  "citedByCount": 14,
  "fullTextUrlList": {"fullTextUrl": [{"documentStyle": "pdf", "url": "..."}]}
}
```

**这些类布尔字段是字符串 `"Y"` / `"N"`，不是 JSON 布尔值。** 真值判断对 `"N"` 也会通过，
所以要用显式比较。论文不在 PMC 时，`pmcid` 是缺失，而不是 null。

预印本（`SRC:"PPR"`）记录的结构不同：服务器名在
`bookOrReportDetails.publisher` 里，`journalInfo` 缺失。不要假定所有语料库用同一套 schema。

## 标识符

每条结果都带 `id` + `source`，这个**组合**才是键——单独的 `id` 跨语料库并不唯一。
接收论文路径的端点需要 `{source}/{id}`，如 `MED/32117569`。预印本 ID 带 `PPR` 前缀
（`PPR1283561`），是 Europe PMC 自己的编号，不是 bioRxiv 的；用记录里的 `doi` 做交叉引用。

## 分页与计数核对

1. 首个响应里的 `hitCount` 就是总数。
2. 用 `cursorMark=*` 发起请求，之后每次调用都传入上一次返回的 `nextCursorMark`。
3. **当 `resultList.result` 为空，或 `nextCursorMark` 等于你发出的游标时，就停止。** 这里
   没有 null 终止符：遍历到底时 Europe PMC 返回空结果列表并把你的游标原样回显。因此
   探测结束要多花一次空请求——这是预期行为，不是故障。
4. 用取回的条数和 `hitCount` 核对，并把两者都报告出来。

验证过的遍历（`AUTH:"Doudna J" AND PUB_YEAR:2013 AND SRC:"MED"`，`pageSize=5`）：每页 5、5、5、4
条，然后第 5 次请求返回 0 条、游标不变。取回 19 条，`hitCount` 19。

`scripts/paginate.py --api europepmc` 实现了这套逻辑，包括游标重复的停止条件。

很深的 `page` 偏移量会退化且被限制上限；超过几页的遍历，受支持的路径是 `cursorMark`。
