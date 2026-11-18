# VM-F11 (T024): tài liệu mới, Enter Data, Auto date/time, tự phát hiện quan hệ

Power BI Desktop 2.159, 2026-11-18, Claude lái VM. Tài liệu mới bằng "Blank report". Ảnh đã cắt (không lộ tài khoản). Tệp Desktop lưu: `f11-desktop.pbix` (ngoài git, bản sau bước c2). Các bản trung gian ở `build/f2-out/f11/f11-step{1..5}.pbix`:

| Bước | Trạng thái |
|---|---|
| step1 | Enter Data `Table`, rồi nạp `Sales`, `Customers`, `products` cùng lúc |
| step2 | step1 + biểu đồ cột Sum of Amount theo `OrderDate` (phân cấp) |
| step3 | step2 + nạp thêm `Table (2)` (Manager, Region); đây là `f11-desktop.pbix` |
| step4 | step3, tắt Auto date/time |
| step5 | step4, bật lại Auto date/time |

## (a) Màn trống và Enter Data

**Màn "Add data to your report"** (`a3`).
- Tài liệu mới chưa có bảng nào thì canvas hiện tiêu đề "Add data to your report", dòng "Once loaded, your data will appear in the Data pane." và bốn ô:

  | Ô | Mở |
  |---|---|
  | Import data from Excel | hộp Open của Windows, lọc "Excel Files" (`a11`) |
  | Import data from SQL Server | hộp "SQL Server database": Server, Database (optional) (`a12`) |
  | Paste data into a blank table | hộp "Create Table" (`a4`) |
  | Use sample data | hộp "Two ways to use sample data": Launch tutorial, Load sample data (`a13`) |

- Dưới bốn ô có liên kết "Get data from another source →", mở hộp Get Data đầy đủ (`a14`).
- **Khi nào biến mất:** ngay khi có một bảng được nạp, ví dụ bảng Enter Data.
  - Thay vào đó là gợi ý "Build visuals with your data / Select or drag fields from the Data pane onto the report canvas." (`a6`), không có nút bấm.
  - Huỷ một hộp thoại không làm màn trống biến mất.

**Hộp "Create Table"** (`a4`).
- Ban đầu lưới có một cột "Column1", một dòng, nút "+" thêm cột hoặc dòng.
- Ô Name mặc định "Table"; nếu đã có "Table" thì mặc định "Table (2)", rồi "Table (3)" (`a8`).
- Nút Load, Edit, Cancel.
- **Dán TSV:** dòng đầu tự thành tiêu đề, kèm băng "The first row of data that you pasted has been promoted to column headers." và nút "Undo Headers" (`a5`).
- **Cancel khi lưới đã có dữ liệu** thì hỏi "Are you sure you want to exit? Your changes to the table will be lost." với Yes/No (`a9`).
- **Giới hạn:** dán quá cỡ thì báo "The clipboard contents are too large to be pasted into the table. Please split your data into multiple tables with less than 3,000 cells. You can combine them into a single table within the Power Query Editor." và lưới giữ nguyên (`a10`).
  - Đếm cả dòng tiêu đề.
  - Dán 1 cột × 3 000 dòng (tiêu đề + 2 999) thì được nhận.
  - Dán 3 001 dòng thì bị từ chối.
  - Vậy giới hạn là ≤ 3 000 ô trong clipboard.
- **M nguyên văn** (`enter-data-table.m`), bảng 3 cột × 5 dòng: chữ Việt, số, ô trống.
  - Ký tự U+FEFF ở đầu "Tên" là do cách dán qua clipboard của buổi VM (tệp UTF-16 có BOM), không phải do Desktop.

  ```
  let
      Source = Table.FromRows(Json.Document(Binary.Decompress(Binary.FromText("i45W…AA==", BinaryEncoding.Base64), Compression.Deflate)), let _t = ((type nullable text) meta [Serialized.Text = true]) in type table [#"Tên" = _t, #"Số lượng" = _t, #"Ghi chú" = _t]),
      #"Changed Type" = Table.TransformColumnTypes(Source,{{"Tên", type text}, {"Số lượng", type number}, {"Ghi chú", type text}})
  in
      #"Changed Type"
  ```

  - **Phần nén** là JSON mảng các dòng, mọi ô là chuỗi, ô trống là `""` (không phải `null`): `[["Áo thun","12","mới"],["Quần jean","5",""],["Giày","","cũ"],["Mũ","3.5","đỏ"],["Túi xách","-7","x"]]`.
    - JSON gọn, không khoảng trắng, chữ có dấu không thoát.
    - Nén Deflate thô (không header zlib), rồi Base64.
    - zlib `compressobj(level 1–9, wbits -15)` cho đúng từng byte chuỗi Base64 của Desktop (97 byte).
  - Tên cột có ký tự không phải chữ/số thì viết `#"…"`.
  - Bước `Changed Type`:
    - cột toàn số (kể cả `3.5`, `-7`, ô trống) thành `type number`;
    - cột chữ thành `type text`.
  - Trong mô hình: `Số lượng` kiểu Double (8), `SummarizeBy` Sum; `Tên` và `Ghi chú` kiểu String, `SummarizeBy` None.
  - Tên cột trong mô hình (`ExplicitName`, `SourceColumn`) **không có U+FEFF**, dù M có `#"\uFEFFTên"`. Desktop bỏ U+FEFF đầu tên cột khi nạp; `Table (2)` cũng vậy với `Manager`.
- **Sửa lại:** trong Power Query, bước Source có bánh răng; bấm vào thì mở lại "Create Table" với dữ liệu cũ (`a7`).
  - Ở chế độ sửa không có ô Name; nút là OK và Cancel.
- Nạp Enter Data không cần Refresh.

## (b) Auto date/time

- **Tuỳ chọn** (`b3`, `b4`):
  - Global ▸ Data Load ▸ Time intelligence ▸ "Auto date/time for new files", mặc định bật;
  - Current File ▸ Data Load ▸ Time intelligence ▸ "Auto date/time", mặc định bật cho tài liệu mới.
- Tài liệu mới có chú thích mô hình `__PBI_TimeIntelligenceEnabled = 1`.
- **Mỗi cột kiểu Date hoặc DateTime** của bảng thường có một `LocalDateTable_<guid>`.
  - Ví dụ: `Sales[OrderDate]` (date), `Sales[OrderTime]` (datetime), `Customers[JoinDate]` (date) thành 3 bảng cục bộ.
  - Ngoài ra mô hình có một `DateTableTemplate_<guid>`.
- Bảng tính toán. Thuộc tính và biểu thức của bảng:

  | Bảng | IsHidden | ShowAsVariationsOnly | IsPrivate | Chú thích bảng | Biểu thức |
  |---|---|---|---|---|---|
  | `DateTableTemplate_<guid>` | 1 | 0 | 1 | `__PBI_TemplateDateTable = true` | `Calendar(Date(2015,1,1), Date(2015,1,1))` |
  | `LocalDateTable_<guid>` | 1 | 1 | 0 | `__PBI_LocalDateTable = true` | `Calendar(Date(Year(MIN('Sales'[OrderDate])), 1, 1), Date(Year(MAX('Sales'[OrderDate])), 12, 31))` |

- **Cột**, giống nhau ở bảng mẫu và bảng cục bộ. Tất cả ẩn, `SummarizeBy` None.
  - Mỗi cột có chú thích `TemplateId`: Year, MonthNumber, Month, QuarterNumber, Quarter, Day.
  - Các cột số có thêm `PBI_FormatHint {"isGeneralNumber":true}`.

  | Cột | Biểu thức | Kiểu | DataCategory | FormatString | Sắp theo |
  |---|---|---|---|---|---|
  | `Date` | cột của Calendar | DateTime | PaddedDateTableDates | General Date | |
  | `Year` | `YEAR([Date])` | Int64 | Years | 0 | |
  | `MonthNo` | `MONTH([Date])` | Int64 | MonthOfYear | 0 | |
  | `Month` | `FORMAT([Date], "MMMM")` | String | Months | | `MonthNo` |
  | `QuarterNo` | `INT(([MonthNo] + 2) / 3)` | Int64 | QuarterOfYear | 0 | |
  | `Quarter` | `"Qtr " & [QuarterNo]` | String | Quarters | | `QuarterNo` |
  | `Day` | `DAY([Date])` | Int64 | DayOfMonth | 0 | |

- **Phân cấp** "Date Hierarchy" (không ẩn): Year(0), Quarter(1), Month(2), Day(3), ở mỗi bảng cục bộ và ở bảng mẫu. Mỗi phân cấp có bảng `U$`.
- **Quan hệ:**
  - từ cột ngày tới `LocalDateTable_…[Date]`, tên là GUID trần (không tiền tố);
  - `IsActive` 1, `CrossFilteringBehavior` 1, `JoinOnDateBehavior` 2 (DatePartOnly), nhiều–một;
  - mỗi quan hệ có bảng `R$`.
- **`Variation`:**
  - mỗi cột ngày có một dòng: `Name` "Variation", `RelationshipID` là quan hệ ngày, `DefaultHierarchyID` là "Date Hierarchy" của bảng cục bộ, `IsDefault` 1;
  - Data pane hiện biểu tượng lịch và mũi tên mở cạnh cột ngày (`b5`).
- **Biểu đồ** (`b6`): tích `OrderDate` rồi `Amount` thì ra biểu đồ cột "Sum of Amount by Year".
  - Trục X có `OrderDate` gồm 4 cấp Year, Quarter, Month, Day.
  - Ngăn lọc có 4 thẻ "OrderDate - Year/Quarter/Month/Day is (All)".
  - PBIR `visual.json` (`visual-theo-nam.json`):
    - mỗi cấp là `HierarchyLevel { Hierarchy { PropertyVariationSource { SourceRef Entity "Sales", Name "Variation", Property "OrderDate" }, Hierarchy "Date Hierarchy" }, Level "Year" }`;
    - `queryRef` "Sales.OrderDate.Variation.Date Hierarchy.Year", `nativeQueryRef` "OrderDate Year";
    - cờ `active` đánh dấu cấp đang hiện.
- **Performance Analyzer** (`b7`):
  - mức Year (`pa-year.dax`): `SUMMARIZECOLUMNS('LocalDateTable_…'[Year], "SumAmount", CALCULATE(SUM('Sales'[Amount])))`, rồi `SAMPLE(3502, …, [Year], 1)`, `ORDER BY [Year]`;
  - "Go to next level" tới Quarter (`pa-quarter.dax`):
    - nhóm theo `[Quarter]`, `[QuarterNo]`;
    - `TOPN(1001, …, [QuarterNo], 1, [Quarter], 1)`, `ORDER BY [QuarterNo], [Quarter]`;
    - cột sắp theo đi kèm; không còn lọc năm.
- **Tắt Auto date/time** (step4):
  - xoá hết `LocalDateTable_…`, `DateTableTemplate_…`, quan hệ ngày, `Variation`;
  - chú thích thành `__PBI_TimeIntelligenceEnabled = 0`;
  - biểu tượng lịch ở Data pane biến mất (`b8`);
  - visual đang dùng phân cấp được Desktop viết lại thành một `Column` `Sales.OrderDate` (giữ `queryRef` cũ "…Variation.Date Hierarchy.Year").
- **Bật lại** (step5):
  - sinh lại đủ bảng với GUID mới, chú thích thành 1;
  - visual không trở lại dạng phân cấp.

## (c) Tự phát hiện quan hệ

- **Tuỳ chọn:** Current File ▸ Data Load ▸ Relationships có ba ô (`b4`):
  - "Import relationships from data sources on first load", bật;
  - "Update or delete relationships when refreshing data", tắt;
  - "Autodetect new relationships after data is loaded", bật.
- **Nạp cùng lúc** `Sales` (xlsx), `Customers` (xlsx), `products` (csv). Ba truy vấn được tạo trong Power Query rồi một lần Close & Apply (`c1`). Chỉ tạo một quan hệ:
  - `AutoDetected_<guid>`: `Sales[CustomerID]` (số, lặp) → `Customers[CustomerID]` (số, duy nhất);
  - nhiều–một, `CrossFilteringBehavior` 1 (một chiều), hoạt động.
- **Không tạo:**
  - `Sales[ProductID]` (số) với `products[ProductID]` (chữ "P01"…), vì cùng tên nhưng khác kiểu;
  - `Sales[Region]` với `Customers[Region]`, vì cả hai phía đều lặp;
  - Enter Data `Table` không có cột trùng tên với bảng nào.
- **Nạp thêm vào mô hình đã có quan hệ:** thêm `Table (2)` (Manager, Region; Region duy nhất) bằng Enter Data (`c2`).
  - `AutoDetected_…`: `Sales[Region]` → `Table (2)[Region]`, hoạt động.
  - `AutoDetected_…`: `Customers[Region]` → `Table (2)[Region]`, **không hoạt động**.
    - Nếu hoạt động thì Sales tới `Table (2)` sẽ có hai đường: trực tiếp, và qua Customers.
    - Desktop vẫn tạo quan hệ nhưng tắt nó.
  - Cả hai nhiều–một, một chiều.
- Quan hệ ngày của Auto date/time không có tiền tố `AutoDetected_`.

## Còn chưa quan sát

- Tên cột trùng nhưng khác hoa thường (`customerid` với `CustomerID`).
- Cột số thực làm khoá.
- Hai phía cùng duy nhất (một–một).
- Quan hệ tự tạo có được hoàn tác bằng Ctrl+Z không: Desktop không có hoàn tác cho lần nạp.
