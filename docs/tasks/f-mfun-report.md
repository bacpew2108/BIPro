# Báo cáo hoàn thành gói F-MFUN: Thư viện hàm M (Power Query)

## 1. Danh sách file đã tạo / sửa

### Sửa đổi:
- `Sources/MEngine/Library/TableColumns.swift`: Đăng ký và cài đặt toàn bộ hàm thao tác cột.
- `Sources/MEngine/Library/TableRows.swift`: Đăng ký và cài đặt toàn bộ hàm thao tác dòng.
- `Sources/MEngine/Library/TextNumberDateList.swift`: Tập hợp các hàm nhóm giá trị từ các module `Value*`.

### Tạo mới trong `Sources/MEngine/Library/`:
- `Sources/MEngine/Library/TableColumnsTypes.swift`: Xử lý chuyển đổi kiểu dữ liệu cột cho `Table.TransformColumnTypes`, mặt nạ lỗi `errorMask`.
- `Sources/MEngine/Library/TableRowsHelper.swift`: Cắt dòng `sliceRows` tối ưu trực tiếp trên `ColumnPayload.Codes` và dịch chuyển `errorMask`.
- `Sources/MEngine/Library/ValueText.swift`: 15 hàm xử lý văn bản `Text.*`.
- `Sources/MEngine/Library/ValueNumber.swift`: 7 hàm xử lý số `Number.*`.
- `Sources/MEngine/Library/ValueDate.swift`: 7 hàm xử lý ngày `Date.*` cùng thuật toán civil date của Howard Hinnant.
- `Sources/MEngine/Library/ValueList.swift`: 14 hàm danh sách `List.*`.
- `Sources/MEngine/Library/ValueReplacerSplitter.swift`: 4 hàm `Replacer.*`, `Splitter.*`, `Combiner.*`.

### Tạo mới trong `Tests/MEngineTests/Library/`:
- `Tests/MEngineTests/Library/ValueLibraryTests.swift`: 39 unit test kiểm thử độc lập mọi hàm giá trị cùng các ca biên/lỗi.
- `Tests/MEngineTests/Library/TableRowsTests.swift`: 10 unit test kiểm thử các hàm dòng.
- `Tests/MEngineTests/Library/TableColumnsTests.swift`: 9 unit test kiểm thử các hàm cột.
- `Tests/MEngineTests/Library/GoldenChainTests.swift`: Test golden `chuoi-2.m` (98 dòng, 7 cột, khớp từng ô với Desktop), `chuoi-1.m` đến bước `Uppercased Text` (43 dòng, khớp count theo Product của pivot Desktop, kiểm tra mọi bước trung gian), test lỗi chuyển kiểu và test benchmark 1 triệu dòng.

---

## 2. Tóm tắt kết quả triển khai

- Đã triển khai đầy đủ **78 hàm M** theo đúng danh sách yêu cầu.
- Toàn bộ hàm tuân thủ chuẩn `Sendable`, Swift 6 concurrency check không phát sinh cảnh báo hay lỗi.
- Đánh dấu chính xác cờ `observed: true` cho các hàm đã quan sát trong golden Desktop 2.159 (`Text.Upper`, `Number.From`, `List.Sum`, `Replacer.ReplaceText`, `Splitter.SplitTextByDelimiter`, `Table.PromoteHeaders`, `Table.TransformColumnTypes`, `Table.RenameColumns`, `Table.RemoveColumns`, `Table.AddColumn`, `Table.AddIndexColumn`, `Table.SplitColumn`, `Table.TransformColumns`, `Table.RowCount`, `Table.SelectRows`, `Table.Sort`, `Table.FirstN`, `Table.Skip`, `Table.Distinct`, `Table.ReplaceValue`, `Table.FillDown`, `Table.ReverseRows`, `Table.ReplaceErrorValues`). Toàn bộ hàm còn lại đánh dấu `observed: false` kèm ghi chú `// [SUY ĐOÁN]`.
- Giữ nguyên toàn bộ mã lõi M, không sửa ngoài danh sách được giao.
- Kiểm tra tính duy nhất trong bảng đăng ký thư viện qua `MLibraryTests.registryHasNoDuplicateNames`.

---

## 3. Kết quả chạy kiểm thử

### Dòng kết quả kiểm thử toàn bộ test suite (`swift test`):
```
✔ Test run with 1950 tests passed after 44.320 seconds.
```

### Kết quả `GoldenChainTests`:
- `goldenChuoi2ChayTron`: Vượt qua. Kết quả bảng 98 dòng, 7 cột (`OrderID`, `OrderDate`, `Region`, `CustomerID`, `Product`, `Qty`, `Amount`), cột `Price` đã loại bỏ, `Region` toàn 0 dạng số nguyên và không có ô lỗi. Mọi ô đều khớp chính xác với `chuoi-2-98-dong.tsv`.
- `goldenChuoi1DenUppercasedTextVaTungBuoc`: Vượt qua. Chạy qua từng bước trung gian:
  - `"Sorted Rows"`: Tăng dần theo `OrderDate`, ổn định theo `OrderID`.
  - `"Removed Columns"`: Không còn cột `Price`.
  - `"Replaced Value"`: Không còn dòng nào có `Vung` chứa `"North"`.
  - `"Filtered Rows"`: Đạt đúng 43 dòng.
  - `"Added Index"`: Index từ 0 đến 42.
  - `"Reversed Rows"`: Đảo ngược chính xác thứ tự Index từ 42 về 0.
  - `"Split Column by Delimiter"`: Có đủ hai cột `Vung.1` và `Vung.2`, phân tách dấu cách chuẩn CSV.
  - `"Uppercased Text"`: Bảng 43 dòng, đếm phân bố theo `Product` bằng Swift dictionary khớp chính xác 100% cột Count trong `chuoi-1-pivot-6-dong.tsv` (GIÀY: 8, MŨ: 11, QUẦN JEAN: 3, TÚI XÁCH: 3, ÁO THUN: 7, ĐỒNG HỒ: 11).
- `testLoiChuyenKieuVaReplaceErrorValues`: Vượt qua. Cột văn bản `{"South", "North", "5"}` chuyển sang `Int64.Type` đưa hai ô lỗi vào `errorMask`, ô `"5"` thành 5, sau đó `Table.ReplaceErrorValues` thay thành `0, 0, 5`.

---

## 4. Đo kiểm hiệu năng 1 triệu dòng × 10 cột

Chạy lệnh `BIPRO_HEAVY=1 swift test --filter motTrieuDongHieuNang` trên bảng 1.000.000 dòng × 10 cột (2 integer, 2 double, 1 datetime, 4 string, 1 boolean).

Kết quả đo đạc thực tế (trên bản Debug, macOS Apple Silicon):
- `Table.FirstN` (lấy 100 dòng đầu): **0.000s** (dưới 1ms)
- `Table.Skip` (bỏ 100 dòng đầu, giữ 999.900 dòng): **0.807s** (< 5s)
- `Table.Distinct` (lọc trùng theo cột phân loại): **1.137s** (< 5s)
- `Table.TransformColumnTypes` (chuyển đổi 1 triệu dòng từ double sang int64): **1.025s** (< 5s)
- `Table.Sort` (sắp xếp 1 triệu dòng theo cột số nguyên): **3.065s** (< 5s)

Toàn bộ các phép toán đều hoàn thành dưới ngưỡng 5.0 giây nhờ cơ chế:
1. Slicing trực tiếp trên mảng mã `Codes` của `ColumnPayload.encoded` thay vì giải mã và nạp lại dictionary.
2. Tiền trích xuất mảng khoá phẳng trước khi sắp xếp, tránh hàng chục triệu lần gọi `cell()` và cấp phát enum `MValue` trong comparator.
3. Lọc trùng `Distinct` bằng hashing `StoredValue` có sẵn thay vì so sánh $O(N^2)$.

---

## 5. Quyết định kỹ thuật

- **Tách module rõ ràng**: Nhóm hàm giá trị được chia thành `ValueText`, `ValueNumber`, `ValueDate`, `ValueList`, `ValueReplacerSplitter` và gộp qua `TextNumberDateList.swift` giúp dễ đọc và bảo trì.
- **Dịch chuyển mặt nạ lỗi `errorMask`**: Mọi phép biến đổi dòng (`Sort`, `SelectRows`, `Distinct`, `ReverseRows`, `Skip`, `Range`, `PromoteHeaders`) đều tính toán chỉ số dòng mới `newRowIndex` từ `oldRowIndex` để bảo toàn ô lỗi.
- **Xử lý CSV QuoteStyle**: `Splitter.SplitTextByDelimiter` tuân thủ bọc ngoặc kép `QuoteStyle.Csv` và unescape `""` thành `"`.

---

## 6. Danh sách hàm ở mức [SUY ĐOÁN]

- **Text**: `Text.Lower`, `Text.Proper`, `Text.Trim`, `Text.Clean`, `Text.Length`, `Text.Contains`, `Text.StartsWith`, `Text.EndsWith`, `Text.Replace`, `Text.Combine`, `Text.From`, `Text.Start`, `Text.End`, `Text.PadStart`.
- **Number**: `Number.Round`, `Number.Abs`, `Number.RoundDown`, `Number.RoundUp`, `Number.Mod`, `Number.IntegerDivide`.
- **Date**: `Date.Year`, `Date.Month`, `Date.Day`, `Date.From`, `Date.AddDays`, `Date.AddMonths`, `Date.DayOfWeek`.
- **List**: `List.Count`, `List.Distinct`, `List.Max`, `List.Min`, `List.Average`, `List.Sort`, `List.Transform`, `List.Select`, `List.Contains`, `List.First`, `List.Last`, `List.Numbers`, `List.Reverse`.
- **Replacer / Combiner**: `Replacer.ReplaceValue`, `Combiner.CombineTextByDelimiter`.
- **Table.Rows**: `Table.LastN`, `Table.RemoveFirstN`, `Table.RemoveLastN`, `Table.Range`, `Table.FillUp`, `Table.RemoveRowsWithErrors`, `Table.SelectRowsWithErrors`.
- **Table.Columns**: `Table.SelectColumns`, `Table.ReorderColumns`, `Table.DuplicateColumn`, `Table.CombineColumns`, `Table.ColumnNames`, `Table.ColumnCount`.

---

## 7. Đề xuất cho lead

1. **Bảng chưa thăng tiêu đề chứa lẫn kiểu**: Khi tạo bảng `#table({"C1", "C2"}, {{"Name", "Age"}, {"Alice", 30}, {"Bob", 25}})` (dòng đầu là chuỗi tiêu đề, dòng dưới là số), `MTables.inferType` ném `MError.unsupported` vì `ColumnStore` chưa có cột kiểu `any`. Trong tương lai, khi hỗ trợ nạp nguồn dạng thô trước khi thăng tiêu đề, nên có cơ chế cho phép cột suy ra kiểu chuỗi nếu dòng đầu là text hoặc thêm hỗ trợ kiểu cột `any`.
2. **Biểu thức bản ghi tự tham chiếu tên trường**: Biểu thức dạng `[Names = Names]` khi định nghĩa bản ghi bị Evaluator bắt lỗi "Phát hiện vòng tham chiếu khi tính 'Names'" do tra cứu tên trường trong chính bản ghi đang dựng. Trong Power Query Desktop, `[Names = Names]` cho phép lấy giá trị `Names` ở môi trường bên ngoài để gán vào trường `Names` của bản ghi mới. Đề xuất Evaluator phân giải vế phải từ scope ngoài khi vế phải là định danh trùng tên trường chưa có giá trị.

---

## 8. Tình trạng tồn đọng

Không có tồn đọng. Tất cả 7 tiêu chí bàn giao đều đã đạt 100%.
