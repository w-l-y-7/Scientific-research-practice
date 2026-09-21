# PMC (PubMed Central)

PMC 是生物医学与生命科学论文的**全文仓储**。它和 PubMed 相互独立——PubMed 有引文和摘要，PMC 有全文。并非所有 PubMed 论文都在 PMC 里，反之亦然。

## 用于 PMC 的 E-utilities

### 基础 URL

```
https://eutils.ncbi.nlm.nih.gov/entrez/eutils/
```

与 PubMed 相同的 E-utilities，但用 `db=pmc`。

### eSearch——检索 PMC

```
GET /esearch.fcgi?db=pmc&term={query}&retmode=json
```

参数与 PubMed eSearch 相同。返回 PMC UID（数字，如 `13033346`）。要得到 PMCID，需要在前加 "PMC"（如 `PMC13033346`）。

### eFetch——获取全文 XML

```
GET /efetch.fcgi?db=pmc&id={pmcid}&retmode=xml
```

| rettype | retmode | 返回 |
|---------|---------|---------|
| *（省略）* | `xml` | JATS XML——**只有开放获取论文**才给全文；否则只给元数据，且不报错。使用前先看下面的陷阱。 |
| `medline` | `text` | MEDLINE 格式 |

**示例：**
```
https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pmc&id=7029759&retmode=xml
```

该 XML 采用 JATS（Journal Article Tag Suite）格式：
- `<front>`——期刊元数据、论文元数据、作者信息
- `<body>`——论文全文，含 `<sec>` 章节、`<p>` 段落、`<fig>` 图
- `<back>`——`<ref-list>`，含全部参考文献

只传数字 ID（不要传 "PMC7029759"，只传 "7029759"）。

### 陷阱：对于非 OA 论文，eFetch 返回只有元数据的 XML，HTTP 状态码却是 200

这是本技能里最危险的失败，因为响应里没有任何地方说明它失败了。
当出版商不允许再分发 XML 时，eFetch 会返回一个**结构完整的
`<pmc-articleset>`**，里面只有 `<front>` 元数据、**没有 `<body>`**，失败原因写在一段 XML
*注释*里——而所有标准解析器都会丢弃注释。2026-07-27 在 PMCID 1500000 上验证：

```
HTTP/1.1 200 OK

<pmc-articleset><article article-type="obituary" ...>
  <!--The publisher of this article does not allow downloading of the full text in XML form.-->
  <front>...</front>
</article></pmc-articleset>
```

如果一个 agent 取到这段 XML、解析它，然后报告“已获取全文”，那它其实只拿到了标题、期刊和作者列表。
**这是常见情况，不是边缘情况：** 通过 eFetch 取全文的范围仅限于约 300 万篇的 PMC Open Access Subset，
而 PMC 收录约 1000 万篇——所以你交给 eFetch 的绝大多数 PMCID 返回时都没有 body。

**在声称拿到全文之前，务必先确认 `<body>` 存在。** 有三种办法，按推荐程度排序：

1. **先查可用性**，用下面的 PMC OA Web Service。它能在你花掉这次请求之前告诉你有没有对应的包。
2. **用 `scripts/jats_to_text.py`**。当论文只有元数据时，它以 `no <body> element` 非零退出，
   并把出版商限制的那条注释暴露出来，而不是丢弃。
3. **退回到 Europe PMC**（`references/europepmc.md`）。对同一篇论文，它的 `fullTextXML` 端点返回
   干净的 **404**，而不是没有 body 的 200——诚实的失败比貌似成功的失败更好处理。

如果全文拿不到，就明确说明，并提供摘要（PubMed eFetch）或其他位置的 OA 副本（Unpaywall、CORE），
而不要把 `<front>` 元数据当作论文本身呈现。

## PMC OA Web Service——全文到底有没有？

它和 ID Converter 不是一回事：它回答的是“这个 PMCID 有没有可下载的全文包”，
而这正是上面那个 eFetch 陷阱要求你事先知道的事。

```
GET https://www.ncbi.nlm.nih.gov/pmc/utils/oa/oa.fcgi?id={pmcid}
```

返回 XML（没有 JSON 选项）。2026-07-27 验证：

```xml
<OA><records returned-count="1" total-count="1">
  <record id="PMC7029759" citation="F1000Res. 2020 Feb 7; 9:72" license="CC BY" retracted="no">
    <link format="tgz" updated="2024-04-23 12:25:15"
          href="ftp://ftp.ncbi.nlm.nih.gov/pub/pmc/oa_package/e5/c9/PMC7029759.tar.gz"/>
  </record>
</records></OA>
```

要区分这两种失败码——它们含义不同，而且都伴随 **HTTP 200** 返回：

| 响应 | 含义 |
|---|---|
| 带 `<record>` 和 `<link>` 的 `<records>` | 在 OA Subset 中；全文可以取到 |
| `<error code="idIsNotOpenAccess">` | 论文存在，但**不在** OA Subset 中——eFetch 只会返回元数据。这种情况应转去 Europe PMC 或 Unpaywall。 |
| `<error code="idDoesNotExist">` | 没有这个 PMCID。这是标识符有误，不是覆盖缺口——重新检查格式，或通过 ID Converter 转换。 |

值得留意的单条记录属性：

| 属性 | 为什么重要 |
|---|---|
| `license` | 实际的重用条款（`CC BY`、`CC BY-NC` 等）。引用或再分发文本时要报告它。 |
| `retracted` | `"no"` 或 `"yes"`。把已撤稿论文当作当前证据来综述是正确性错误，不是格式问题——引用前先检查。 |
| `citation` | 人类可读的引文字符串，便于溯源。 |

`format` 的取值是 `tgz`（论文 XML 加图）以及有时是 `pdf`。**`href` 是 FTP URL，
把协议换成 HTTPS 不管用**——`https://ftp.ncbi.nlm.nih.gov/pub/pmc/oa_package/...`
返回 404（2026-07-27 验证）。按原样使用 FTP URL，或者在本服务确认论文在子集里之后，
通过 HTTPS 从 eFetch / Europe PMC `fullTextXML` 取同样的 XML。

## BioC API——结构化全文

以结构化 passage 格式获取全文的另一条途径。

### 基础 URL

```
https://www.ncbi.nlm.nih.gov/research/bionlp/RESTful/pmcoa.cgi/
```

### 端点

```
GET /BioC_{format}/{id}/{encoding}
```

| 参数 | 取值 |
|-----------|--------|
| `format` | `json` 或 `xml` |
| `id` | PMID（如 `17299597`）或 PMCID（如 `PMC7029759`） |
| `encoding` | `unicode` 或 `ascii` |

**示例：**
```
https://www.ncbi.nlm.nih.gov/research/bionlp/RESTful/pmcoa.cgi/BioC_json/PMC7029759/unicode
```

**响应结构（JSON）：**
```json
{
  "source": "PMC",
  "documents": [{
    "id": "PMC7029759",
    "infons": {"license": "...", "doi": "..."},
    "passages": [
      {
        "offset": 0,
        "infons": {"section_type": "TITLE"},
        "text": "Article title..."
      },
      {
        "offset": 42,
        "infons": {"section_type": "ABSTRACT"},
        "text": "Abstract text..."
      },
      {
        "offset": 500,
        "infons": {"section_type": "INTRO"},
        "text": "Introduction text..."
      }
    ]
  }]
}
```

章节类型：`TITLE`、`ABSTRACT`、`INTRO`、`METHODS`、`RESULTS`、`DISCUSS`、`CONCL`、`REF`、`SUPPL`、`FIG`、`TABLE`

**覆盖范围：** PMC Open Access Subset 中约 300 万篇论文。

## PMC ID Converter API

在 PMID、PMCID、DOI 和 Manuscript ID 之间转换。

### 基础 URL

```
https://pmc.ncbi.nlm.nih.gov/tools/idconv/api/v1/articles/
```

### 参数

| 参数 | 必填 | 说明 |
|-----------|----------|-------------|
| `ids` | 是 | 最多 200 个逗号分隔的 ID |
| `idtype` | 否 | `pmcid`、`pmid`、`mid`、`doi`（默认：自动识别） |
| `format` | 否 | `json`、`xml`、`csv`（默认：xml） |
| `tool` | 建议 | 你的应用名 |
| `email` | 建议 | 你的联系邮箱 |

**示例：**
```
https://pmc.ncbi.nlm.nih.gov/tools/idconv/api/v1/articles/?ids=PMC7029759&format=json
```

**响应：**
```json
{
  "status": "ok",
  "records": [{
    "pmcid": "PMC7029759",
    "pmid": "32117569",
    "doi": "10.12688/f1000research.22211.2"
  }]
}
```

只返回在 PMC 中的论文结果。如果论文在 PubMed 但不在 PMC，就不会返回 PMCID。

## 限流

| 服务 | 限制 |
|---------|-------|
| E-utilities（`db=pmc`） | 无 key 时每秒 3 次，有 key 时每秒 10 次 |
| BioC API | 遵循 NCBI 通用政策（无 key 时每秒 3 次） |
| ID Converter | 遵循 NCBI 通用政策 |

E-utility 请求要带 `tool` 和 `email` 参数。大批量任务应避开高峰时段（周一至周五 5AM–9PM ET）。
