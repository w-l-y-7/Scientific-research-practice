"""QCEW 年度文件批量下载与解压（阶段 02）。

只拉原始数据，不筛选、不合并——过滤和面板合并留给 03_clean.R。

用法:
    python 02_fetch.py --check                  # 只查连通性和文件大小，不下载
    python 02_fetch.py --years 2019             # 拉单年
    python 02_fetch.py --years 2000-2019        # 拉区间
    python 02_fetch.py --years 2019 --keep-csv  # 解压后保留 CSV
    python 02_fetch.py --years 2019 --force     # 忽略 manifest 哈希，强制重下
    python 02_fetch.py --from-file 手下的.zip    # 浏览器手动下的包，登记进 manifest

不给 --years 时默认 2000-2019（下载量以 --check 实测为准，先跑 --check 再定）。
产物落在 data/raw/qcew/，运行留痕在 logs/。

网络被 Akamai 按 IP/地区拦时（见 README 已知坑①），自动下载会 403。
此时用浏览器手动下载，再用 --from-file 登记——走同一套校验，manifest 里记 origin=manual。
"""

import csv
import hashlib
import json
import re
import shutil
import sys
import urllib.error
import urllib.request
import zipfile
from datetime import datetime
from pathlib import Path

# 脚本位置反推仓库根目录，这样从哪个 cwd 运行都对
ROOT = Path(__file__).resolve().parents[2]

RAW_DIR = ROOT / "data" / "raw" / "qcew"
ZIP_DIR = RAW_DIR / "zip"
CSV_DIR = RAW_DIR / "csv"
MANIFEST = RAW_DIR / "manifest.json"
LOG_DIR = ROOT / "logs"

URL_TEMPLATE = "https://data.bls.gov/cew/data/files/{y}/csv/{y}_annual_singlefile.zip"

# 不带浏览器 UA 会被 BLS 的 Akamai 防护挡成 403，而且拿到的是一个 0 字节文件、
# 脚本不会报错，一直跑到样本量守卫才炸。别删这个头。
USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
)

YEARS_DEFAULT = "2000-2019"

# 样本量守卫。QCEW annual singlefile 含全地区 x 全行业 x 各所有制，
# 正常在百万行量级，十万是保守下限。作用是拦住"下载解压出了问题但脚本继续跑"。
MIN_ROWS_PER_YEAR = 100_000

HEAD_TIMEOUT = 30       # 秒，只探测用
DOWNLOAD_TIMEOUT = 600  # 秒，单年压缩包百 MB 量级，给宽一点


def opt(name, default):
    """取 --name 后面跟的值；没写就用默认值；写了却没给值直接报错。"""
    if name not in sys.argv:
        return default
    i = sys.argv.index(name)
    if i + 1 >= len(sys.argv) or sys.argv[i + 1].startswith("--"):
        sys.exit(f"{name} 后面要跟一个值，例如 {name} 2019 或 {name} 2000-2019")
    return sys.argv[i + 1]


def parse_years(text):
    """'2019' -> (2019, 2019)；'2000-2019' -> (2000, 2019)。"""
    if "-" in text:
        a, b = text.split("-", 1)
        return int(a), int(b)
    y = int(text)
    return y, y


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def probe(url):
    """只问大小，不下载。返回 (状态说明, 字节数或 None)。

    先试 HEAD；有些 CDN 不支持 HEAD（405/403），退到 Range 请求从
    Content-Range 里读总大小。
    """
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=HEAD_TIMEOUT) as r:
            size = r.headers.get("Content-Length")
            return f"HTTP {r.status}", int(size) if size and size.isdigit() else None
    except urllib.error.HTTPError as e:
        if e.code not in (403, 405):
            return f"HTTP {e.code}", None
    except Exception as e:
        return f"失败 {type(e).__name__}: {e}", None

    req = urllib.request.Request(
        url, headers={"User-Agent": USER_AGENT, "Range": "bytes=0-0"}
    )
    try:
        with urllib.request.urlopen(req, timeout=HEAD_TIMEOUT) as r:
            cr = r.headers.get("Content-Range", "")  # 形如 bytes 0-0/123456
            total = cr.rsplit("/", 1)[-1] if "/" in cr else ""
            return f"HTTP {r.status}", int(total) if total.isdigit() else None
    except Exception as e:
        return f"失败 {type(e).__name__}: {e}", None


def download(url, dest):
    """带 UA 下载到 dest，返回写入字节数。

    先写 .part 再改名，中途断掉不会留半个文件冒充完整包。
    """
    tmp = dest.parent / (dest.name + ".part")
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    n = 0
    try:
        with urllib.request.urlopen(req, timeout=DOWNLOAD_TIMEOUT) as r, open(tmp, "wb") as f:
            while True:
                chunk = r.read(1 << 20)
                if not chunk:
                    break
                f.write(chunk)
                n += len(chunk)
    except urllib.error.HTTPError as e:
        tmp.unlink(missing_ok=True)
        raise RuntimeError(
            f"HTTP {e.code} <- {url}\n"
            f"  403 一般是 Akamai 挡了 UA，先确认脚本顶部的 USER_AGENT 没被改动"
        ) from e
    except Exception:
        tmp.unlink(missing_ok=True)
        raise
    tmp.replace(dest)
    return n


def extract(zip_path, out_dir):
    """解压到 out_dir，返回解出的文件路径列表。

    挡一道 zip-slip：成员名爬到 out_dir 外面就直接报错，不许落盘。
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    base = out_dir.resolve()
    out = []
    with zipfile.ZipFile(zip_path) as z:
        for m in z.infolist():
            target = (out_dir / m.filename).resolve()
            if target != base and base not in target.parents:
                raise RuntimeError(f"压缩包成员路径越界，拒绝解压: {m.filename}")
            z.extract(m, out_dir)
            out.append(out_dir / m.filename)
    return out


def profile(csv_path):
    """读表头，数数据行数。返回 (列名列表, 行数)。

    行数按换行符数，不走 csv.reader——500MB 的文件用 reader 要跑好几分钟，
    而守卫只要求量级正确。QCEW 的文本字段里不含换行，两种数法结果一致。
    表头必须走 csv.reader：QCEW 的字段名是带引号的（"area_fips",...），
    按逗号裸切会连引号一起记进 manifest。
    """
    with open(csv_path, "rb") as f:
        head = f.readline()
        newlines = 0
        tail = b""
        for chunk in iter(lambda: f.read(1 << 20), b""):
            newlines += chunk.count(b"\n")
            tail = chunk[-1:]
    # 末行没有换行结尾时补一行；文件若在表头后就结束，tail 为空，行数为 0
    rows = newlines if tail in (b"", b"\n") else newlines + 1
    cols = next(csv.reader([head.decode("utf-8-sig")]))
    return cols, rows


def load_manifest():
    if MANIFEST.exists():
        with open(MANIFEST, encoding="utf-8") as f:
            return json.load(f)
    return {}


def save_manifest(m):
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    with open(MANIFEST, "w", encoding="utf-8") as f:
        json.dump(m, f, ensure_ascii=False, indent=2, sort_keys=True)


def mb(n):
    return f"{n / 1048576:.1f} MB"


def year_from_name(name):
    """从文件名抠 4 位年份；抠不到返回 None。BLS 的命名是 YYYY_annual_singlefile.zip。"""
    m = re.search(r"(\d{4})", name)
    return int(m.group(1)) if m else None


def year_from_zip(zip_path):
    """读包内 CSV 的第一条数据，抠 year 列——只读两行，不解压整包。

    用途是文件名被改过时兜底。
    """
    with zipfile.ZipFile(zip_path) as z:
        name = next((n for n in z.namelist() if n.lower().endswith(".csv")), None)
        if not name:
            return None
        with z.open(name) as f:
            cols = next(csv.reader([f.readline().decode("utf-8-sig")]), [])
            if "year" not in cols:
                return None
            row = next(csv.reader([f.readline().decode("utf-8-sig")]), [])
    i = cols.index("year")
    if len(row) <= i:
        return None
    v = row[i].strip()
    return int(v) if v.isdigit() else None


def ingest_zip(zip_path, keep_csv):
    """解压、数行、过守卫。返回 (列名, 行数, CSV 文件名, 包内 CSV 个数)。

    自动下载和手动登记都走这里，两条路的校验必须一模一样。
    """
    files = extract(zip_path, CSV_DIR)
    csvs = [p for p in files if p.suffix.lower() == ".csv"]
    if not csvs:
        raise RuntimeError(f"{zip_path.name} 解压后没找到 CSV：{[p.name for p in files]}")
    cols, rows = profile(csvs[0])
    if rows < MIN_ROWS_PER_YEAR:
        raise RuntimeError(
            f"{zip_path.name} 只解出 {rows:,} 行，低于守卫阈值 {MIN_ROWS_PER_YEAR:,}\n"
            f"  下载或解压可能有问题，已中止（改阈值前先查清楚原因）"
        )
    if not keep_csv:
        for p in csvs:
            p.unlink()
    return cols, rows, csvs[0].name, len(csvs)


def register_local(src, keep_csv, force, manifest, log, fh):
    """把浏览器手动下下来的包登记进 manifest。返回 (年份, 行数, 列名, CSV 名, 字节数)。

    用户明确指了这个文件，所以默认就登记它；哈希和原记录不同会警告，但不拦——
    自动下载那条路才需要拦，因为那边没人盯着。
    """
    if not src.exists():
        raise RuntimeError(f"找不到文件：{src}")
    if not zipfile.is_zipfile(src):
        raise RuntimeError(f"不是有效的 zip：{src}\n  浏览器报错时会把错误页存成 .zip")

    year = year_from_name(src.name) or year_from_zip(src)
    if year is None:
        raise RuntimeError(
            f"认不出年份：{src.name} 里没有 4 位年份，包内也没读到 year 列\n"
            f"  重命名成 YYYY_annual_singlefile.zip 再试"
        )

    ZIP_DIR.mkdir(parents=True, exist_ok=True)
    dest = ZIP_DIR / f"{year}_annual_singlefile.zip"

    # 已经在库且哈希一致，就不重复解压那 500MB
    if dest.exists() and not force and manifest.get(str(year), {}).get("sha256") == sha256(dest):
        log(f"  {year}  跳过（{dest.name} 已在，哈希与 manifest 一致）", fh)
        e = manifest[str(year)]
        return year, e["rows"], e["columns"], e["csv"], e["zip_bytes"]

    if dest.resolve() != src.resolve():
        shutil.copy2(src, dest)
        log(f"  {year}  已复制 -> {dest}", fh)

    nbytes = dest.stat().st_size
    digest = sha256(dest)
    old = manifest.get(str(year), {}).get("sha256")
    if old and old != digest:
        log(f"  {year}  警告：哈希与原有记录不同（{old[:12]}… -> {digest[:12]}…），已按你指定的文件更新", fh)
    log(f"  {year}  {mb(nbytes)}  sha256 {digest[:12]}…", fh)

    cols, rows, csv_name, n_csvs = ingest_zip(dest, keep_csv)
    if n_csvs > 1:
        log(f"  {year}  注意：包里有 {n_csvs} 个 CSV，只登记了 {csv_name}", fh)
    log(f"  {year}  {csv_name}  {rows:,} 行 x {len(cols)} 列", fh)

    manifest[str(year)] = {
        "origin": "manual",
        "source_path": str(src),
        "url": URL_TEMPLATE.format(y=year),
        "sha256": digest,
        "zip_bytes": nbytes,
        "csv": csv_name,
        "rows": rows,
        "columns": cols,
        "fetched_at": datetime.now().isoformat(timespec="seconds"),
        "script": "code/02_fetch/02_fetch.py",
    }
    save_manifest(manifest)
    return year, rows, cols, csv_name, nbytes


def main():
    check_only = "--check" in sys.argv
    keep_csv = "--keep-csv" in sys.argv
    force = "--force" in sys.argv
    from_file = opt("--from-file", None)
    y0, y1 = parse_years(opt("--years", YEARS_DEFAULT))

    if from_file is not None and check_only:
        sys.exit("--from-file 是登记本地文件，--check 是探测远端，两个不能一起用")

    LOG_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    # 同一秒内跑两次会撞名，撞了就加序号——日志被悄悄覆盖就丢了运行痕迹
    log_path = LOG_DIR / f"02_fetch_{stamp}.log"
    suffix = 2
    while log_path.exists():
        log_path = LOG_DIR / f"02_fetch_{stamp}_{suffix}.log"
        suffix += 1

    manifest = load_manifest()
    done, skipped, total_bytes = [], 0, 0
    sizes_known = True

    def log(msg, fh):
        print(msg)
        fh.write(msg + "\n")

    with open(log_path, "w", encoding="utf-8-sig") as fh:
        if from_file is not None:
            log(f"QCEW 手动登记 {stamp}  {from_file}", fh)
        else:
            log(f"QCEW 拉取 {stamp}  年份 {y0}-{y1}"
                + ("  [--check：只探测，不下载]" if check_only else ""), fh)

        try:
            if from_file is not None:
                year, rows, cols, _, nbytes = register_local(
                    Path(from_file).expanduser(), keep_csv, force, manifest, log, fh
                )
                done.append((year, rows))
                total_bytes += nbytes

            elif check_only:
                for y in range(y0, y1 + 1):
                    status, size = probe(URL_TEMPLATE.format(y=y))
                    if size is None:
                        sizes_known = False
                    else:
                        total_bytes += size
                    log(f"  {y}  {status}  {mb(size) if size else '大小未知'}", fh)

            else:
                ZIP_DIR.mkdir(parents=True, exist_ok=True)
                for y in range(y0, y1 + 1):
                    url = URL_TEMPLATE.format(y=y)
                    zip_path = ZIP_DIR / f"{y}_annual_singlefile.zip"
                    entry = manifest.get(str(y), {})

                    if zip_path.exists() and entry and not force:
                        got = sha256(zip_path)
                        if got == entry.get("sha256"):
                            log(f"  {y}  跳过（哈希与 manifest 一致）", fh)
                            skipped += 1
                            continue
                        # 对不上就停：既不静默覆盖，也不静默沿用
                        raise RuntimeError(
                            f"{zip_path.name} 的哈希和 manifest 对不上\n"
                            f"  manifest 记录 {str(entry.get('sha256'))[:12]}…，实际 {got[:12]}…\n"
                            f"  确认文件无误后用 --force 重下"
                        )

                    nbytes = download(url, zip_path)
                    if nbytes == 0:
                        raise RuntimeError(f"{y} 下到 0 字节，多半是被挡了，不是真的空文件")
                    log(f"  {y}  下载 {mb(nbytes)}", fh)

                    cols, rows, csv_name, n_csvs = ingest_zip(zip_path, keep_csv)
                    if n_csvs > 1:
                        log(f"  {y}  注意：包里有 {n_csvs} 个 CSV，只登记了 {csv_name}", fh)
                    log(f"  {y}  {csv_name}  {rows:,} 行 x {len(cols)} 列", fh)

                    manifest[str(y)] = {
                        "origin": "download",
                        "url": url,
                        "sha256": sha256(zip_path),
                        "zip_bytes": nbytes,
                        "csv": csv_name,
                        "rows": rows,
                        "columns": cols,
                        "fetched_at": datetime.now().isoformat(timespec="seconds"),
                        "script": "code/02_fetch/02_fetch.py",
                    }
                    save_manifest(manifest)
                    done.append((y, rows))
                    total_bytes += nbytes

        except Exception as e:
            log(f"\n中止：{e}", fh)
            log(f"日志 -> {log_path}", fh)
            return 1

        log("", fh)
        if check_only:
            if sizes_known:
                log(f"探测 {y1 - y0 + 1} 年，全下约 {total_bytes / 1073741824:.2f} GB", fh)
            else:
                log("部分年份没拿到大小，合计不完整", fh)
        else:
            log(f"完成 {len(done)} 项，跳过 {skipped} 项，本次新增 {total_bytes / 1073741824:.2f} GB", fh)
            for y, rows in done:
                log(f"  {y}  {rows:,} 行", fh)
        log(f"产物 -> {RAW_DIR}", fh)
        log(f"日志 -> {log_path}", fh)
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    sys.exit(main())
