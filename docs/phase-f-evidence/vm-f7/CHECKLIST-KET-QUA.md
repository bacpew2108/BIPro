# Gate T090 (US7): Desktop mở tệp BI Pro có bảng JSON và Parquet — ĐẠT

Ngày 2026-11-16, Power BI Desktop 2.159 trong VM, Claude lái VM (người dùng cho phép, gồm cả gate này). Tệp: `build/f-out/f7/bipro-f7.pbix`
do `F7JsonParquetGateTests` tạo trên tài liệu mới (File ▸ Mới): Get Data ▸ JSON `orders.json` (mở thẳng Query Editor, Close & Apply),
Get Data ▸ Parquet `sales_2026.parquet` và `parquet/types_snappy.parquet` (Load), hai measure + hai card, lưu lần đầu.

| # | Kiểm | Kết quả |
|---|---|---|
| 1 | Desktop mở tệp, không báo lỗi, không cần Refresh | ĐẠT: 3 bảng `orders`, `sales_2026`, `types_snappy`; card "3.65M Tổng Amount" (`g1-desktop-mo-file.png`; card thứ hai nằm chồng cùng chỗ, giới hạn đã biết khi chèn visual bằng API) |
| 2 | Số liệu trong DAX query view của Desktop | ĐẠT: orders 203 dòng, Σ Lines.Qty 521; sales_2026 10 000 dòng, Σ Amount 3 654 202,84; types_snappy 1 000 dòng, Σ Money 252 471,72, 314 cờ TRUE; khớp số tính bằng Python (`g2-desktop-dax-so-lieu.png`) |
| 3 | Mô hình | ĐẠT: 3 bảng, 2 measure, 0 quan hệ |
| 4 | Power Query của Desktop đọc M do BI Pro ghi | ĐẠT: `orders` có đúng 7 bước như Desktop tự tạo (Source … Changed Type, có biểu tượng cài đặt bước) (`g3-desktop-pq-buoc-json.png`). Xem trước báo `DataFormat.Error` vì đường dẫn nguồn là đường dẫn Mac (như các gate trước) |

Bấm thử trong app BI Pro (cùng ngày): Lấy dữ liệu ▸ Tệp JSON mở thẳng Trình chỉnh sửa truy vấn với 7 bước, 6 cột · 203 dòng
(`b1-bipro-json-query-editor.png`); Lấy dữ liệu ▸ Apache Parquet mở Trình điều hướng, xem trước 200 dòng, tổng 10 000 dòng (`b2-bipro-parquet-navigator.png`);
cả hai nạp vào mô hình.

Dọn VM: Desktop đã tắt, thư mục `C:\Users\bacpew\f7g` và `f7` đã xoá; ảnh gốc (có thanh tài khoản) đã xoá, chỉ giữ ảnh cắt.

## T094 (US8, PostgreSQL), 2026-11-17, Claude lái VM

Tệp `build/f-out/f7db/bipro-f7db.pbix` (BI Pro, `GetDataSecretsTests`: tài liệu mới → Get Data ▸ PostgreSQL `10.211.55.2:55432;sales` → Load `public.sales` + câu SQL `Query1` → card measure `Tổng amount` → lưu lần đầu).

| Mục | Kết quả |
|---|---|
| Desktop 2.159 mở tệp | ĐẠT: bảng `public sales`, `Query1` ở Data pane (ảnh `g4-desktop-mo-bipro-f7db.png`) |
| Số | ĐẠT: card `350.32K` = Σ amount 350 317,03 (psql) |
| Refresh trong Desktop chạy M BI Pro ghi | ĐẠT: thêm tạm một dòng amount 1 000 trên máy chủ, Refresh → `351.32K` (ảnh `g5-desktop-refresh-bipro-f7db.png`); đã xoá dòng thử |
| Mật khẩu trong tệp | Không có (`GetDataSecretsTests` soát mọi phần ZIP và mô hình ABF đã giải nén, UTF-8 và UTF-16) |

## T094 (US8, SQLite), 2026-11-17, Claude lái VM

Tệp `build/f-out/f7db/bipro-f7sqlite.pbix` (BI Pro, `F7SQLiteGateTests`: tài liệu mới → Get Data ▸ SQLite `sales_2026.sqlite` → Load NorthSales, Customers, Sales → card `Tổng Amount` → lưu lần đầu).

| Mục | Kết quả |
|---|---|
| Desktop 2.159 mở tệp | ĐẠT: Customers, NorthSales, Sales ở Data pane (ảnh `g6-desktop-mo-bipro-f7sqlite.png`) |
| Số | ĐẠT: card `350.32K` = Σ Amount 350 317,03 (sqlite3) |
| Refresh trong Desktop | Không thử: M ghi đường dẫn tệp trên máy Mac (như CSV/Excel), VM không có đường dẫn đó |

## T103 (Fixed decimal), 2026-11-17, Claude lái VM

- Quan sát: Desktop lưu cột `Currency.Type` với `Column.DataType` 10, FormatString `\$#,0.###############;(\$#,0.###############);\$#,0.###############`, chú thích `PBI_FormatHint {"currencyCulture":"en-US"}`, giá trị Int64 nhân 10⁴ (`DictionaryStorage.DataType` 6, `Statistics_DBType` 6). Giá trị 922337203685477,5807 (Int64 lớn nhất) bị từ chối khi nạp ("contains a value … which is not supported", ảnh `t2-currency-gioi-han.png`). Golden `f9currency-desktop.pbix` (ngoài git).
- Gate: `build/f-out/f9/bipro-currency.pbix` (`CurrencyQueryApplyTests`: CSV → Query Editor đổi Price, Amount sang Fixed decimal → Close & Apply → card → lưu) mở trong Desktop, card `37.86K` = Σ Amount 37 860,12 (Python): **ĐẠT** (ảnh `g7-desktop-mo-bipro-currency.png`).
