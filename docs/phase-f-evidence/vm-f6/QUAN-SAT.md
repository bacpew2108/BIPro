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

## 5. VM-F9 (T115, 2026-11-17): Desktop sửa công thức, xoá cột tính toán, xoá bảng tính toán

Power BI Desktop 2.159, Claude lái VM. Nền: bản sao `Nhom6_f4.pbix` (gate T085, có bảng tính toán `Lịch 2026` và cột tính toán `Dim_District[Nhãn đầy đủ]` do BI Pro ghi, cùng 7 cột tính toán gốc của Nhom6). Thao tác trong Table view, lưu đè, chép về `f9calc-desktop.pbix` (cùng thư mục, ngoài git). So `metadata.sqlitedb` và danh sách tệp ABF trước/sau.

**Giao diện.**
- Sửa công thức: chọn cột ở lưới, sửa ở thanh công thức `branch_label = Dim_District[city] & " - " & Dim_District[state_abbrev]`, Enter. Hộp "Working on it" rồi lưới hiện giá trị mới (`c1-sua-cong-thuc.png`).
- Xoá cột: Data pane, chuột phải cột ▸ "Delete from model" ▸ hộp **"Delete column — Are you sure you want to delete 'Nhãn đầy đủ'?"** Yes/Cancel (`c2-xoa-cot-hoi.png`).
- Xoá bảng: chuột phải bảng ▸ "Delete from model" ▸ hộp **"Delete table — Are you sure you want to delete 'Lịch 2026'?"** Yes/Cancel (`c3-xoa-bang-hoi.png`, sau khi xoá `c4-sau-khi-xoa.png`).
- Desktop không kiểm nơi dùng trước khi xoá trong lần này (cột và bảng không có ai dùng). [SUY ĐOÁN] xoá cột đang dùng thì visual hỏng, không bị chặn; BI Pro giữ quy tắc chặn của Phase E.

**Sửa công thức (cột `branch_label`, ID 7767), những gì đổi.**
- `Column`: cùng ID, chỉ đổi `Expression`, `ModifiedTime`, `RefreshedTime`. Không đổi kiểu, thuộc tính, `LineageTag`.
- Dữ liệu cột ghi lại:
  - `DataVersion` của `ColumnPartitionStorage` và `DictionaryStorage` tăng 7 → 8.
  - Tên tệp trong `StorageFile` đổi tiền tố theo `DataVersion` (`7.Dim District (28).branch label (7767).dictionary` → `8.…`). ID dòng `StorageFile` giữ nguyên.
  - `DictionaryStorage.Size` đổi theo từ điển mới.
- Bảng `H$` của cột được dựng lại với **ID mới**:
  - Bảng `H$` có `Table`, `Column`, `Partition` mới, `SystemFlags = 1`.
  - `AttributeHierarchyStorage` đổi `SystemTableID` sang bảng `H$` mới, `DataVersion` 3 → 5, và cập nhật `MinValue`, `MaxValue`, `StringValueMaxLength`.
  - `AttributeHierarchy` đổi `ModifiedTime` và `RefreshedTime`.
- Bảng `U$` của phân cấp người dùng "Địa lý" cũng được dựng lại với ID mới, vì cột là cấp "Chi nhánh" của phân cấp đó.
  - `HierarchyStorage.SystemTableID` đổi; `Hierarchy` đổi `ModifiedTime` và `RefreshedTime`.
- `TableStorage` của bảng: `Version` 7 → 9, `Settings` 4353 → 4097.
- `Table.StructureModifiedTime`, `Model.StructureModifiedTime` và 4 dòng `DBPROPERTIES` (LAST…) cập nhật; `MAXID` tăng.
- `Culture` và `LinguisticMetadata` được thay dòng mới. Đây là việc dọn dẹp riêng của Desktop, không phụ thuộc thao tác.

**Xoá cột tính toán (`Nhãn đầy đủ`, ID 11891).**
- Bỏ các dòng `Column`, `ColumnStorage`, `AttributeHierarchy`, `AttributeHierarchyStorage`, `ColumnPartitionStorage`, `DictionaryStorage`, `SegmentStorage`, `StorageFile` của cột.
- Bỏ cả bảng `H$` của cột (`Table`, `Column`, `Partition`, `PartitionStorage`, `SegmentMapStorage`, `StorageFolder`…).
- Bỏ 7 tệp ABF: `.dictionary`, `.0.idf`, `.0.idfmeta`, và `ID_TO_POS`/`POS_TO_ID` của `H$`.
- Không đụng cột khác.

**Xoá bảng tính toán (`Lịch 2026`, ID 11953).**
- Như xoá bảng thường: bỏ `Table`, các cột (RowNumber và `Date`), `Partition` kiểu 2 (`QueryDefinition` là biểu thức DAX), kho lưu trữ, bảng `H$` của cột `Date`, và 9 tệp ABF.

**Các tệp ABF khác giữ nguyên byte và cỡ.**

**Áp vào BI Pro (T116).**
- Xoá cột hoặc bảng tính toán: bỏ dòng và tệp như trên. Xoá bảng tính toán dùng lại đường `dropTable`.
- Sửa công thức cột: giữ ID cột, ghi lại dữ liệu cột (`DataVersion` + 1, tên tệp đổi tiền tố, `StorageFile` giữ ID), dựng lại `H$` của cột và `U$` của phân cấp có cột làm cấp, cập nhật `Expression`.
- Sửa công thức bảng tính toán: chưa quan sát. [SUY ĐOÁN] như thay dữ liệu bảng (giữ ID bảng, cột cùng tên giữ ID).
- Còn dùng ở visual, measure, quan hệ, sắp xếp hay phân cấp thì chặn xoá, như Phase E.

## 6. VM-F9b (T116, 2026-11-17): cột của bảng tính toán lấy từ cột mô hình

Gate T116 lần đầu trượt: Desktop mở `Nhom6_t116.pbix` báo **"Unable to execute DAX — An unexpected error occurred (file 'TMProcessJob.cpp', line 1356, function 'TMProcessPartitionJob::CreateReaderFromExpression')"**, báo cáo trống. File nền chỉ có thao tác thêm (đường T082–T085, chưa có sửa/xoá) cũng lỗi y hệt; gate T085 lọt vì bảng `CALENDAR` không có cột lấy từ mô hình.

Quan sát: Claude lái VM, mở Nhom6 gốc, Table view ▸ New table `T116X = DISTINCT(Fact_Loan[age_group_at_loan])`, lưu, so `metadata.sqlitedb` với bảng BI Pro ghi cùng biểu thức.
- Cột kết quả (`Type = 4`): Desktop ghi `SourceColumn = Fact_Loan[age_group_at_loan]` (tên đủ bảng của cột nguồn) và `ColumnOriginID = 11655` (ID cột nguồn). BI Pro ghi `[age_group_at_loan]` và 0. Cột mới không có nguồn gốc (như `Date` của `CALENDAR`) là `[Tên]`.
- Khác nữa, chưa thấy cần: `Partition.SystemFlags = 2`, `Column.SystemFlags = 2`, `TableStorage.Version = 1`, chú thích `PBI_Id` và `SummarizationSetBy`.

Áp vào BI Pro: engine trả tên nguồn theo lineage cột kết quả (`calculatedTableWithSources`), `ColumnSignature.sourceColumn`, bộ ghi đặt `SourceColumn` và `ColumnOriginID` (tra theo tên bảng và cột). Golden `docs/phase-f-evidence/vm-f9/obs-desktop.pbix` để ngoài git.
