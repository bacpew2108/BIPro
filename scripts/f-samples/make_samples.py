#!/usr/bin/env python3
"""Sinh file mẫu cho Phase F (Get Data, Power Query) vào build/f-out/samples/.

Chỉ dùng thư viện chuẩn của Python (không pip, không mạng). Dữ liệu xác định (seed cố định), tên cột như
specs/010-f-get-data-power-query-t3: OrderID, OrderDate, Region, CustomerID, Product, Qty, Price, Amount.
Chạy: python3 scripts/f-samples/make_samples.py [--large]   (--large thêm sales_1m.csv, 1 triệu dòng)
Parquet không sinh ở đây (chưa có công cụ chuẩn): xem task T089.
"""
import csv
import datetime
import json
import os
import random
import sqlite3
import sys
import zipfile
from xml.sax.saxutils import escape

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "build", "f-out", "samples")
REGIONS = ["North", "South", "East", "West", "Trung tâm"]
PRODUCTS = ["Áo thun", "Quần jean", "Giày", "Mũ", "Túi xách", "Đồng hồ"]
EPOCH = datetime.date(1899, 12, 30)


def rows(n, seed=2026, dirty=False):
    rng = random.Random(seed)
    out = []
    for i in range(1, n + 1):
        date = datetime.date(2026, 1, 1) + datetime.timedelta(days=rng.randrange(0, 365))
        qty = rng.randrange(1, 20)
        price = round(rng.choice([9.99, 14.5, 25, 39.9, 120.0, 7.25]), 2)
        region = rng.choice(REGIONS)
        product = rng.choice(PRODUCTS)
        customer = rng.randrange(1, 51)
        amount = round(qty * price, 2)
        out.append([i, date, region, customer, product, qty, price, amount])
    if dirty:
        out[2][4] = ""            # chuỗi rỗng
        out[3][2] = None          # null
        out[4][5] = "n/a"         # chữ lẫn trong cột số
        out[5][6] = None
        out.append(list(out[0]))  # dòng trùng
    return out


HEADER = ["OrderID", "OrderDate", "Region", "CustomerID", "Product", "Qty", "Price", "Amount"]


def write_csv(path, data, delimiter=",", encoding="utf-8", bom=False):
    with open(path, "w", newline="", encoding=encoding) as f:
        if bom and encoding.lower().startswith("utf-8"):
            f.write("﻿")
        w = csv.writer(f, delimiter=delimiter, quoting=csv.QUOTE_MINIMAL)
        w.writerow(HEADER)
        for r in data:
            w.writerow(["" if v is None else (v.isoformat() if isinstance(v, datetime.date) else v) for v in r])


def col(n):  # 0 -> A
    s = ""
    n += 1
    while n:
        n, rem = divmod(n - 1, 26)
        s = chr(65 + rem) + s
    return s


def write_xlsx(path):
    data = rows(500)
    customers = [[i, f"Khách {i}", rng_choice(i)] for i in range(1, 51)]
    shared, index = [], {}

    def sst(text):
        if text not in index:
            index[text] = len(shared)
            shared.append(text)
        return index[text]

    def cell(ref, v, style=None):
        s = f' s="{style}"' if style is not None else ""
        if v is None:
            return ""
        if isinstance(v, bool):
            return f'<c r="{ref}" t="b"{s}><v>{int(v)}</v></c>'
        if isinstance(v, (int, float)):
            return f'<c r="{ref}"{s}><v>{v}</v></c>'
        return f'<c r="{ref}" t="s"{s}><v>{sst(v)}</v></c>'

    def sheet_xml(table_rows, first_row=1, extra=""):
        body = []
        for r_i, r in enumerate(table_rows, start=first_row):
            cells = "".join(cell(f"{col(c_i)}{r_i}", v, st) for c_i, (v, st) in enumerate(r))
            body.append(f'<row r="{r_i}">{cells}</row>')
        return ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
                'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
                f'<sheetData>{"".join(body)}</sheetData>{extra}</worksheet>')

    # Sheet "Sales": tiêu đề + 500 dòng; ngày là số kèm kiểu ngày (style 1); cột Amount là ô công thức.
    sales_rows = [[(h, None) for h in HEADER]]
    for r in data:
        serial = (r[1] - EPOCH).days
        sales_rows.append([(r[0], None), (serial, 1), (r[2], None), (r[3], None), (r[4], None), (r[5], None), (r[6], None), (r[7], None)])
    sales = sheet_xml(sales_rows, extra='<tableParts count="1"><tablePart r:id="rId1"/></tableParts>')
    # đổi ô Amount thành công thức có giá trị đã tính
    for i, r in enumerate(data, start=2):
        sales = sales.replace(f'<c r="H{i}"><v>{r[7]}</v></c>', f'<c r="H{i}"><f>F{i}*G{i}</f><v>{r[7]}</v></c>')
    # Sheet "Customers"
    cust = sheet_xml([[("CustomerID", None), ("Name", None), ("Segment", None)]] + [[(a, None), (b, None), (c, None)] for a, b, c in customers])
    # Sheet "Notes": hai hàng đầu trống, tiêu đề ở hàng 3, một ô trống giữa dữ liệu
    notes = sheet_xml([[("Key", None), ("Value", None)], [("a", None), (1, None)], [("b", None), (None, None)], [("c", None), (3, None)]], first_row=3)
    tables = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<table xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" id="1" name="SalesTable" displayName="SalesTable" '
              f'ref="A1:H{len(data) + 1}" totalsRowShown="0"><autoFilter ref="A1:H{len(data) + 1}"/><tableColumns count="8">'
              + "".join(f'<tableColumn id="{i + 1}" name="{h}"/>' for i, h in enumerate(HEADER)) + '</tableColumns></table>')
    ns = "http://schemas.openxmlformats.org/officeDocument/2006"
    files = {
        "[Content_Types].xml": ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            '<Default Extension="xml" ContentType="application/xml"/>'
            '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
            + "".join(f'<Override PartName="/xl/worksheets/sheet{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' for i in (1, 2, 3))
            + '<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>'
            '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
            '<Override PartName="/xl/tables/table1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.table+xml"/>'
            '</Types>'),
        "_rels/.rels": ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            f'<Relationship Id="rId1" Type="{ns}/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'),
        "xl/workbook.xml": ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            f'<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="{ns}/relationships">'
            '<sheets><sheet name="Sales" sheetId="1" r:id="rId1"/><sheet name="Customers" sheetId="2" r:id="rId2"/>'
            '<sheet name="Notes" sheetId="3" r:id="rId3"/></sheets></workbook>'),
        "xl/_rels/workbook.xml.rels": ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            + "".join(f'<Relationship Id="rId{i}" Type="{ns}/relationships/worksheet" Target="worksheets/sheet{i}.xml"/>' for i in (1, 2, 3))
            + f'<Relationship Id="rId4" Type="{ns}/relationships/sharedStrings" Target="sharedStrings.xml"/>'
            f'<Relationship Id="rId5" Type="{ns}/relationships/styles" Target="styles.xml"/></Relationships>'),
        "xl/worksheets/sheet1.xml": sales,
        "xl/worksheets/_rels/sheet1.xml.rels": ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            f'<Relationship Id="rId1" Type="{ns}/relationships/table" Target="../tables/table1.xml"/></Relationships>'),
        "xl/worksheets/sheet2.xml": cust,
        "xl/worksheets/sheet3.xml": notes,
        "xl/tables/table1.xml": tables,
        "xl/styles.xml": ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            '<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>'
            '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
            '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
            '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
            '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
            '<xf numFmtId="14" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs></styleSheet>'),
    }
    files["xl/sharedStrings.xml"] = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        f'<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="{len(shared)}" uniqueCount="{len(shared)}">'
        + "".join(f"<si><t>{escape(t)}</t></si>" for t in shared) + "</sst>")
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for name, content in files.items():
            z.writestr(name, content)


def rng_choice(i):
    return ["Retail", "Wholesale", "Online"][i % 3]


def write_sqlite(path):
    if os.path.exists(path):
        os.remove(path)
    db = sqlite3.connect(path)
    db.execute("CREATE TABLE Sales (OrderID INTEGER PRIMARY KEY, OrderDate TEXT, Region TEXT, CustomerID INTEGER, Product TEXT, Qty INTEGER, Price REAL, Amount REAL)")
    db.executemany("INSERT INTO Sales VALUES (?,?,?,?,?,?,?,?)", [[r[0], r[1].isoformat(), *r[2:]] for r in rows(1000)])
    db.execute("CREATE TABLE Customers (CustomerID INTEGER PRIMARY KEY, Name TEXT, Segment TEXT)")
    db.executemany("INSERT INTO Customers VALUES (?,?,?)", [(i, f"Khách {i}", rng_choice(i)) for i in range(1, 51)])
    db.execute("CREATE VIEW NorthSales AS SELECT * FROM Sales WHERE Region = 'North'")
    db.commit()
    db.close()


def write_json(path):
    rng = random.Random(7)
    orders = []
    for i in range(1, 101):
        lines = [{"Sku": rng.choice(PRODUCTS), "Qty": rng.randrange(1, 5)} for _ in range(rng.randrange(1, 4))]
        orders.append({"OrderID": i, "Customer": {"Id": rng.randrange(1, 51), "Region": rng.choice(REGIONS)}, "Lines": lines, "Note": None if i % 10 == 0 else f"đơn {i}"})
    with open(path, "w", encoding="utf-8") as f:
        json.dump(orders, f, ensure_ascii=False, indent=1)


def main():
    os.makedirs(OUT, exist_ok=True)
    p = lambda name: os.path.join(OUT, name)
    write_csv(p("sales_100.csv"), rows(100))
    write_csv(p("sales_2026.csv"), rows(10000))
    write_csv(p("sales_dirty.csv"), rows(30, dirty=True))
    write_csv(p("sales_semicolon.csv"), rows(30), delimiter=";")
    write_csv(p("sales_utf16.csv"), rows(30), encoding="utf-16")
    write_csv(p("sales_utf8bom.csv"), rows(30), bom=True)
    with open(p("customers.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["CustomerID", "Name", "Segment"])
        for i in range(1, 51):
            w.writerow([i, f"Khách {i}", rng_choice(i)])
    with open(p("multiline.csv"), "w", newline="", encoding="utf-8") as f:
        f.write('Id,Note\n1,"dòng một\ndòng hai"\n2,"có ""ngoặc kép"", dấu phẩy"\n3,\n')
    write_xlsx(p("sales_2026.xlsx"))
    write_sqlite(p("sales_2026.sqlite"))
    write_json(p("orders.json"))
    if "--large" in sys.argv:
        write_csv(p("sales_1m.csv"), rows(1_000_000))
    for name in sorted(os.listdir(OUT)):
        print(f"{os.path.getsize(p(name)):>10}  {name}")


if __name__ == "__main__":
    main()
