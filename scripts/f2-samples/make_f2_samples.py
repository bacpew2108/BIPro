#!/usr/bin/env python3
"""Sinh file mẫu cho đợt tồn đọng sau Phase F (specs/011-ton-dong-sau-phase-f) vào build/f2-out/samples/.

Chỉ thư viện chuẩn Python, cộng pyarrow và numpy đã có trên máy (không pip, không mạng). Dữ liệu xác định (seed cố định).

  python3 scripts/f2-samples/make_f2_samples.py            # mẫu nhỏ: sales_2026.xlsx, customers.xlsx, products.csv,
                                                           #          text_cases.csv, repeat_1m.csv
  python3 scripts/f2-samples/make_f2_samples.py --large    # thêm big_10m.parquet (10 triệu dòng × 10 cột, khoảng 200 MB)

Quan hệ dự kiến cho tự phát hiện (VM-F11c):
- Sales[CustomerID] (số, lặp) → Customers[CustomerID] (số, duy nhất): Desktop nên tạo nhiều–một.
- Sales[ProductID] là số, Products[ProductID] là chữ "P01"…: trùng tên khác kiểu.
- Sales[Region] và Customers[Region]: trùng tên, cả hai phía không duy nhất.
nested.parquet (lược đồ lồng struct/list tới độ sâu 3, có NULL và danh sách rỗng) sinh cùng mẫu thường (VM-F15, T039).
"""
import csv
import datetime
import os
import random
import sys
import zipfile
from xml.sax.saxutils import escape

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "build", "f2-out", "samples")
REGIONS = ["North", "South", "East", "West", "Trung tâm"]
SEGMENTS = ["Retail", "Wholesale", "Online"]
PRODUCTS = ["Áo thun", "Quần jean", "Giày", "Mũ", "Túi xách", "Đồng hồ"]
EPOCH = datetime.datetime(1899, 12, 30)


def col(n):
    s, n = "", n + 1
    while n:
        n, rem = divmod(n - 1, 26)
        s = chr(65 + rem) + s
    return s


def write_xlsx(path, sheet, header, rows):
    """Một trang tính. Ô: int/float số; datetime.date → số kèm kiểu ngày (style 1); datetime.datetime → kiểu ngày giờ (style 2);
    chuỗi → shared string; None → ô bỏ trống."""
    shared, index = [], {}

    def sst(text):
        if text not in index:
            index[text] = len(shared)
            shared.append(text)
        return index[text]

    def cell(ref, v):
        if v is None:
            return ""
        if isinstance(v, datetime.datetime):
            return f'<c r="{ref}" s="2"><v>{(v - EPOCH).total_seconds() / 86400!r}</v></c>'
        if isinstance(v, datetime.date):
            return f'<c r="{ref}" s="1"><v>{(datetime.datetime.combine(v, datetime.time()) - EPOCH).days}</v></c>'
        if isinstance(v, (int, float)):
            return f'<c r="{ref}"><v>{v}</v></c>'
        return f'<c r="{ref}" t="s"><v>{sst(v)}</v></c>'

    body = []
    for r_i, r in enumerate([header] + rows, start=1):
        body.append(f'<row r="{r_i}">' + "".join(cell(f"{col(c)}{r_i}", v) for c, v in enumerate(r)) + "</row>")
    ns = "http://schemas.openxmlformats.org/officeDocument/2006"
    main = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    files = {
        "[Content_Types].xml": ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            '<Default Extension="xml" ContentType="application/xml"/>'
            '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
            '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
            '<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>'
            '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
            '</Types>'),
        "_rels/.rels": ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            f'<Relationship Id="rId1" Type="{ns}/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'),
        "xl/workbook.xml": ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            f'<workbook xmlns="{main}" xmlns:r="{ns}/relationships"><sheets><sheet name="{escape(sheet)}" sheetId="1" r:id="rId1"/></sheets></workbook>'),
        "xl/_rels/workbook.xml.rels": ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            f'<Relationship Id="rId1" Type="{ns}/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
            f'<Relationship Id="rId2" Type="{ns}/relationships/sharedStrings" Target="sharedStrings.xml"/>'
            f'<Relationship Id="rId3" Type="{ns}/relationships/styles" Target="styles.xml"/></Relationships>'),
        "xl/worksheets/sheet1.xml": ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            f'<worksheet xmlns="{main}" xmlns:r="{ns}/relationships"><sheetData>{"".join(body)}</sheetData></worksheet>'),
        "xl/styles.xml": ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            f'<styleSheet xmlns="{main}"><numFmts count="1"><numFmt numFmtId="164" formatCode="yyyy\\-mm\\-dd\\ hh:mm:ss"/></numFmts>'
            '<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>'
            '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
            '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
            '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
            '<cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
            '<xf numFmtId="14" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
            '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs></styleSheet>'),
    }
    files["xl/sharedStrings.xml"] = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        f'<sst xmlns="{main}" count="{len(shared)}" uniqueCount="{len(shared)}">'
        + "".join(f'<si><t xml:space="preserve">{escape(t)}</t></si>' for t in shared) + "</sst>")
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for name, content in files.items():
            z.writestr(name, content)


def sales_rows(n=500, seed=2026):
    rng = random.Random(seed)
    out = []
    for i in range(1, n + 1):
        day = datetime.date(2025, 1, 1) + datetime.timedelta(days=rng.randrange(0, 730))     # 2025–2026: hai năm cho phân cấp ngày
        moment = datetime.datetime.combine(day, datetime.time(rng.randrange(0, 24), rng.randrange(0, 60), rng.randrange(0, 60)))
        qty = rng.randrange(1, 20)
        price = rng.choice([9.99, 14.5, 25.0, 39.9, 120.0, 7.25])
        out.append([i, day, moment, rng.choice(REGIONS), rng.randrange(1, 51), rng.randrange(1, 7), qty, price, round(qty * price, 2)])
    return out


SALES_HEADER = ["OrderID", "OrderDate", "OrderTime", "Region", "CustomerID", "ProductID", "Qty", "Price", "Amount"]


def write_customers(path):
    rng = random.Random(51)
    rows = [[i, f"Khách {i}", SEGMENTS[i % 3], rng.choice(REGIONS), datetime.date(2020, 1, 1) + datetime.timedelta(days=rng.randrange(0, 1800))]
            for i in range(1, 51)]
    write_xlsx(path, "Customers", ["CustomerID", "Name", "Segment", "Region", "JoinDate"], rows)


def write_products(path):
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["ProductID", "Product", "Category"])
        for i, name in enumerate(PRODUCTS, start=1):
            w.writerow([f"P{i:02d}", name, "Thời trang" if i <= 4 else "Phụ kiện"])


TEXT_CASES = [
    "Hà Nội", "Hà Nội", "ĐÀ NẴNG", "  khoảng trắng   giữa  ", "", None, "abc", "ABC", "a*b?c~d", "1,5", "1.5", " 12 ",
    "-3.75", "😀 emoji", "x😀y", "Ngày 1/2/2026", "Trường Đại học Bách khoa", "aaaaaaaaaa", "tab\tgiữa", "dòng\nmới",
]


def write_text_cases(path):
    import unicodedata
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["ID", "Txt", "Nfd", "Num"])
        for i, t in enumerate(TEXT_CASES, start=1):
            nfd = None if t is None else unicodedata.normalize("NFD", t)
            w.writerow([i, "" if t is None else t, "" if nfd is None else nfd, [0, 1, -1, 2.5, 100, 1234567.891][i % 6]])


def write_repeat_1m(path):
    """1 triệu dòng: Batch lặp thành run dài (10 000 dòng mỗi giá trị), Status vài giá trị ngẫu nhiên, Flag gần như toàn 0,
    Value ngẫu nhiên (gần như không lặp)."""
    rng = random.Random(1_000_000)
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["ID", "Batch", "Status", "Flag", "Value"])
        for i in range(1_000_000):
            w.writerow([i + 1, f"B{i // 10_000:03d}", rng.choice(["Mới", "Đang xử lý", "Xong"]), 1 if i % 50_000 == 0 else 0,
                        rng.randrange(0, 1_000_000_000)])


def write_big_10m(path):
    import numpy as np
    import pyarrow as pa
    import pyarrow.parquet as pq
    n = 10_000_000
    rng = np.random.default_rng(10)
    base = np.datetime64("2024-01-01", "s")
    table = pa.table({
        "ID": pa.array(np.arange(1, n + 1, dtype=np.int64)),
        "CustomerID": pa.array(rng.integers(1, 51, n, dtype=np.int64)),
        "Region": pa.array(np.array(REGIONS, dtype=object)[rng.integers(0, len(REGIONS), n)]),
        "Qty": pa.array(rng.integers(1, 20, n, dtype=np.int64)),
        "Price": pa.array(np.round(rng.choice([9.99, 14.5, 25.0, 39.9, 120.0, 7.25], n), 2)),
        "Amount": pa.array(np.round(rng.random(n) * 1000, 2)),
        "OrderTime": pa.array(base + rng.integers(0, 2 * 365 * 86400, n).astype("timedelta64[s]")),
        "Batch": pa.array(np.array([f"B{i:04d}" for i in range(1000)], dtype=object)[np.arange(n) // 10_000]),
        "Flag": pa.array(np.arange(n) % 1000 == 0),
        "Code": pa.array(rng.integers(0, 2**31, n, dtype=np.int64)),
    })
    pq.write_table(table, path, compression="snappy", row_group_size=1_000_000)


def write_nested(path):
    """6 dòng, lược đồ lồng: struct, list, list of struct, struct lồng struct và list (độ sâu 3), có NULL, danh sách rỗng, phần tử NULL."""
    import pyarrow as pa
    import pyarrow.parquet as pq
    point = pa.struct([("x", pa.int64()), ("y", pa.string())])
    deep = pa.struct([("inner", pa.struct([("v", pa.float64())])), ("tags", pa.list_(pa.string()))])
    table = pa.table({
        "id": pa.array([1, 2, 3, 4, 5, 6], pa.int64()),
        "s": pa.array([{"a": 1, "b": "một"}, {"a": None, "b": "hai"}, None, {"a": 4, "b": None}, {"a": 5, "b": "năm"}, {"a": 6, "b": ""}],
                      pa.struct([("a", pa.int64()), ("b", pa.string())])),
        "l": pa.array([[1, 2, 3], [], None, [None, 5], [7], [8, 9]], pa.list_(pa.int64())),
        "ls": pa.array([[{"x": 1, "y": "a"}, {"x": 2, "y": "b"}], [], None, [{"x": None, "y": "c"}], [None], [{"x": 6, "y": "Đà Nẵng"}]],
                       pa.list_(point)),
        "d": pa.array([{"inner": {"v": 1.5}, "tags": ["x", "y"]}, {"inner": None, "tags": []}, None,
                       {"inner": {"v": None}, "tags": None}, {"inner": {"v": -2.25}, "tags": ["z"]}, {"inner": {"v": 0.0}, "tags": [None]}], deep),
    })
    pq.write_table(table, path, compression="snappy")


def main():
    os.makedirs(OUT, exist_ok=True)
    p = lambda name: os.path.join(OUT, name)
    write_xlsx(p("sales_2026.xlsx"), "Sales", SALES_HEADER, sales_rows())
    write_customers(p("customers.xlsx"))
    write_products(p("products.csv"))
    write_text_cases(p("text_cases.csv"))
    write_repeat_1m(p("repeat_1m.csv"))
    write_nested(p("nested.parquet"))
    if "--large" in sys.argv:
        write_big_10m(p("big_10m.parquet"))
    for name in sorted(os.listdir(OUT)):
        print(f"{name}\t{os.path.getsize(p(name))}")


if __name__ == "__main__":
    main()
