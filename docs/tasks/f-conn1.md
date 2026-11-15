Bạn làm việc trong repo Swift "BI Pro" (ứng dụng macOS giống Power BI Desktop, SwiftUI, macOS 15), trong một git worktree riêng tách từ `main`. Phase F đang làm phần Get Data. Gói của bạn, **F-CONN1**: bốn nguồn dữ liệu đọc file thành bảng trong bộ nhớ: **CSV, Excel (.xlsx), SQLite, JSON**. Chỉ dùng framework hệ thống và thư viện của repo; không thêm package, không tải gì từ mạng.

## Đọc trước (hợp đồng đã có, giữ nguyên)

- `Sources/Connectors/DataSource.swift`: `DataSource`, `SourceItem`, `SourceError`, `SourceColumn`, `SourceProgress`. Đây là API bạn cài đặt.
- `specs/010-f-get-data-power-query-t3/contracts/data-source.md`: bất biến của hợp đồng.
- `Sources/ColumnStore/TableData.swift` và `InMemoryColumnSource.swift` (phần `ColumnBuilder`): kết quả của bạn là `TableData`, cột dựng bằng `ColumnBuilder.integers/doubles/currency/dateTimes/booleans/strings` (`nil` là ô trống/BLANK; chuỗi rỗng `""` khác BLANK). Ô lỗi dùng `TableData.errorMask` (cột → dòng → thông điệp).
- `Sources/PBIXKit/ZipArchive.swift`: đọc ZIP, đã giải nén `deflate` (dùng cho xlsx).
- `Tests/ConnectorsTests/FFixtures.swift`, `DataSourceContractTests.swift`: mẫu viết test. `FFixtures.sample("tên")` trả đường dẫn file mẫu trong `build/f-out/samples/` (thư mục chỉ đọc; đã được nối sẵn vào worktree của bạn). File mẫu do `scripts/f-samples/make_samples.py` sinh; bạn không chạy script đó.

## File được sửa hoặc tạo (không sửa gì ngoài danh sách)

- `Sources/Connectors/Common/**`: dò kiểu cột, đặt tên cột, trợ giúp chung.
- `Sources/Connectors/CSV/**`, `Sources/Connectors/Excel/**`, `Sources/Connectors/SQLite/**`, `Sources/Connectors/JSON/**`.
- `Tests/ConnectorsTests/**`: chỉ **thêm** file mới (`ColumnTypeDetectorTests.swift`, `CSVSourceTests.swift`, `ExcelSourceTests.swift`, `SQLiteSourceTests.swift`, `JSONSourceTests.swift`); không sửa `FFixtures.swift`, `FixturesTests.swift`, `DataSourceContractTests.swift`.
- `docs/tasks/f-conn1-report.md`: báo cáo cuối.

Mọi file khác giữ nguyên, gồm `Package.swift` (target `Connectors` đã phụ thuộc `ColumnStore`, `PBIXKit` và liên kết `sqlite3`), `DataSource.swift`, và mọi thứ ngoài `Sources/Connectors/**`. Target `Connectors` dùng Swift 6 (kiểm tra đồng thời nghiêm ngặt): kiểu công khai phải `Sendable`.

## API công khai (giữ đúng tên; lead gọi từ Navigator và Query Editor)

```swift
public struct CSVSource: DataSource {
    public struct Options: Sendable, Equatable {
        public var delimiter: Character?        // nil = tự dò trong {",", ";", "\t", "|"}
        public var encoding: String.Encoding?   // nil = tự dò (BOM UTF-8/UTF-16, rồi UTF-8, rồi Windows-1252)
        public var promoteHeaders = true        // hàng đầu thành tên cột; false = Column1, Column2, ...
        public var detectTypes = true           // false = mọi cột là chuỗi
        public init(...)
    }
    public init(url: URL, options: Options = Options())
}
public struct ExcelSource: DataSource {
    public struct Options: Sendable, Equatable {
        public var promoteHeaders = true
        public var detectTypes = true
        public var trimLeadingEmpty = false     // true = bỏ hàng/cột trống ở đầu vùng dữ liệu
    }
    public init(url: URL, options: Options = Options())
}
public struct SQLiteSource: DataSource { public init(url: URL) }
public struct JSONSource: DataSource   { public init(url: URL) }

// Common
public enum ColumnTypeDetector {
    public static let sampleRows = 200
    /// Dò kiểu từ danh sách chuỗi (CSV) theo quy tắc bên dưới; trả cột và ô lỗi (nếu có).
    public static func column(from strings: [String?], name: String) -> (data: ColumnData, errors: [Int: String])
}
public enum ColumnNaming {
    /// Tên cột sau thăng cấp tiêu đề: rỗng → "Column<n>" (n từ 1, theo vị trí); trùng → "Tên.1", "Tên.2".
    public static func unique(_ headers: [String?]) -> [String]
}
```

Mỗi nguồn trả các mục qua `items()`; mỗi mục là một `SourceItem` (struct `Sendable`) cài `preview(limit:)` và `load(progress:)`.

## Hành vi cần cài

Quy tắc dưới đây là **[SUY ĐOÁN]** (chưa đối chiếu Power BI Desktop; buổi VM-F2 sẽ chốt). Đặt mỗi quy tắc trong một hàm riêng, nhỏ, có chú thích `[SUY ĐOÁN]`, để lead sửa nhanh khi có quan sát.

**Dò kiểu (CSV)**: lấy tối đa `sampleRows` ô không rỗng đầu tiên của cột (ô `""` là `nil`).
- Mọi ô là số nguyên (`-?\d+`, vừa Int64) → `integer`.
- Mọi ô là số (có phần thập phân hoặc mũ, dấu thập phân `.` bất kể locale) → `double`.
- Mọi ô là `true`/`false` (không phân biệt hoa thường) → `boolean`.
- Mọi ô là ngày `yyyy-MM-dd` hoặc ngày giờ `yyyy-MM-dd HH:mm:ss` / `yyyy-MM-dd'T'HH:mm:ss` → `dateTime` (số ngày kể từ 1899-12-30, như `StoredValue.dateTime`).
- Còn lại → `string`.
- Ô nằm ngoài mẫu mà không đọc được theo kiểu đã chọn → ô trống trong cột và một mục trong `errors` (thông điệp tiếng Việt, ví dụ `Không thể chuyển 'n/a' sang số nguyên`). Cột toàn ô rỗng → `string` với mọi ô `nil`.

**CSV**: ô trong ngoặc kép có thể chứa dấu phân cách, xuống dòng, `""` (một dấu `"`); chấp nhận `\n`, `\r\n`, `\r`; dòng cuối không có xuống dòng; BOM UTF-8/UTF-16 bị bỏ khỏi dữ liệu; hàng ngắn hơn tiêu đề điền `nil`, hàng dài hơn tiêu đề báo `SourceError.unreadable` kèm số dòng. File rỗng → `SourceError.empty`. File chỉ có tiêu đề → bảng 0 dòng, kiểu cột `string`. Một mục duy nhất: `kind = .file`, `name` = tên file bỏ đuôi. `preview(limit:)` đọc theo luồng và dừng sau `limit` dòng dữ liệu, không nạp cả file. `load` gọi `progress` (0…1, theo byte đã đọc) ít nhất ở đầu và cuối, kiểm `Task.isCancelled` (ném `SourceError.cancelled`).

**Excel**: `items()` liệt kê mọi trang tính theo thứ tự trong workbook (`kind = .sheet`), rồi mọi bảng đặt tên (`kind = .namedTable`, từ `xl/tables/*.xml`, theo `ref`). Đọc `workbook.xml` + `_rels`, `sharedStrings.xml`, `styles.xml` (ô có `numFmtId` ngày/giờ, gồm 14–22, 45–47, hoặc định dạng tuỳ chỉnh chứa `y`, `d`, `h`, `s` ngoài ngoặc/chuỗi, là ngày), `sheetN.xml` (ô `t="s"` chuỗi dùng chung, `t="str"` chuỗi công thức, `t="inlineStr"`, `t="b"`, `t="e"` lỗi, số; ô công thức lấy giá trị `<v>` đã tính), hệ ngày 1900 (mặc định, số ngày ≥ 61 đã khớp gốc 1899-12-30) và 1904 (`workbookPr date1904="1"`). Đọc `sheetN.xml` bằng `XMLParser` kiểu SAX, không dựng cả cây. Cột kiểu: mọi ô là ngày → `dateTime`; mọi ô logic → `boolean`; mọi ô số → `integer` nếu toàn số nguyên, ngược lại `double`; mọi ô chuỗi → `string`; **lẫn kiểu → `string`**, số viết ở dạng bất biến locale (`1`, `1.5`). Ô lỗi Excel (`#N/A`...) → ô trống trong cột và một mục `errors`. Ô trống → `nil`. `trimLeadingEmpty == false`: vùng dữ liệu bắt đầu ở `A1`, hàng/cột trống ở đầu giữ nguyên (cột `Column1…`, hàng `nil`); `true`: bắt đầu ở ô đầu tiên có dữ liệu. Bảng đặt tên chỉ lấy vùng `ref`, và cột lấy tên từ `tableColumn` của bảng. `rowCountHint` của trang tính/bảng lấy từ `dimension`/`ref` khi có. `preview` dừng sau `limit` hàng.

**SQLite**: mở chỉ đọc (`SQLITE_OPEN_READONLY`); không bao giờ ghi vào file. Liệt kê bảng (`kind = .table`) và khung nhìn (`kind = .view`) trong `sqlite_master`, bỏ bảng `sqlite_*`. Kiểu cột theo kiểu khai báo (so khớp không phân biệt hoa thường, theo chuỗi con): chứa `INT` → `integer`; `REAL`, `FLOA`, `DOUB`, `NUMERIC`, `DECIMAL` → `double`; `BOOL` → `boolean`; `DATE`, `TIME` → `dateTime` (đọc chuỗi ISO 8601; giá trị không đọc được là ô lỗi); còn lại (`TEXT`, `CHAR`, `CLOB`, không khai báo, `BLOB`) → `string` (BLOB báo `SourceError.unsupported("cột BLOB …")` khi `load`). `NULL` → `nil`. Tên bảng/cột có ký tự đặc biệt phải được trích dẫn đúng (`"` nhân đôi). `preview` dùng `LIMIT`. `rowCountHint` = `SELECT COUNT(*)` chỉ khi bảng nhỏ hơn 1 000 000 dòng (không chạy cho khung nhìn).

**JSON**: gốc là mảng bản ghi (đối tượng) → một mục (`kind = .record`, tên = tên file bỏ đuôi); gốc là một đối tượng → một hàng; gốc là mảng giá trị đơn → bảng một cột `Value`. Cột = hợp của các khoá, theo thứ tự xuất hiện lần đầu; khoá thiếu → `nil`. Kiểu cột: như CSV nhưng từ giá trị JSON (`number` nguyên → `integer`, có phần lẻ → `double`, `bool` → `boolean`, `string` → `string`, lẫn kiểu → `string`; không dò chuỗi ngày). Giá trị lồng (đối tượng hoặc mảng) → chuỗi JSON gọn trong cột `string` **[SUY ĐOÁN]** (bảng chưa chứa được bản ghi lồng; lead xử lý ở bước mở rộng cột sau). Đọc bằng `JSONSerialization`. JSON không hợp lệ → `SourceError.unreadable` kèm vị trí nếu có.

**Chung**: lỗi trả `SourceError` với thông điệp tiếng Việt dành cho người dùng (không dán đường dẫn đầy đủ, không mật khẩu). File không tồn tại hoặc không đọc được → `SourceError.unreadable`. Không ghi vào file nguồn.

## Dữ liệu kiểm (sự thật độc lập, tính bằng Python trên chính file mẫu; dùng làm hằng trong test)

| File mẫu | Sự thật |
|---|---|
| `sales_2026.csv` | 10 000 dòng; cột `OrderID, OrderDate, Region, CustomerID, Product, Qty, Price, Amount`; kiểu: integer, dateTime, string, integer, string, integer, double, double. Dòng đầu: `1, 2026-03-02, Trung tâm, 7, Đồng hồ, 11, 120.0, 1320.0`. Dòng cuối: `10000, 2026-11-23, East, 43, Quần jean, 14, 25, 350`. Tổng `Qty` = 99742; tổng `Amount` = 3654202.84 (sai số 0,01); 5 giá trị `Region` khác nhau. File dùng xuống dòng `\r\n`. |
| `sales_100.csv` | 100 dòng; tổng `Amount` = 37860.12; tổng `Qty` = 1058; cùng dòng đầu như trên. |
| `sales_dirty.csv` | 31 dòng (30 + 1 dòng trùng ở cuối, trùng dòng đầu). Dòng 3 (đếm từ 1, không tính tiêu đề): `Product` là chuỗi rỗng. Dòng 4: `Region` rỗng. Dòng 5: `Qty` = `n/a` (cột `Qty` còn lại toàn số nguyên; vì 5 < 200 nên `n/a` nằm trong mẫu → cả cột `Qty` là `string`). Dòng 6: `Price` rỗng → ô trống. |
| `sales_semicolon.csv` | dấu phân cách `;`, 30 dòng, dòng đầu như `sales_100.csv`. |
| `sales_utf16.csv` | UTF-16 có BOM, 30 dòng, dòng đầu như trên. |
| `sales_utf8bom.csv` | UTF-8 có BOM, 30 dòng; tên cột đầu đúng là `OrderID` (không dính BOM). |
| `multiline.csv` | cột `Id, Note`; 3 dòng; `Note` dòng 1 = `dòng một\ndòng hai`; dòng 2 = `có "ngoặc kép", dấu phẩy`; dòng 3 = ô trống (`nil`); `Id` integer. |
| `customers.csv` | 50 dòng; `CustomerID, Name, Segment`; dòng đầu `1, Khách 1, Wholesale`; dòng cuối `50, Khách 50, Online`. |
| `sales_2026.xlsx` | Trang tính `Sales`, `Customers`, `Notes` (theo thứ tự) rồi bảng đặt tên `SalesTable`. `Sales`: 500 dòng dữ liệu + tiêu đề, cột `OrderDate` là ô số có kiểu ngày (dòng 1: 46083 = 2026-03-02), cột `Amount` là ô công thức (giá trị đã tính dòng 1 = 1320); dòng đầu `1, 2026-03-02, Trung tâm, 7, Đồng hồ, 11, 120, 1320`; dòng cuối `500, …, North, 5, Mũ, 2, 9.99, 19.98`. `Customers`: 50 dòng, dòng đầu `1, Khách 1, Wholesale`. `Notes`: hai hàng đầu trống, tiêu đề `Key, Value` ở hàng 3, dữ liệu `a,1`, `b,(trống)`, `c,3`; với `trimLeadingEmpty = true` và `promoteHeaders = true` → cột `Key, Value`, 3 dòng, `Value` = 1, `nil`, 3 (integer). `SalesTable`: cùng dữ liệu `Sales`, 500 dòng. |
| `sales_2026.sqlite` | Bảng `Sales` (1000 dòng; `OrderDate` khai báo TEXT nên là `string`; `Qty` integer; `Price`, `Amount` double; tổng `Qty` = 9972, tổng `Amount` = 350317.03), bảng `Customers` (50 dòng), khung nhìn `NorthSales` (201 dòng). Dòng đầu `Sales`: `1, "2026-03-02", Trung tâm, 7, Đồng hồ, 11, 120.0, 1320.0`. |
| `orders.json` | mảng 100 bản ghi; khoá `OrderID` (integer), `Customer` (đối tượng lồng → chuỗi JSON), `Lines` (mảng lồng → chuỗi JSON), `Note` (string; `nil` ở các bản ghi 10, 20, …, 100). Bản ghi 1: `OrderID = 1`, `Customer` chứa `"Id":5`, `Note = "đơn 1"`. Tổng số phần tử `Lines` = 203. |

Ngoài file mẫu, viết thêm test với **file nhỏ tạo ngay trong test** (ghi vào thư mục tạm của test, xoá sau khi xong) cho: CRLF/LF/CR, dòng cuối không xuống dòng, hàng ngắn/dài hơn tiêu đề, file rỗng, file chỉ có tiêu đề, tên cột trùng và rỗng (`ColumnNaming.unique`), số rất lớn (vượt Int64 → `double`), ô ngoài mẫu 200 dòng không đọc được (một cột 250 dòng toàn số nguyên với `abc` ở dòng 230 → kiểu integer, ô dòng 230 trống, một mục `errors`), huỷ giữa chừng (`Task` bị huỷ → `SourceError.cancelled`), `preview` trên file CSV sinh 300 000 dòng xong trong dưới 2 giây (ngưỡng rộng, chỉ để chứng minh không đọc cả file).

## Làm theo thứ tự này (từng lát: viết test đỏ trước, rồi cài đặt cho xanh)

1. `Common`: `ColumnTypeDetector`, `ColumnNaming`.
2. `CSVSource`.
3. `SQLiteSource`.
4. `JSONSource`.
5. `ExcelSource` (lớn nhất; tách đọc ZIP/XML, kiểu ô, và dựng bảng thành các hàm nhỏ).

Mọi test dùng dữ liệu mẫu thật và các hằng ở bảng trên; không so khớp bằng cách tính lại chính kết quả của mã đang test; không sửa hay tắt test có sẵn.

## Lệnh được phép (chạy từng lệnh riêng, không dùng `&&`, `;`, `|`, `cd`, `rm`, `cp`, `mkdir`, `python`)

`swift build`, `swift test`, `swift test --filter <tên>`, `git status`, `git diff`, `git diff --stat`, `git grep <mẫu>`, `git log --oneline`, `ls <thư mục>`. Dùng công cụ đọc/ghi file của bạn để tạo và sửa file. Lần chạy `swift build`/`swift test` đầu tiên biên dịch lại cả repo, mất vài phút.

## Tiêu chí xong việc (tất cả phải đúng, kiểm từng mục)

1. `swift build` không lỗi, không cảnh báo mới từ `Sources/Connectors/**`.
2. `swift test` **toàn bộ** qua (test cần file Nhom6 của người dùng sẽ tự bỏ qua; đó là bình thường). Chép dòng kết quả cuối (`Test run with N tests passed`) vào báo cáo.
3. Mỗi dòng của bảng "Dữ liệu kiểm" có ít nhất một test khẳng định đúng giá trị ghi ở đó (số dòng, tên cột, kiểu, dòng đầu/cuối, tổng), cho cả `preview` và `load`.
4. Mỗi hành vi in đậm ở mục "Hành vi cần cài" có test.
5. `git status` chỉ liệt kê file trong danh sách được sửa; bạn không commit, không push.
6. Báo cáo ngắn `docs/tasks/f-conn1-report.md`: file đã tạo/sửa, tóm tắt thay đổi, dòng kết quả `swift test`, mọi quy tắc [SUY ĐOÁN] bạn chọn khác gợi ý (và vì sao), việc còn tồn đọng. Không bàn giao như đã xong khi còn mục nào chưa đạt: ghi rõ mục nào và lý do.
