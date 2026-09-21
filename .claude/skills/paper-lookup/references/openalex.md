# OpenAlex API

OpenAlex 收录了 2.5 亿以上的学术著作、作者、机构、来源和主题，是一个综合性索引。它是本技能里覆盖面最广的跨学科数据库。

## 基础 URL

```
https://api.openalex.org
```

## 认证

- **建议使用 API key**（免费）。在 https://openalex.org/settings/api 申请
- 传参方式：`?api_key=YOUR_KEY`
- 旧的礼貌池仍然可用：加上 `?mailto=you@example.com` 可以获得更好的限流额度

## 限流

- 最高 **100 请求/秒**
- 按用量计费，每天有 $1 免费额度
- 按 ID/DOI 查询单个实体免费（不限量）
- 列表 + 筛选查询：每次约 $0.0001（每天免费约 10,000 次）
- 检索查询：每次约 $0.001（每天免费约 1,000 次）

## 主要端点

### 1. 获取单个著作

```
GET /works/{id}
```

支持多种 ID 格式：
```
/works/W2741809807                              (OpenAlex ID)
/works/doi:10.7717/peerj.4375                  (DOI)
/works/pmid:29456894                            (PMID)
/works/https://doi.org/10.7717/peerj.4375      (完整 DOI URL)
```

### 2. 检索著作

```
GET /works?search={query}&per_page={n}&page={n}
```

| 参数 | 默认值 | 说明 |
|-----------|---------|-------------|
| `search` | -- | 全文检索（标题、摘要、全文）。支持布尔运算：`AND`、`OR`、`NOT`（需大写） |
| `search.exact` | -- | 不做词干提取 |
| `search.semantic` | -- | AI 嵌入检索（beta，1 请求/秒，最多 50 条结果） |
| `filter` | -- | 逗号分隔的 `field:value` 键值对 |
| `sort` | relevance | `cited_by_count:desc`、`publication_date:desc`、`relevance_score:desc` |
| `per_page` | 25 | 每页结果数（最大 100） |
| `page` | 1 | 页码（`page * per_page` 最大为 10,000） |
| `cursor` | -- | 深度分页的第一页用 `*` |
| `select` | -- | 逗号分隔的返回字段 |
| `group_by` | -- | 按字段聚合 |

**高级检索：** 支持通配符（`machin*`）、模糊匹配（`machin~1`）、邻近检索（`"climate change"~5`）、布尔分组。

**示例：**
```
https://api.openalex.org/works?search=CRISPR+gene+therapy&filter=from_publication_date:2023-01-01&sort=cited_by_count:desc&per_page=10
```

### 3. 筛选著作

```
GET /works?filter={filters}
```

主要筛选字段：
| 筛选字段 | 示例 | 说明 |
|--------|---------|-------------|
| `from_publication_date` | `2023-01-01` | 发表日期晚于此日期 |
| `to_publication_date` | `2024-12-31` | 发表日期早于此日期 |
| `publication_year` | `2024` | 精确年份 |
| `type` | `article` | 著作类型 |
| `cited_by_count` | `>100` | 引用数阈值 |
| `is_oa` | `true` | 仅开放获取 |
| `has_abstract` | `true` | 有摘要 |
| `authorships.author.id` | `A5048491430` | 按作者 ID |
| `primary_location.source.id` | `S137773608` | 按期刊/来源 |
| `institutions.country_code` | `us` | 按国家 |
| `concepts.id` | `C41008148` | 按概念/主题 |
| `doi` | `10.1038/nature12373` | 按 DOI |

**运算符：** `>`、`<`、`!`（取反）、`|`（筛选条件内部的 OR）

**示例：**
```
https://api.openalex.org/works?filter=from_publication_date:2024-01-01,type:article,is_oa:true,cited_by_count:>50
```

### 4. 其他实体

```
GET /authors?search={name}
GET /authors/{id}
GET /sources?search={name}          (期刊、仓库)
GET /sources/{id}
GET /institutions?search={name}
GET /institutions/{id}
GET /topics/{id}
```

作者和机构接受类似的 filter/sort/分页参数。

### 5. 游标分页（用于超过 10,000 条结果）

```
GET /works?filter=publication_year:2024&cursor=*&per_page=100
```

响应里包含 `meta.next_cursor`。在下一次请求中用 `cursor={value}` 传回去。`next_cursor` 为 null 时停止。

## 响应格式

### Work 对象（关键字段）

```json
{
  "id": "https://openalex.org/W2741809807",
  "doi": "https://doi.org/10.7717/peerj.4375",
  "title": "The state of OA",
  "publication_year": 2018,
  "publication_date": "2018-02-13",
  "type": "article",
  "language": "en",
  "is_retracted": false,
  "cited_by_count": 1169,
  "open_access": {
    "is_oa": true,
    "oa_status": "gold",
    "oa_url": "https://doi.org/10.7717/peerj.4375"
  },
  "authorships": [{
    "author": {"id": "https://openalex.org/A5048491430", "display_name": "Heather Piwowar"},
    "institutions": [{"display_name": "Impactstory"}]
  }],
  "primary_location": {
    "source": {"display_name": "PeerJ", "issn_l": "2167-8359"}
  },
  "abstract_inverted_index": {"Despite": [0], "growing": [1], "interest": [2], ...},
  "referenced_works": ["https://openalex.org/W123...", ...],
  "ids": {"openalex": "...", "doi": "...", "pmid": "..."}
}
```

### 摘要倒排索引

摘要以 `{word: [positions]}` 形式存储。重建方法：
```python
def reconstruct(inverted_index):
    positions = {}
    for word, indices in inverted_index.items():
        for idx in indices:
            positions[idx] = word
    return ' '.join(positions[i] for i in sorted(positions.keys()))
```

### 列表响应

```json
{
  "meta": {"count": 3771834, "page": 1, "per_page": 10},
  "results": [...]
}
```

## 错误格式

API key 无效时返回 HTTP 403，超出限流时返回 429。错误响应里带一个 message 字段。
