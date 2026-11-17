#!/usr/bin/env python3
"""Sinh tệp Parquet mẫu cho Phase F, US7 (T089) bằng pyarrow có sẵn trên máy (công cụ chuẩn, không phải mã tự viết của BI Pro).

Dữ liệu giống sales_2026.csv của make_samples.py (cùng seed), nên đối chiếu được giá trị với CSV.
Ra build/f-out/samples/:
  sales_2026.parquet          10 000 dòng, mặc định pyarrow (SNAPPY, từ điển, trang dữ liệu v1)
  parquet/types_*.parquet     nhiều kiểu (bool, int32, int64, float, double, chuỗi có null, date32, timestamp ms/us, decimal),
                              mỗi tệp một cách mã hoá/nén: gzip, uncompressed + PLAIN, trang v2, nhiều row group, zstd (để thử báo lỗi)
  sales_1m.parquet            1 triệu dòng (chỉ khi --large), cho test lớn T090
Chạy: python3 scripts/f-samples/make_parquet.py [--large]
"""
import datetime
import decimal
import os
import sys

sys.dont_write_bytecode = True   # không để __pycache__ trong repo khi import make_samples

import pyarrow as pa
import pyarrow.parquet as pq

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_samples import OUT, rows  # noqa: E402

SALES_SCHEMA = pa.schema([
    ("OrderID", pa.int64()), ("OrderDate", pa.date32()), ("Region", pa.string()), ("CustomerID", pa.int64()),
    ("Product", pa.string()), ("Qty", pa.int64()), ("Price", pa.float64()), ("Amount", pa.float64()),
])


def sales_table(n):
    data = rows(n)
    return pa.table([[r[i] for r in data] for i in range(8)], schema=SALES_SCHEMA)


def types_table(n=1000):
    base = datetime.datetime(2026, 1, 1, 8, 30, 0)
    cols = {
        "Id": pa.array(range(1, n + 1), pa.int64()),
        "Small": pa.array([None if i % 13 == 0 else (i % 200) - 100 for i in range(n)], pa.int32()),
        "Flag": pa.array([None if i % 17 == 0 else i % 3 == 0 for i in range(n)], pa.bool_()),
        "Ratio": pa.array([None if i % 19 == 0 else i / 8.0 for i in range(n)], pa.float32()),
        "Value": pa.array([None if i % 23 == 0 else i * 1.25 - 300.5 for i in range(n)], pa.float64()),
        "Name": pa.array([None if i % 11 == 0 else ("" if i % 29 == 0 else f"Tên {i % 37} ✓") for i in range(n)], pa.string()),
        "Day": pa.array([None if i % 31 == 0 else datetime.date(2025, 12, 31) + datetime.timedelta(days=i) for i in range(n)], pa.date32()),
        "StampMs": pa.array([base + datetime.timedelta(minutes=37 * i) for i in range(n)], pa.timestamp("ms")),
        "StampUs": pa.array([None if i % 7 == 0 else base + datetime.timedelta(seconds=i, microseconds=250 * i) for i in range(n)],
                            pa.timestamp("us")),
        "Money": pa.array([None if i % 9 == 0 else decimal.Decimal(i * 137 - 40000) / 100 for i in range(n)], pa.decimal128(9, 2)),
        "Big": pa.array([decimal.Decimal(i * 1234567 - 600000000) / 10000 for i in range(n)], pa.decimal128(18, 4)),
    }
    return pa.table(cols)


def main():
    os.makedirs(OUT, exist_ok=True)
    sub = os.path.join(OUT, "parquet")
    os.makedirs(sub, exist_ok=True)
    out = []

    def write(table, path, **kw):
        pq.write_table(table, path, **kw)
        out.append(path)

    write(sales_table(10_000), os.path.join(OUT, "sales_2026.parquet"))
    t = types_table()
    write(t, os.path.join(sub, "types_snappy.parquet"))
    write(t, os.path.join(sub, "types_gzip.parquet"), compression="gzip")
    write(t, os.path.join(sub, "types_plain.parquet"), compression="none", use_dictionary=False)
    write(t, os.path.join(sub, "types_v2.parquet"), data_page_version="2.0")
    write(t, os.path.join(sub, "types_groups.parquet"), row_group_size=128, data_page_size=512)
    write(t, os.path.join(sub, "types_zstd.parquet"), compression="zstd")
    if "--large" in sys.argv:
        write(sales_table(1_000_000), os.path.join(OUT, "sales_1m.parquet"))
    for path in out:
        print(f"{os.path.getsize(path):>10}  {os.path.relpath(path, OUT)}")


if __name__ == "__main__":
    main()
