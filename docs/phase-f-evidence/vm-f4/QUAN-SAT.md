# VM-F4 (T067): Desktop 2.159 quan sát Merge, Append, Group By, Custom Column, join/group/pivot, 2026-11-16

Claude lái VM theo lời cho phép của người dùng. Dữ liệu: `sales_2026.xlsx` (Sales 500 dòng, Customers 50 dòng) cho phần hộp thoại; bảng `#table` nhỏ viết tay cho phần ngữ nghĩa (probe M `golden/p1..p5.m`, chạy trong Advanced Editor của truy vấn trống; kết quả đọc từ lưới xem trước, `~` là null). Ảnh cắt không lộ tài khoản. VM đã dọn (thư mục `f4`, Desktop đóng, không lưu file).

## 1. Lệnh ↔ bước ↔ M (nguyên văn Desktop)

| Lệnh | Tên bước | M |
|---|---|---|
| Merge Queries (Sales ⋈ Customers, `CustomerID`, mặc định Left Outer) | `Merged Queries` | `Table.NestedJoin(#"Changed Type", {"CustomerID"}, Customers, {"CustomerID"}, "Customers", JoinKind.LeftOuter)` |
| Mở rộng cột bảng lồng (chọn hết, tiền tố bật) | `Expanded Customers` | `Table.ExpandTableColumn(#"Merged Queries", "Customers", {"CustomerID", "Name", "Segment"}, {"Customers.CustomerID", "Customers.Name", "Customers.Segment"})` |
| Group By (3 khoá, Count Rows) | `Grouped Rows` | `Table.Group(#"Expanded Customers", {"Customers.CustomerID", "Customers.Name", "Customers.Segment"}, {{"Count", each Table.RowCount(_), Int64.Type}})` |
| Append Queries (hai bảng, chọn truy vấn hiện tại) | `Appended Query` | `Table.Combine({#"Changed Type", #"Changed Type"})` (truy vấn hiện tại thành bước cuối của nó; truy vấn khác thì viết tên truy vấn) |
| Custom Column | `Added Custom` | `Table.AddColumn(#"Appended Query", "Custom", each <công thức>)` |

Hộp thoại (ảnh `merge-hop-thoai.png`, `custom-column-hop-thoai.png`): Merge: "Select a table and matching columns to create a merged table.", bảng trên là truy vấn hiện tại (5 dòng đầu), menu chọn bảng thứ hai (liệt kê cả "Sales (Current)"), bấm tiêu đề cột để chọn khoá (theo thứ tự), "Join Kind" mặc định "Left Outer (all from first, matching from second)", ô "Use fuzzy matching", dòng trạng thái "Select the same number of columns from both visible tables to continue." rồi "The selection matches 500 of 500 rows from the first table."; OK mờ tới khi đủ khoá hai bên. Hộp mở rộng: "Expand / Aggregate", danh sách cột (kể cả cột khoá), ô "Use original column name as prefix" bật sẵn. Append: "Concatenate rows from two tables into a single table.", "Two tables / Three or more tables", "Table to append"; danh sách bảng gồm truy vấn hiện tại và các truy vấn KHÔNG gây vòng tham chiếu (Sales đã dùng Customers nên không hiện). Group By: hộp mở ở chế độ Advanced khi chọn nhiều cột; "New column name" mặc định "Count", "Operation" mặc định "Count Rows". Custom Column: "New column name" mặc định "Custom", "Custom column formula", "Available columns" + "<< Insert", dải "No syntax errors have been detected.".

## 2. Ngữ nghĩa (probe M; kỳ vọng chạy tự động ở `Tests/MEngineTests/Library/DesktopProbeTests.swift`)

- **Join** (`Table.Join`, `NestedJoin` rồi mở): khoá `null` khớp `null`; phân biệt hoa thường (`a` ≠ `A`); khác kiểu không khớp và không lỗi (`1` với `"1"` ra 0 dòng); trùng tên cột ở hai bảng là lỗi; kiểu mặc định của `NestedJoin` là LeftOuter; `ExpandTableColumn` đặt tên mới trùng cột có sẵn là lỗi. Dòng không khớp luôn ở CUỐI kết quả; với Full Outer: dòng phải không khớp trước, dòng trái không khớp sau. **Thứ tự các dòng khớp do Desktop quyết (băm), không theo bảng trái hay phải** (Merge Sales × Customers cho thứ tự dòng khác Sales); BI Pro giữ thứ tự dòng trái và không thể giống từng dòng, các phép tổng hợp thì giống.
- **Group** (`Table.Group`): Global theo thứ tự xuất hiện đầu tiên (không sắp), khoá `null` là một nhóm; Local tách theo đoạn liên tiếp (hai `null` liên tiếp gộp một). `List.Median` của {3,1} = 2, của {2,5} = 3,5.
- **Pivot** (`Table.Pivot`): nhóm sắp theo các cột khoá TĂNG DẦN (số theo giá trị, `null` trước, nhiều cột theo thứ tự cột); không có hàm tổng hợp mà một ô có hai giá trị thì LỖI Ở Ô (bảng vẫn có, ô đó "Error"), không ném cả hàm; ô không có giá trị là `null`.
- **Unpivot / UnpivotOtherColumns**: bỏ ô `null`; thứ tự theo hàng rồi theo cột xoay.
- **Combine** (`Table.Combine`): hợp cột theo thứ tự thấy đầu tiên, ô thiếu là `null`. Cột cùng tên khác kiểu (số và chữ) Desktop cho phép (cột `any`); BI Pro chưa có cột lẫn kiểu nên báo "Chưa hỗ trợ".
- Danh sách `List.Transform` giữ lỗi của phần tử trong danh sách (ô lỗi khi dựng `#table`), không ném ngay.

## 3. Còn chưa quan sát

Merge nhiều cột khoá bằng hộp thoại; Group By hộp Basic với Sum/Average...; hộp Append "Three or more tables"; Query Dependencies; Advanced Editor kiểm cú pháp ngoài thông báo "No syntax errors have been detected."; tên bước Desktop sinh cho Sum/Average/Median/Min/Max của Group By (M của bước đoán theo dạng `each List.Sum([Cột]), type nullable number`).
