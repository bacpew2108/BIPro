# VM-F5: file `.pbix` mới do Desktop tạo (Desktop 2.159, 2026-11-16)

Người dùng cho lái VM. Desktop mở trống (Start ▸ Blank report), lưu ngay thành `blank.pbix`; rồi Get data ▸ Text/CSV ▸ `sales_100.csv` ▸ Load, lưu lại (bản chép ra Mac đặt tên `one-table.pbix`). File không đưa vào git (ở `build/f-out/f5/`). Đọc bằng `pbix-dump info|files|extract` và `sqlite3`.

## 1. Tập thành phần (cả hai file giống nhau, 11 phần)

| Phần | Mã hoá | Ghi chú |
|---|---|---|
| `Version` | UTF-16LE, không BOM | `1.32` |
| `[Content_Types].xml` | UTF-8 có BOM | `Default json`, `Override` cho `/Version`, `/Settings`, `/Metadata`, `/SecurityBindings`, `/DataModel` |
| `Settings` | UTF-16LE | `{"Version":4,"ReportSettings":{},"QueriesSettings":{"TypeDetectionEnabled":true,"RelationshipImportEnabled":true,"Version":"2.159.1206.0"}}` |
| `Metadata` | UTF-16LE | `{"Version":5,"AutoCreatedRelationships":[],"CreatedFrom":"Cloud","CreatedFromRelease":"2026.10"}` |
| `Report/StaticResources/SharedResources/BaseThemes/Fluent2-CY26SU10.json` | UTF-8 | chủ đề nền 39 KB |
| `Report/definition/version.json` | UTF-8 | `"version":"2.0.0"` |
| `Report/definition/report.json` | UTF-8 | `themeCollection.baseTheme` Fluent2-CY26SU10 (`reportVersionAtImport` visual 2.14.0, report 3.4.0, page 2.3.1), `resourcePackages` SharedResources, `settings` (6 cờ) |
| `Report/definition/pages/pages.json` | UTF-8 | một trang, `activePageName` = tên trang |
| `Report/definition/pages/<20 hex>/page.json` | UTF-8 | `displayName` "Page 1", `FitToPage`, 1920×1080, chưa có visual |
| `SecurityBindings` | nhị phân | 454 byte, khối DPAPI theo máy (BI Pro không tạo được; BI Pro đã bỏ phần này khi lưu từ Phase D mà Desktop vẫn mở) |
| `DataModel` | ZIP stored | XPress9; file trống 8,8 KB |

**Không có `DataMashup`, không có `DiagramLayout`, không có `Report/Layout`** (báo cáo PBIR). Truy vấn M của bảng nạp nằm ở `Partition.QueryDefinition` trong mô hình (như VM-F8).

## 2. Mô hình trống

- ABF có 3 tệp: `<GUID>.0.db.xml`, `0.CryptKey.bin` (144 byte), `metadata.sqlitedb` (328 KB, 73 bảng lược đồ, `SCHEMAVERSION` 126).
- Dòng có dữ liệu: `DBPROPERTIES` 12, `Model` 1 (`Culture` en-US, `DefaultPowerBIDataSourceVersion` 2, `DataAccessOptions` legacyRedirects + returnErrorValuesAsNull), `Culture` 1 (en-US), `Annotation` 1: `__PBI_TimeIntelligenceEnabled = 1` (Auto date/time bật). `MAXID` 11.
- Lược đồ khác Nhom6 ở một chỗ dù cùng `SCHEMAVERSION`: `ColumnStorage` **không có** cột `FullTextIndexStorageID`, `FullTextIndexStorage` không có `ColumnStorageID`. Bộ ghi bảng của BI Pro trước đây luôn ghi cột này nên lỗi trên file mới; đã sửa để chỉ ghi khi bảng có cột đó.

## 3. File một bảng (`sales_100`, 100 dòng, 8 cột)

- 28 bảng: `sales_100` và, vì Auto date/time bật, `DateTableTemplate_<GUID>` (ẩn, riêng tư) cùng `LocalDateTable_<GUID>` (ẩn, `ShowAsVariationsOnly`) cho cột `OrderDate`, kèm một `Relationship`, `Variation`, 2 `Hierarchy` (Date Hierarchy), 8 `Level`, các bảng `H$`/`U$`/`R$`.
- Chú thích mô hình: `PBI_QueryOrder = ["sales_100"]` (tạo khi có truy vấn đầu tiên). Bảng: `PBI_ResultType = Table`.

## 4. Quyết định cho BI Pro (T076)

- "File → Mới" dựng tài liệu từ **mẫu `DataModel` trống do Desktop tạo** (đóng trong mã, `NewDocumentTemplate.swift`) vì `metadata.sqlitedb` trống có 73 bảng lược đồ; các phần ngoài mô hình dựng tay theo bảng trên, bỏ `SecurityBindings`.
- Sửa hai chú thích mô hình của mẫu: `__PBI_TimeIntelligenceEnabled = 0` (BI Pro chưa dựng bảng ngày cục bộ, phân cấp và quan hệ ẩn mà Desktop sinh khi bật; Nhom6 cũng tắt), `PBI_QueryOrder = []` (bộ ghi nối tên bảng khi nạp, như Desktop).
- Tên trang 20 ký tự hex sinh mới mỗi lần, tên hiển thị "Page 1" như Desktop.
