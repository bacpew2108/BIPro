# Mô hình dữ liệu Phase F

## Truy vấn và bước (`MEngine`, `BIPro/Query/Editor`)

- **Query**: `id`, `name`, `steps: [Step]`, `enableLoad: Bool`, `source: SourceRef?`, `loadedTable: TableName?`, `errorState: QueryError?`. Tên duy nhất trong tài liệu, không trùng bảng khác (hậu tố như Desktop).
- **Step**: `name` (duy nhất trong truy vấn; "Source", "Navigation", "Promoted Headers", "Changed Type"… theo quan sát), `expression: String` (M), `kind: StepKind` (lệnh ribbon sinh ra, hoặc `custom`), `result: PreviewTable?` (≤ 1000 dòng, cache), `error: MError?`.
- **Biểu thức đầy đủ**: `let <bước 1> = …, <bước 2> = … in <bước cuối>`; Advanced Editor sửa nguyên văn, phân tích lại thành bước; phần không phân tích thành bước được thì giữ nguyên làm một bước `custom`.
- **Dependencies**: đồ thị truy vấn → truy vấn (tham chiếu, Merge, Append) và nguồn; không vòng.

## Giá trị M (`MValue`)

`null`, `logical`, `number` (Double, Decimal cho currency), `text`, `date`, `time`, `datetime`, `duration`, `list`, `record`, `table (TableData)`, `function`, `error(reason, message, detail)`. Ô lỗi nằm trong cột `TableData` qua mặt nạ lỗi; lỗi cấp bước làm hỏng bước và các bước sau.

## `TableData` (`ColumnStore`, mới)

- `columns: [(name, type, ColumnData)]`, `rowCount`, `errorMask: [columnIndex: [row: MError]]` (thưa).
- Kiểu: `integer` (Int64), `double`, `currency` (Int64 chia 10 000, "Fixed decimal"), `dateTime`, `boolean`, `string`; `any` chỉ trong M (đã đổi kiểu khi nạp).
- Bất biến: mọi cột cùng `rowCount`; tên cột duy nhất; `ColumnData` mã hoá từ điển có `null` là BLANK.

## Nguồn dữ liệu (`Connectors`)

- **DataSource**: `kind` (`csv`, `excel`, `json`, `sqlite`, `parquet`, `postgres`), `location` (đường dẫn hoặc máy chủ/cơ sở dữ liệu), `options` (mã hoá, dấu phân cách, trang tính…), `credentialRef` (khoá Keychain, không có mật khẩu trong mô hình).
- **SourceItem**: `kind` (sheet, table, namedTable, view, record…), `name`, `columns`, `rowCountHint`; `preview(limit)`, `load()` trả `TableData`.

## Bảng nạp và lưu T3

- **LoadedTable** (BIPro) = `TableData` + tên truy vấn; sang PBIXKit thành **`NewTable`** (lớp tham chiếu, `ModelEdit` so và băm theo định danh; không chứa `TableData` vì PBIXKit không phụ thuộc ColumnStore): tên bảng, `queryName`, `TableData` (trong bộ nhớ đến khi lưu), ánh xạ cột → `ColumnID` mô hình, trạng thái `new | replaced | unchanged`.
- **`ModelEdit` mới**: `.addTable(LoadedTable)`, `.replaceTable(name, LoadedTable)`, `.dropTable(name)`, `.addCalculatedColumn(table, name, dax)`, `.addCalculatedTable(name, dax)`; mở rộng danh sách của Phase E.
- **`VertiPaqWriter.ColumnInput` mở rộng**: `Values` thêm `currency([Int64?])`, `dateTime([Double?])`, `boolean([Bool?])`, `int64`/`double` nhận `nil`; `EncodedTable` thêm danh sách tệp `H$` nếu cần; `DictionaryStorage`, `ColumnStorage`, `Segment`, `Partition`, thống kê min/max/distinct.
- **DataMashup**: `version`, `package` (`Section1.m` text, `Formulas`, `Config/Package.xml`), `permissions` (XML), `metadata` (XML, mục theo truy vấn: `FillEnabled`, `FillToDataModelEnabled`, `LastAnalysisServicesFormulaText`…), `permissionBindings` (byte nguyên).

## Cột và bảng tính toán

- **CalculatedColumn**: bảng, tên, biểu thức DAX, kiểu suy ra, dữ liệu (mã hoá khi lưu), phụ thuộc (cột/measure).
- **CalculatedTable**: tên, biểu thức DAX, kiểu cột suy ra, dữ liệu.
- Thứ tự tính = sắp xếp tô-pô đồ thị phụ thuộc; vòng → lỗi `CircularDependency`.

## Tài liệu mới

- **NewDocument**: tập thành phần tối thiểu (S3), `Version`, `Metadata`, `Settings`, `Report` trống một trang, `DataModel` trống, `DataMashup` trống.

## Chuyển trạng thái

`Query` chưa nạp → (Close & Apply) → `LoadedTable.new` → (lưu T3) → bảng trong `DataModel` + `DataMashup`. Sửa truy vấn đã nạp → `replaced` → quan hệ/measure giữ khi cột còn, cột mất thì chặn/cảnh báo (FR-054).
