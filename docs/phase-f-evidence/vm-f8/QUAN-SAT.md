# VM-F8: Enable load, cột `any`, truy vấn tham chiếu (Desktop 2.159, 2026-11-16)

Người dùng cho lái VM. File gốc: `q1-csv.pbix` do BI Pro lưu (bảng `sales_2026` + truy vấn M), mở trong Desktop, sửa, lưu lại; siêu dữ liệu trích bằng `pbix-dump extract … metadata.sqlitedb`. Ảnh chụp VM không giữ (thanh tiêu đề có tài khoản đăng nhập).

## 1. Tắt Enable load (chuột phải truy vấn ▸ Enable load)

- Hộp cảnh báo: **"Possible Data Loss Warning. Disabling load will remove the table from the report, and any visuals that use its columns will be broken."** Nút Continue / Cancel. Truy vấn chuyển chữ nghiêng trong danh sách (như `DataFolder`).
- Close & Apply: bảng `sales_2026` biến khỏi Data pane và khỏi `[Table]`.
- **Truy vấn lưu ở bảng `Expression` (cấp mô hình), không còn ở `Partition`:**

| Cột `Expression` | Giá trị |
|---|---|
| `ModelID` | 1 |
| `Name` | tên truy vấn (`sales_2026`) |
| `Kind` | 0 (M) |
| `Expression` | toàn bộ `let … in …` nguyên văn (cùng chuỗi trước đó nằm ở `Partition.QueryDefinition`) |
| `QueryGroupID`, `ParameterValuesColumnID`, `ExpressionSourceID` | 0 |
| `LineageTag` | GUID (chữ thường, có gạch) |
| `ModifiedTime` | tick .NET |
| `Description`, `MAttributes`, `SourceLineageTag`, `RemoteParameterName` | rỗng (NULL) |

- Chú thích (`Annotation`) cho dòng `Expression` (`ObjectType` 41, `ObjectID` = `Expression.ID`): `PBI_NavigationStepName = Navigation` và `PBI_ResultType = Table` (truy vấn tham số `DataFolder`: chỉ `PBI_ResultType = Text`).
- Chú thích mô hình `PBI_QueryOrder` (ObjectType 1, ObjectID 1) là mảng JSON tên **mọi** truy vấn theo thứ tự trong danh sách, kể cả không nạp (`…,"DataFolder","Dim_Trans_Type","sales_2026","Query1"]`). File do BI Pro lưu trước đó không có `sales_2026` trong mảng này (Desktop vẫn mở được và tự thêm).
- Truy vấn tham số (`DataFolder`: `"C:\…" meta [IsParameterQuery = true, Type = "Text", …]`) cũng ở `Expression`; Nhom6 gốc đã có sẵn.

## 2. Cột `any` (Table.Combine hai cột `A`: Int64 và text)

- Xem trước Power Query: cột `A` kiểu "Any" (số canh phải, chữ canh trái), `B` text.
- Close & Apply nạp được: **cột `A` thành `string`** (`ExplicitDataType` 2, `SummarizeBy` 2): giá trị `"1"` và `"x"` (đọc bằng `pbix-dump rows`). Không báo lỗi.

## 3. Truy vấn tham chiếu truy vấn khác (chuột phải ▸ Reference)

- `Query1 (2)` có M `let Source = Query1 in Source`, cả hai đều nạp.
- Lưu: **mỗi truy vấn nạp chỉ có `Partition.QueryDefinition` của chính nó; truy vấn được tham chiếu KHÔNG sinh thêm dòng `Expression`.** Phân vùng của `Query1 (2)`: `Type = 4`, `Mode = 0`, `QueryDefinition` = đúng chuỗi trên. Giải quyết rủi ro T074 (BI Pro chỉ ghi `QueryDefinition` từng bảng là đúng dạng Desktop).
- Bảng mới có chú thích `PBI_NavigationStepName = Navigation`, `PBI_ResultType = Table` (ObjectType 3); `PBI_QueryOrder` thêm tên bảng mới ở cuối.

## 4. Gate Desktop cho phần BI Pro đã cài (cùng ngày)

Ba file Nhom6 do BI Pro lưu (`FGateTests.taoFileGateF8`, nguồn CSV `C:\Users\bacpew\f6\`), chép sang VM, mở trong Desktop 2.159:

| File | Kết quả | Bằng chứng |
|---|---|---|
| `g1-hidden.pbix` (`sales_2026` tắt Enable load, lưu thành dòng `Expression`) | **ĐẠT.** Mở không lỗi; Data pane 11 bảng, không còn `sales_2026`; Power Query có `sales_2026` chữ nghiêng (như `DataFolder`) trong Queries [13]; chọn nó xem trước 8 cột, 500 dòng, 4 bước (Source, Promoted Headers, Changed Type, Kept First Rows) | `g1-truy-van-tat-enable-load.png` |
| `g2-rel.pbix` (thay dữ liệu `Dim_Loan_Profile` còn 5 dòng; bảng nằm trong quan hệ) | **ĐẠT.** Mở không lỗi (không có "system table is missing"); Table view `Dim_Loan_Profile (5 rows)`; Manage relationships còn đủ, gồm `Fact_Loan (loan_profile_key)` → `Dim_Loan_Profile` Active, Many to one, Single. Chỉ mục `R$` dựng lại. Đếm dòng qua quan hệ khớp đếm trực tiếp theo khoá bằng engine BI Pro (test `HiddenQueryTests`); Desktop chưa đối chiếu bằng visual | `g2-bang-thay-5-dong.png`, `g2-quan-he.png` |
| `g3-merge.pbix` (T074: Merge + mở rộng, Append tham chiếu truy vấn khác, Group By) | **ĐẠT.** 4 bảng mới nạp; Power Query đọc đúng M: `sales_2026` 10 cột 300 dòng (bước Merged Queries, Expanded customers), `sales_2026 (2)` = `Table.Combine({#"Kept First Rows", sales_2026})` 10 cột 400 dòng, `sales_2026 (3)` Group By 5 dòng (Trung tâm 1982/20347, South 1994/19519, North 2030/20088, East 2005/20402, West 1989/19386) trùng từng ô với bảng BI Pro đã lưu | `g3-merge-expand.png`, `g3-append-tham-chieu.png`, `g3-group-by.png` |

Ghi nhận: thứ tự dòng sau Merge do Desktop tự quyết (nhóm theo khoá, ví dụ OrderID 1, 14, 22 cùng CustomerID 7 đứng đầu) khác thứ tự dòng trái BI Pro giữ; số dòng và giá trị khớp (đã biết từ VM-F4). Truy vấn Nhom6 gốc báo `DataSource.NotFound` vì đường dẫn máy `LOQ`: bình thường, không do BI Pro.
