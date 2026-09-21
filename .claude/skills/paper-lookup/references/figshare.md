# Figshare

综合性研究仓库（图、数据集、海报、论文、媒体）。用户提到 Figshare 或 `figshare.com` 的 DOI，或者想把文件存缴到那里时，用它。它不是期刊索引。要期刊 OA PDF 用 Unpaywall；要 EBI 托管的研究数据包用 BioStudies；要 CERN 风格的软件存缴优先用 Zenodo。

下面所有数字均为 2026-09-10 实测。

## 基础 URL

```
https://api.figshare.com/v2
```

文档：https://docs.figshare.com/v2/

## 认证

公开的论文元数据不需要 token。私有记录、上传和账户相关端点需要（`Authorization: token ACCESS_TOKEN`）。本技能只用公开路由。

## 限流

API 站点上有文档；交互式使用时远低于上限即可。串行请求。

## 核心端点

### 1. 检索 —— 用 POST，不是 GET

```
POST /v2/articles/search
Content-Type: application/json

{"search_for": "CRISPR", "page": 1, "page_size": 10}
```

实测：HTTP 200，一个**裸 JSON 数组**（没有 `total`，也没有 `hits` 包装）。第一条 hit 是 CRISPR 的补充数据集（`defined_type_name: dataset`）。

响应体里没有计数，这次调用也没有可用的 `Link`/`X-Count` 头。靠 `page` 翻页，直到某页返回的条数少于 `page_size` 或为空。不要凭空编一个 total。

**GET 不是检索。** 这个陷阱会让你自信地报出一篇错误的论文：

```
GET /v2/articles?search_for=CRISPR&page_size=1
```

实测：HTTP 200，返回一篇论文，标题 *Social capital in the workplace…*，DOI `10.1016/j.labeco.2007.07.006`。查询字符串被忽略；你只是在列举论文。如果用户要的是 CRISPR，而你用了 GET，你会带着 200 报出一个错的对象。

### 2. 单篇论文

```
GET /v2/articles/{id}
```

```
GET /v2/articles/12345
```

实测：HTTP 200，返回 `id`、`title`、`doi`、`defined_type_name`、`url`、authors、files、license。检索之后用它，或者用户已经有一个 Figshare id 时用它。

文件在公开时会出现在 article 对象上。404 要么是没有这个 id，要么是你无权读取的记录（API 对这两种情况都用 404）。

## 典型工作流

1. 带 JSON body 调 `POST /articles/search`。
2. 从每个元素里读 `id`、`title`、`doi`、`defined_type_name`。
3. 只有需要文件或更完整的记录时才 `GET /articles/{id}`。
4. 如果用户要的是*关于*某主题的论文，去 OpenAlex / PubMed。Figshare 检索是仓库检索。

## 失败模式

| 你做了什么 | 会发生什么 | 该怎么办 |
|---|---|---|
| `GET /articles?search_for=…` | HTTP 200，一批不相关的、大致是最新的论文 | 用 POST `/articles/search` |
| 指望拿到 `{hits: …, total: N}` | 一个裸数组 | 把 `[]` 当空；没有 total 可对照 |
| 把一条 Figshare hit 报成期刊论文 | `defined_type_name` 可能是 dataset、figure、media | 读出来并报告类型 |
