# 阶段 02 · 数据拉取

对应 [CLAUDE.md](../CLAUDE.md) 第一节路径规范、[README.md](../README.md) 第二节阶段 2。
这里只拉原始数据，**不筛选、不合并**——过滤和面板合并是阶段 3 的事，走 `03_clean.R`。

```powershell
# 先探体积，不下载（强烈建议第一步）
.\.venv\Scripts\python.exe "empirical study\code\02_fetch\02_fetch.py" --check

# 拉单年验证字段
.\.venv\Scripts\python.exe "empirical study\code\02_fetch\02_fetch.py" --years 2019

# 确认无误后拉全区间
.\.venv\Scripts\python.exe "empirical study\code\02_fetch\02_fetch.py" --years 2000-2019

# 网络被拦时（见已知坑①）：先用浏览器下好，再登记进来
.\.venv\Scripts\python.exe "empirical study\code\02_fetch\02_fetch.py" --from-file "$env:USERPROFILE\Downloads\2019_annual_singlefile.zip"
```

不给参数会打印用法。脚本用 `__file__` 反推根目录，从哪个 cwd 跑都行。

## 开关

| 开关 | 作用 |
| --- | --- |
| `--check` | 只发 HEAD 请求，打印每个 URL 的 HTTP 状态和真实 `Content-Length`，不下载 |
| `--years 2019` | 拉单年 |
| `--years 2000-2019` | 拉区间；省略则默认 2000-2019 |
| `--keep-csv` | 解压后保留 CSV（默认解压完即删，只留 zip，省盘） |
| `--force` | 忽略 manifest 里的哈希，强制重下 |
| `--from-file <路径>` | 登记浏览器手动下载的包；与 `--check` 互斥 |

## 产物

| 路径 | 内容 |
| --- | --- |
| `data/raw/qcew/zip/YYYY_annual_singlefile.zip` | 原始压缩包，幂等跳过 |
| `data/raw/qcew/csv/` | 解压出的 CSV，默认用完即删 |
| `data/raw/qcew/manifest.json` | 每年一条：URL、sha256、字节数、列名、行数、抓取时间 |
| `logs/02_fetch_YYYYMMDD_HHMMSS.log` | 运行留痕，含 HTTP 状态、字节数、行数 |

`data/raw/` 已被根 `.gitignore` 排除，不会进版本库。`logs/` 会进——按
[README.md](../README.md) 第六节红线，日志是复现记录的一部分。

## 两条守卫

**哈希幂等。** 重跑时比对 `manifest.json` 里记录的 sha256：一致就跳过，不一致就**报错停下**，
既不静默覆盖也不静默沿用。要重下得显式 `--force`。

**样本量守卫。** 单年解压出的行数低于 `MIN_ROWS_PER_YEAR`（默认 10 万）立即中止并打印实际值。
QCEW annual singlefile 正常在百万行量级，十万是保守下限。这条拦的是「下载或解压出了问题、
但脚本继续往下跑」——AI 改代码时最容易悄悄改动的就是样本规模。

## 手动兜底

网络被 Akamai 拦掉时（已知坑①），自动下载走不通。此时用浏览器下载，再用 `--from-file` 登记。
**登记走的是和自动下载同一套校验**：同样的解压、同样的哈希、同样的行数守卫。

```powershell
.\.venv\Scripts\python.exe "empirical study\code\02_fetch\02_fetch.py" --from-file "C:\Users\你\Downloads\2019_annual_singlefile.zip"
```

- 年份优先从文件名里抠（`YYYY_annual_singlefile.zip`）；文件名被改过就读包内 `year` 列兜底，
  两个都认不出才报错
- 包会被复制进 `data/raw/qcew/zip/`，manifest 里 `origin` 记为 `manual`，并记下 `source_path`
- 目标位置已有同名包且哈希一致时跳过，不重复解压那 500MB
- 哈希和原记录不同会**警告但不拦**——到这个模式就是你明确指了文件，脚本不该再替你否决；
  自动下载那条路才拦，因为那边没人盯着

手动下的包也进 manifest、也有哈希，所以**可复现性没丢**：第三方能核对拿到的是同一个文件。

## 已知坑

**① `data.bls.gov` 按来源 IP / 地区拦。** 2026-09-20 实测：直连时整个主机返回 403，
**连根路径 `/` 都是 403**；换浏览器 UA、补齐全套浏览器请求头、用 curl 或 Python 都一样。
所以是 Akamai 在边缘按来源 IP 拦，**不是 UA 问题**。挂上代理（实测日本节点
`127.0.0.1:7897`）后，curl 和本脚本立刻都拿到 200。

**这是环境问题，不是脚本问题。** 第三方复现时若遇 403，先确认网络出口，再跑 `--check`。
注意别用「手工 curl 一下」来判断网络：被挡时响应体可能被写成 **0 字节文件而 curl 不报错**，
脚本里有「下到 0 字节即中止」的检查，手工操作没有。

**② 表头带引号。** QCEW 的字段名是 `"area_fips","own_code",...` 这种带引号形式，
所以解析表头必须走 `csv.reader`，按逗号裸切会把引号一起记进 manifest。

**③ 早期年份的布局可能不同。** 2019 年实测 38 列；约 2011 年前后的字段可能有差异。
脚本**不按硬编码列名做事**，只读表头记进 manifest，真字段以实拉那一年的日志为准。

**④ 体积参考（2019 年实测，已用 `--from-file` 核对过）。** 压缩包 74.8 MB，解压后 488.6 MB，
**3,588,374 行**数据（表头不算行；换行计数与 `csv.reader` 两种数法已核对一致）。
按此推算 20 年全量约 **1.5 GB 下载**、解压后近 10 GB——所以默认解压完即删 CSV，
只留 zip 和 manifest。要留着 CSV 加 `--keep-csv`。

**③ 不需要 `unzip`。** 解压走 Python 的 `zipfile`，不依赖系统命令。
（网上不少示例写 `shell unzip`，在 Windows 上会直接失败。）

## 下一步

阶段 3 `03_clean.R` 已建，读这里产出的年度 zip。按 [README.md](../README.md) 第三节，
阶段 3 的样本规则（筛选怎么写、保留哪些地区层级、`own_code==5` 之外的取舍）
是 HITL 节点，要研究者确认后才能动手。

> 想先跳过数据这条线、直接学方法，可以走 [05_main](../05_main/README.md) 的
> `mpdta` 示例面板路线——不需要本阶段的产物。
