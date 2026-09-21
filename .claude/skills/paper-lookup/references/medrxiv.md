# medRxiv API

medRxiv 是健康科学预印本服务器。它的 API 和 bioRxiv 完全一样 —— 相同的端点、相同的响应格式 —— 只需把服务器参数换成 `medrxiv`。

**重要：** 和 bioRxiv 一样，这里也**没有关键词搜索**。要按关键词检索 medRxiv 内容，用 Semantic Scholar、OpenAlex 或 PubMed。

## 基础 URL

```
https://api.biorxiv.org
```

（基础 URL 和 bioRxiv 相同 —— 服务器在路径里指定。）

**要用 `api.biorxiv.org`，不要用 `api.medrxiv.org`。** `api.medrxiv.org` 这个主机能应答一部分路径，但和前者并不等价，而且它的失败方式很生硬（2026-07-27 实测）：

| 请求 | 结果 |
|---|---|
| `api.medrxiv.org/details/medrxiv/10d` | **HTTP 500**，响应体为空 |
| `api.medrxiv.org/details/medrxiv/2024-01-01/2024-01-03/0` | 200，但 `count: 60` —— 返回整个区间，无视文档写的每页条数，而且 `messages` 里少了 `category` |
| `api.biorxiv.org/details/medrxiv/2024-01-01/2024-01-03/0` | 200，`count: 30`，`messages` 块完整 |

下面每个示例都用 `api.biorxiv.org`。

## 认证

无需认证。完全公开的 API。

## 核心端点

### 1. 内容详情 —— 按日期范围浏览

```
GET /details/medrxiv/{interval}/{cursor}/{format}
```

| 参数 | 取值 | 说明 |
|-----------|--------|-------------|
| `interval` | `YYYY-MM-DD/YYYY-MM-DD` | 日期范围（含两端） |
| | `N`（整数） | 最近 N 篇预印本 |
| | `Nd`（整数 + "d"） | 最近 N 天 |
| `cursor` | 整数（默认 `0`） | 绝对记录偏移量。**`/details/` 每页返回 30 条，所以步长取 30** —— 见分页。 |
| `format` | `json`（默认）、`xml` | 响应格式 |

可选：`?category=cardiovascular%20medicine`（空格用 URL 编码）

**示例：**
```
https://api.biorxiv.org/details/medrxiv/2024-01-01/2024-01-31/0
https://api.biorxiv.org/details/medrxiv/5
https://api.biorxiv.org/details/medrxiv/10d
```

### 2. 内容详情 —— 按 DOI 查询

```
GET /details/medrxiv/{doi}/na/{format}
```

**示例：**
```
https://api.biorxiv.org/details/medrxiv/10.1101/2021.04.29.21256344/na/json
```

### 3. 已发表论文链接

```
GET /pubs/medrxiv/{interval}/{cursor}
GET /pubs/medrxiv/{doi}/na
```

把预印本关联到它们正式发表的期刊版本。预印本 DOI 和发表 DOI 都接受。

## 响应格式

和 bioRxiv 相同：

```json
{
  "messages": [{
    "status": "ok",
    "category": "all",
    "interval": "2024-01-01:2024-01-03",
    "funder": "all",
    "cursor": 0,
    "count": 30,
    "count_new_papers": "46",
    "total": "60"
  }],
  "collection": [{
    "title": "Paper title...",
    "authors": "Surname, A.; Surname, B.",
    "author_corresponding": "Full Name",
    "author_corresponding_institution": "Institution",
    "doi": "10.1101/2021.04.29.21256344",
    "date": "2021-05-03",
    "version": "1",
    "type": "PUBLISHAHEADOFPRINT",
    "license": "cc_by_nc_nd",
    "category": "cardiovascular medicine",
    "abstract": "Full abstract text...",
    "published": "10.1371/journal.pone.0256482",
    "server": "medRxiv"
  }]
}
```

## 分页

**`/details/` 每页 30 条，`/pubs/` 每页 100 条** —— 和 bioRxiv 相同，陷阱也一样是静默的：`cursor` 是绝对记录偏移量，步长不对的值照样返回 HTTP 200，按 100 的步长走 `/details/`，每 100 条跳过第 30-99 条，表面上却像成功了。按响应实际报告的 `count` 来步进。完整行为见 `references/biorxiv.md` 的分页和 `messages` 两节，包括 `total` 和 `count_new_papers` 为什么不同，以及哪些端点根本不暴露计数。

`scripts/paginate.py --api medrxiv` 用正确的步长实现了这套遍历。

## 限流

没有文档化的限流规则。无需认证。

## 分类

`addiction-medicine`, `allergy-and-immunology`, `anesthesia`, `cardiovascular-medicine`, `dentistry-and-oral-medicine`, `dermatology`, `emergency-medicine`, `endocrinology`, `epidemiology`, `forensic-medicine`, `gastroenterology`, `genetic-and-genomic-medicine`, `geriatric-medicine`, `health-economics`, `health-informatics`, `health-policy`, `health-systems-and-quality-improvement`, `hematology`, `hiv-aids`, `infectious-diseases`, `intensive-care-and-critical-care-medicine`, `medical-education`, `medical-ethics`, `nephrology`, `neurology`, `nursing`, `nutrition`, `obstetrics-and-gynecology`, `occupational-and-environmental-health`, `oncology`, `ophthalmology`, `orthopedics`, `otolaryngology`, `pain-medicine`, `palliative-medicine`, `pathology`, `pediatrics`, `pharmacology-and-therapeutics`, `primary-care-research`, `psychiatry-and-clinical-psychology`, `public-and-global-health`, `radiology-and-imaging`, `rehabilitation-medicine-and-physical-therapy`, `respiratory-medicine`, `rheumatology`, `sexual-and-reproductive-health`, `sports-medicine`, `surgery`, `toxicology`, `transplantation`, `urology`
