1111111 1

---
name: citation-management
description: 引用管理流水线：从文献笔记里抽出 DOI，联网抓 BibTeX 元数据，去重排序写成 references.bib，再校验并出一份 JSON 报告。用户说「整理引用」「更新参考文献」「管理引用」「跑一下引用流水线」「/citation-management」时使用。
---
# citation-management：DOI → BibTeX → 校验报告

把文献笔记里的 DOI 变成规范的 `references.bib`，并检查里面有没有毛病。

**核心原则：`raw.bib` 是机器的，`references.bib` 也是机器的，人只改笔记。**
要改作者名、补页码，请改 `literature_notes/summary_table.md` 然后重跑，不要手改 `.bib`——下次一跑就被覆盖。

## 触发条件

用户想把笔记里的文献整理成 BibTeX、或者要检查参考文献有没有问题，就用本技能。

---

## 目录约定

| 文件                                  | 作用                             | 谁写   |
| ------------------------------------- | -------------------------------- | ------ |
| `literature_notes/summary_table.md` | 文献笔记，**唯一的输入端** | 人     |
| `citations/doi_list.txt`            | 抽出来的 DOI 清单                | 脚本 1 |
| `citations/raw.bib`                 | 原始抓取结果，未去重未排序       | 脚本 2 |
| `citations/references.bib`          | 最终成品                         | 脚本 3 |
| `citations/validation.json`         | 校验报告                         | 脚本 4 |

脚本都在本技能的 `scripts/` 下，用 `python` 直接跑，只依赖标准库。

---

## 执行步骤

### 第 0 步：确认入口存在

先看 `literature_notes/summary_table.md` 在不在。

- **不在** → 停下来问用户笔记放哪了。**不要**自己去猜论文、不要自己编 DOI。
- **在** → 通读一遍，确认里面确实有 DOI。

### 第 1 步：抽 DOI

```powershell
python .claude/skills/citation-management/scripts/extract_metadata.py literature_notes/summary_table.md --dois-only -o citations/doi_list.txt
```

笔记里的 DOI 支持裸写、`https://doi.org/...`、`doi:...` 三种写法。抽出来一行一个，方便人工过一眼。

### 第 2 步：抓元数据

```powershell
python .claude/skills/citation-management/scripts/extract_metadata.py citations/doi_list.txt -o citations/raw.bib
```

走 Crossref 的内容协商，对方直接返回 BibTeX。查不到的 DOI 和网络失败的会分开报在末尾。

### 第 3 步：去重排序

```powershell
python .claude/skills/citation-management/scripts/format_bibtex.py citations/raw.bib -o citations/references.bib
```

**这一步会覆盖 `citations/references.bib`，覆盖前必须先备份。** 用户明确要求过这条。

```powershell
if (Test-Path citations/references.bib) { Copy-Item citations/references.bib citations/references.bib.bak -Force }
```

跑完确认新文件没问题再谈删不删 `.bak`。**备份这步不能省，也不能靠「看起来是流水线生成的」来判断**——手工整理的版本一旦被覆盖就找不回来了。

### 第 4 步：校验

```powershell
python .claude/skills/citation-management/scripts/validate_citations.py citations/references.bib -o citations/validation.json
```

退出码 0 = 没有 error。跑完**必须把发现的问题列给用户看**，不能只说「校验完成」。

---

## 怎么读校验报告

| severity | code                  | 意思                                | 怎么办                                              |
| -------- | --------------------- | ----------------------------------- | --------------------------------------------------- |
| error    | `missing_field`     | 缺该类型必需的字段                  | 回笔记里补，或换一个更准的 DOI                      |
| error    | `bad_doi`           | DOI 格式不合法                      | 多半是从正文粘过来的，尾标点没剥干净                |
| error    | `bad_year`          | year 不是四位数字                   | 手改`raw.bib` 没用，要改上游                      |
| error    | `duplicate_key`     | 引用键撞车                          | 三篇同姓同年的文章常见，脚本已自动加后缀            |
| error    | `unparsed`          | 括号不配对                          | 条目被截断了，检查抓取过程                          |
| warning  | `no_doi`            | 没 DOI                              | 会议论文、预印本常有，人工确认即可                  |
| warning  | `odd_year`          | 年份离谱                            | 通常是抓错了条目                                    |
| warning  | `unescaped_special` | 标题里有裸的`&` `%` `_` `#` | LaTeX 会编译失败，要写成`\&` `\%` `\_` `\#` |

---

## 坑

1. **arXiv 上引用键会重**。同一篇预印本和正式版常在库里各有一条，DOI 不同、标题相同，去重规则按 DOI 优先，所以**会留下两条**。要合并得人工决定留哪条。
2. **arXiv 的 DOI 形如 `10.48550/arXiv.2503.07504`**，Crossref 不一定收录。查不到属正常，此时该条以 arXiv 元数据为准。
3. **`raw.bib` 别手改**。它每次都会被整个重写，改了也白改。
4. **Crossref 偶尔 429**。脚本内建了退避重试，真失败了就等几分钟重跑第 2 步。
5. **中文文献大多没有 DOI**。中文期刊常只有 CNKI 链接，这类走人工录入，不要硬套本流程。

---

## 红线

- 不改用户的文献笔记。
- 不编造 DOI、作者、页码。查不到就报「查不到」，让它缺着。
- 覆盖 `references.bib` 前先确认它是流水线产物。
- 校验出 error 要如实列出来，不能因为「数量不多」就省略。
