# BioStudies

EMBL-EBI 的档案库，存放生命科学研究的数据产出：既有托管在此的文件，也有指向 ArrayExpress、BioImages、ENA 等档案库的外链。用户想要*论文背后的数据集*、BioStudies accession（`S-BSST…`、`S-EPMC…`、`S-CMO…`、`E-MTAB…`），或者“EBI 里的补充数据”时用它。它不是论文索引。

先在 PubMed / Europe PMC 找到论文，再带着 accession 或研究记录里出现的关键词来这里。

下面所有数字均为 2026-09-10 实测。

## 基础 URL

```
https://www.ebi.ac.uk/biostudies/api/v1
```

## 认证

无。

## 限流

没有公布每秒上限。串行请求。EBI 要求合理使用。

## 核心端点

### 1. 检索研究

```
GET /search?query={text}&page={n}&pageSize={n}
```

```
GET /search?query=organoid&pageSize=2
```

实测：HTTP 200，返回如下字段

| 字段 | 本次调用的值 | 含义 |
|---|---|---|
| `page` | 1 | 从 1 开始计数 |
| `pageSize` | 2 | |
| `totalHits` | 4195，稍后一次调用是 4480 | **近似值** |
| `isTotalHitsExact` | `false` | 不要像对待 Europe PMC 的 `hitCount` 那样去对照 |
| `nextCursor` | `null` | 用 `page=` 翻页，不是游标 |
| `hits` | 2 条研究摘要 | |

一条 hit 包含 `accession`、`type`（`study`）、`title`、`author`、`files`（计数）、`release_date`、`isPublic`、`content`（压平的文本块）。`author` 可能是空字符串。

相隔几秒的两次调用之间，`totalHits` 就变动了几百，而 `isTotalHitsExact` 一直是 false。报告时写“约 N 项研究”并附上你取的那一页。不要声称对着这个数字完成了完整遍历。

第 2 页（`page=2&pageSize=2`）返回了不同的 accession，`nextCursor` 仍是 `null`。不断递增 `page`，直到 `hits` 为空。

### 2. 单条研究

```
GET /studies/{accession}
```

```
GET /studies/S-CMO2844
```

实测：HTTP 200。响应体**不是**搜索 hit 的那种结构：

```json
{
  "accno": "S-CMO2844",
  "type": "submission",
  "attributes": [{"name": "Title", …}, {"name": "ReleaseDate", …}],
  "section": { "type": "Study", "accno": "s1", "attributes": […], "subsections": […] }
}
```

标题在 `attributes` 里（name 为 `Title`），不在 `title`。文件和链接嵌套在 `section.subsections` 底下。顺着这棵树走；不要指望顶层有 `files: [ …urls ]`。

404 表示没有这个公开 accession。

## 典型工作流

1. 用论文标题、accession 或生物学关键词检索。
2. 从 `hits[]` 取出 `accession`。
3. `GET /studies/{accession}` 拿到 submission 树和文件列表。
4. 引用 accession 和 BioStudies URL（`https://www.ebi.ac.uk/biostudies/studies/{accession}`）。
5. 如果用户其实要的是论文，带着标题或研究 attributes 里的 DOI 回到 PubMed / Europe PMC。

## 失败模式

| 你做了什么 | 会发生什么 | 该怎么办 |
|---|---|---|
| 把 `totalHits` 当成精确值 | 计数会漂移；`isTotalHitsExact` 是 false | 写“约 N”；不要按 exit-4 去对照 |
| 在 `/studies/{acc}` 上指望有搜索那套字段 | 没有 `title`，也没有 `files` 计数 | 去读 `attributes` 和 `section` |
| 把 BioStudies 当成 PubMed 用 | 这里是研究，不是论文 | 先查文献 API |
| 等 `nextCursor` | 它一直是 `null` | 用 `page` |
