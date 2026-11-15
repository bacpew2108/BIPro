# VM-F1/F2: Desktop nạp CSV và Excel, lưu `.pbix` (2026-11-15)

Người làm: Claude lái Power BI Desktop 2.159.1231 (bản Store, Windows 11 trong Parallels) theo cho phép của bạn trong phiên này. File mẫu: `build/f-out/samples/sales_2026.csv` và `.xlsx`, thêm `probe.csv` do tôi dựng (6 dòng, mỗi cột một kiểu) để giải mã định dạng. Không lưu file `.pbix` của Desktop vào git. Ảnh chỉ giữ phần hộp thoại hoặc lưới dữ liệu (không có địa chỉ tài khoản).

## 1. Điều quan trọng nhất: `.pbix` do Desktop lưu KHÔNG có phần `DataMashup`

File lưu từ Desktop 2.159 gồm: `Version`, `[Content_Types].xml`, `Settings`, `Metadata`, `SecurityBindings`, `DataModel`, `Report/**`. Không có `DataMashup`. Truy vấn M nằm trong mô hình: `Partition.QueryDefinition` (kiểu 4, `Mode` 0, `State` 1, `DataView` 3). Nhom6 cũng không có `DataMashup`. Hệ quả cho kế hoạch: **T018/T019 (đọc/ghi `DataMashup`) không cần cho file mới**; chỉ cần nếu gặp file cũ có phần này. T061 (ghi truy vấn M) chỉ ghi `QueryDefinition`.

## 2. Hộp thoại nạp (VM-F2, quan sát)

- **Text/CSV:** hộp "sales_2026.csv": File Origin `65001: Unicode (UTF-8)` (file có chữ Việt) hoặc `1252: Western European (Windows)` (file ASCII `probe.csv`), Delimiter `Comma`, Data Type Detection `Based on first 200 rows`; ghi chú "The data in the preview has been truncated due to size limits."; nút `Load`, `Transform Data`, `Cancel`, `Extract Table Using Examples`.
- **Kiểu dò từ CSV:** `OrderID` Int64, `OrderDate` date (`type date`, định dạng `Long Date`), `Region` text, `CustomerID` Int64, `Qty` Int64, `Price` và `Amount` `type number` (double); ô trống số = `null`; ô trống chuỗi = chuỗi rỗng (không phải null).
- **Excel:** Navigator liệt kê **bảng đặt tên trước** (`SalesTable`), rồi các trang tính **theo thứ tự chữ cái** (`Customers`, `Notes`, `Sales`), không theo thứ tự trong workbook (Sales, Customers, Notes). `[SUY ĐOÁN]` cũ của BI Pro (trang tính theo thứ tự workbook rồi bảng) sai: sửa lại. Bảng đặt tên có biểu tượng bảng, trang tính biểu tượng lưới.
- Sau Load nhiều mục, Desktop hiện "Detecting relationships…" và **tự tạo quan hệ** `Sales[CustomerID] → Customers[CustomerID]` và `sales_2026[CustomerID] → Customers[CustomerID]` (nhiều-một, một chiều). Ghi nhận cho FR sau (BI Pro chưa tự dò).
- Sau Load: dải "There are pending changes in your queries that haven't been applied" (Apply changes / Discard changes) trong lúc đang nạp.

## 3. Truy vấn M Desktop sinh ra (`Partition.QueryDefinition`)

```
let
    Source = Csv.Document(File.Contents("C:\Users\Bacpew\f1\sales_2026.csv"),[Delimiter=",", Columns=8, Encoding=65001, QuoteStyle=QuoteStyle.None]),
    #"Promoted Headers" = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
    #"Changed Type" = Table.TransformColumnTypes(#"Promoted Headers",{{"OrderID", Int64.Type}, {"OrderDate", type date}, {"Region", type text}, {"CustomerID", Int64.Type}, {"Product", type text}, {"Qty", Int64.Type}, {"Price", type number}, {"Amount", type number}})
in
    #"Changed Type"
```

Excel: `Source = Excel.Workbook(File.Contents("…xlsx"), null, true)`, `Sales_Sheet = Source{[Item="Sales",Kind="Sheet"]}[Data]`, `#"Promoted Headers" = Table.PromoteHeaders(Sales_Sheet, [PromoteAllScalars=true])`, `#"Changed Type" = …`. Tên bước: `Source`, `Promoted Headers`, `Changed Type` (Excel thêm `<Tên>_Sheet`). Đây là golden cho `StepFactory` (T055).

## 4. Hàng `Column` Desktop ghi (so với BI Pro)

- Cột dữ liệu: `Alignment` **1**, `State` 1, `IsNullable` 1, `Type` 1, `SourceColumn` = tên cột; `FormatString` `0` (Int64), `Long Date` (date), rỗng (double, text).
- `SummarizeBy`: số thực 3; Int64 `Qty` 3; Int64 tên `…ID` 2 (`CustomerID`); `OrderID` 6 (`[SUY ĐOÁN]`: cột duy nhất → Đếm; BI Pro chưa tái hiện); chuỗi và ngày 2.
- Cột `RowNumber-2662979B-1795-4F74-8F37-6A1BA8059B61`: **tên cố định cho mọi bảng**, ẩn, `IsKey` 1, `IsUnique` 1, `Type` 3.
- Bảng ngày tự động: mỗi cột ngày có `LocalDateTable_<guid>` kèm hàng hệ thống (Auto date/time); chưa ghi trong BI Pro (không bắt buộc để mở file).

## 5. Lưu trữ VertiPaq mà Desktop ghi cho mỗi bảng (đã đối chiếu từng byte)

- **Mã hoá:** chuỗi, ngày (double) và số nguyên/thập phân lớn dùng **từ điển băm** (`.dictionary`, `DictionaryStorage.Type` 1, `BaseId` 2, id dữ liệu = chỉ số + 3, NULL = 2); số nguyên và thập phân ít chữ số dùng **mã hoá theo giá trị** (không có `.dictionary`, `Type` 2, `Magnitude` ≠ 0, có tệp `.hidx` cạnh bảng, `AttributeHierarchyStorage.MaterializationType` 1, `ColumnDataToPosition` -1). BI Pro dùng từ điển băm cho mọi kiểu (Desktop chấp nhận, đã mở được).
- **`.idf`/`.idfmeta` cột:** bảng 16 run (run đầu = một khối bit-packed `0xFFFFFFFF`, 15 run còn lại bằng 0); `.idfmeta` 264 byte: ô "distinct states" luôn 0; "original min" luôn 2; "other RLE runs" = 1; thành phần thứ nhất của "facet" = min(số dòng, 13) `[SUY ĐOÁN]`; phần đuôi `SDOs` ghi (0, 16) và (8 + 16×8, số từ). Khi Desktop thấy lợi nó dùng RLE; BI Pro luôn bit-packed, Desktop chấp nhận.
- **Bảng hệ thống `H$<Bảng> (<id>)$<Cột> (<id>)` cho từng cột dùng từ điển băm** (bảng ẩn `SystemFlags` 1; cột `POS_TO_ID`, `ID_TO_POS`; phân vùng `Type` 3, `Mode` 2; `SegmentMapStorage` `Type` 2, `RecordCount` = id lớn nhất + 1, `SegmentCount` 2, `RecordsPerSegment` = số mục từ điển kể cả NULL; 316 byte `.idfmeta`). Cột mã hoá theo giá trị chỉ có `POS_TO_ID`. Định dạng đã giải xong và khớp từng byte với **9 cột thật của Marketing** (chuỗi có dấu, double, int, có NULL, 4 đến 1250 mục): xem `HierarchyEncodingTests`, `DesktopGoldenTests`. Chuỗi sắp theo so sánh văn hoá en-US (khớp Desktop trên tiếng Việt có dấu của Marketing; `Đ` chưa thử).
- **Cột RowNumber (mã hoá theo giá trị):** `DictionaryStorage` `LastId` 2 và `Size` 144 (mọi cột mã hoá theo giá trị), không phải id lớn nhất.
- `DictionaryStorage`: `IsOperatingOn32` 1 cho từ điển int phần tử 4 byte; chuỗi `DictionaryFlags` 3; `Size` của từ điển chuỗi/số là kích thước bộ nhớ ước tính (17120 cho 4 chuỗi một ký tự), **không phải** kích thước tệp; BI Pro ghi kích thước tệp và Desktop vẫn mở được.
- `ColumnStorage`: `Collation`/`OrderByColumn` NULL; chuỗi `Statistics_XMType` 2, double 1; `Statistics_OthersRLERuns` 1 (RowNumber 0, `EncodingHint` 1).

## 6. Kết quả đối chiếu trên Desktop

Xem `docs/phase-f-evidence/vm-f0/CHECKLIST-KET-QUA.md` (lần 4: file mở được, 100 dòng đúng, dòng 8 trống, Marketing 1 363 dòng nguyên vẹn).

## 7. Bổ sung 2026-11-15 tối: logic, cột ít giá trị, từ điển chuỗi rỗng

- **Logic** (CSV `true/false`, ô trống thành null; Desktop dò `type logical`): `Column.DataType` 11, `SummarizeBy` 2, `FormatString` `"TRUE";"TRUE";"FALSE"`, `Statistics_DBType` 11; Desktop lưu mã hoá theo giá trị (`DictionaryStorage` Type 2, DataType 6, `BaseId` -3 khi có null và -2 khi chỉ true), `MinValue`/`MaxValue` `FALSE`/`TRUE`. BI Pro ghi cột logic bằng từ điển băm số nguyên 0/1 (như cột số nguyên); Desktop mở được (file `f1-f`).
- **Bảng `H$` của cột ít giá trị:** mảng `POS_TO_ID` / `ID_TO_POS` (cùng độ dài `maxID + 1`) được cắt thành đoạn `card` dòng (`RecordsPerSegment`): 1 giá trị = 4 đoạn, 2 giá trị = 3 đoạn (2, 2, 1), từ 3 giá trị trở lên 2 đoạn. Mỗi đoạn lưu `u64 n` + `n` từ u64, `n = số dòng của đoạn / 2 + 1`. `.idfmeta` có một khối `CS` mỗi đoạn và phần đuôi `SDOs` với (độ lệch byte, số từ) của từng đoạn (596 byte cho 4 đoạn, 456 cho 3, 316 cho 2). `SegmentMapStorage.SegmentCount` và `SegmentStorage.SegmentCount` bằng số đoạn. Khớp byte với file Desktop (bảng `probe4`: cột hằng, hai giá trị, chuỗi rỗng, ngày hằng); lỗi trước đó "DBCC failed while checking the 'H$…' table … segment map" khi cột có một giá trị.
- **Từ điển chuỗi có mục rỗng:** tiêu đề trang đặt cờ 1 (xem `CHECKLIST-KET-QUA.md`).
