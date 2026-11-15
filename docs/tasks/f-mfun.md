Bạn làm việc trong repo Swift "BI Pro" (ứng dụng macOS giống Power BI Desktop, macOS 15), trong một git worktree riêng tách từ `main`. Phase F đang làm Power Query. Lõi ngôn ngữ M (lexer, parser, evaluator) đã xong. Gói của bạn, **F-MFUN**: **thư viện hàm M** (`Table.*`, `Text.*`, `Number.*`, `Date.*`, `List.*`, `Replacer.*`, `Splitter.*`) chạy trên `TableData`, khớp **kết quả thật của Power BI Desktop 2.159** ghi trong golden. Chỉ dùng framework hệ thống; không thêm package, không tải gì từ mạng.

## Đọc trước (đã có, giữ nguyên, không sửa)

- `Sources/MEngine/Value.swift`: `MValue`, `MFunction` (`name`, `parameters: [MParameter]`, `observed`, `implementation`), `MError` (`.expression(msg)`, `.unsupported(tên)`), `MType`.
- `Sources/MEngine/Library/Support.swift`: trợ giúp lấy đối số có kiểu (`args.table(i, "Tên")`, `.text`, `.number`, `.list`, `.function`, `.optional(i)`) và `MFunction.call([MValue])` để gọi vị từ/hàm M truyền vào. **Dùng chúng**, thông điệp lỗi tiếng Việt, nêu tên hàm.
- `Sources/MEngine/TableBuilder.swift` (`MTables`): `value(_:)`, `cell(_:row:column:)`, `row(_:_:)` (một hàng thành bản ghi), `build(names:types:rows:)` (dựng bảng từ hàng `MValue` có kiểu cột), `identical`. Dựng bảng kết quả bằng `MTables.build` hoặc `TableData(columns:errorMask:)`.
- `Sources/ColumnStore/TableData.swift`: `TableData` (`columns`, `rowCount`, `errorMask` cột → dòng → thông điệp, `value(row:column:)`, `error(row:column:)`, `index(ofColumn:)`); `ColumnBuilder.integers/doubles/currency/dateTimes/booleans/strings` (`nil` là ô trống). Ô lỗi của M **không** nằm trong cột (ô đó là BLANK) mà ở `errorMask`.
- `Sources/MEngine/Contracts.swift` (`MLibrary.all` gộp `TableColumnsLibrary`, `TableRowsLibrary`, `ValueLibrary`, `JoinGroupLibrary`) và các file khung `Library/TableColumns.swift`, `TableRows.swift`, `TextNumberDateList.swift` (hiện `functions` rỗng; bạn điền).
- `Sources/MEngine/Operators.swift` (`MOperators.equals`, `compare`, `number`): dùng cho so sánh, sắp xếp, `Table.Distinct`; **không** tự viết lại quy tắc so sánh M.
- `Sources/MEngine/Builtins.swift`: `#table`, `#date`, hằng `Order.Ascending` (0), `Order.Descending` (1), `QuoteStyle.None` (0), `QuoteStyle.Csv` (1), kiểu `Int64.Type`… Bạn **không** sửa file này.
- `docs/phase-f-evidence/vm-f3/QUAN-SAT.md` mục 1 (bảng lệnh ↔ tên bước ↔ biểu thức M nguyên văn) và mục 2 (lỗi chuyển kiểu, `Error` trong ô), `SUY-DOAN-M.md` (hành vi lõi đã đối chiếu Desktop).
- Golden: `docs/phase-f-evidence/vm-f3/golden/chuoi-1.m` + `chuoi-1-pivot-6-dong.tsv`, `chuoi-2.m` + `chuoi-2-98-dong.tsv`. Đây là M **nguyên văn do Desktop sinh** và bảng Desktop nạp. Trợ giúp test: `Tests/MEngineTests/Library/GoldenFixtures.swift` (`GoldenFixtures.run("chuoi-2.m")`, `run("chuoi-1.m", upTo: "Uppercased Text")`, `tsv(_:)`, `salesPromoted()`); đã có `Order.*`/`QuoteStyle.*`, `MEnvironment`, `MEvaluator(environment:).evaluate(source:upTo:rowLimit:)`. Nếu `GoldenFixtures.run` trả `nil` (thiếu file mẫu `build/f-out/samples/sales_2026.xlsx`) thì test tự bỏ qua. Mẫu viết test: `Tests/MEngineTests/EvaluatorTests.swift`, `DesktopObservedTests.swift`.

## File được sửa hoặc tạo (không sửa gì ngoài danh sách)

- `Sources/MEngine/Library/TableColumns.swift`: hàm cột (`TableColumnsLibrary.functions`). Được tách thêm file mới trong `Sources/MEngine/Library/` với tên bắt đầu bằng `TableColumns` (ví dụ `TableColumnsTypes.swift`) nếu file quá lớn.
- `Sources/MEngine/Library/TableRows.swift`: hàm dòng (`TableRowsLibrary.functions`); tách thêm `TableRows*.swift` nếu cần.
- `Sources/MEngine/Library/TextNumberDateList.swift`: hàm giá trị (`ValueLibrary.functions`); tách thêm `Value*.swift` nếu cần.
- `Tests/MEngineTests/Library/TableColumnsTests.swift`, `TableRowsTests.swift`, `ValueLibraryTests.swift`, `GoldenChainTests.swift` (tạo mới).
- `docs/tasks/f-mfun-report.md`: báo cáo cuối.

Mọi file khác giữ nguyên, gồm `Package.swift`, `Lexer/Parser/Evaluator/Value/Operators/Builtins/Contracts/Support/TableBuilder.swift`, `Library/TableJoinGroup.swift` (lead: Merge, Group, Pivot, Unpivot, Join), `Tests/MEngineTests/Library/GoldenFixtures*.swift`, và mọi test có sẵn. Target `MEngine` dùng Swift 6 (kiểm tra đồng thời nghiêm ngặt): kiểu công khai phải `Sendable`. **Nếu thấy lõi M (Evaluator, Operators…) sai hoặc thiếu thứ bạn cần, không sửa: ghi vào báo cáo, mục "Đề xuất cho lead", rồi làm tiếp phần còn lại.**

## Danh sách hàm

Tên đầy đủ, tham số đúng thứ tự và tên như tài liệu M (tham số tuỳ chọn đánh `isOptional: true`, nhận `.null` khi không truyền). `observed: true` **chỉ** khi hành vi đã được golden ở trên đối chiếu (ghi chú ở cột "Golden"); còn lại `observed: false` và chú thích `[SUY ĐOÁN]` trên dòng khai báo, hành vi theo tài liệu công khai của M (văn hoá en-US).

**Cột** (`TableColumnsLibrary`):

| Hàm | Golden (QUAN-SAT mục 1) |
|---|---|
| `Table.PromoteHeaders(table, optional options)`; `options` là bản ghi, `[PromoteAllScalars = true]` | dòng đầu thành tên cột; mọi giá trị vô hướng được ép sang chuỗi. Tên cột rỗng/null hoặc trùng thì đổi theo quy tắc M (`Column1`; trùng → `Tên_1`) **[SUY ĐOÁN]**. Test trên `#table` viết tay (golden chạy từ bảng đã thăng tiêu đề) |
| `Table.TransformColumnTypes(table, typeTransformations, optional culture)` | `{{"Qty", Int64.Type}, {"OrderDate", type date}, {"Region", type text}, {"Price", type number}}`. Chuyển văn bản "South" sang số nguyên **không ném lỗi**: cả cột vẫn là cột số nguyên, ô đó vào `errorMask` với thông điệp bắt đầu bằng `DataFormat.Error` và có chữ `We couldn't convert to Number.`; ô `null` vẫn `null`. Cột `dateTime` sang `type date` giữ nguyên số ngày, bỏ phần giờ **[SUY ĐOÁN phần giờ]**. Ô lỗi có sẵn giữ lỗi. Chuyển `type text` từ số: số nguyên viết không có phần thập phân (`1`), số thực ngắn nhất (`9.99`) |
| `Table.RenameColumns(table, renames, optional missingField)` | `{{"Region", "Vung"}}` |
| `Table.RemoveColumns(table, columns, optional missingField)` | `{"Price"}`; cột không có → lỗi `Expression.Error` trừ khi `MissingField.Ignore` (không cần hỗ trợ hằng đó; chỉ cần lỗi rõ) |
| `Table.SelectColumns`, `Table.ReorderColumns`, `Table.DuplicateColumn(table, column, newName)` | [SUY ĐOÁN] |
| `Table.AddColumn(table, newColumnName, columnGenerator, optional columnType)` | `each [Qty] * 2` không gán kiểu → cột kiểu `any`: **bảng chưa có cột `any`**, nên suy kiểu cột từ các giá trị (dùng `MTables.build` với kiểu `nil`; cột lẫn kiểu thì ném `MError.unsupported`) |
| `Table.AddIndexColumn(table, newColumnName, optional initialValue, optional increment, optional columnType)` | `"Index", 0, 1, Int64.Type`, cột nguyên |
| `Table.SplitColumn(table, sourceColumn, splitter, optional columnNamesOrNumber, …)` | `Splitter.SplitTextByDelimiter(" ", QuoteStyle.Csv)` với tên `{"Vung.1", "Vung.2"}`: cột nguồn bị thay bởi các cột mới ở đúng vị trí; phần thiếu là `null`; dữ liệu "Bac" (không có dấu cách) cho `Vung.1 = "Bac"`, `Vung.2 = null`; kiểu cột mới là `text` (golden gán lại kiểu ở bước sau) |
| `Table.CombineColumns(table, sourceColumns, combiner, column)` | [SUY ĐOÁN]; `Combiner.CombineTextByDelimiter(delimiter)` cần cài kèm |
| `Table.TransformColumns(table, transformOperations, optional defaultTransformation, optional missingField)` | `{{"Product", Text.Upper, type text}}`; phần tử có hoặc không có kiểu thứ ba |
| `Table.ColumnNames(table)`, `Table.RowCount(table)`, `Table.ColumnCount(table)` | `each Table.RowCount(_)` trong golden Group By |

**Dòng** (`TableRowsLibrary`):

| Hàm | Golden |
|---|---|
| `Table.SelectRows(table, condition)` | `each ([Qty] = 1 or [Qty] = 2)`: vị từ nhận **bản ghi của hàng** (`MTables.row`); kết quả `true` giữ; `null` hoặc không phải logic → lỗi `Expression.Error` "không phải true/false" |
| `Table.Sort(table, comparisonCriteria)` | `{{"OrderDate", Order.Ascending}}`; cũng nhận `"Cột"` hoặc `{"Cột", Order.Descending}`; **ổn định**; `null` xếp trước giá trị khi tăng dần (như M); so sánh bằng `MOperators.compare` |
| `Table.FirstN(table, countOrCondition)`, `Table.Skip(table, countOrCondition)`, `Table.LastN`, `Table.RemoveFirstN`, `Table.RemoveLastN`, `Table.Range` | `FirstN(…,100)`, `Skip(…,2)` đã quan sát; `countOrCondition` là số (không cần hỗ trợ vị từ nếu khó, nhưng thì báo `unsupported` rõ). Số vượt quá số dòng không lỗi |
| `Table.Distinct(table, optional equationCriteria)` | `{"Vung"}`: giữ dòng đầu của mỗi nhóm khoá, **giữ thứ tự xuất hiện**; trên dữ liệu thử còn 5 dòng, đơn 313, 293, 113, 251, 199 (dữ liệu đã qua các bước trước theo `chuoi-*` trong QUAN-SAT; bạn tự dựng bảng nhỏ viết tay để test, không dựa vào số này nếu không dựng lại được) |
| `Table.ReplaceValue(table, oldValue, newValue, replacer, columnsToSearch)` | `"North","Bac",Replacer.ReplaceText,{"Vung"}`: thay chuỗi con trong cột văn bản; cài `Replacer.ReplaceText`, `Replacer.ReplaceValue` (thay cả giá trị khi bằng nhau) |
| `Table.FillDown(table, columns)`, `Table.FillUp` | `{"Vung"}`: ô `null` lấy giá trị ô liền trên khác `null` |
| `Table.ReverseRows(table)` | đã quan sát |
| `Table.ReplaceErrorValues(table, errorReplacement)` | `{{"Region", 0}}`: ô lỗi trong cột thành giá trị đó; cột kiểu số nguyên nhận 0 |
| `Table.RemoveRowsWithErrors(table, optional columns)`, `Table.SelectRowsWithErrors` | [SUY ĐOÁN] |

**Giá trị** (`ValueLibrary`): tối thiểu và đúng, mỗi hàm một test.
- `Text.Upper` (đã quan sát; chuỗi Việt có dấu: `"áo thun"` → `"ÁO THUN"`; `null` → `null`), `Text.Lower`, `Text.Proper`, `Text.Trim`, `Text.Clean`, `Text.Length`, `Text.Contains`, `Text.StartsWith`, `Text.EndsWith`, `Text.Replace`, `Text.Combine`, `Text.From`, `Text.Start`, `Text.End`, `Text.PadStart`.
- `Number.From` (`"1,5"` → 15 theo en-US, đã quan sát), `Number.Round`, `Number.Abs`, `Number.RoundDown`, `Number.RoundUp`, `Number.Mod`, `Number.IntegerDivide`.
- `Date.Year`, `Date.Month`, `Date.Day`, `Date.From`, `Date.AddDays`, `Date.AddMonths`, `Date.DayOfWeek` (dùng `MDates` ở `Sources/MEngine/Dates.swift`).
- `List.Sum` (đã quan sát: `List.Sum({})` = `null`), `List.Count`, `List.Distinct`, `List.Max`, `List.Min`, `List.Average`, `List.Sort`, `List.Transform`, `List.Select`, `List.Contains`, `List.First`, `List.Last`, `List.Numbers`, `List.Reverse`.
- `Replacer.ReplaceText`, `Replacer.ReplaceValue`, `Splitter.SplitTextByDelimiter(delimiter, optional quoteStyle)` (trả hàm `text → list`; `QuoteStyle.Csv` = 1 coi ngoặc kép là dấu bọc), `Combiner.CombineTextByDelimiter(delimiter)`. Hàm trả hàm: dùng `MFunction` trả `.function(MFunction)`.

Tên hàm ngoài danh sách trên: **không cài**; lõi sẽ báo `MError.unsupported` (đúng ý: không đoán).

## Quy tắc chung

- Giữ **thứ tự cột** và **kiểu cột** của bảng đầu vào trừ khi hàm đổi chúng. `Table.*` trả `TableData` mới, không sửa bảng cũ. Ô lỗi (`errorMask`) phải được chuyển theo khi dòng/cột được giữ, sắp lại, lọc hoặc đổi tên (cột/dòng chỉ số đổi thì dịch mặt nạ cho đúng).
- Lỗi chương trình dùng `MError.expression("…")` tiếng Việt, nêu tên hàm và đối số; không `fatalError`, không `try!` trên dữ liệu người dùng, không chia/lập chỉ mục mà chưa kiểm biên.
- Vị từ/biến đổi do người dùng viết chạy trên **mỗi hàng**: gọi `MFunction.call` một lần mỗi hàng; **không** dựng lại bản ghi cho mọi cột nếu hàm chỉ cần một cột khi bạn biết trước (tối ưu sau khi test xanh). Bảng 1 triệu dòng phải đủ nhanh: `Table.SelectRows`, `Sort`, `Distinct`, `FirstN`, `Skip`, `TransformColumnTypes` trên 1 triệu dòng × 10 cột mỗi hàm dưới 5 giây ở bản release (đo bằng test nặng, bật khi `BIPRO_HEAVY=1`; không bắt buộc đạt nếu vị từ do người dùng chậm, nhưng ghi số đo vào báo cáo).
- Không đọc hay ghi file, không mạng.

## Làm theo thứ tự này (từng lát: viết test đỏ trước, rồi cài đặt cho xanh)

1. `ValueLibrary` (Text, Number, Date, List, Replacer, Splitter, Combiner): giá trị viết tay độc lập.
2. `TableRowsLibrary` (dòng), test trên bảng nhỏ dựng bằng `#table`/`MTables.build`.
3. `TableColumnsLibrary` (cột), cùng cách.
4. `GoldenChainTests`: chạy golden bằng `GoldenFixtures` (xem bên dưới).

## Test golden bắt buộc (`GoldenChainTests.swift`)

- `chuoi-2.m` chạy trọn: kết quả là bảng **98 dòng**, 7 cột `OrderID, OrderDate, Region, CustomerID, Product, Qty, Amount` (không còn `Price`), khớp **từng ô** với `chuoi-2-98-dong.tsv` (so ngày dạng `yyyy-MM-dd`; số so bằng chuỗi 0,000001; `Region` toàn `0`; dòng đầu `3, 2026-09-09, 0, 40, Áo thun, 19, 758.1`). Cột `Region` kiểu số nguyên, không ô lỗi.
- `chuoi-1.m` chạy đến bước `"Uppercased Text"` (các bước sau là Group, Unpivot, Pivot: lead cài sau): 43 dòng; cột `Vung.1`, `Vung.2`, `Product` in hoa; số dòng theo `Product` của bảng kết quả (đếm ngay trong test bằng từ điển Swift, **không** dùng `Table.Group`) khớp cột `Count` của `chuoi-1-pivot-6-dong.tsv` (GIÀY 8, MŨ 11, QUẦN JEAN 3, TÚI XÁCH 3, ÁO THUN 7, ĐỒNG HỒ 11, tên đã in hoa); chạy đến từng bước trung gian để kiểm: `"Sorted Rows"` tăng dần theo `OrderDate` (kiểm cặp liền kề, ổn định theo `OrderID` ở ngày trùng vì dữ liệu sinh theo thứ tự), `"Removed Columns"` không còn `Price`, `"Replaced Value"` không còn dòng nào có `Vung` chứa `North`, `"Filtered Rows"` 43 dòng, `"Added Index"` Index 0…42, `"Reversed Rows"` đảo thứ tự bước trước, `"Split Column by Delimiter"` có `Vung.1`, `Vung.2`.
- Test lỗi chuyển kiểu: dựng bảng có cột văn bản `South`, `North`, `5`; `Table.TransformColumnTypes` sang `Int64.Type`: cột số nguyên, hai ô lỗi (`errorMask`), ô `5` = 5; `Table.ReplaceErrorValues(…, {{"Cột", 0}})` cho `0, 0, 5`.

Mọi test dùng giá trị viết tay độc lập hoặc golden Desktop; **không** tính lại kết quả bằng chính hàm đang test; không sửa hay tắt test có sẵn; không hard-code kết quả trong mã nguồn để test qua.

## Lệnh được phép (chạy từng lệnh riêng, không dùng `&&`, `;`, `|`, `cd`, `rm`, `cp`, `mkdir`, `python`)

`swift build`, `swift test`, `swift test --filter <tên>`, `git status`, `git diff`, `git diff --stat`, `git grep <mẫu>`, `git log --oneline`, `ls <thư mục>`, `cmp <a> <b>`. Dùng công cụ đọc/ghi file của bạn để tạo và sửa file. Lần chạy `swift build`/`swift test` đầu tiên biên dịch lại cả repo, mất vài phút. Test nặng chạy bằng `BIPRO_HEAVY=1 swift test --filter <tên>`.

## Tiêu chí xong việc (tất cả phải đúng, kiểm từng mục)

1. `swift build` không lỗi, không cảnh báo mới từ file của bạn.
2. `swift test` **toàn bộ** qua (test cần file Nhom6 của người dùng tự bỏ qua; bình thường). Chép dòng kết quả cuối (`Test run with N tests passed`) vào báo cáo.
3. `GoldenChainTests`: cả `chuoi-2` (98 dòng, từng ô) và `chuoi-1` đến `Uppercased Text` đều qua, **không bị bỏ qua** (file `build/f-out/samples/sales_2026.xlsx` có sẵn trong worktree của bạn; báo cáo ghi rõ test có chạy thật).
4. Mỗi hàm trong danh sách có ít nhất một test giá trị viết tay (đúng, và một trường hợp lỗi hoặc biên: bảng 0 dòng, cột không tồn tại, `null`); mỗi hàm có cờ `observed` đúng theo cột "Golden" (hàm đã quan sát là `true`, còn lại `false` kèm chú thích `[SUY ĐOÁN]`).
5. `MLibraryTests.registryHasNoDuplicateNames` vẫn qua (tên hàm không trùng giữa các nhóm và với `TableJoinGroup`).
6. `git status` chỉ liệt kê file trong danh sách được sửa; bạn không commit, không push.
7. Báo cáo ngắn `docs/tasks/f-mfun-report.md`: file đã tạo/sửa, tóm tắt, dòng kết quả `swift test`, số đo hiệu năng 1 triệu dòng (nếu đã đo), mọi quyết định bạn chọn khác gợi ý (và vì sao), mục "Đề xuất cho lead" (lỗi hoặc thiếu sót của lõi M), hàm đã cài ở mức `[SUY ĐOÁN]`, việc còn tồn đọng. Không bàn giao như đã xong khi còn mục nào chưa đạt: ghi rõ mục nào và lý do.
