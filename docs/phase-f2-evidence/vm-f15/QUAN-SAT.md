# VM-F15 (T039): quan sát Desktop 2.159, dở dang (2026-11-19)

## PostgreSQL `f15.public.types_f15` (máy chủ `bipro-pg`, `scripts/f2-samples/pg_seed.sh`; VM ở múi giờ SE Asia +07)

M Desktop sinh (Navigator): `Source = PostgreSQL.Database("10.211.55.2:55432", "f15")`, `public_types_f15 = Source{[Schema="public",Item="types_f15"]}[Data]`.

| Cột PG | Power Query (`Table.Schema`) | Mô hình | Giá trị |
|---|---|---|---|
| integer | Int32.Type | Integer, định dạng `0` | |
| timestamptz | **DateTime.Type** (không phải datetimezone) | Date/Time, `General Date` | đổi sang giờ địa phương của máy: `08:30+07` → 08:30, `08:30:00.25-05` → 20:30:00.25 |
| time | Time.Type | Date/Time, `Long Time` | ngày 1899-12-30 + giờ; 23:59:59.5 giữ phần lẻ (0,999994212962963) |
| interval | Duration.Type | Number (số ngày) | tháng = 30 ngày: `1 mon 2 days` → 32, `-1 year -2 mons 3 days` → -417, `00:00:00.5` → 5,787E-06 |
| bytea | Binary.Type | **cột bị bỏ khi nạp** (không có trong mô hình) | |
| int[], text[] | Text.Type (NativeTypeName `array`) | Text | dạng văn bản PG: `{1,NULL,3}`, `{{1,2},{3,4}}`, `{"có \"ngoặc\"","x,y"}`, `{}` |

Ảnh: `p0-xem-truoc.png`, `p1-xem-truoc-mang.png`, `p2-pq-kieu-postgres.png`.

## Chưa xong
- Parquet `nested.parquet` (sinh bằng `make_f2_samples.py`, đã chép vào `C:\Users\bacpew\f15`): đang dán M vào Query2 trong Power Query.
- SQLite driver thứ hai: VM chưa có.
- Chưa lưu `f15-desktop.pbix`. Desktop đang mở `C:\Users\bacpew\f15\nen.pbix` với Power Query (Query1 = Table.Schema, Query2 dở) — bỏ, không áp dụng.
