# arXiv API

arXiv 是预印本服务器，涵盖物理学、数学、计算机科学、定量生物学、定量金融、统计学、电气工程和经济学。

**重要：** arXiv API 返回的是 **Atom XML**，不是 JSON。没有 JSON 选项。

## 基础 URL

```
https://export.arxiv.org/api/query
```

## 认证

无需认证。完全公开。

## 查询参数

```
GET https://export.arxiv.org/api/query?search_query={query}&start={n}&max_results={n}
```

| 参数 | 是否必填 | 默认值 | 说明 |
|-----------|----------|---------|-------------|
| `search_query` | 是* | -- | 用字段前缀 + 布尔运算符检索 |
| `id_list` | 是* | -- | 逗号分隔的 arXiv ID（例如 `2103.15348,2005.14165`） |
| `start` | 否 | 0 | 分页偏移量（从 0 开始） |
| `max_results` | 否 | 10 | 每次请求返回的结果数（最大 2000；绝对上限 30000） |
| `sortBy` | 否 | `relevance` | `relevance`、`lastUpdatedDate`、`submittedDate` |
| `sortOrder` | 否 | `descending` | `ascending` 或 `descending` |

*`search_query` 和 `id_list` 至少要提供一个。两者可以组合使用（取交集）。

## 检索字段前缀

| 前缀 | 检索范围 |
|--------|----------|
| `ti:` | 标题 |
| `au:` | 作者 |
| `abs:` | 摘要 |
| `co:` | 评论 |
| `jr:` | 期刊引用 |
| `cat:` | 学科分类 |
| `rn:` | 报告号 |
| `all:` | 所有字段 |

## 布尔运算符

- `AND` —— 同时满足两个条件
- `OR` —— 满足任一条件
- `ANDNOT` —— 排除
- 括号用于分组（URL 编码为 `%28` / `%29`）
- 引号包裹的短语（URL 编码为 `%22`）

## 查询示例

**检索所有字段：**
```
https://export.arxiv.org/api/query?search_query=all:transformer+attention&max_results=5
```

**作者 + 分类：**
```
https://export.arxiv.org/api/query?search_query=au:hinton+AND+cat:cs.LG&max_results=10
```

**标题检索：**
```
https://export.arxiv.org/api/query?search_query=ti:%22attention+is+all+you+need%22
```

**按 ID 查询：**
```
https://export.arxiv.org/api/query?id_list=2103.15348
```

**多个 ID：**
```
https://export.arxiv.org/api/query?id_list=2103.15348,2005.14165,1706.03762
```

**日期范围** —— 方括号**必须**做百分号编码，写成 `%5B` / `%5D`：
```
https://export.arxiv.org/api/query?search_query=cat:cs.AI+AND+submittedDate:%5B202401010000+TO+202412312359%5D
```

把字面量 `[` 和 `]` 传给 `curl`，请求还没发出去就失败了：curl 把它们当作通配范围，直接退出 **3**（`bad range specification`），没有任何输出，也没有 HTTP 状态码可供排查。2026-07-27 验证：

```bash
# 退出码 3，什么都没抓到，也没有错误响应体可读
curl.exe -s "https://export.arxiv.org/api/query?search_query=submittedDate:[202401010000+TO+202401020000]"

# 退出码 0，totalResults 为 35 —— 两种改法都可行
curl.exe -s  "https://export.arxiv.org/api/query?search_query=cat:cs.AI+AND+submittedDate:%5B202401010000+TO+202401020000%5D"
curl.exe -sg "https://export.arxiv.org/api/query?search_query=cat:cs.AI+AND+submittedDate:[202401010000+TO+202401020000]"
```

优先用编码后的形式，而不是 `curl -g`：编码形式才是 API 期望的输入，而且复制到抓取工具、Python 客户端或非 curl 的 shell 里都能用。时间戳是 UTC 的 `YYYYMMDDHHMM` 格式，范围两端都包含。

## 响应格式（Atom XML）

```xml
<feed xmlns="http://www.w3.org/2005/Atom">
  <opensearch:totalResults>1234</opensearch:totalResults>
  <opensearch:startIndex>0</opensearch:startIndex>
  <opensearch:itemsPerPage>10</opensearch:itemsPerPage>

  <entry>
    <id>http://arxiv.org/abs/1706.03762v7</id>   <!-- 这里是 http，而下面的链接是 https -->
    <title>Attention Is All You Need</title>
    <summary>The dominant sequence transduction models are based on...</summary>
    <published>2017-06-12T17:57:34Z</published>
    <updated>2023-08-02T00:00:12Z</updated>
    <author><name>Ashish Vaswani</name></author>
    <author><name>Noam Shazeer</name></author>
    <!-- 更多作者 -->
    <category term="cs.CL" scheme="http://arxiv.org/schemas/atom"/>
    <arxiv:primary_category term="cs.CL"/>
    <link rel="alternate" type="text/html" href="https://arxiv.org/abs/1706.03762v7"/>
    <link rel="related" type="application/pdf" title="pdf" href="https://arxiv.org/pdf/1706.03762v7"/>
    <arxiv:comment>15 pages, 5 figures</arxiv:comment>
    <!-- <arxiv:doi> 和 <arxiv:journal_ref> 只在作者登记过时才出现。
         1706.03762 两者都没有。 -->
  </entry>
</feed>
```

### 每个 entry 的关键 XML 元素

| 元素 | 说明 |
|---------|-------------|
| `<id>` | arXiv URL：`http://arxiv.org/abs/{id}` |
| `<title>` | 论文标题 |
| `<summary>` | 摘要 |
| `<published>` | 首次提交日期（ISO 8601） |
| `<updated>` | 最新版本日期 |
| `<author><name>` | 每位作者一个 |
| `<category term="...">` | 学科分类 |
| `<arxiv:primary_category>` | 主分类 |
| `<link rel="alternate">` | 摘要页 URL |
| `<link rel="related" title="pdf">` | PDF URL |
| `<arxiv:doi>` | **期刊** DOI，且只在作者登记过时才有 —— 见下文 |
| `<arxiv:comment>` | 作者评论 |
| `<arxiv:journal_ref>` | 期刊引用，同样是有条件出现 |

### `<arxiv:doi>` 不是 arXiv DOI

`<arxiv:doi>` 里装的是*已发表期刊版本*的 DOI（如 `10.1103/PhysRevD.50.43`）。对于从未发表、或作者从未登记的预印本，这个元素**不存在**。2026-07-27 验证：`id_list=1706.03762`（"Attention Is All You Need"）返回的结果里**完全没有** `<arxiv:doi>` 元素。

arXiv 也会自己生成 DOI，惯例是 `10.48550/arXiv.{id}`，但 **API 从不返回它**，而且自己拼出来的 DOI 只在部分场合能用。2026-07-27 对 `1706.03762` 的验证结果：

| 把 `10.48550/arXiv.1706.03762` 发到 | 结果 |
|---|---|
| `doi.org` | **200** —— 能解析 |
| Crossref `/works/10.48550%2FarXiv.1706.03762` | **404** `Resource not found` —— 它是 DataCite DOI，没有在 Crossref 注册 |
| OpenAlex `/works/doi:10.48550/arXiv.1706.03762` | **404**，而且 `filter=doi:...` 返回 `count: 0` |

OpenAlex 查不到不是大小写的问题 —— `doi:10.48550/arxiv.2102.05095` 和 `doi:10.48550/arXiv.2102.05095` 都返回 200，说明查询不区分大小写，而且对很多 arXiv 预印本*确实*有效。问题在于**在 OpenAlex 里不是每篇 arXiv 论文都挂在 `10.48550` 这个 DOI 下**：OpenAlex 把 "Attention Is All You Need" 存为 `W2626778328`，DOI 是 `10.65215/2q58a426`，arXiv 现在也在用这个前缀。

所以，不要把拼出来的 arXiv DOI 当成到处都能用的标识符，也不要把它返回的 404 报告成"论文未找到"。改用 **arXiv ID** 交叉查询 —— Semantic Scholar 的 `ARXIV:{id}` 前缀（见 `references/semantic-scholar.md`）—— 或者用标题检索，这些都不行之后再回退到拼出来的 DOI。

## 解析技巧

用 `scripts/arxiv_atom.py`，不要自己重新推导解析逻辑：

```bash
curl.exe -s "https://export.arxiv.org/api/query?id_list=1706.03762" | python scripts/arxiv_atom.py -
```

它为每个 entry 输出一条 JSON 记录（`arxiv_id`、`version`、`title`、`abstract`、`authors`、`categories`、`doi`、`pdf_url`、各种日期），再加上 feed 的 `total_results`。命名空间和下面这些坑它都已经处理好了。

如果你确实要自己解析：命名空间是 `http://www.w3.org/2005/Atom`，arXiv 的扩展在 `http://arxiv.org/schemas/atom`。有四个地方会坑人：

- **feed 自己也有 `<link>`。** 第一个 `<entry>` 之前有一个 `<link
  type="application/atom+xml">`，指回查询本身。取"第一个 `<link>`"拿到的是查询 URL，不是论文。要用 `rel`/`type` 匹配：摘要页是 `rel="alternate"
  type="text/html"`，PDF 是 `rel="related" type="application/pdf" title="pdf"`。
- **同一个响应里 URL 协议不一致。** 2026-07-27 在 `id_list=1706.03762` 上验证：entry 的 `<id>` 是 `http://arxiv.org/abs/1706.03762v7`，而*同一批*页面的
  `<link href>` 却是 `https://arxiv.org/abs/...` 和 `https://arxiv.org/pdf/...`，feed 级的 `<id>` 又是 `https://arxiv.org/api/...`。不要对协议做字符串匹配或归一化 —— 取路径的最后一段。
- **ID 带版本后缀。** 是 `1706.03762v7`，不是 `1706.03762`。和 DOI、Semantic Scholar 的 `ARXIV:` 查询、或用户给的 ID 比对之前，先去掉结尾的 `vN`。
- **`<title>` 和 `<summary>` 是硬换行的**，句子中间会插进换行和连续空格。显示或比对之前先把空白折叠掉。

## 失败模式

以下情况都不是 HTTP 错误。全部于 2026-07-27 验证。

**未知的字段前缀会被静默改写成 `all:`。** `search_query=badfield:xyz` 不会报错 —— arXiv 会重新解释它，实际执行 `all:badfield:xyz`，返回一堆看起来合理、但根本不是你想要的查询结果。feed 自己的 `<title>` 会回显*实际执行*的查询：

```xml
<title>arXiv Query: search_query=all:badfield:xyz&amp;id_list=&amp;start=0&amp;max_results=1</title>
```

所以前缀写错一个字母（把 `au:` 写成 `author:`，把 `abs:` 写成 `abstract:`），就会把一次精准检索降级成全文检索，而且没有任何警告。只用上表里的前缀，并且在相信结果之前，拿 feed 的 `<title>` 和实际发出的查询对照一下。

**参数格式错误时，返回的"错误"伪装成了一条结果。** `start=notanumber` 返回 HTTP **200**、`<opensearch:totalResults>1</opensearch:totalResults>`，以及一个 `<entry>`：

```xml
<entry><title>Error</title><summary>start must be an integer</summary></entry>
```

读取 `totalResults` 得到 1、然后取 `entry[0]` 的 agent，会报告一篇标题为 "Error" 的论文。把任何 entry 当成论文之前，先检查有没有 `<title>Error</title>`。（`search_query` 和 `id_list` 都省略时确实返回 HTTP 400，同样带这个 Error entry。）

**限流响应不是 XML。** 超出限流后，arXiv 返回纯文本正文 `Rate exceeded.` —— 14 字节，没有 feed，也没有 Atom 外壳。它带着 HTTP **429** 到达；如果持续触发限流，连接会被直接断开（curl 报告 `HTTP=000`）。由于不带 `-f` 的 `curl -s` 不管状态码是什么都会打印正文，一条直接接给解析器的流水线会看到"第 1 行第 0 列语法错误"，读起来像是响应损坏，而不是节流问题。在断定 API 出故障之前，先检查状态码和原始字节；解决办法是等待，不是更用力地重试。

这很容易触发 —— 限流规则是每 **3** 秒一次请求 —— 而且**格式错误的请求比合法请求罚得更重**：2026-07-27 观察到，正常查询照常服务，而反复发送的 `start=notanumber` 请求被限流超过 30 分钟。arXiv 拒绝过的请求不要重试，先把它改对。

**真正查不到是无提示且正常的：** `totalResults` 为 0，`<entry>` 元素也为零。`id_list` 里放一个不存在的 arXiv ID 也是同样表现 —— `id_list=9999.99999` 返回 `totalResults` 0，没有 entry，没有错误。这种情况要报告为"arXiv 中未找到"，而不是请求失败。

`scripts/arxiv_atom.py` 遇到 Error entry 时会以非零码退出，并报告被回显的查询，这样被改写的前缀就会暴露出来，而不是悄无声息地滑过去。

## 常用分类

| 分类 | 领域 |
|----------|-------|
| `cs.AI` | 人工智能 |
| `cs.CL` | 计算与语言（NLP） |
| `cs.CV` | 计算机视觉 |
| `cs.LG` | 机器学习 |
| `stat.ML` | 机器学习（统计学） |
| `q-bio` | 定量生物学 |
| `physics` | 物理学（所有子分类） |
| `math` | 数学（所有子分类） |
| `econ` | 经济学 |
| `eess` | 电气工程与系统科学 |

完整列表：https://arxiv.org/category_taxonomy

## 限流

- **每 3 秒 1 次请求**（硬性限制）
- 同一时间只允许单个连接
- 搜索结果每天缓存一次 —— 同一查询在 24 小时内不会看到新结果
- 批量数据请改用 OAI-PMH 接口
