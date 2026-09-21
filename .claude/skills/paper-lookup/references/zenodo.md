# Zenodo

CERN 的综合性研究仓库：论文、预印本、软件、数据集、演示文稿和海报，每一条都有 DataCite DOI（`10.5281/zenodo.…`）。用户想要的是存缴记录或文件、而不是期刊论文索引时，用它。要期刊 OA PDF 用 Unpaywall。要 EBI 托管的生物学数据集，先试 BioStudies。

下面所有数字均为 2026-09-10 实测。

## 基础 URL

```
https://zenodo.org/api
```

文档：https://developers.zenodo.org/

## 认证

**已发布的记录是公开的。** `GET /api/records` 不需要 token 就能用。

存缴 / 发布（`/api/deposit/depositions`）需要个人访问 token，不在本技能范围内。没有 token 时该路径返回 HTTP **403** `Permission denied.`（不一定是 401）。不要从文献检索流程里启动存缴。

## 限流

没有公布每秒上限。保持礼貌；长时间遍历要串行。

## 核心端点

### 1. 检索已发布记录

```
GET /api/records?q={elasticsearch}&type={type}&size={n}&page={n}
```

`q` 是 Elasticsearch 语法。`type` 按 Invenio 资源类型过滤（`publication`、`software`、`dataset`、`image`、`poster`、`presentation`、`video`、`other`）。默认搜索把它们全都混在一起。

```
GET /api/records?q=CRISPR+organoid&size=2
```

实测：HTTP 200，`hits.total` 为 3499，两条 hit。第一条是 SSRN 的 *publication*（论文），不是数据集。始终要看 `metadata.resource_type`。

```
GET /api/records?q=scanpy&type=software&size=2
```

实测：`hits.total` 为 40；两条 hit 的 `resource_type.type` 都是 `software`。

响应结构：

```json
{
  "hits": { "total": 3499, "hits": [ { "id": …, "doi": …, "metadata": {…}, "files": […], "links": {…} } ] },
  "links": { "self": "…", "next": "…" }
}
```

用 `page`（从 1 开始）和 `size` 翻页。`links.next` 存在时跟着它走。

### 2. 按 id 或 DOI 取单条记录

```
GET /api/records/{id}
GET /api/records?q=doi:10.5281/zenodo.{id}
```

**要跟随重定向。** concept（父）记录 id 会 302 跳到最新版本：

```
GET /api/records/3246410
  -> 302  Location: /api/records/3246411
GET /api/records/3246411   （curl.exe -L 之后）
  -> 200  id=3246411
          doi=10.5281/zenodo.3246411          # 本版本
          conceptdoi=10.5281/zenodo.3246410   # 全部版本
          conceptrecid=3246410
```

不带 `-L` 的 `curl` 返回的是 HTML “Redirecting…”，JSON 解析会失败。用 `-L`，然后两个 DOI 都要报告：version DOI 是你实际取到的那个文件；concept DOI 是稳定的、可引用全部版本的 id。

文件（若有）在 `files[]` 里，下载 URL 在 `links` 下。一条记录可以已经发布，却仍然没有可下载的文件。

## 典型工作流

1. 用 `q` 检索，如果用户说的是软件、数据或海报，再加上 `type`。
2. 从 `hits.hits[]` 取 `id` / `doi`。
3. 带 `-L` 执行 `GET /api/records/{id}`，拿到文件和 concept/version 这一对。
4. 如果用户要的是期刊 PDF，停下来，用论文的 DOI 去查 Unpaywall，不要去爬 Zenodo 落地页。

## 失败模式

| 你做了什么 | 会发生什么 | 该怎么办 |
|---|---|---|
| 检索时不带 `type` | 软件、数据和论文混在一起 | 加 `type=` 过滤，或报告资源类型 |
| `GET /records/{conceptrecid}` 不带 `-L` | HTTP 302 + HTML | 跟随重定向；两个 DOI 都记录 |
| 以为存缴文档里的认证是必需的 | 你去向用户要 token 来*检索* | 检索是公开的 |
| 把你下载的文件引成了 `10.5281/zenodo.{concept}` | Concept DOI 代表所有版本 | 溯源信息里用 version DOI |
