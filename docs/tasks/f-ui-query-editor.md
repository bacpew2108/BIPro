Bạn làm việc trong repo Swift "BI Pro" (ứng dụng macOS giống Power BI Desktop, SwiftUI, macOS 15), trong một git worktree riêng tách từ `main`. Phase F đang làm Power Query. Gói của bạn, **F-UI vòng Query Editor**: vẽ **cửa sổ Query Editor** (Chuyển đổi dữ liệu) bằng SwiftUI, từ trạng thái `QueryEditorState` đã có: cột Queries, lưới xem trước, khung Query Settings với Applied Steps, thanh công thức M, column profile, ribbon (Home, Transform, Add Column, View), hộp Advanced Editor, hộp hỏi khi chèn bước giữa và khi đóng chưa áp dụng. **Chỉ vẽ và nối lệnh vào `QueryEditorState`; không viết logic truy vấn.** Chỉ dùng framework hệ thống và thư viện của repo; không thêm package, không tải gì từ mạng. Giao diện **tiếng Việt**.

## Đọc trước (đã có, giữ nguyên, không sửa)

- `Sources/BIPro/Query/QueryEditorState.swift`: **toàn bộ API bạn dùng**; đọc kỹ. Tóm tắt (đều `@MainActor`, `@Observable`):
  - Dữ liệu vẽ: `queries: [QueryModel]` (`id`, `name`, `steps: [QueryStep]` (`id`, `name`, `expression`, `kind`), `enableLoad`, `lockedStepCount`, `loadedTableName`, `isModified`), `selectedQueryID`, `selectedQuery`, `selectedStepIndex`, `preview: TableData?` (tối đa 1000 dòng, bước đang chọn), `profiles: [ColumnProfile]` (cùng thứ tự cột của `preview`: `columnName`, `valid`, `error`, `empty`, `distinct`, `unique`, `min`, `max`, `average` (chuỗi đã định dạng hoặc nil), `distribution: [ProfileBucket(label, count)]`), `errorMessage` (lỗi của bước đang chọn; khi có thì `preview == nil`), `stepErrors: [tênBước: thôngĐiệp]`, `hasPendingChanges`, `hasUnappliedQueries`, `applyMessage`, `isApplying`, `canUndo`, `canRedo`, `advancedSource`.
  - Lệnh: `selectQuery(id)`, `selectStep(index)`, `perform(_ command: StepCommand, confirmInsert: Bool = false) -> StepCommandOutcome` (`.applied`, `.needsInsertConfirmation`, `.rejected(lýDo)`), `deleteStep(at:) -> String?`, `renameStep(at:to:) -> String?`, `setExpression(at:_:) -> String?`, `moveStep(at:by:) -> String?`, `applyAdvancedSource(_:) -> String?`, `renameQuery(_:to:existingTableNames:) -> String?`, `setEnableLoad(_:_:)`, `undo()`, `redo()`. Các hàm trả `String?` trả **lý do từ chối bằng tiếng Việt** (hiện cho người dùng) hoặc `nil` khi đã làm. `refresh()` do trạng thái tự gọi sau mỗi thay đổi; bạn không gọi.
- `Sources/MEngine/StepFactory.swift`: kiểu `StepCommand` (các ca và tham số), `SortKey`, `ColumnRename`, `ColumnTypeChange`, `MColumnType`, `TextFormat`, `ErrorReplacement`, `MLiteral`. Bạn chỉ **dựng giá trị `StepCommand`** từ thao tác của người dùng rồi gọi `state.perform`.
- `Sources/ColumnStore/TableData.swift` (`columns[i].name`, `.data.type`, `rowCount`, `value(row:column:)`, `errorMask`) và `Contracts.swift` (`StoredValue`, `DAXType`).
- `Sources/BIPro/Query/Editor/NavigatorFormat.swift` (`cell(_:)` định dạng ô, dùng lại), `NavigatorPreviewGrid.swift` (mẫu lưới SwiftUI thuần và cờ `scrollable`), `NavigatorView.swift` (mẫu cửa sổ, tiêu đề, chân).
- `Sources/BIPro/DesignSystem/Tokens.swift` (`DS.Palette`, `DS.Typeface`, `DS.Radius`, `DS.Space`; màu nhấn hệ thống `#0A84FF`) và `Components.swift` (`PrimaryButtonStyle`, `SecondaryButtonStyle`, `SearchField`, `CheckboxMark`, `Badge`, `SectionLabel`, `TileBackground`): **dùng lại**, không đặt màu hay cỡ chữ tự do.
- Thiết kế để đặt cạnh (mở ảnh trước khi vẽ): `UIdesign/lumen_analytics_query_editor_1/screen.png` (tab View, có column profile), `UIdesign/lumen_analytics_query_editor_transform_tab/screen.png` (tab Transform), `UIdesign/lumen_analytics_query_editor_2/screen.png`, `_3/screen.png`, kèm `code.html`; `UIdesign/lumen_analytics_design_system/DESIGN.md`. **Ảnh thiết kế ở tỉ lệ 1,25×**: chia toạ độ cho 1,25. Quan sát hành vi thật của Power BI Desktop 2.159 (ảnh chụp): `docs/phase-f-evidence/vm-f3/QUAN-SAT.md` mục 1 và 2, `hop-thoai-insert-step.png`, `advanced-editor-chuoi-buoc.png`, `loi-chuyen-kieu-error-trong-o.png`, `buoc-remove-duplicates.png`.
- Mẫu xuất ảnh PNG: `Tests/BIProTests/Charts/NewChartsImageTests.swift` (hàm `png(_:size:)` dùng `ImageRenderer`, `scale = 2`) và `Tests/BIProTests/Query/Editor/GetDataImageTests.swift`. `FFixtures.sample("tên")` (`Tests/BIProTests/Model/FFixtures.swift`) trả đường dẫn file mẫu trong `build/f-out/samples/` (đã nối sẵn vào worktree của bạn; bạn không chạy script sinh).

## File được sửa hoặc tạo (không sửa gì ngoài danh sách)

Tạo mới trong `Sources/BIPro/Query/Editor/`:
- `QueryEditorWindow.swift`: `QueryEditorWindow` (gốc) và bố cục tổng.
- `QueryListView.swift` (khung Queries bên trái), `AppliedStepsView.swift` (Query Settings), `PreviewGridView.swift`, `ColumnProfileView.swift`, `QueryRibbonView.swift`, `FormulaBarView.swift`, `AdvancedEditorSheet.swift`, `QueryCommandPopovers.swift` (hộp nhập tham số nhỏ), `QueryRibbonCommand.swift` (logic thuần của lệnh ribbon), `QueryEditorFormat.swift` (logic thuần định dạng).
- Tách thêm file `Query*.swift` trong thư mục này nếu cần.

Tạo mới trong `Tests/BIProTests/Query/Editor/`: `QueryRibbonCommandTests.swift`, `QueryEditorFormatTests.swift`, `QueryEditorImageTests.swift`.

Tạo mới: `docs/tasks/f-ui-query-editor-report.md` (báo cáo cuối).

Mọi file khác giữ nguyên, gồm `Package.swift`, **`QueryEditorState.swift`**, `SourceQuery.swift`, `NavigatorState.swift`, `Model/Edit/**`, mọi thứ trong `Sources/MEngine/**`, `Shell/**` (`ShellView.swift`, `Ribbon.swift`, `GetDataDialog.swift`), `Workspace.swift`, `DocumentState*.swift`, `App.swift`, `DesignSystem/**`, các file `Navigator*.swift` và `ConnectorCatalog.swift`, và mọi test có sẵn. Lead sẽ nối cửa sổ vào Ribbon "Chuyển đổi dữ liệu" và vào hộp thoại Navigator; bạn **không** nối. Nếu thấy `QueryEditorState` thiếu thứ bạn cần, ghi vào báo cáo mục "Đề xuất cho lead" và làm tiếp phần còn lại.

## API công khai (giữ đúng tên; lead gọi)

```swift
struct QueryEditorWindow: View {
    init(state: QueryEditorState,
         existingTableNames: Set<String>,          // tên bảng đang có trong mô hình (để đổi tên truy vấn khỏi trùng)
         onApply: @escaping () -> Void,            // "Đóng và áp dụng" / "Áp dụng": lead gọi state.closeAndApply rồi gán state.applyMessage; view KHÔNG tự đóng
         onClose: @escaping () -> Void,            // đóng cửa sổ (sau khi đã xử lý hộp "Thay đổi chưa áp dụng")
         scrollable: Bool = true)                  // false chỉ cho test xuất ảnh (xem "Test và ảnh")
}
enum QueryRibbonTab: CaseIterable { case home, transform, addColumn, view }
enum QueryRibbonCommand: CaseIterable { ... }       // xem "Lệnh ribbon"
enum QueryEditorFormat {
    static func percent(_ part: Int, of total: Int) -> String        // "93%": làm tròn gần nhất; total == 0 → "0%"
    static func statusSummary(columns: Int, rows: Int) -> String     // rows ≤ 999: "9 cột · 500 dòng"; rows ≥ 1000: "9 cột · 999+ dòng"
    static func profileCaption(rowsProfiled: Int) -> String          // "Dựa trên 1000 dòng đầu" (rowsProfiled là số dòng của preview; < 1000 thì "Dựa trên 500 dòng")
    static func typeBadge(_ type: DAXType) -> String                 // integer, double, currency → "123"; string → "ABC"; dateTime → "Ngày"; boolean → "T/F"
    static func countLine(_ profile: ColumnProfile) -> Int           // valid + error + empty
}
```

## Hành vi cần cài

**Cửa sổ** (mặc định 1280 × 800 pt; tiêu đề "{tên truy vấn đang chọn} — Trình chỉnh sửa truy vấn", huy hiệu "Đã sửa" khi `state.hasPendingChanges`): dải tab ribbon (Tệp không làm, mờ; Trang chủ, Chuyển đổi, Thêm cột, Xem), thân ribbon, thanh công thức, ba cột (Queries 250 pt, lưới + profile giữa, Query Settings 290 pt), thanh trạng thái. Ba cột co hẹp được bằng tuỳ chọn tab **Xem** (hiện/ẩn thanh công thức, khung Queries, Query Settings, column profile) là `@State` giao diện thuần.

**Khung Queries** (`QueryListView`): tiêu đề "Truy vấn [N]"; mỗi truy vấn một dòng phẳng (biểu tượng bảng, tên); dòng đang chọn tô màu nhấn chữ trắng (như thiết kế); truy vấn **tắt Enable load** (`!enableLoad`) hiện chữ nghiêng mờ; truy vấn có `stepErrors` không rỗng hiện biểu tượng cảnh báo `DS.Palette.warning`. Bấm = `state.selectQuery`. Chuột phải: "Bật tải vào mô hình" (dấu tích, gọi `setEnableLoad`), "Đổi tên…" (hộp nhỏ; lý do từ chối của `renameQuery` hiện trong hộp). **Không** vẽ thư mục nhóm (mô hình không có nhóm).

**Query Settings + Applied Steps** (`AppliedStepsView`): nhãn "THUỘC TÍNH", ô "Tên" sửa được (Enter gọi `renameQuery`; lý do từ chối hiện dưới ô, màu danger); nhãn "CÁC BƯỚC ĐÃ ÁP DỤNG", mỗi bước một dòng theo `selectedQuery.steps`: tên; bước đang chọn tô nhấn chữ trắng kèm nút ✕ (gọi `deleteStep(at:)`); bước có trong `stepErrors` hiện biểu tượng cảnh báo `DS.Palette.danger`, rê chuột/long-press hiện thông điệp; bước khoá (`index < lockedStepCount`) hiện biểu tượng khoá nhỏ mờ thay cho bánh răng và **không** có ✕ (tooltip "Bước do nguồn tạo, chưa sửa được"). Bấm dòng = `selectStep`. Chuột phải bước chưa khoá: "Đổi tên…", "Xoá", "Chuyển lên", "Chuyển xuống" (gọi `moveStep(at:by:)`). Mọi `String?` trả về hiện trong một dải thông báo nhỏ đóng được (không dùng hộp thoại modal). Dưới danh sách: nút "Hoàn tác" và "Làm lại" (`undo`, `redo`, tắt theo `canUndo`/`canRedo`; phím ⌘Z, ⇧⌘Z khi cửa sổ đang chọn).

**Thanh công thức** (`FormulaBarView`): ký hiệu `fx`, rồi ô chữ đơn cách hiện `= {biểu thức của bước đang chọn}` (không in dấu `=` nếu biểu thức đã bắt đầu bằng `=`; bản thân biểu thức **không** chứa `=`: chỉ hiển thị thêm). Bước chưa khoá: sửa được, Enter hoặc nút ✓ gọi `setExpression(at: selectedStepIndex, text)`; nút ✕ trả lại văn bản cũ; lý do từ chối (lỗi cú pháp có dòng, cột) hiện ngay dưới thanh, màu danger. Bước khoá: chỉ đọc, nền mờ. Nút mũi tên cuối thanh mở rộng ô thành nhiều dòng.

**Lưới xem trước** (`PreviewGridView`) từ `state.preview` (chỉ SwiftUI thuần, cột rộng 140 pt, cột `#` 40 pt, hàng cao 26 pt, `NavigatorFormat.cell` cho ô):
- Tiêu đề cột: huy hiệu loại `QueryEditorFormat.typeBadge`, tên cột, mũi tên; **thanh chất lượng** từ `profiles[i]`: thanh ngang xanh (valid) / đỏ (error) / xám (empty) theo tỉ lệ, và dòng "93% 0% 7%" (valid, error, empty, `QueryEditorFormat.percent`), cùng "{distinct} giá trị khác nhau" khi bật "Phân bố cột" (tab Xem). Bật/tắt riêng "Chất lượng cột", "Phân bố cột", "Hồ sơ cột" ở tab Xem (mặc định bật cả ba).
- Bấm tiêu đề = chọn cột (viền nhấn, nền `selectionSoft`); ⌘-bấm hoặc ⇧-bấm = chọn thêm nhiều cột. Cột đang chọn là đối tượng của lệnh ribbon và của `ColumnProfileView`. Bấm đúp tên cột = ô sửa tên tại chỗ, Enter gọi `perform(.renameColumns([ColumnRename(old:new:)]))`.
- Ô có trong `errorMask` hiện "Lỗi" trong viên thuốc đỏ (`DS.Palette.danger`, nền đỏ nhạt cả ô); bấm vào ô lỗi thì hiện thông điệp lỗi ở khung nhỏ dưới lưới (chữ của `errorMask`, ví dụ "DataFormat.Error: We couldn't convert to Number. Details: South").
- `state.errorMessage != nil`: thay lưới bằng biểu tượng cảnh báo, thông điệp nguyên văn (danger) và gợi ý "Chọn bước trước đó trong Các bước đã áp dụng hoặc sửa biểu thức"; `preview == nil` và không lỗi: vòng quay "Đang tính xem trước…".
- Tiêu đề phía trên lưới: tên truy vấn và viên "Cột đang chọn: {tên}" khi có.

**Column profile** (`ColumnProfileView`, đáy cửa sổ, đóng được bằng ✕): khi chọn đúng **một** cột có trong `profiles`. Trái "Thống kê cột ({tên})": Số dòng (`countLine`), Khác nhau (`distinct`), Lỗi (`error`, màu danger nếu > 0), Duy nhất (`unique`), Trống (`empty`, màu cảnh báo nếu > 0), Nhỏ nhất, Lớn nhất, Trung bình (`—` khi nil); phải "Phân bố giá trị ({tên})" `{distinct} giá trị`: mỗi `ProfileBucket` một dòng: nhãn, thanh ngang (độ dài theo `count` / `count` lớn nhất), "{count} ({phần trăm của countLine})". Dòng chú thích `profileCaption`.

**Thanh trạng thái**: biểu tượng chấm xanh + `statusSummary`; "Phân tích cột dựa trên 1000 dòng đầu"; ở phải **"Đóng và áp dụng"** (`PrimaryButtonStyle`; gọi `onApply`; tắt khi `state.isApplying`, kèm vòng quay) và "Đóng" (`SecondaryButtonStyle`, Esc). Khi `state.applyMessage != nil` hiện thông điệp đó (danger) trên thanh, đóng được. "Đóng" khi `state.hasPendingChanges || state.hasUnappliedQueries`: hiện hộp "Thay đổi chưa áp dụng" ("Có thay đổi trong truy vấn chưa được áp dụng vào mô hình.") với ba nút "Áp dụng" (gọi `onApply`), "Bỏ thay đổi" (gọi `onClose` không áp dụng), "Huỷ" (ở lại); không có thay đổi thì "Đóng" gọi thẳng `onClose`.

**Hộp "Chèn bước"**: mọi lệnh ribbon gọi `state.perform(command)`; kết quả `.needsInsertConfirmation` thì hiện hộp "Chèn bước: Bạn có chắc muốn chèn một bước không? Chèn bước ở giữa có thể ảnh hưởng đến các bước sau và làm truy vấn bị lỗi." với "Chèn" (gọi lại `perform(command, confirmInsert: true)`) và "Huỷ" (Desktop 2.159, `hop-thoai-insert-step.png`); `.rejected(lýDo)` thì hiện `lýDo` ở dải thông báo; `.applied` không hiện gì.

**Advanced Editor** (`AdvancedEditorSheet`, nút "Trình soạn thảo nâng cao" ở tab Trang chủ và Xem): sheet 760 × 520, tiêu đề "Trình soạn thảo nâng cao — {tên truy vấn}", vùng soạn chữ đơn cách nhiều dòng (SwiftUI `TextEditor` hoặc `CodeEditor` có sẵn nếu dùng được trong `ImageRenderer`; ưu tiên `TextEditor`), khởi tạo bằng `state.advancedSource`; nút "Xong" gọi `applyAdvancedSource(text)`: `nil` thì đóng, có lý do thì hiện lý do (danger) và giữ sheet; "Huỷ". Dải dưới: "Không có lỗi cú pháp" (xanh) khi lý do rỗng.

**Lệnh ribbon** (`QueryRibbonCommand`, logic thuần có test; nút ribbon dựng từ đây). Mỗi lệnh có `title` (tiếng Việt), `tab`, `isAvailable` (false → nút mờ, tooltip "Sắp có") và hàm `stepCommand(context:) -> StepCommand?` với `context` (struct `Sendable` bạn định nghĩa) gồm: `selectedColumns: [String]` theo thứ tự trên lưới, `columnTypes: [String: DAXType]`, `allColumns: [String]`, và tham số đã nhập (số dòng, dấu phân cách, văn bản tìm/thay, tên cột mới, công thức…). Trả `nil` khi thiếu đầu vào (ví dụ chưa chọn cột); `isEnabled(context)` suy từ đó (nút mờ khi `nil` và không cần tham số). Bảng ánh xạ **bắt buộc** (tab: lệnh → `StepCommand`):

| Tab | Lệnh | `StepCommand` | Đầu vào |
|---|---|---|---|
| Trang chủ | Xoá cột | `.removeColumns(selectedColumns)` | ≥ 1 cột chọn |
| Trang chủ | Sắp xếp tăng / giảm | `.sortRows([SortKey(column: c, descending: …)])` cho mỗi cột chọn theo thứ tự | ≥ 1 cột |
| Trang chủ | Giữ N dòng đầu | `.keepTopRows(n)` | n ≥ 1 (hộp nhập số) |
| Trang chủ | Xoá N dòng đầu | `.removeTopRows(n)` | n ≥ 1 |
| Trang chủ | Xoá dòng trùng | `.removeDuplicates(selectedColumns)` | ≥ 1 cột |
| Trang chủ | Dùng dòng đầu làm tiêu đề | `.promoteHeaders` | — |
| Trang chủ | Kiểu dữ liệu ▸ Số nguyên / Số thập phân / Văn bản / Ngày / Ngày giờ / Đúng-Sai | `.changeType(selectedColumns.map { ColumnTypeChange(column: $0, type: …) })` với `.wholeNumber`, `.decimal`, `.text`, `.date`, `.dateTime`, `.logical` | ≥ 1 cột |
| Trang chủ | Thay giá trị | `.replaceValue(old: .text(a), new: .text(b), columns: selectedColumns)` | ≥ 1 cột, hộp "Tìm" và "Thay bằng" |
| Trang chủ | Lọc theo giá trị | `.filterEquals(column: c, values: danhSách)` | đúng 1 cột; hộp liệt kê `ColumnProfile.distribution` của cột (tối đa 20 giá trị, nhãn nguyên văn, ô tích); giá trị số dùng `.number`, còn lại `.text`: nếu cột là `integer`/`double` mà nhãn không đọc được thành số thì bỏ nhãn đó |
| Chuyển đổi | Đảo thứ tự dòng | `.reverseRows` | — |
| Chuyển đổi | Điền xuống / Điền lên | `.fillDown(selectedColumns)` / `.fillUp(selectedColumns)` | ≥ 1 cột |
| Chuyển đổi | Định dạng ▸ chữ thường, CHỮ HOA, Viết Hoa Mỗi Từ, Cắt khoảng trắng, Làm sạch | `.format(.lowercase / .uppercase / .capitalizeEachWord / .trim / .clean, columns: selectedColumns)` | ≥ 1 cột kiểu `string` |
| Chuyển đổi | Tách cột theo dấu phân cách | `.splitByDelimiter(column: c, delimiter: d, into: ["c.1", …, "c.n"])` | đúng 1 cột `string`; hộp nhập "Dấu phân cách" và "Số cột" (n ≥ 2); tên cột mới `"{tên cột}.{i}"` |
| Chuyển đổi | Nhóm theo (đếm dòng) | `.groupByCount(keys: selectedColumns, newColumn: "Count")` | **`isAvailable = false`** (lead cài hàm M ở T068) |
| Chuyển đổi | Bỏ xoay các cột khác | `.unpivotOtherColumns(keep: selectedColumns)` | **`isAvailable = false`** |
| Chuyển đổi | Xoay cột | `.pivot(attributeColumn: c, valueColumn: v)` | **`isAvailable = false`** |
| Thêm cột | Cột chỉ mục ▸ Từ 0 / Từ 1 | `.addIndexColumn(start: 0 hoặc 1, step: 1)` | — |
| Thêm cột | Cột tuỳ chỉnh | `.addCustomColumn(name: tên, formula: công thức)` | hộp: tên (mặc định "Custom"), công thức M (ví dụ `[Qty] * 2`), cả hai không rỗng (cắt khoảng trắng) |

Tab **Xem**: các ô tích hiện/ẩn (thanh công thức, khung Queries, Query Settings, chất lượng cột, phân bố cột, hồ sơ cột), nút "Trình soạn thảo nâng cao". Tab **Trang chủ** thêm nhóm "Đóng": "Đóng và áp dụng" (▸ menu: "Đóng và áp dụng", "Áp dụng", "Đóng"; "Áp dụng" gọi `onApply` mà không đóng; "Đóng" như nút dưới). Biểu tượng dùng SF Symbols; **không** vẽ nút của Power BI mà BI Pro không có (Python script, Statistics, Scientific, Parse, Merge/Append, Run R, "Query Dependencies", "Schema View", "Top 1000 rows/Profile entire dataset"): thiết kế có nhưng không làm. Nhóm lệnh chỉ có lệnh trong bảng trên và các nút ở đoạn này.

**Hộp nhập tham số** (`QueryCommandPopovers`): popover nhỏ cho lệnh cần tham số (số dòng, tìm/thay, dấu phân cách và số cột, tên và công thức cột, danh sách giá trị lọc): nút "OK" tắt khi `stepCommand` trả `nil`; Enter = OK; Esc = đóng.

**Quy tắc chung**: không giữ trạng thái nghiệp vụ trong view; mọi thứ lấy từ `state` hoặc `@State` giao diện thuần (tab đang chọn, cột đang chọn, hộp đang mở, văn bản đang gõ, bật/tắt khung). Không gọi `DispatchQueue`/`Task` để tính dữ liệu; chỉ gọi hàm đồng bộ của `state`. Không dùng `NSViewRepresentable` trong lưới và các khung cần xuất ảnh.

## Làm theo thứ tự này (từng lát: viết test đỏ trước nếu có logic thuần, rồi cài đặt cho xanh)

1. `QueryEditorFormat` và `QueryRibbonCommand` (logic thuần, test với giá trị viết tay).
2. `PreviewGridView`, `ColumnProfileView` + ảnh `qe-main.png`.
3. `AppliedStepsView`, `QueryListView`, `FormulaBarView`, `QueryRibbonView`, `QueryCommandPopovers`.
4. `AdvancedEditorSheet`, hộp "Chèn bước", hộp "Thay đổi chưa áp dụng".
5. `QueryEditorWindow` ghép tất cả + các ảnh còn lại.

## Test và ảnh

Test logic dùng giá trị viết tay độc lập (không tính lại bằng chính công thức của mã): ví dụ `percent(93, of: 100) == "93%"`, `percent(1, of: 3) == "33%"`, `percent(0, of: 0) == "0%"`, `statusSummary(columns: 9, rows: 500) == "9 cột · 500 dòng"`, `statusSummary(columns: 9, rows: 1000) == "9 cột · 999+ dòng"`, `typeBadge(.integer) == "123"`, và với `QueryRibbonCommand`: chưa chọn cột thì `removeColumns` không có lệnh (nil) và mờ; chọn `["Region", "Qty"]` thì `removeColumns` trả `.removeColumns(["Region", "Qty"])`; `sort` tăng hai cột trả hai `SortKey` theo thứ tự; `changeType` số nguyên trả `.changeType([ColumnTypeChange(column: "Qty", type: .wholeNumber)])`; `splitByDelimiter` với `" "` và 2 cột trên cột "Vung" trả `into: ["Vung.1", "Vung.2"]`, nhưng trên cột `integer` trả nil; `groupByCount`, `unpivotOtherColumns`, `pivot` có `isAvailable == false`; `addCustomColumn` với tên rỗng trả nil. Test mọi lệnh trong bảng ánh xạ ít nhất một ca đúng và một ca thiếu đầu vào.

`QueryEditorImageTests.swift` xuất PNG (luôn truyền `scrollable: false`, tạo thư mục `build/f-out/ui/`) bằng một `QueryEditorState` dựng tay (không cần file ngoài): bảng 12 dòng với cột `OrderID` (integer), `OrderDate` (dateTime), `Region` (string, một ô trống), `Qty` (integer), `Amount` (double, một ô lỗi qua `errorMask`), thêm truy vấn bằng `state.addQuery(from: LoadedTable(name: "Sales", data: bảng, origin: LoadedOrigin(kind: .csv, location: "/tmp/sales.csv", itemName: "Sales", itemKind: .file)))`, rồi `await state.refresh()` trước khi xuất, và các bước thêm bằng `state.perform(...)`:
- `qe-main.png` (1280 × 800): tab Trang chủ, bước cuối (`Changed Type`) đang chọn, cột `Region` đang chọn, column profile mở.
- `qe-transform.png` (1280 × 800): tab Chuyển đổi, đã `perform(.filterEquals(...))` và `perform(.sortRows(...))`, bước cuối đang chọn.
- `qe-error.png` (1280 × 800): bước người dùng có biểu thức lỗi (`state.setExpression(at:…)` trỏ cột không có) đang chọn: khung báo lỗi và dấu cảnh báo ở Applied Steps.
- `qe-advanced.png` (760 × 520): `AdvancedEditorSheet` với `advancedSource` của truy vấn.

**Tự xem từng ảnh (đọc ảnh bằng công cụ của bạn)**: không trống, không có biểu tượng "cấm" (vàng/đỏ), khớp bố cục thiết kế trong 6 pt, chữ tiếng Việt đủ dấu; ghi vào báo cáo từng ảnh khớp hay lệch ở đâu. **`ImageRenderer` vẽ trống nội dung `ScrollView` và `LazyVStack`, và vẽ `NSViewRepresentable` thành biểu tượng cấm**: mọi view có vùng cuộn (`PreviewGridView`, `AppliedStepsView`, `QueryListView`, `ColumnProfileView`, `AdvancedEditorSheet`, `QueryEditorWindow`) nhận tham số `scrollable: Bool = true`; khi `false` vẽ nội dung bằng `VStack`/`HStack` thường (cắt vừa khung). Mẫu cách làm: `NavigatorPreviewGrid.swift`. Sheet và popover không xuất ảnh được qua `ImageRenderer`: vẽ nội dung của chúng thành view riêng (ví dụ `AdvancedEditorContent`) để xuất ảnh.

## Lệnh được phép (chạy từng lệnh riêng, không dùng `&&`, `;`, `|`, `cd`, `rm`, `cp`, `mkdir`, `python`)

`swift build`, `swift test`, `swift test --filter <tên>`, `git status`, `git diff`, `git diff --stat`, `git grep <mẫu>`, `git log --oneline`, `ls <thư mục>`, `cmp <a> <b>`. Dùng công cụ đọc/ghi file và đọc ảnh của bạn để tạo, sửa file và xem ảnh. Lần chạy `swift build`/`swift test` đầu tiên biên dịch lại cả repo, mất vài phút.

## Tiêu chí xong việc (tất cả phải đúng, kiểm từng mục)

1. `swift build` không lỗi, không cảnh báo mới từ file của bạn.
2. `swift test` **toàn bộ** qua (test cần file Nhom6 của người dùng tự bỏ qua; bình thường). Chép dòng kết quả cuối (`Test run with N tests passed`) vào báo cáo.
3. Mỗi lệnh trong bảng ánh xạ và mỗi hàm `QueryEditorFormat` có test với giá trị viết tay; không sửa hay tắt test có sẵn; không hard-code kết quả.
4. Bốn ảnh PNG đã xuất, tự xem, không trống, khớp thiết kế trong 6 pt; báo cáo ghi đường dẫn và nhận xét từng ảnh. Grep tất cả chuỗi hiển thị để chắc không có chữ của thiết kế mà BI Pro không có (Python, Statistics, Scientific, Parse, Merge, Append, Dependencies, "Profile entire dataset"…), không nút tắt vẫn trông như bật, không nút giả (nút nào không có lệnh thì mờ kèm tooltip "Sắp có", hoặc không vẽ).
5. Mọi nút của ribbon gọi đúng `state.perform` (hoặc hàm của state tương ứng); không có logic truy vấn trong view; `git grep` không thấy `MQuery`/`MEvaluator` trong `Sources/BIPro/Query/Editor/` ngoài `StepCommand` và các kiểu tham số của nó.
6. `git status` chỉ liệt kê file trong danh sách được sửa; bạn không commit, không push.
7. Báo cáo ngắn `docs/tasks/f-ui-query-editor-report.md`: file đã tạo, tóm tắt, dòng kết quả `swift test`, đường dẫn bốn ảnh kèm nhận xét, mọi quyết định bạn chọn khác gợi ý (và vì sao), mục "Đề xuất cho lead", việc còn tồn đọng. Không bàn giao như đã xong khi còn mục nào chưa đạt: ghi rõ mục nào và lý do.
