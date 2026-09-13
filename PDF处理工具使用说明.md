# PDF 处理工具使用说明

> 涵盖 pymupdf4llm、markitdown、pdfplumber 三件工具。读研报、财报、招股书、央行报告这类文档时按用途选。

处理研报、财报、招股书、央行报告这类 PDF 的三件工具。按用途分：

- **pymupdf4llm**：PDF 转 Markdown，适合读正文（管理层讨论、行业分析、政策文件）
- **markitdown**：各种办公格式转 Markdown，PDF 也能转但会丢词间空格
- **pdfplumber**：精确抽表格和字符坐标，适合抠数字（三大报表、财务附注）

下面所有命令都在本机实测过，版本是 markitdown 0.1.7、pdfplumber 0.11.10、pymupdf4llm 1.28.2。

**这三件的开源协议不一样，用之前先看第七节**——其中一个是 AGPL，涉及发布代码时有约束。

---

## 一、最常用命令（速查）

### 转 Markdown

```powershell
# 输出到文件
markitdown 年报2024.pdf -o 年报2024.md

# 直接看（不落盘）
markitdown 研报.pdf

# 批量转当前目录所有 PDF
Get-ChildItem *.pdf | ForEach-Object { markitdown $_.Name -o ($_.BaseName + ".md") }
```

### 抽表格

```powershell
# 先激活环境（每次开新终端都要做一次）
.\.venv\Scripts\activate

# 把 PDF 里所有表格导出成 CSV
python extract_tables.py 财报.pdf
```

`extract_tables.py` 已经在项目根目录了，脚本逻辑见第五节。跑之前记得先激活环境。

### 临时用一下（不想激活环境）

```powershell
uv run --with pdfplumber python 你的脚本.py
```

---

## 二、环境

项目根目录下的 `.venv` 里装了 pdfplumber：

| 工具 | 安装方式 | 怎么调用 | 协议 |
|---|---|---|---|
| pymupdf4llm | uv 全局工具 | 直接敲 `pymupdf4llm` | AGPL ⚠ |
| markitdown | uv 全局工具 | 直接敲 `markitdown` | MIT |
| pdfplumber | 项目 `.venv` | 先 `activate`，再 `import pdfplumber` | MIT |

markitdown 是命令行工具，装在哪都能敲；pdfplumber 是 Python 库，必须 `import`，所以要先进环境。`requirements.txt` 已列好依赖，换机器时重建：

```powershell
uv venv .venv
uv pip install -r requirements.txt
```

---

## 三、markitdown 怎么用

### 基本形式

```powershell
markitdown <文件>              # 输出到屏幕
markitdown <文件> -o <输出>    # 输出到文件
markitdown <文件> -x .pdf      # 从管道读时手动指定格式
markitdown --version
```

### 支持的格式

PDF、DOCX、PPTX、XLSX、XLS、HTML、EPUB、CSV、JSON、XML、图片、音频、ZIP。

金融场景常用的三种情况：

```powershell
# 券商研报（PDF）
markitdown 策略报告.pdf -o 策略报告.md

# 交易所公告（DOCX）
markitdown 公告.docx -o 公告.md

# 数据附表（XLSX）——表格会转成 Markdown 表格
markitdown 财务数据.xlsx -o 财务数据.md
```

### 什么时候别用 markitdown（改用 pymupdf4llm）

markitdown 转 PDF 会**丢词间空格**，实测把 `guide planning decisions` 输出成 `guideplanningdecisions`、`unknown environments` 输出成 `unknownenvironments`。读正文还能靠上下文猜，但**数字和专有名词会连成一片**，不适合拿来核对财报数据。

要转论文、研报正文，用同机装好的另一个工具：

```powershell
pymupdf4llm 研报.pdf --out ./out
```

它保留标题层级、上下标、斜体，空格也正常，输出在 `./out/<文件名>/<文件名>.md`。

**分工建议**：正文用 pymupdf4llm，办公格式（docx/pptx/xlsx）用 markitdown，数字表格用 pdfplumber。

不过 pymupdf4llm 是 AGPL 协议，自己用没问题，**要发布代码的场景先看第七节**。

---

## 四、pdfplumber 怎么用

### 打开文件

```python
import pdfplumber

with pdfplumber.open("财报.pdf") as pdf:
    print(len(pdf.pages))          # 页数
    p = pdf.pages[0]               # 第一页
    print(p.width, p.height)       # 页面尺寸，A4 约 595 × 842
    print(p.page_number)           # 1（真实页码，从 1 开始）

# 只读指定页，大文件能省很多时间
with pdfplumber.open("财报.pdf", pages=[10, 11, 12]) as pdf:
    ...
```

`with` 语句会自动关文件，别漏。

### 抽文本

```python
p.extract_text()                 # 普通抽取
p.extract_text(layout=True)      # 保留排版，空白被保留，适合看左右分栏
p.extract_words()                # 词 + 坐标：[{'text':..., 'x0':..., 'top':...}, ...]
p.chars                          # 字符级，每个字带 x0/top，用于精确定位
```

一句话总结：`extract_text()` 读数，`layout=True` 看排版，`extract_words()` / `chars` 定位。

### 抽表格

```python
p.extract_tables()               # 本页所有表格
p.extract_table()                # 本页第一个表格
p.find_tables()                  # 返回 Table 对象，能拿到位置
```

返回的是二维列表，每个单元格是字符串，**空单元格是 `None`**。

```python
# 转成 CSV
import csv
with open("表格.csv", "w", newline="", encoding="utf-8-sig") as f:
    csv.writer(f).writerows(rows)
```

`encoding="utf-8-sig"` 是为了 Excel 打开中文不乱码。

`find_tables()` 拿到的是 `Table` 对象，公开属性只有这几个：

| 属性 / 方法 | 作用 |
|---|---|
| `.bbox` | 表格位置 `(x0, top, x1, bottom)` |
| `.rows` / `.columns` | 行数 / 列数 |
| `.cells` | 单元格坐标 |
| `.extract()` | 抽成二维列表 |
| `.page` | 所属页 |

**注意**：`Table` 没有 `.cell()`、`.row()`、`.settings`，别照着别的库的写法写。

### 裁剪区域

财报里一页常混着正文和表格，先裁再抽：

```python
left = p.crop((0, 0, p.width / 2, p.height))      # 左半页
top_half = p.crop((0, 0, p.width, p.height / 2))  # 上半页
print(left.extract_text())
```

### 导出为图片

```python
img = p.to_image(resolution=150)
img.save("第3页.png")
```

`to_image()` 只依赖 pypdfium2，本机已装好，不用额外装 poppler。

---

## 五、金融科技场景实战

### 三大报表提取（`extract_tables.py`）

项目根目录已经有现成的 `extract_tables.py`：

```powershell
python extract_tables.py 财报.pdf          # 只留看起来像表格的
python extract_tables.py 财报.pdf --all    # 全都导出，不过滤
```

在 `财报/` 目录下按页生成 `p10_t1.csv`、`p10_t2.csv`，文件名带页码，方便回溯原页。

脚本做三件事：

1. 每页先试有线策略，抽不出像样的表格再退到 text 策略（见下方「三个坑」第 1 条）
2. 清洗单元格：去掉换行和多余空格
3. 用一个启发式过滤掉被误判成表格的正文

**过滤规则**（`extract_tables.py` 顶部有两个常量可调）：

| 规则 | 阈值 | 依据 |
|---|---|---|
| 列数 ≥ `MIN_COLS` | 2 | 只有一列的"表格"必是正文 |
| 单元格均长 ≤ `MAX_AVG_CELL` | 30 | 实测真表格 9~14，被误判的正文 39~53 |

**这个过滤是启发式的，会漏也会误留，务必人工过一遍。** 实测一篇 8 页论文：13 个候选被筛到 5 个，抽查其中 3 个，只有 1 个是真表格（数字对照表），另外 2 个是图注和算法伪代码。想自己判断就加 `--all` 全部导出再看。

阈值这两个数字是按上面那篇论文定的，**换一批文档要重新校准**：先 `--all` 导出，看误留的那些表格均长是多少，再调 `MAX_AVG_CELL`。

**注意**：有边框的表走 `lines` 策略，抽出来干净；无边框的表只能走 `text` 策略，列宽靠文字对齐推断，表头被折行时会出现 `Method Sm` / `allMaps` 这种从中间断开的单元格，数字行一般是准的。财报里的表格大多无边框，所以 text 策略是主力。

### 定位特定章节再抽取

年报动辄两三百页，全量抽太慢，先用关键字定位页码：

```python
import pdfplumber

KEYWORDS = ["合并资产负债表", "合并利润表", "合并现金流量表"]

hits = {}
with pdfplumber.open("年报.pdf") as pdf:
    for page in pdf.pages:
        text = page.extract_text() or ""
        for kw in KEYWORDS:
            if kw in text:
                hits.setdefault(kw, []).append(page.page_number)

for kw, pages in hits.items():
    print(kw, "->", pages)
```

拿到页码后，再用 `pages=[...]` 定点抽表，几十秒的事。

### 用坐标对齐跨页表格

财报的表常跨页，且**表头只出现在第一页**。跨页表的值往往落在相同的 x 区间，可以用坐标把一个指标在多个页面上取出来：

```python
with pdfplumber.open("年报.pdf") as pdf:
    for page in pdf.pages[9:11]:
        for w in page.extract_words():
            if w["x0"] > 400 and w["text"].replace(",", "").replace(".", "").isdigit():
                print(page.page_number, w["text"], round(w["x0"], 1))
```

先打印出来看清 x 范围，再把条件收紧，比硬写正则可靠。

### 数字清洗

会计写法和 Python 的浮点数不一样，读进来必须转：

```python
def to_number(s):
    """'(1,234.56)' -> -1234.56  |  '12.5%' -> 12.5  |  '—' / '-' / '' -> None

    注意百分号是直接去掉的：'12.5%' 返回 12.5 而不是 0.125，用的时候自己记得那是百分比。
    返回 None 表示这一格不是数字（空值、破折号、说明文字），不是 0。
    """
    if not s:
        return None
    s = s.strip().replace(",", "").replace(" ", "")
    if s in {"—", "-", "–", "N/A", ""}:
        return None
    negative = s.startswith("(") and s.endswith(")")
    s = s.strip("()").rstrip("%")
    try:
        v = float(s)
    except ValueError:
        return None
    return -v if negative else v
```

**括号是负数**，这是会计准则，不是笔误。另外 `None` 和 `0` 要分开处理——空值当成 0 会拉低你的求和结果。

---

## 六、三个坑

### 1. 无边框表格默认抽不出来

这是最要紧的一条。pdfplumber 默认用「有线」策略找表格边框，但**很多财报表格根本没有线**，只有对齐的数字。

实测同一页：默认 `extract_tables()` 返回 `0` 个，换成 text 策略返回 `1` 个。

```python
page.extract_tables()                                     # 有线表格
page.extract_tables({"vertical_strategy": "text",       # 无线表格
                     "horizontal_strategy": "text"})
```

`extract_tables.py` 已经帮你两个策略都试了。但要注意顺序不能写成「lines 非空就不试 text」——有线策略经常返回一堆一行一列的垃圾，会挡掉真正该用 text 抽的表。要判断「有没有像样的表」，不能只看「有没有表」。

### 2. 单元格里有换行符

表格里一个格子塞不下时，PDF 会折行，抽出来就成了 `"Frontier 1\nPat"`。直接写 CSV 会把一行拆成两行——注意 `csv` 模块遇到内嵌换行会自动加引号，所以文件能正常打开，但那一格的内容是断的。`extract_tables.py` 里的 `clean()` 会把它压成一行。

### 3. 中文乱码

部分中文 PDF 内嵌字体没有 unicode 映射，`extract_text()` 出来是乱码（`口口口` 或乱字符）。这不是代码问题，是 PDF 本身没有文本层。

判断办法：

```python
text = page.extract_text() or ""
print(repr(text[:80]))
```

如果全是替换字符，说明这份 PDF 需要 OCR，pdfplumber 和 markitdown 都做不了，得另找 OCR 工具。

另外，如果是**扫描件**（整页是图片），同样没有文本层，先用 `page.to_image()` 导出图片确认一下。

---

## 七、开源协议（重要）

三件工具不是一个协议，写作业没事，**发布代码或做商业项目前一定要看这一节**。

| 工具 | 协议 | 性质 |
|---|---|---|
| markitdown | MIT | 宽松，随便用 |
| pdfplumber | MIT | 宽松，随便用 |
| **pymupdf4llm**（含底层的 `pymupdf`） | **AGPL-3.0 或 Artifex 商业许可**（双许可） | 强传染性 |

**AGPL-3.0 意味着什么**

它是 GPL 的加强版，多了一条网络条款：

- 你**分发**用到它的软件 → 你的代码也要按 AGPL 开源
- 你把它做成**网络服务**给别人用（哪怕不分发安装包）→ 同样要开源
- 想闭源商用 → 得买 Artifex 的商业授权

**什么情况不用担心**

- 自己写作业、做课程项目、读文献、本地分析数据
- 只在自己机器上跑，不对外提供服务

**什么情况要注意**

- 实习或工作项目里打算用，且代码要交付给公司
- 想把成果开源到 GitHub（那就得整个项目按 AGPL 开源）
- 想做个小工具给别人用、或者部署到服务器上

**真到那一步怎么办**

换掉就行，功能上 MIT 的替代方案够用：

| 原来用它做什么 | 换成 |
|---|---|
| PDF 转 Markdown | `markitdown`（也是 MIT，就是词间空格会丢） |
| 抽表格和文本 | `pdfplumber`（MIT，本文档第四节已经写全了） |

也就是说，**这套流程里真正不可替代的是 pdfplumber，而它是 MIT**。pymupdf4llm 只是读正文更舒服，不是非它不可。

---

## 八、一句话总结

| 场景 | 工具 | 协议 |
|---|---|---|
| 读研报、年报正文 | `pymupdf4llm` | AGPL |
| 转 docx / pptx / xlsx | `markitdown` | MIT |
| 抽财报表格 | `pdfplumber` + text 策略 | MIT |
| 表格导出 Excel | csv + `utf-8-sig` | — |
| 扫描件 | 都不行，要 OCR | — |
