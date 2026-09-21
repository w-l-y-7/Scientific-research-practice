# PubTator3

NCBI 在 PubMed 摘要（以及部分 PMC 全文）上做文本挖掘得到的注释：基因、疾病、化学物质、物种、变异和细胞系，外加带类型的关系。当用户想要*论文中的实体*，或者提到某个规范化实体（`@CHEMICAL_remdesivir`）的论文时用它；用户想要引文列表时不要用。

Europe PMC 的 `/textMinedTerms` 是更简薄的逐篇替代方案。PubMed 检索不会把 "remdesivir" 规范化成概念 ID。PubTator3 API **不是**旧的 PubTator / `CBBresearch` 端点。

下文所有数据核实于 2026-09-10。

## 基础 URL

```
https://www.ncbi.nlm.nih.gov/research/pubtator3-api
```

文档：https://www.ncbi.nlm.nih.gov/research/pubtator3/api

## 认证

无。

## 限流

每秒不超过 **3 个请求**。串行发送。批量注释导出请用 FTP 站点（`https://ftp.ncbi.nlm.nih.gov/pub/lu/PubTator3/`），不要走 API。

## 关键端点

### 1. 把提及解析为实体 ID

```
GET /entity/autocomplete/?query={text}&concept={type}&limit={n}
```

`concept` 可选（`chemical`、`disease`、`gene`、`species`、`variant`、`cellline`）。

```
GET /entity/autocomplete/?query=remdesivir&limit=3
```

返回一个 JSON 数组。首个命中项（已核实）：

```json
{
  "_id": "@CHEMICAL_remdesivir",
  "biotype": "chemical",
  "db_id": "C000606551",
  "db": "ncbi_mesh",
  "name": "remdesivir"
}
```

用 `_id`（`@CHEMICAL_remdesivir`）检索，不要用显示名。相近的同义词（`@CHEMICAL_GS_441524_triphosphate`）是不同的实体。

### 2. 按文本、实体或关系检索论文

```
GET /search/?text={query}&page={n}
```

`text` 可以是自由文本、`@TYPE_name` 实体 ID、布尔组合或关系：

```
@CHEMICAL_Doxorubicin AND @DISEASE_Neoplasms
relations:ANY|@CHEMICAL_Doxorubicin|@DISEASE_Neoplasms
relations:ANY|@CHEMICAL_Doxorubicin|DISEASE
```

```
GET /search/?text=@CHEMICAL_remdesivir
```

已核实：`count` 23295，`page_size` 10，`current` 1，`total_pages` 2330，`results` 长度 10。首个结果的 `pmid` 是**整数**（`37711410`）；`_id` 是字符串。用 `page` 翻页（从 1 开始）。没有游标。

不要把它当作通用的 PubMed 替代品。它的排序以实体为中心。

### 3. 导出 PMID 的注释

```
GET /publications/export/{format}?pmids={id,id}&full={true|false}
```

`format` 为 `pubtator`、`biocxml` 或 `biocjson`。`full=true`（PMC 全文）只对 `biocxml` / `biocjson` 有效。

```
GET /publications/export/biocjson?pmids=29355051
```

这个 JSON **不是**裸的 BioC 文档。它是：

```json
{ "PubTator3": [ { "_id": "29355051|None", "id": "29355051", "passages": [...], "relations": [...] } ] }
```

在 PMID 29355051 上核实：一个文档，两个 passage，第一个 passage 有 5 条注释。一条注释形如：

```json
{
  "infons": {
    "type": "Species",
    "database": "ncbi_taxonomy",
    "normalized_id": 112863,
    "biotype": "species"
  },
  "text": "Lycium barbarum",
  "locations": [{"offset": 14, "length": 15}]
}
```

读取 `PubTator3[0].passages[].annotations`。返回 200 且 `"PubTator3": []` 表示"没有文档"，不是可以忽略的传输成功。

### 4. 相关实体

```
GET /relations?e1={entityId}&type={relation}&e2={entity_type}
```

关系类型包括 `treat`、`cause`、`interact`、`associate`、`positive_correlate`、`negative_correlate`、`prevent`、`inhibit`、`stimulate`、`drug_interact`。`e1` 必须是 autocomplete 的 `_id`。

## 典型工作流

1. 对用户的字符串做 autocomplete → 得到 `@CHEMICAL_…` / `@DISEASE_…`。
2. 用该 ID 检索（如果用户问的是"X 治疗什么？"，还要带上关系）。
3. 对将要报告的 PMID 导出 `biocjson`，并列出注释。
4. 论文本身（摘要、OA PDF）去 PubMed / Europe PMC / Unpaywall 取。PubTator 不是全文库。

## 失败模式

| 你的操作 | 会发生什么 | 怎么办 |
|---|---|---|
| 把导出的 JSON 当作 BioC 根节点解析 | 顶层没有 `passages` | 往下进到 `PubTator3` |
| 检索 `remdesivir`，并把命中项当作精确化学物质的论文 | 那是关键词检索，不是概念检索 | 先 autocomplete，再检索 `@CHEMICAL_remdesivir` |
| 调用旧的 `pubtator-api` 或 `CBBresearch` URL | 可能仍返回 200，但接口契约已经变了 | 用 `pubtator3-api` |
| `format=pubtator` 时传 `full=true` | 拿不到全文 | 用 `biocjson` 或 `biocxml` |
| 并发扇出 | 很容易超过 3 req/s | 串行发送 |
