# VM-F3: Power Query Editor trong Desktop (T047), 2026-11-15

Người làm: Claude lái Power BI Desktop 2.159.1231 (bạn cho phép trong phiên này). Dữ liệu: `sales_2026.xlsx`, trang `Sales` (500 dòng). Hai chuỗi lệnh dài trên Ribbon, mỗi chuỗi Close & Apply rồi lưu; đọc lại `Partition.QueryDefinition` và dữ liệu bảng bằng `pbix-dump`. Mẹo tooling: gõ chữ vào Desktop qua phím hay rớt ký tự; dán qua clipboard ổn định (`type file | clip` trong VM bằng `prlctl exec`, rồi Ctrl+V). Biểu thức M dài chạy bằng `Expression.Evaluate(Text.FromBinary(File.Contents(...)), #shared)` từ một Blank Query.

Golden: `golden/chuoi-1.m` + `golden/chuoi-1-pivot-6-dong.tsv`, `golden/chuoi-2.m` + `golden/chuoi-2-98-dong.tsv` (M nguyên văn của Desktop và dữ liệu bảng đã nạp). Ảnh: Advanced Editor, hộp thoại Insert Step, lỗi chuyển kiểu, bước Remove Duplicates, kết quả kiểm [SUY ĐOÁN] (`kiem-tra-suy-doan-m.png`).

## 1. Lệnh Ribbon ↔ tên bước ↔ biểu thức M

Truy vấn ban đầu từ Navigator (Excel): `Source`, `Sales_Sheet` (Applied Steps hiện "Navigation"), `Promoted Headers`, `Changed Type` (xem `vm-f1/QUAN-SAT.md` mục 3). Tên bước ở dạng hiển thị = tên bước M (`#"Tên bước"`); bước trùng tên thêm số (`Changed Type1`).

| Lệnh (tab) | Tên bước | Biểu thức M (nguyên văn) |
|---|---|---|
| Sort Ascending (Home) | `Sorted Rows` | `Table.Sort(#"Changed Type",{{"OrderDate", Order.Ascending}})` |
| Remove Columns (Home) | `Removed Columns` | `Table.RemoveColumns(#"Sorted Rows",{"Price"})` |
| Đổi tên cột (nhấp đúp tiêu đề) | `Renamed Columns` | `Table.RenameColumns(#"Removed Columns",{{"Region", "Vung"}})` |
| Replace Values (Home; cột văn bản) | `Replaced Value` | `Table.ReplaceValue(#"Renamed Columns","North","Bac",Replacer.ReplaceText,{"Vung"})` |
| Lọc theo danh sách giá trị (mũi tên cột) | `Filtered Rows` | `Table.SelectRows(#"Replaced Value", each ([Qty] = 1 or [Qty] = 2))` |
| Index Column ▸ From 0 (Add Column) | `Added Index` | `Table.AddIndexColumn(#"Filtered Rows", "Index", 0, 1, Int64.Type)` |
| Custom Column (Add Column), tên mặc định "Custom" | `Added Custom` | `Table.AddColumn(#"Added Index", "Custom", each [Qty] * 2)` (không gán kiểu) |
| Reverse Rows (Transform) | `Reversed Rows` | `Table.ReverseRows(#"Added Custom")` |
| Fill ▸ Down (Transform) | `Filled Down` | `Table.FillDown(#"Reversed Rows",{"Vung"})` |
| Split Column ▸ By Delimiter (dấu cách, mọi lần xuất hiện) | `Split Column by Delimiter` rồi `Changed Type1` | `Table.SplitColumn(#"Filled Down", "Vung", Splitter.SplitTextByDelimiter(" ", QuoteStyle.Csv), {"Vung.1", "Vung.2"})`; rồi `Table.TransformColumnTypes(#"Split Column by Delimiter",{{"Vung.1", type text}, {"Vung.2", type text}})` (phần thiếu là `null`) |
| Format ▸ UPPERCASE (Transform) | `Uppercased Text` | `Table.TransformColumns(#"Changed Type1",{{"Product", Text.Upper, type text}})` |
| Group By, Basic, Count Rows (Transform) | `Grouped Rows` | `Table.Group(#"Uppercased Text", {"Product"}, {{"Count", each Table.RowCount(_), Int64.Type}})` (nhóm theo thứ tự xuất hiện đầu tiên) |
| Unpivot Other Columns (Transform) | `Unpivoted Other Columns` | `Table.UnpivotOtherColumns(#"Grouped Rows", {"Product"}, "Attribute", "Value")` |
| Pivot Column (Transform; Values Column `Value`) | `Pivoted Column` | `Table.Pivot(#"Unpivoted Other Columns", List.Distinct(#"Unpivoted Other Columns"[Attribute]), "Attribute", "Value", List.Sum)`; **các hàng ra theo thứ tự ký tự của cột còn lại** (GIÀY, MŨ, QUẦN JEAN, TÚI XÁCH, ÁO THUN, ĐỒNG HỒ), không theo thứ tự xuất hiện |
| Remove Duplicates (Remove Rows ▸) | `Removed Duplicates` | `Table.Distinct(#"Replaced Value", {"Vung"})` (giữ dòng đầu của mỗi nhóm; trên dữ liệu thử còn 5 dòng: đơn 313, 293, 113, 251, 199) |
| Keep Top Rows (Keep Rows ▸), hộp "Number of rows" | `Kept First Rows` | `Table.FirstN(#"Changed Type",100)` |
| Remove Top Rows (Remove Rows ▸), hộp "Number of rows" | `Removed Top Rows` | `Table.Skip(#"Removed Columns",2)` |
| Data Type ▸ Whole Number (cột văn bản "South"…) | `Changed Type1` | `Table.TransformColumnTypes(#"Removed Top Rows",{{"Region", Int64.Type}})`; ô lỗi hiện `Error` |
| Replace Errors (Transform ▸ Replace Values ▸), giá trị 0 | `Replaced Errors` | `Table.ReplaceErrorValues(#"Changed Type1", {{"Region", 0}})` |

Menu và hộp thoại quan sát được: Remove Rows ▸ (Remove Top Rows, Bottom Rows, Alternate Rows, Duplicates, Blank Rows, Errors); Keep Rows ▸ (Top, Bottom, Range of Rows, Duplicates, Errors); Split Column ▸ (By Delimiter, By Number of Characters, By Positions, By Lowercase to Uppercase, By Uppercase to Lowercase, By Digit to Non-Digit, By Non-Digit to Digit); Format ▸ (lowercase, UPPERCASE, Capitalize Each Word, Trim, Clean, Add Prefix, Add Suffix); Data Type ▸ (Decimal Number, Fixed decimal number, Whole Number, Percentage, Date/Time, Date, Time, Date/Time/Timezone, Duration, Text, True/False, Binary); Fill ▸ (Down, Up); Unpivot Columns ▸ (Unpivot Columns, Unpivot Other Columns, Unpivot Only Selected Columns); Index Column ▸ (From 0, From 1, Custom…); Close & Apply ▸ (Close & Apply, Apply, Close).

## 2. Hành vi giao diện

- Thanh trạng thái dưới lưới: "8 COLUMNS, 500 ROWS" và "Column profiling based on top 1000 rows"; góc phải "PREVIEW DOWNLOADED AT <giờ>".
- Chuyển kiểu lỗi: cả cột hiện `Error` (không dừng truy vấn); bấm vào một ô lỗi thì khung dưới lưới ghi "DataFormat.Error: We couldn't convert to Number." và "Details: South" (giá trị gốc). Bước vẫn hợp lệ (không có dấu cảnh báo ở bước).
- **Chèn bước giữa chừng:** chọn bước cũ rồi làm lệnh mới thì hiện hộp "Insert Step: Are you sure you want to insert a step? Inserting an intermediate step may affect subsequent steps, which could cause your query to break." (Insert / Cancel). Bước mới chèn ngay sau bước đang chọn và bước kế tiếp được nối lại vào bước mới (`Removed Top Rows` đổi tham chiếu sang `#"Removed Columns"`).
- Xoá bước bằng dấu X cạnh tên bước; bước sau không bị tự sửa nếu nó không phụ thuộc.
- Close & Apply: đóng cửa sổ, báo cáo hiện "Working on it" rồi bảng xuất hiện ở Data pane. File lưu sau đó có `Partition.QueryDefinition` = đúng M trên, **không có `DataMashup`**, `Mode` 0.
- Kiểu cột sau Apply: `Int64.Type` thành cột số nguyên (`FormatString` `0`), `type date` thành ngày (`Long Date`), `type number` thành thập phân; cột `OrderID` và `CustomerID` (số nguyên tên "…ID", không nằm trong quan hệ) có `SummarizeBy` 6 (đếm), cột `Region` kiểu số nguyên sau chuyển kiểu có 3 (cộng dồn). Khi có quan hệ (VM-F1) cột khoá có 2.

## 3. Dữ liệu đối chiếu (golden)

- Chuỗi 1 (đủ 19 bước) → bảng 2 cột 6 dòng: GIÀY 8, MŨ 11, QUẦN JEAN 3, TÚI XÁCH 3, ÁO THUN 7, ĐỒNG HỒ 11 (tổng 43 dòng sau lọc `Qty` 1 hoặc 2).
- Chuỗi 2 → bảng 98 dòng, 7 cột (`OrderID` từ 3, `Price` đã bỏ, `Region` toàn 0 sau Replace Errors).

## 4. Kiểm các [SUY ĐOÁN] của lõi M

Xem `SUY-DOAN-M.md` (cột kết quả điền) và `m-suy-doan.m` (biểu thức chạy trong Desktop). Khác biệt đã sửa: `#date = #datetime` là false và `#date < #datetime` báo lỗi (BI Pro trước đây so theo số ngày). Khác biệt chưa sửa: `#table` không nêu kiểu cho cột kiểu `any` (Desktop `Any.Type`, BI Pro suy `number`/`text` vì `ColumnStore` không có cột `any`); toán tử `meta` (Desktop hỗ trợ, BI Pro báo chưa hỗ trợ).
