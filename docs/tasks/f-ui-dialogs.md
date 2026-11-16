Bạn làm việc trong repo Swift "BI Pro" (ứng dụng macOS giống Power BI Desktop, SwiftUI, macOS 15), trong một git worktree riêng tách từ `main`. Phase F đang làm Power Query. Gói của bạn, **F-UI vòng 2 (hộp thoại nâng cao)**: vẽ các hộp thoại **Merge Queries (Gộp truy vấn)**, **Append Queries (Nối truy vấn)**, **Group By (Nhóm theo, cơ bản và nâng cao)**, **Custom Column (Cột tuỳ chỉnh)**, nút **mở rộng cột bảng lồng** sau Merge, và cửa sổ **Query Dependencies (Phụ thuộc truy vấn)**, rồi nối chúng vào ribbon của Query Editor đã có. **Chỉ vẽ và nối lệnh vào `QueryEditorState`; không viết logic truy vấn M.** Chỉ dùng framework hệ thống và thư viện của repo; không thêm package, không tải gì từ mạng. Giao diện **tiếng Việt**.

## Đọc trước (đã có, không sửa trừ danh sách bên dưới)

- `Sources/BIPro/Query/QueryEditorState.swift` và **`Sources/BIPro/Query/QueryEditorState+Advanced.swift`**: toàn bộ API bạn dùng (`@MainActor`, `@Observable`). Phần dành riêng cho gói này, trong `+Advanced`:
  - `mergeCandidates: [QueryModel]`: truy vấn khác mà Merge/Append dùng được (đã loại truy vấn gây vòng tham chiếu). Dùng nó làm danh sách chọn bảng thứ hai.
  - `resultColumns(ofQuery: UUID) async -> [QueryColumnInfo]?` (`name`, `type: DAXType`) và `resultPreview(ofQuery: UUID, limit: Int = 20) async -> TableData?`: cột và vài dòng đầu của truy vấn khác (bất đồng bộ; gọi trong `.task` của view, hiện "Đang tải…" khi chưa có, thông báo lỗi nhỏ khi `nil`).
  - `preview: TableData?` (bước đang chọn, tối đa 1000 dòng) và `profiles`: bảng bên trái của Merge là `preview` của bước đang chọn (3 dòng đầu); `selectedQuery?.name` là tên truy vấn.
  - `nestedColumnNames: [String]` (cột đang chứa bảng lồng trong `preview`, tức kết quả Merge chưa mở) và `nestedColumns(of: String) -> [QueryColumnInfo]?` (cột có thể mở).
  - `formulaError(_ formula: String) -> String?`: kiểm cú pháp công thức Custom Column; `nil` là hợp lệ, còn lại là lý do tiếng Việt kèm dòng, cột.
  - `dependencyGraph: DependencyGraphModel` (`nodes: [DependencyNode]` gồm `id`, `title`, `kind: .source/.query`, `enableLoad`; `edges: [DependencyEdge]` gồm `from` (nút bị dùng) và `to` (truy vấn dùng nó); `cycle: [String]?`).
  - Lệnh: `perform(_ command: StepCommand, confirmInsert: Bool = false) -> StepCommandOutcome` (`.applied`, `.needsInsertConfirmation`, `.rejected(lýDo)`), như ribbon hiện tại.
- `Sources/MEngine/StepFactory.swift`: các ca `StepCommand` bạn dựng: `.merge(otherQuery:leftKeys:rightKeys:kind:newColumn:)`, `.expandColumn(column:names:prefixed:)`, `.append(queries:)`, `.groupBy(keys:aggregates:)`, `.addCustomColumn(name:formula:)`; kiểu `JoinChoice` (`.leftOuter .rightOuter .fullOuter .inner .leftAnti .rightAnti`), `GroupAggregate(name:operation:column:)`, `GroupOperation` (`.sum .average .median .min .max .countRows .countDistinctRows`). Bạn chỉ **dựng giá trị `StepCommand`** từ thao tác của người dùng.
- Mẫu cửa sổ và ribbon đã làm: `Sources/BIPro/Query/Editor/QueryEditorWindow.swift` (cách hiện sheet con, cờ `scrollable`, `FixedImageFrame`), `QueryRibbonView.swift`, `QueryRibbonCommand.swift`, `QueryCommandPopovers.swift`, `PreviewGridView.swift`, `AdvancedEditorSheet.swift`, `NavigatorFormat.swift`, `Sources/BIPro/DesignSystem/Tokens.swift`, `Components.swift` (dùng lại, không đặt màu hay cỡ chữ tự do).
- Thiết kế (mở ảnh trước khi vẽ; **ảnh ở tỉ lệ 1,25×**, chia toạ độ cho 1,25): `UIdesign/lumen_analytics_query_editor_merge_dialog_1/screen.png` và `_2`, `UIdesign/lumen_analytics_query_editor_custom_column_dialog_26_rows/screen.png`, `UIdesign/lumen_analytics_query_dependencies_exact_graph_coordinates/screen.png`, kèm `code.html` và `UIdesign/lumen_analytics_design_system/DESIGN.md`. Không có thiết kế cho Append và Group By: dựng theo cùng ngôn ngữ của hộp Merge.
- Mẫu xuất ảnh PNG: `Tests/BIProTests/Query/Editor/QueryEditorImageTests.swift` (hàm `png(_:size:)` dùng `ImageRenderer`).

## File được sửa hoặc tạo (không sửa gì ngoài danh sách)

Tạo mới trong `Sources/BIPro/Query/Editor/Dialogs/`:
- `MergeDialogModel.swift` + `MergeDialog.swift`, `AppendDialogModel.swift` + `AppendDialog.swift`, `GroupByDialogModel.swift` + `GroupByDialog.swift`, `CustomColumnDialog.swift`, `ExpandColumnModel.swift` + `ExpandColumnPopover.swift`, `DependencyLayout.swift` + `QueryDependenciesView.swift`. Các file `*Model.swift`/`DependencyLayout.swift` là **logic thuần** (struct, không SwiftUI, có test); phần vẽ ở file còn lại.

Sửa file có sẵn (chỉ phần cần để nối):
- `QueryRibbonCommand.swift`: `groupByCount`, `unpivotOtherColumns`, `pivot` thành `isAvailable == true` (engine đã cài; lead đã chạy thử qua `perform`); `groupByCount` mở hộp Group By thay vì tự chạy với tên "Count" (`needsParameters == true`); `addCustomColumn` mở hộp Cột tuỳ chỉnh thay cho popover cũ.
- `QueryRibbonView.swift`, `QueryEditorWindow.swift`, `PreviewGridView.swift` (nút mở rộng ở tiêu đề cột bảng lồng), `QueryCommandPopovers.swift` (bỏ phần popover Custom Column đã thay bằng hộp mới; giữ phần còn lại).
- `Tests/BIProTests/Query/Editor/QueryRibbonCommandTests.swift`: **chỉ** đổi kỳ vọng `isAvailable` của ba lệnh nói trên từ `false` thành `true` (và các ca liên quan tới popover Custom Column nếu bạn đổi API); không sửa hay tắt test nào khác.

Tạo mới trong `Tests/BIProTests/Query/Editor/`: `DialogModelsTests.swift`, `DependencyLayoutTests.swift`, `DialogsImageTests.swift`. Tạo mới: `docs/tasks/f-ui-dialogs-report.md` (báo cáo cuối).

Mọi file khác giữ nguyên, gồm `Package.swift`, **`QueryEditorState.swift`**, **`QueryEditorState+Advanced.swift`**, `SourceQuery.swift`, `Sources/MEngine/**`, `Sources/ColumnStore/**`, `Model/Edit/**`, `Shell/**`, `Workspace.swift`, `DocumentState*.swift`, `DesignSystem/**`, các file Navigator, và mọi test có sẵn trừ chỗ đã nêu. Nếu thấy `QueryEditorState` thiếu thứ bạn cần, ghi vào báo cáo mục "Đề xuất cho lead" và làm tiếp phần còn lại.

## Hành vi cần cài

Mọi hộp thoại là **sheet con** của `QueryEditorWindow` (như `AdvancedEditorSheet`), nền sáng, chữ tiếng Việt, **Esc = Huỷ, Enter = OK** khi OK đang bật. Mỗi hộp có nút "Huỷ" (`SecondaryButtonStyle`) và "OK" (`PrimaryButtonStyle`, mờ khi chưa hợp lệ). Khi bấm OK: gọi `state.perform(command)`; `.applied` thì đóng hộp; `.needsInsertConfirmation` thì dùng **đúng hộp "Chèn bước" đã có** trong `QueryEditorWindow` (cùng đường với lệnh ribbon khác; "Chèn" gọi lại `perform(command, confirmInsert: true)`); `.rejected(lý do)` thì hiện lý do (danger) trong hộp và **không đóng**. Mọi hộp tách nội dung thành view riêng không phụ thuộc sheet (ví dụ `MergeDialogContent`) nhận `scrollable: Bool = true` để xuất ảnh (xem "Test và ảnh").

### Merge Queries ("Gộp truy vấn")

Mở từ nút **"Gộp truy vấn"** ở tab Trang chủ (mờ kèm tooltip khi `state.mergeCandidates` rỗng: "Cần có truy vấn khác để gộp"). Bố cục theo `merge_dialog_1/screen.png`:
- Tiêu đề "Gộp truy vấn", phụ đề "Chọn bảng và các cột khớp nhau để ghép dữ liệu.".
- **"NGUỒN CHÍNH"**: viên tên truy vấn đang chọn; lưới 3 dòng đầu của `state.preview` (cột rộng 140 pt, `NavigatorFormat.cell`). Bấm tiêu đề cột = chọn/bỏ chọn cột khoá; thứ tự chọn là thứ tự khoá; tiêu đề cột khoá tô nền nhạt và hiện huy hiệu "KHOÁ 1", "KHOÁ 2"… ; góc phải "N cột đã chọn".
- **"BẢNG THỨ HAI"**: menu chọn một truy vấn trong `state.mergeCandidates` (mặc định không chọn gì; chọn rồi mới hiện lưới); lưới 3 dòng đầu từ `resultPreview(ofQuery:limit: 3)` (hiện "Đang tải…" trong lúc chờ; lỗi thì thông báo nhỏ); chọn cột khoá giống trên.
- **"KIỂU JOIN"**: menu 6 mục, mặc định "Ngoài trái": Ngoài trái (tất cả từ bảng đầu, khớp từ bảng thứ hai) = `.leftOuter`; Ngoài phải (tất cả từ bảng thứ hai, khớp từ bảng đầu) = `.rightOuter`; Ngoài đầy đủ (tất cả hàng của cả hai) = `.fullOuter`; Trong (chỉ hàng khớp) = `.inner`; Chống trái (chỉ hàng của bảng đầu không khớp) = `.leftAnti`; Chống phải (chỉ hàng của bảng thứ hai không khớp) = `.rightAnti`.
- Chân hộp: dải trạng thái. Chưa chọn bảng thứ hai hoặc khoá: "Chọn bảng thứ hai và cột khớp ở cả hai bảng." Số khoá hai bên khác nhau: "Số cột khoá hai bên phải bằng nhau (trái N, phải M)." Có cặp khoá khác kiểu (so `DAXType`; số nguyên và số thực coi cùng kiểu): "Cột khoá \"X\" (văn bản) và \"Y\" (số) khác kiểu nên sẽ không khớp dòng nào." (cảnh báo vàng, **không chặn** OK). Hợp lệ: "Đã chọn N cặp cột khoá." (xanh). OK bật khi có bảng thứ hai và số khoá hai bên bằng nhau, ≥ 1.
- OK dựng `.merge(otherQuery: tênBảngThứHai, leftKeys: [...], rightKeys: [...], kind: kiểu, newColumn: tênBảngThứHai)`.
- **Không vẽ**: "Card Match Density", "Use fuzzy matching", dòng "The selection matches N of M rows", nút ?, các mục thiết kế mà BI Pro không có.

Logic thuần `MergeDialogModel` (struct, có test): cột trái/phải, `leftKeys`/`rightKeys` có thứ tự, `toggleLeft(_:)`, `toggleRight(_:)`, `kind`, `secondQuery`, `statusMessage`/mức độ (`.info/.warning/.ok`), `isValid`, `command() -> StepCommand?`.

### Mở rộng cột bảng lồng

Sau Merge, cột bảng lồng (`state.nestedColumnNames`) hiện trong lưới: ô là chữ "Bảng" (nghiêng, màu nhấn) và **tiêu đề cột có nút mở rộng** (biểu tượng `arrow.left.and.right.square`). Bấm nút mở popover `ExpandColumnPopover`: ô "Chọn tất cả cột", danh sách cột từ `state.nestedColumns(of:)` (mỗi cột một ô tích, mặc định chọn hết), ô tích "Dùng tên cột gốc làm tiền tố" (mặc định bật), nút OK/Huỷ. OK dựng `.expandColumn(column:names:prefixed:)` (chỉ những cột đã tích theo thứ tự gốc, ≥ 1). Logic thuần `ExpandColumnModel` có test (chọn tất cả/bỏ tất cả, thứ tự, `isValid`, `command()`).

### Append Queries ("Nối truy vấn")

Nút **"Nối truy vấn"** ở tab Trang chủ (mờ khi `mergeCandidates` rỗng). Hộp: hai chế độ chuyển bằng nút chọn "Hai bảng" và "Từ ba bảng": "Hai bảng": bảng chính là truy vấn đang chọn (chỉ đọc), menu chọn **một** bảng thứ hai từ `mergeCandidates`. "Từ ba bảng": danh sách `mergeCandidates` mỗi dòng một ô tích; **thứ tự nối là thứ tự chọn** (hiện số thứ tự 1, 2, 3… cạnh ô đã tích); bên trên ghi "Bảng chính: {tên}". Hiện dưới hộp, cho từng bảng đã chọn, danh sách cột lấy từ `resultColumns` để người dùng thấy cột nào sẽ thành `null` (một dòng nhỏ: "{N} cột chung, {M} cột chỉ có ở bảng này"), tính từ tên cột; không chặn OK. OK bật khi chọn ≥ 1 bảng. OK dựng `.append(queries: [tênTheoThứTựChọn])`. Logic thuần `AppendDialogModel` có test (thứ tự chọn, bỏ chọn xoá số thứ tự và dồn lại, `isValid`, `command()`, chế độ "Hai bảng" chỉ giữ một).

### Group By ("Nhóm theo")

Nút **"Nhóm theo"** ở tab Chuyển đổi (đã có; nay mở hộp). Hộp có nút chọn "Cơ bản" / "Nâng cao":
- **Cơ bản**: menu "Nhóm theo" (một cột, mặc định cột đang chọn nếu có đúng một, không thì cột đầu), ô "Tên cột mới" (mặc định "Count"), menu "Phép tính" (Đếm số dòng = `.countRows`, Đếm số dòng khác nhau = `.countDistinctRows`, Tổng = `.sum`, Trung bình = `.average`, Trung vị = `.median`, Nhỏ nhất = `.min`, Lớn nhất = `.max`), menu "Cột" (chỉ khi phép tính cần cột; chỉ liệt kê cột số `integer/double/currency` cho Tổng/Trung bình/Trung vị, mọi cột cho Nhỏ nhất/Lớn nhất).
- **Nâng cao**: danh sách "Nhóm theo" nhiều dòng (mỗi dòng một menu cột + nút xoá; nút "+ Thêm nhóm"; ≥ 1 dòng; các cột không được lặp), danh sách "Phép tổng hợp" nhiều dòng (tên cột mới, phép tính, cột; nút xoá; nút "+ Thêm phép tổng hợp"; ≥ 1 dòng).
- Kiểm: tên cột mới không rỗng, không trùng nhau, không trùng cột nhóm; phép tính cần cột thì phải có cột đúng kiểu. Lỗi hiện đỏ dưới dòng liên quan và làm OK mờ.
- OK dựng `.groupBy(keys: [...], aggregates: [GroupAggregate(name:operation:column:)])` (cơ bản cũng qua `.groupBy`).
Logic thuần `GroupByDialogModel` có test (cơ bản và nâng cao chuyển qua lại giữ dữ liệu, cột hợp lệ theo phép tính, kiểm tên trùng, `command()`).

### Custom Column ("Cột tuỳ chỉnh")

Theo `custom_column_dialog_26_rows/screen.png`: ô "Tên cột mới" (mặc định "Custom"), vùng soạn công thức nhiều dòng đơn cách (`TextEditor`), bên phải danh sách "Cột có sẵn" (tên cột của `state.preview`; bấm đúp chèn `[tên]` tại cuối công thức, kèm nút "<< Chèn"), dải dưới: "Không phát hiện lỗi cú pháp" (xanh) khi `state.formulaError(công thức) == nil`, ngược lại hiện lý do (danger). Kiểm mỗi lần đổi văn bản (hàm đồng bộ, nhanh). OK bật khi tên không rỗng (sau cắt khoảng trắng) và công thức hợp lệ; dựng `.addCustomColumn(name:formula:)`. **Không** vẽ ví dụ công thức giả, "Learn about Power Query formulas" hay mục thiết kế không có thật.

### Query Dependencies ("Phụ thuộc truy vấn")

Nút ở tab **Xem**, mở sheet lớn (mặc định 1000 × 640 pt, co giãn) theo `query_dependencies_exact_graph_coordinates/screen.png`, **rút gọn**: tiêu đề "Phụ thuộc truy vấn", vùng đồ thị có chấm lưới nền, các **cột theo độ sâu** (cột 1 "NGUỒN DỮ LIỆU" gồm nút `.source`; các cột sau "TRUY VẤN" theo độ sâu phụ thuộc: truy vấn không dùng truy vấn nào ở cột đầu, truy vấn dùng chúng ở cột kế…), mỗi nút là thẻ (biểu tượng, tên, dòng phụ: nguồn = "Tệp", truy vấn = "Truy vấn" kèm "Không nạp" nghiêng mờ khi `!enableLoad`), **mũi tên cong** nối theo `edges`, thanh dưới có "Thu phóng − 100% +", "Vừa khung" và nút "Đóng". Bấm một thẻ = chọn: thẻ viền nhấn, các nút liên quan (gồm mọi nút thượng nguồn và hạ nguồn gián tiếp) giữ nguyên, nút khác mờ; khung nhỏ góc phải dưới "Đã chọn: {tên} · Thượng nguồn: N nút · Hạ nguồn: M nút" (có ✕ để bỏ chọn). Có `cycle` thì hiện dải đỏ "Vòng tham chiếu: A → B → A". **Không** vẽ: bộ lọc/thẻ/Tags, Export, Auto-arrange, "Stage Columns", "Model Inspector" bên trái, cột "SEMANTIC MODEL".
Logic thuần `DependencyLayout` (struct, có test): từ `DependencyGraphModel` ra `depth` của từng nút (nguồn = 0; truy vấn = 1 + độ sâu lớn nhất của nút nó dùng; **truy vấn nằm trong vòng thì gán độ sâu theo thứ tự duyệt và không treo**), vị trí `(cột, hàng)` ổn định theo thứ tự trong `nodes`, `upstream(of:)` và `downstream(of:)` (tập id, gián tiếp, không gồm chính nó, chịu được vòng).

### Ribbon

- Tab Trang chủ: thêm nhóm "Kết hợp": "Gộp truy vấn", "Nối truy vấn".
- Tab Chuyển đổi: "Nhóm theo" mở hộp (đã mô tả); "Bỏ xoay các cột khác" và "Xoay cột" nay bật (gọi `perform` với `stepCommand(context:)` như lệnh khác; tooltip "Xoay cột: chọn cột thuộc tính trước, cột giá trị sau").
- Tab Thêm cột: "Cột tuỳ chỉnh" mở hộp.
- Tab Xem: "Phụ thuộc truy vấn".
Biểu tượng SF Symbols. Mọi nút ribbon khác giữ nguyên.

## Quy tắc chung

Không giữ trạng thái nghiệp vụ trong view ngoài `@State` giao diện (đang gõ, mục đang chọn của hộp) và các struct logic thuần ở trên. Không dùng `NSViewRepresentable` trong nội dung cần xuất ảnh. Không đặt `MQuery`/`MEvaluator` trong `Sources/BIPro/Query/Editor/` (chỉ `import MEngine` cho `StepCommand`, `JoinChoice`, `GroupAggregate`, `GroupOperation`). Bất đồng bộ chỉ ở chỗ gọi `resultColumns`/`resultPreview` trong `.task`.

## Làm theo thứ tự này (từng lát: test đỏ trước cho logic thuần, rồi cài đặt cho xanh)

1. Các `*Model` và `DependencyLayout` (logic thuần) kèm test.
2. `GroupByDialog`, `CustomColumnDialog`, nối ribbon (kèm bật ba lệnh).
3. `MergeDialog`, `ExpandColumnPopover` (và nút ở `PreviewGridView`), `AppendDialog`.
4. `QueryDependenciesView`.
5. Ảnh PNG và báo cáo.

## Test và ảnh

Test logic dùng giá trị viết tay độc lập (không tính lại bằng công thức của mã): ví dụ Merge: chọn cột trái `["ID"]` và phải `["Cust"]`, kiểu `.inner` → `.merge(otherQuery: "Orders", leftKeys: ["ID"], rightKeys: ["Cust"], kind: .inner, newColumn: "Orders")`; hai khoá trái một khoá phải → `isValid == false` và thông báo "Số cột khoá hai bên phải bằng nhau (trái 2, phải 1).", bấm lại cột khoá bỏ chọn và dồn thứ tự; khoá khác kiểu → cảnh báo vàng nhưng `isValid == true`; Append: chọn `["B", "C"]` rồi bỏ `"B"` → `.append(queries: ["C"])`; Group By: cơ bản `Region` + `.sum` trên `Amt` đặt tên "Total" → `.groupBy(keys: ["Region"], aggregates: [GroupAggregate(name: "Total", operation: .sum, column: "Amt")])`, `.sum` trên cột văn bản không hợp lệ, hai phép tổng hợp cùng tên → không hợp lệ; Expand: bỏ tích "Amt" trong `["Cust","Amt","Region"]` → `names == ["Cust","Region"]`; `DependencyLayout` trên đồ thị `Raw` (nguồn `a.xlsx`) → `Clean` → `Final`: độ sâu 0, 1, 2, 3; `downstream(of: "query:Raw") == ["query:Clean", "query:Final"]`; vòng `A ↔ B` không treo. Mỗi struct logic có ít nhất một ca đúng và một ca thiếu đầu vào.

`DialogsImageTests.swift` xuất PNG (luôn `scrollable: false`, thư mục `build/f-out/ui/`) bằng `QueryEditorState` dựng tay (không cần file ngoài; mẫu: `QueryEditorImageTests.swift`, hoặc truy vấn `QueryModel(name:steps:[QueryStep(name: "Source", expression: "#table(...)", kind: StepKind.custom)])` thêm bằng `state.addQuery(_, base: nil)`; ví dụ "Customers" (`ID`, `Name`) và "Orders" (`Cust`, `Amt`, `Region`) như `Tests/BIProTests/Query/AdvancedQueryTests.swift`, **đọc file này làm mẫu**), gọi `await state.refresh()` trước khi xuất:
- `qe2-merge.png` (1000 × 760): hộp Merge đã chọn khoá hai bên, kiểu Trong.
- `qe2-merge-expand.png` (640 × 480): popover mở rộng cột của kết quả Merge (cột "Orders").
- `qe2-append.png` (760 × 560): hộp Append chế độ "Từ ba bảng" đã chọn hai bảng.
- `qe2-groupby.png` (760 × 560): Group By nâng cao, hai nhóm và hai phép tổng hợp.
- `qe2-custom.png` (900 × 560): hộp Cột tuỳ chỉnh có công thức hợp lệ, và một ca lỗi cú pháp nếu muốn (`qe2-custom-error.png`).
- `qe2-dependencies.png` (1000 × 640): đồ thị 4–5 nút (một nguồn tệp, hai truy vấn nối tiếp, một truy vấn Merge dùng hai truy vấn, một truy vấn tắt Enable load), một nút đang chọn.
**Tự xem từng ảnh (đọc ảnh bằng công cụ của bạn)**: không trống, không có biểu tượng "cấm" (vàng/đỏ), chữ tiếng Việt đủ dấu, khớp bố cục thiết kế trong 6 pt (Merge, Custom Column, Dependencies); ghi vào báo cáo từng ảnh khớp hay lệch ở đâu. `ImageRenderer` vẽ trống nội dung `ScrollView`/`LazyVStack`/`TextEditor` có thể thành khối trống: dùng tham số `scrollable: Bool` (khi `false` dùng `VStack`/`HStack` thường, và `Text` thay `TextEditor`). Lưới 3 dòng của Merge/Append luôn dùng `VStack` (ít dòng, không cần cuộn). Grep tất cả chuỗi hiển thị để chắc không có chữ của thiết kế mà BI Pro không có (fuzzy, Density, SQL Server, Tags, Export, Auto-arrange…), không nút giả (nút không có lệnh thì mờ kèm tooltip "Sắp có" hoặc không vẽ).

## Lệnh được phép (chạy từng lệnh riêng, không dùng `&&`, `;`, `|`, `cd`, `rm`, `cp`, `mkdir`, `python`)

`swift build`, `swift test`, `swift test --filter <tên>`, `git status`, `git diff`, `git diff --stat`, `git grep <mẫu>`, `git log --oneline`, `ls <thư mục>`, `cmp <a> <b>`. Dùng công cụ đọc/ghi file và đọc ảnh của bạn để tạo, sửa file và xem ảnh. Lần chạy `swift build`/`swift test` đầu tiên biên dịch lại cả repo, mất vài phút.

## Tiêu chí xong việc (tất cả phải đúng, kiểm từng mục)

1. `swift build` không lỗi, không cảnh báo mới từ file của bạn.
2. `swift test` **toàn bộ** qua (test cần file Nhom6 của người dùng tự bỏ qua; bình thường). Chép dòng kết quả cuối (`Test run with N tests passed`) vào báo cáo.
3. Mỗi struct logic (`MergeDialogModel`, `ExpandColumnModel`, `AppendDialogModel`, `GroupByDialogModel`, `DependencyLayout`) có test giá trị viết tay; không sửa hay tắt test có sẵn (ngoài ba kỳ vọng `isAvailable` nêu trên); không hard-code kết quả.
4. Các ảnh PNG đã xuất, tự xem, không trống, báo cáo ghi đường dẫn và nhận xét từng ảnh. Grep chuỗi thừa (mục trên).
5. Mỗi hộp OK gọi đúng `state.perform` với `StepCommand` đúng; `.needsInsertConfirmation` đi qua hộp "Chèn bước" có sẵn; `.rejected` hiện lý do và không đóng hộp. `git grep MQuery Sources/BIPro/Query/Editor` và `git grep MEvaluator Sources/BIPro/Query/Editor` không có kết quả.
6. `git status` chỉ liệt kê file trong danh sách được sửa; bạn không commit, không push.
7. Báo cáo ngắn `docs/tasks/f-ui-dialogs-report.md`: file đã tạo/sửa, tóm tắt, dòng kết quả `swift test`, đường dẫn các ảnh kèm nhận xét, mọi quyết định khác gợi ý (và vì sao), mục "Đề xuất cho lead", việc còn tồn đọng. Không bàn giao như đã xong khi còn mục nào chưa đạt: ghi rõ mục nào và lý do.
