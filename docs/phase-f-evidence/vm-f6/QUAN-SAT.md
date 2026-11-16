# VM-F6 (T080): cột và bảng tính toán do Desktop lưu (2026-11-16)

Đọc từ file do Desktop lưu có sẵn, không lái VM: bản Nhom6 dùng cho test (`~/Downloads/bipro-golden/Nhom6_work.pbix`, giống `Nhom6_Dashboard (1).pbix`) có 7 cột tính toán; `~/Downloads/DWH&BI/w8.3.pbix` (bài tập của người dùng) có bảng tính toán `Ngày` và 3 cột tính toán. Chỉ đọc (`pbix-dump extract … metadata.sqlitedb`, `sqlite3`). Phần cần Desktop xác nhận lại (tạo mới trong Desktop 2.159, bảng tính toán thứ hai) để ở gate T085.

## 1. Cột tính toán (Nhom6)

| Bảng | Cột | Biểu thức (rút gọn) | Kiểu |
|---|---|---|---|
| Dim_Date | MonthIndex | `IF(Dim_Date[date_key] = -1, BLANK(), year*12 + month_num)` | Int64 |
| Fact_Transaction | trans_hour | `HOUR(Fact_Transaction[trans_timestamp])` (1 056 320 dòng) | Int64, định dạng `00":00"` |
| Dim_District | branch_label | `city & ", " & state_abbrev` | String |
| Dim_Date | month_start | `IF(…, BLANK(), DATE(year, month_num, 1))` | DateTime, `MMM yyyy` |
| Fact_Loan | age_at_loan | `VAR b = RELATED(Dim_Client[birth_date]) VAR d = RELATED(Dim_Date[full_date]) RETURN …` | Int64 |
| Fact_Loan | age_group_at_loan_order | `SWITCH(TRUE(), …)` trên `Fact_Loan[age_at_loan]` (cột tính toán khác) | Int64 |
| Fact_Loan | age_group_at_loan | như trên, trả chuỗi | String |

Dòng `Column`: `Type = 2`, `Expression` = DAX, `State = 1`, `ExplicitDataType` = `InferredDataType` (6, 2 hoặc 9), `SummarizeBy = 2`, `IsNullable = 1`, `ExpressionContext = 1`, `EncodingHint = 0`, `SourceColumn` rỗng; có `AttributeHierarchyID` và bảng `H$<bảng>$<cột>` như cột thường.

**Desktop lưu sẵn dữ liệu VertiPaq** cho cột tính toán: `ColumnStorage` (tên `"<cột> (<ID>)"`), từ điển, thống kê (`Statistics_DistinctStates`, `Statistics_RowCount` bằng số dòng bảng), cùng phân vùng M của bảng (`Partition.Type = 4`). Mở file không cần tính lại. Golden của engine là chính giá trị đã lưu.

## 2. Bảng tính toán (w8.3, `Ngày = CALENDAR(DATE(1986,1,1), DATE(2022,12,31))`)

- `Table`: `SystemFlags = 2` (giống `LocalDateTable_…`/`DateTableTemplate_…` của Desktop), `IsHidden = 0`, `IsPrivate = 0`, `ShowAsVariationsOnly = 0`, có `LineageTag`; chú thích bảng `PBI_Id`. Bảng ngày tự động khác ở chú thích `__PBI_LocalDateTable`/`__PBI_TemplateDateTable` và cờ ẩn/riêng tư. **BI Pro trước đây coi `SystemFlags ≠ 0` là bảng hệ thống nên bỏ mất bảng này** (Data pane, engine); đã sửa: phân vùng kiểu 2, không riêng tư, không chỉ hiện như biến thể, không có chú thích bảng ngày tự động thì là bảng người dùng.
- `Partition`: `Type = 2` (Calculated), `Mode = 0`, `DataView = 3`, `State = 1`, `QueryDefinition` = biểu thức DAX, `DataSourceID = 0`.
- Cột của bảng: `RowNumber` (`Type 3`); `Date` có `Type = 4` (cột của bảng tính toán), `InferredName = Date`, `ExplicitName` rỗng, `SourceColumn = [Date]`, `ExplicitDataType = 1` (tự động), `InferredDataType = 9`. Cột tính toán thêm trên bảng (`Ngày`, `Tháng`, `Năm` = `DAY/MONTH/YEAR('Ngày'[Date])`) là `Type = 2`, `ExplicitDataType = 1`, `InferredDataType = 6`, `SummarizeBy = 3`.
- Dữ liệu cũng lưu sẵn trong VertiPaq, dòng theo thứ tự CALENDAR (ngày tăng dần).

## 3. Engine BI Pro (T081)

`DAXEngine.calculatedColumn(table:expression:)` (mỗi dòng trong row context của chính nó, bộ lọc rỗng) và `calculatedTable(expression:)` (thêm hàm `CALENDAR`, `EARLIER`, `EARLIEST`) cho kết quả **trùng từng dòng** với giá trị Desktop đã lưu cho cả 7 cột Nhom6 và bảng `Ngày` cùng 3 cột (`Tests/DAXEngineTests/CalculatedColumnTests.swift`, BIPRO_HEAVY).

## 4. Còn chờ Desktop (gate T085)

- Bảng tính toán do Desktop 2.159 mới tạo có `SystemFlags = 2` không (chỉ có một mẫu, từ phiên bản cũ hơn).
- Desktop có chấp nhận file BI Pro ghi cột/bảng tính toán kèm dữ liệu VertiPaq mà không cần Refresh.
