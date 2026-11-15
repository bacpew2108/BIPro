Bạn làm việc trong repo Swift "BI Pro" (ứng dụng macOS giống Power BI Desktop, SwiftUI, macOS 15), trong một git worktree riêng tách từ `main`. Phase F đang làm phần Get Data. Gói của bạn, **F-UI (Get Data + Navigator)**: vẽ hai màn hình SwiftUI **hộp thoại Get Data** (chọn nguồn) và **Navigator** (chọn mục, xem trước, Tải), từ trạng thái `NavigatorState` đã có. Chỉ dùng SwiftUI/AppKit hệ thống và thành phần của repo; không thêm package, không tải gì từ mạng. Mọi chữ hiển thị bằng tiếng Việt.

## Đọc trước (đã có, giữ nguyên, không sửa)

- `Sources/BIPro/Query/NavigatorState.swift`: trạng thái bạn vẽ từ đó. Dùng: `phase` (`choosingSource`, `listingItems`, `ready`, `loading`, `failed(String)`), `sourceKind`, `location`, `items: [NavigatorItem]` (`id`, `name`, `kind: SourceItemKind`, `rowCountHint`), `checkedItemIDs`, `toggle(_:)`, `previewItemID`, `preview: TableData?`, `previewError: String?`, `progress` (0…1), `canLoad`, và ba hàm `async`: `openSource(kind:location:)`, `showPreview(_ id:)`, `load(existingNames:) -> [LoadedTable]?`, cùng `cancelLoad()`. Quay về bước chọn nguồn: gán `state.phase = .choosingSource`.
- `Sources/BIPro/Model/Edit/TableLoader.swift`: `LoadedTable` (kết quả của `load`).
- `Sources/ColumnStore/TableData.swift` và `Contracts.swift` (`StoredValue`, `DAXType`): `TableData.columns[i].name`, `.data.type`, `rowCount`, `value(row:column:)`, `errorMask[cột][dòng]`.
- `Sources/BIPro/DesignSystem/Tokens.swift` (`DS.Palette`, `DS.Typeface`, `DS.Radius`, `DS.Space`; màu nhấn hệ thống `#0A84FF`) và `Components.swift` (`PrimaryButtonStyle`, `SecondaryButtonStyle`, `SearchField`, `CheckboxMark`, `Badge`, `SectionLabel`, `TileBackground`): **dùng lại**, không đặt màu hay cỡ chữ riêng.
- Thiết kế để đặt cạnh: `UIdesign/lumen_analytics_get_data_dialog/screen.png` (+ `code.html`) và `UIdesign/lumen_analytics_navigator_dialog_fixed/screen.png` (+ `code.html`), và `UIdesign/lumen_analytics_design_system/DESIGN.md`. Mở hai ảnh trước khi vẽ. **Ảnh thiết kế ở tỉ lệ 1,25×**: chia toạ độ ảnh cho 1,25 ra điểm (pt). Kích thước theo `code.html`: hộp thoại Get Data **840 × 580 pt** (thanh tiêu đề 52, cột trái 200); Navigator **960 × 620 pt** (thanh tiêu đề 46, cột trái 285).
- Mẫu xuất ảnh PNG: `Tests/BIProTests/Charts/NewChartsImageTests.swift` (hàm `png(_:size:)` dùng `ImageRenderer`, `scale = 2`). `FFixtures.sample("tên")` (`Tests/BIProTests/Model/FFixtures.swift`) trả đường dẫn file mẫu trong `build/f-out/samples/` (đã nối sẵn vào worktree của bạn; bạn không chạy script sinh mẫu): `sales_2026.xlsx` (trang tính `Sales` 500 dòng, `Customers` 50 dòng, `Notes` 3 dòng, bảng đặt tên `SalesTable` 500 dòng), `sales_2026.csv` (10 000 dòng, 8 cột `OrderID, OrderDate, Region, CustomerID, Product, Qty, Price, Amount`).

## File được sửa hoặc tạo (không sửa gì ngoài danh sách)

Tạo mới:
- `Sources/BIPro/Shell/GetDataDialog.swift`: `GetDataFlowView` (gốc) và `GetDataDialogView` (bước chọn nguồn).
- `Sources/BIPro/Query/Editor/NavigatorView.swift`, `NavigatorTreeView.swift`, `NavigatorPreviewGrid.swift`, `NavigatorFormat.swift`, `ConnectorCatalog.swift` (tách thêm file trong `Sources/BIPro/Query/Editor/` nếu cần).
- `Tests/BIProTests/Query/Editor/ConnectorCatalogTests.swift`, `NavigatorFormatTests.swift`, `GetDataImageTests.swift`.
- `docs/tasks/f-ui-navigator-report.md`: báo cáo cuối.

Mọi file khác giữ nguyên, gồm `Package.swift`, `NavigatorState.swift`, `TableLoader.swift`, `QueryEditorState.swift`, `Shell/ShellView.swift`, `Shell/Ribbon.swift`, `Workspace.swift`, `App.swift`, `DesignSystem/**`, mọi test có sẵn. Lead sẽ nối hộp thoại vào ruy-băng và cửa sổ; bạn **không** nối. Nếu cần đổi `NavigatorState` hay `TableLoader`, ghi đề xuất vào mục "Đề xuất cho lead" của báo cáo, đừng sửa. Target `BIPro` chạy chế độ Swift 5. Kiểu của bạn để mặc định `internal` (test dùng `@testable import BIPro`).

## API (giữ đúng tên; lead gọi từ Shell)

```swift
struct GetDataFlowView: View {
    init(state: NavigatorState,
         existingTableNames: Set<String>,                        // tên bảng đang có trong mô hình, để khử trùng khi Tải
         pickFile: @escaping (SourceKind) -> String? = GetDataFilePicker.pick,
         onLoad: @escaping ([LoadedTable]) -> Void,              // sau khi state.load thành công
         onTransform: @escaping ([LoadedTable]) -> Void,         // "Chuyển đổi dữ liệu": cũng gọi state.load trước (Query Editor cần dữ liệu)
         onClose: @escaping () -> Void)                          // Hủy khi không đang tải, hoặc đóng sau Tải
}
enum GetDataFilePicker { static func pick(_ kind: SourceKind) -> String? }   // NSOpenPanel, lọc đuôi theo nguồn; nil khi bấm Hủy

enum ConnectorCategory: CaseIterable { case all, file, database }
struct ConnectorEntry: Identifiable { let kind: SourceKind; let title: String; let detail: String; let category: ConnectorCategory; let isDefault: Bool; var isAvailable: Bool { ... } }
enum ConnectorCatalog {
    static let entries: [ConnectorEntry]
    static var availableKinds: Set<SourceKind>                   // hiện {.excel, .csv}; lead thêm .json/.sqlite ở T088/T093 (một chỗ duy nhất)
    static func visible(category: ConnectorCategory, query: String) -> [ConnectorEntry]
    static func count(for category: ConnectorCategory, query: String) -> Int
}
enum NavigatorFormat {
    static func rowCount(_ n: Int?) -> String                    // nil → ""; < 10 000 → "4,210" (nhóm nghìn bằng dấu phẩy); ≥ 10 000 → "18.4k"; ≥ 1 000 000 → "1.2M" (khớp ảnh thiết kế)
    static func cell(_ value: StoredValue) -> String             // xem bên dưới
    static func kindBadge(_ kind: SourceItemKind) -> String      // sheet "Trang tính", namedTable "Bảng đặt tên", table "Bảng", view "Khung nhìn", file "Tệp", record "Bản ghi"
    static func selectedSummary(checked: Int, total: Int) -> String   // "Đã chọn 2 / 4 mục"
    static func truncationNote(previewRows: Int, rowCountHint: Int?) -> String?   // nil trừ khi previewRows == 200 và (hint == nil hoặc hint > 200): "Xem trước bị cắt ở 200 dòng đầu."
}
```

## Hành vi cần cài

**Hộp thoại Get Data** (840 × 580 pt, bo góc `DS.Radius.large`, thanh tiêu đề: "Lấy dữ liệu" + chú thích "Chọn nguồn dữ liệu" + ô tìm "Tìm trình kết nối"):
- Cột trái: nhãn "DANH MỤC", ba dòng `Tất cả` / `Tệp` / `Cơ sở dữ liệu` kèm số lượng (theo ô tìm); dòng đang chọn tô màu nhấn, chữ trắng. Danh mục rỗng sau khi lọc vẫn hiện, số 0.
- Danh sách: sáu nguồn, mỗi nguồn một dòng (ô biểu tượng 36 pt, tên, mô tả một dòng): **Sổ làm việc Excel** (`.xlsx`, huy hiệu "Mặc định", danh mục Tệp), **Văn bản / CSV** (`.csv`, `.tsv`, `.txt`; Tệp), **Tệp JSON** (Tệp), **Apache Parquet** (Tệp), **Cơ sở dữ liệu SQLite** (Cơ sở dữ liệu), **Cơ sở dữ liệu PostgreSQL** (Cơ sở dữ liệu). Nguồn trong `availableKinds` chọn được; nguồn còn lại hiện mờ (opacity 0,5), huy hiệu "Sắp có", **không** chọn được. Dòng chọn có viền nhấn, nền `DS.Palette.selectionSoft`, dấu tích tròn bên phải. Mặc định chọn Excel. Ô tìm lọc theo tên, mô tả và đuôi file (không phân biệt hoa thường và dấu tiếng Việt).
- Chân: nút "Hủy" (`SecondaryButtonStyle`, phím Esc) và "Kết nối →" (`PrimaryButtonStyle`, phím Return); bấm đúp một dòng chọn được = "Kết nối". "Kết nối" gọi `pickFile`; `nil` (người dùng hủy) → ở yên bước chọn nguồn; có đường dẫn → `await state.openSource(kind:location:)` rồi chuyển sang Navigator (`phase` khác `choosingSource`).
- Danh mục thiết kế gồm cả nguồn không làm (SQL Server, Snowflake…): **không vẽ**, chỉ sáu nguồn trên.

**Navigator** (960 × 620 pt; thanh tiêu đề: "Trình điều hướng" · tên file (chữ đơn cách) · huy hiệu loại nguồn):
- Cột trái (285 pt): ô tìm "Tìm bảng và trang tính" (lọc tên không phân biệt hoa thường và dấu); gốc cây = tên file kèm số mục; mục = ô tích (`CheckboxMark`, gọi `state.toggle`), biểu tượng theo loại, tên, `NavigatorFormat.rowCount(rowCountHint)` căn phải chữ đơn cách. Hai nhóm: **[SUY ĐOÁN]** (theo thiết kế; chờ buổi VM-F2 xem Desktop) nhóm đầu gồm mục `file`, `sheet`, `table`, `record`; nhóm hai nhãn "BẢNG ĐẶT TÊN VÀ KHUNG NHÌN" gồm `namedTable`, `view`; nhóm trống thì ẩn cả nhãn. Bấm vào dòng (ngoài ô tích) = xem trước mục đó (`await state.showPreview(id)`), dòng đang xem nền `selectionSoft`. Chân cột: `selectedSummary`.
- Khi `phase` về `.ready` lần đầu mà `previewItemID == nil` và có mục: tự xem trước mục đầu; nếu chỉ có **một** mục (CSV, JSON) thì tự đánh dấu luôn mục đó.
- Cột phải: tiêu đề = biểu tượng, tên mục, huy hiệu `kindBadge`, rồi "Xem trước {preview.rowCount} dòng đầu" (thêm " · tổng {rowCountHint} dòng" khi có hint, số có dấu nhóm). Lưới xem trước **chỉ dùng SwiftUI** (`ScrollView([.horizontal, .vertical])` + `LazyVStack`/`Grid`, cột rộng 140 pt, cột `#` 40 pt; **không** dùng `NSViewRepresentable`/`NSTableView`, vì `ImageRenderer` vẽ chúng thành biểu tượng cấm). Tiêu đề cột: biểu tượng kiểu (số nguyên `#`, số thực `1.2`, ngày giờ lịch, chuỗi `ABC`, logic dấu tích, tiền tệ `$`) + tên. Số chạy đúng chữ số đơn cách và căn phải, chữ căn trái, dòng xen kẽ nền nhẹ.
- `NavigatorFormat.cell`: `blank` → `null` (nghiêng, `tertiaryLabel`); `integer` → số nguyên không nhóm nghìn; `double` → biểu diễn ngắn nhất không mất chữ số (`120`, `9.99`, không `120.0`); `currency(Int64)` → chia 10 000, hai chữ số thập phân; `string` nguyên văn (xuống dòng trong ô thay bằng `↵`); `boolean` → `TRUE`/`FALSE`; `dateTime(d)` = số ngày kể từ 1899-12-30: `yyyy-MM-dd`, thêm ` HH:mm:ss` khi phần lẻ khác 0. Ô có trong `errorMask` hiện `Error` màu `DS.Palette.danger`.
- Chân: bên trái, `truncationNote` (biểu tượng cảnh báo `DS.Palette.warning`), hoặc khi `phase == .loading` thanh tiến độ + "Đang tải… {n}%" (`state.progress`); bên phải "Hủy" (`.loading` → `state.cancelLoad()`, còn lại → `onClose`), "Chuyển đổi dữ liệu" (`Secondary`) và "Tải" (`Primary`); hai nút sau tắt khi `!state.canLoad`. "Tải": `if let tables = await state.load(existingNames:) { onLoad(tables); onClose() }`; "Chuyển đổi dữ liệu": như trên nhưng gọi `onTransform`. Khi `.failed(msg)` sau Tải thì hiện `msg` (màu danger) ở chân và giữ nguyên cây để thử lại sau khi sửa (không có nút thử lại: gán `state.phase = .ready` từ nút "Đóng thông báo").
- `phase == .listingItems`: giữa hộp thoại hiện vòng quay + "Đang đọc nguồn…".
- `phase == .failed(msg)` và `items.isEmpty` (mở nguồn lỗi): thay cả vùng nội dung bằng biểu tượng cảnh báo, `msg` nguyên văn, nút "Chọn nguồn khác" (gán `state.phase = .choosingSource`).
- `state.previewError != nil`: vùng lưới hiện thông báo đó (danger), không dựng lưới; mục vẫn tích được.
- Không giữ trạng thái nghiệp vụ trong view: mọi thứ lấy từ `state` hoặc `@State` giao diện thuần (ô tìm, danh mục đang chọn, nguồn đang chọn).

## Làm theo thứ tự này (từng lát: viết test đỏ trước nếu có logic thuần, rồi cài đặt cho xanh)

1. `NavigatorFormat` + `ConnectorCatalog` (logic thuần, có test).
2. `GetDataDialogView` + `GetDataFilePicker` + xuất ảnh `get-data.png`, so với thiết kế.
3. `NavigatorTreeView`, `NavigatorPreviewGrid`, `NavigatorView` + ảnh `navigator-excel.png`, `navigator-loading.png`, `navigator-error.png`.
4. `GetDataFlowView` nối hai màn hình theo `state.phase`.

## Test và ảnh

Test logic dùng giá trị viết tay độc lập (không tính lại bằng chính công thức của mã): ví dụ `rowCount(50) == "50"`, `rowCount(4210) == "4,210"`, `rowCount(18430) == "18.4k"`, `rowCount(1_200_000) == "1.2M"`; `cell(.double(120)) == "120"`, `cell(.double(9.99)) == "9.99"`, `cell(.dateTime(46083)) == "2026-03-02"`, `cell(.dateTime(46083.5)) == "2026-03-02 12:00:00"`; `cell(.string("a\nb")) == "a↵b"`; `ConnectorCatalog.count(for: .all, query: "")` bằng 6, `.file` bằng 4, `.database` bằng 2, `visible(category: .all, query: "sqlite")` đúng một nguồn, tìm `"excel"` và `".xlsx"` cùng ra Excel; `truncationNote(previewRows: 200, rowCountHint: 10_000) != nil`, `(5, 5) == nil`, `(200, 200) == nil`.

`GetDataImageTests.swift` xuất PNG vào `build/f-out/ui/` (tạo thư mục; xem mẫu `NewChartsImageTests`): `get-data.png` (840 × 580), `navigator-excel.png` (960 × 620; mở `sales_2026.xlsx` thật qua `NavigatorState.openSource`, tích `Sales` và `Customers`, `showPreview` mục `Sales`), `navigator-loading.png` (đặt `state.phase = .loading`, `state.progress = 0.4` trên trạng thái trên), `navigator-error.png` (`openSource` file không có: `/khong/co/file.xlsx`). Thiếu file mẫu thì bỏ qua ca đó (`guard let url = FFixtures.sample(...) else { return }`, như test Nhom6). Mỗi ảnh phải có kích thước đúng và **không trống**: giải mã bằng `NSBitmapImageRep` và khẳng định có ít nhất 20 màu khác nhau trong 2 000 điểm lấy mẫu đều. **Sau khi xuất, tự mở từng ảnh bằng công cụ đọc ảnh và so với thiết kế**: vị trí các khối chính (thanh tiêu đề, cột trái, danh sách/lưới, chân) lệch dưới 4 pt, nhãn và màu đúng (chữ tiếng Việt khác chữ thiết kế là đúng). Ảnh chỉ là để xem bằng mắt, không so điểm ảnh.

## Lệnh được phép (chạy từng lệnh riêng, không dùng `&&`, `;`, `|`, `cd`, `rm`, `cp`, `mkdir`, `python`)

`swift build`, `swift test`, `swift test --filter <tên>`, `git status`, `git diff`, `git diff --stat`, `git grep <mẫu>`, `git log --oneline`, `ls <thư mục>`. Dùng công cụ đọc/ghi file và đọc ảnh của bạn để tạo, sửa file và xem ảnh. Lần chạy `swift build`/`swift test` đầu tiên biên dịch lại cả repo, mất vài phút.

## Tiêu chí xong việc (tất cả phải đúng, kiểm từng mục)

1. `swift build` không lỗi, không cảnh báo mới từ file của bạn.
2. `swift test` **toàn bộ** qua (test cần file Nhom6 của người dùng tự bỏ qua; bình thường). Chép dòng kết quả cuối (`Test run with N tests passed`) vào báo cáo.
3. Mỗi hành vi ở mục "Hành vi cần cài" thuộc logic thuần (định dạng, danh mục, lọc, tóm tắt, ghi chú cắt) có test với giá trị viết tay; không sửa hay tắt test có sẵn.
4. Bốn ảnh PNG đã xuất, tự xem, không trống, khớp thiết kế trong 4 pt; ghi trong báo cáo từng ảnh khớp hay lệch ở đâu.
5. Nguồn không nằm trong `ConnectorCatalog.availableKinds` không chọn được, không gọi `pickFile`.
6. `git status` chỉ liệt kê file trong danh sách được sửa; bạn không commit, không push.
7. Báo cáo ngắn `docs/tasks/f-ui-navigator-report.md`: file đã tạo, tóm tắt, dòng kết quả `swift test`, đường dẫn bốn ảnh, mọi quyết định bạn chọn khác gợi ý (và vì sao), mục "Đề xuất cho lead", việc còn tồn đọng. Không bàn giao như đã xong khi còn mục nào chưa đạt: ghi rõ mục nào và lý do.
