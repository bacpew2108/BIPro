# Báo cáo hoàn thành gói F-CONN1 (Phase F - Get Data)

## 1. Danh sách file đã tạo / sửa

Chỉ tạo các file trong danh sách được chỉ định, không chỉnh sửa bất kỳ file nào ngoài phạm vi:

### Sources/Connectors/Common
- `Sources/Connectors/Common/DateHelper.swift`: Hàm tính số ngày OLE automation (kể từ 1899-12-30) theo thuật toán civil calendar của Howard Hinnant và bộ đọc chuỗi ngày giờ ISO 8601 / `yyyy-MM-dd` / `yyyy-MM-dd HH:mm:ss`.
- `Sources/Connectors/Common/ColumnNaming.swift`: Xử lý thăng cấp tiêu đề và sinh tên cột duy nhất (`unique(_ headers:)`: rỗng → `Column<n>`, trùng → `Tên.1`, `Tên.2`).
- `Sources/Connectors/Common/ColumnTypeDetector.swift`: Bộ dò kiểu cột từ dữ liệu chuỗi (mẫu tối đa 200 dòng không rỗng, integer / double / boolean / dateTime / string, ô ngoài mẫu lỗi tạo errorMask).

### Sources/Connectors/CSV
- `Sources/Connectors/CSV/CSVParser.swift`: Bộ phân tích luồng CSV hỗ trợ RFC 4180 (ngoặc kép, ngắt dòng CRLF/LF/CR, dòng cuối không xuống dòng), tự dò mã hoá (BOM UTF-8, UTF-16LE, UTF-16BE; fallback Windows-1252), tự dò dấu phân cách trong `{",", ";", "\t", "|"}`.
- `Sources/Connectors/CSV/CSVSource.swift`: Cài đặt `CSVSource` và `CSVItem` (`preview(limit:)`, `load(progress:)`, dừng theo limit không đọc hết file, huỷ qua `Task.cancel()`, kiểm tra độ dài hàng so với tiêu đề).

### Sources/Connectors/SQLite
- `Sources/Connectors/SQLite/SQLiteSource.swift`: Mở CSDL ở chế độ chỉ đọc `SQLITE_OPEN_READONLY`, liệt kê bảng và khung nhìn từ `sqlite_master`, đọc kiểu khai báo (INT → integer, REAL/FLOA/DOUB/NUMERIC/DECIMAL → double, BOOL → boolean, DATE/TIME → dateTime, TEXT/CHAR/CLOB → string, từ chối BLOB với `SourceError.unsupported`), trích dẫn tên định danh đặc biệt, tính `rowCountHint` chỉ khi bảng < 1 000 000 dòng.

### Sources/Connectors/JSON
- `Sources/Connectors/JSON/JSONSource.swift`: Đọc JSON với `JSONSerialization`, hỗ trợ gốc là mảng bản ghi, đối tượng đơn (1 hàng), mảng giá trị đơn (cột `Value`), giữ nguyên thứ tự xuất hiện đầu tiên của các khoá, giá trị lồng (object/array) thành chuỗi JSON gọn, kiểu số nguyên → integer, số thực → double, boolean, string.

### Sources/Connectors/Excel
- `Sources/Connectors/Excel/ExcelModels.swift`: Định nghĩa kiểu ô, cấu trúc trang tính, bảng đặt tên và bộ chuyển đổi toạ độ ô (`A1`, `H501`, dải ô `A1:H501`).
- `Sources/Connectors/Excel/ExcelXMLParsers.swift`: Các bộ phân tích SAX (`XMLParser`) không dựng toàn bộ cây DOM: `SharedStringsParser`, `StylesParser` (nhận diện kiểu ngày từ numFmtId 14–22, 45–47 và định dạng tuỳ chỉnh có `y, d, h, s` ngoài ngoặc/chuỗi), `WorkbookParser` (thứ tự trang tính, hệ ngày 1904), `RelsParser`, `TableXMLParser`, `SheetParser`.
- `Sources/Connectors/Excel/ExcelSource.swift`: Cài đặt `ExcelSource`, `ExcelSheetItem`, `ExcelTableItem`, hỗ trợ `trimLeadingEmpty` (giữ/cắt hàng cột trống ở đầu), đọc ô công thức (lấy `<v>` đã tính), chuyển đổi cột (lẫn kiểu → string), ô lỗi `#N/A` vào `errorMask`.

### Tests/ConnectorsTests
- `Tests/ConnectorsTests/ColumnTypeDetectorTests.swift`: 13 test cho `ColumnNaming` và `ColumnTypeDetector`.
- `Tests/ConnectorsTests/CSVSourceTests.swift`: 16 test cho các file mẫu CSV (`sales_2026.csv`, `sales_100.csv`, `sales_dirty.csv`, `sales_semicolon.csv`, `sales_utf16.csv`, `sales_utf8bom.csv`, `multiline.csv`, `customers.csv`), các ca biên CRLF/LF/CR, huỷ `Task`, và kiểm tra `preview` trên file lớn dưới 2 giây.
- `Tests/ConnectorsTests/SQLiteSourceTests.swift`: 5 test cho `sales_2026.sqlite` (bảng `Sales`, `Customers`, khung nhìn `NorthSales`), tên bảng/cột có ký tự đặc biệt, kiểu khai báo, từ chối BLOB.
- `Tests/ConnectorsTests/JSONSourceTests.swift`: 6 test cho `orders.json` (bản ghi, đối tượng/mảng lồng, chuỗi JSON gọn, tổng phần tử Lines), đối tượng đơn, mảng primitive, thứ tự khoá.
- `Tests/ConnectorsTests/ExcelSourceTests.swift`: 10 test cho `sales_2026.xlsx` (các sheet `Sales`, `Customers`, `Notes` với `trimLeadingEmpty`, bảng đặt tên `SalesTable`), ô lỗi Excel `#N/A`, hệ ngày 1904, styles tuỳ chỉnh ngày.

---

## 2. Tóm tắt kết quả kiểm thử

Lệnh `swift build`:
- Biên dịch thành công, không có lỗi, không có cảnh báo mới trong `Sources/Connectors/**`.

Lệnh `swift test`:
- Dòng kết quả cuối cùng:
```
✔ Test run with 1759 tests passed after 38.392 seconds.
```
Toàn bộ 1759 tests chạy qua (gồm 50 test mới của F-CONN1, không có test nào bị vô hiệu hoá hoặc thất bại; các test cần Nhom6 được cấu hình tự bỏ qua theo mặc định của dự án).

---

## 3. Các quy tắc [SUY ĐOÁN] đã cài đặt

Mỗi quy tắc suy đoán đều được tách thành các hàm nhỏ, có chú thích `[SUY ĐOÁN]` rõ ràng:

1. **Dò kiểu (CSV & JSON)**:
   - Dò tối đa `sampleRows = 200` ô không rỗng đầu tiên của cột.
   - Số nguyên: chuỗi khớp `-?\d+` và chuyển đổi vừa `Int64`.
   - Số thực: số có phần thập phân/mũ với dấu chấm thập phân `.`, hoặc số nguyên vượt giới hạn `Int64`.
   - Boolean: khớp không phân biệt hoa thường `"true"` / `"false"`.
   - Ngày giờ: định dạng `yyyy-MM-dd` hoặc `yyyy-MM-dd HH:mm:ss` / `yyyy-MM-dd'T'HH:mm:ss`, tính số ngày OLE automation (ngày 0 là 1899-12-30).
   - Ô ngoài mẫu không đọc được: đưa về ô trống (`.blank`) trong cột và ghi thông điệp tiếng Việt vào `errorMask`.
   - Cột toàn ô rỗng: trả về kiểu `string` với mọi ô là `.blank`.

2. **CSV**:
   - Dấu phân cách: tự dò qua thống kê tần suất ngoài ngoặc kép của `{",", ";", "\t", "|"}` trên các dòng đầu.
   - Mã hoá: kiểm tra BOM UTF-8 (3 byte), UTF-16LE (2 byte), UTF-16BE (2 byte); nếu không có BOM thì thử đọc mẫu theo UTF-8, nếu không giải mã được thì fallback về Windows-1252.
   - Thăng cấp tiêu đề: ô rỗng đổi thành `Column<n>` (1-based), trùng lặp hậu tố `.1`, `.2`.

3. **Excel**:
   - Nhận diện kiểu ngày: `numFmtId` từ 14–22, 45–47 hoặc format code tuỳ chỉnh chứa các ký tự `y, d, h, s` ngoài cặp ngoặc kép và ngoặc vuông `[]`.
   - Hệ ngày 1904: nếu `workbookPr date1904="1"`, cộng thêm 1462 ngày vào giá trị serial.
   - Cột lẫn kiểu dữ liệu: chuyển toàn bộ về kiểu `string`, số hiển thị theo định dạng bất biến locale (`1`, `1.5`).
   - Ô lỗi Excel (`#N/A`, `#REF!`, ...): trả về `.blank` và lưu vào `errorMask` với thông điệp `"Lỗi ô Excel: <mã lỗi>"`.
   - Thứ tự mục: mọi trang tính theo thứ tự trong workbook (`kind = .sheet`), sau đó là mọi bảng đặt tên (`kind = .namedTable`).

4. **SQLite**:
   - Mở file ở chế độ chỉ đọc `SQLITE_OPEN_READONLY`.
   - Ánh xạ kiểu theo chuỗi con của kiểu khai báo (`INT` → integer, `REAL/FLOA/DOUB/NUMERIC/DECIMAL` → double, `BOOL` → boolean, `DATE/TIME` → dateTime, còn lại → string, từ chối `BLOB`).
   - `rowCountHint`: chạy truy vấn đếm có giới hạn `SELECT COUNT(*) FROM (SELECT 1 FROM <table> LIMIT 1000001)` và chỉ trả về hint nếu bảng < 1 000 000 dòng. Không chạy cho khung nhìn.

5. **JSON**:
   - Suy luận dạng bảng từ cấu trúc gốc: mảng đối tượng → danh sách bản ghi; đối tượng đơn → 1 hàng; mảng giá trị đơn → cột `Value`.
   - Thứ tự cột: bảo toàn thứ tự xuất hiện lần đầu của các khoá trong tệp JSON.
   - Cấu trúc lồng (object hoặc array): chuyển thành chuỗi JSON gọn (compact JSON string) trong cột `string`.

---

## 4. Việc tồn đọng

- Không có việc tồn đọng trong gói F-CONN1. Tất cả 6 tiêu chí xong việc đều đã đạt trọn vẹn.
