# Kế hoạch kỹ thuật: Đợt 4 (v1.2) — Mở khoá toàn bộ Ribbon, RLS, Mark as Date Table, Quick Measures & Công cụ DAX/TMDL

**Thư mục spec:** `specs/015-v12-hoan-thien-chuyen-nghiep/`
**Ngày lập:** 2026-11-21
**Trạng thái:** Chờ duyệt (Cổng duyệt 2/3 — `plan.md` & `data-model.md`)
**Tham chiếu:** [spec.md](file:///Users/macprom114/Desktop/PowerBINative/specs/015-v12-hoan-thien-chuyen-nghiep/spec.md), [QUAN-SAT.md](file:///Users/macprom114/Desktop/PowerBINative/docs/phase-v12-evidence/vm-v12/QUAN-SAT.md)

---

## 1. Kiến trúc triển khai 3 nhánh (4A · 4B · 4C)

### Nhánh 4A — Bảng nhớ tạm, Sao định dạng & Tab Dữ liệu / Truy sâu
1. **Cut / Copy / Paste visual (kể cả sang trang khác):**
   - Bổ sung `VisualClipboardItem` và `visualClipboard: [VisualClipboardItem]` trong `LayoutEditor` (hoặc `DocumentState`).
   - `copyVisuals(_ ids:)` chụp `ReportVisual` + byte `visual.json` gốc của các visual đang chọn (bỏ qua nhóm khoá nếu cần, xử lý toạ độ tương đối giữa nhiều visual).
   - `cutVisuals(_ ids:)` gọi `copyVisuals` rồi `delete(ids)` (1 bước hoàn tác `⌘Z`).
   - `pasteVisuals(to pageID:)` sinh mã visual 20 hex mới (qua `PBIRLayoutPatch.rewritingVisualID`), đặt lệch `(+16, +16)` nếu dán cùng trang hoặc giữ nguyên vị trí nếu dán **sang trang khác**, cập nhật `edited[pageID].added` + `edited[pageID].visuals` trong 1 bước `⌘Z`.
   - Nối 3 nút *Cắt / Sao chép / Dán* trên `ReportHomeCommands` (`Ribbon.swift`) và phím tắt `⌘X`/`⌘C`/`⌘V` trong `EditCommands.swift` (chỉ chặn khi `NSApp.keyWindow?.firstResponder is NSText` để không đè soạn văn bản).
2. **Format Painter (Sao định dạng):**
   - Thêm `formatPainterSource: (visualID: String, objects: [String: Any], containerObjects: [String: Any])?` vào `LayoutEditor`.
   - Bấm *Sao định dạng* khi chọn đúng 1 visual → trích toàn bộ `visualContainerObjects` và tập khoá định dạng tương thích (`dataPoint`, `labels`, `legend`, `categoryAxis`, `valueAxis`, `general`, `values`, `columnHeaders`, `grid`) từ `visual.json` nguồn.
   - Bấm lên visual đích trên canvas ở chế độ Sửa → áp đè các khoá tương thích vào `visual.json` đích (1 bước `⌘Z`), rồi tự tắt chế độ Format Painter (hoặc bấm `Esc` để huỷ).
3. **Tab `Data / Drill` & `Show as a table`:**
   - Truyền `state: DocumentState` vào `DataDrillCommands(state:)`.
   - Mở khoá **Drill up**, **Drill down**, **Expand next level** (tăng/giảm `interaction.drillDepth[visualID]` theo số cấp phân cấp/trục của visual đang chọn).
   - Mở khoá **Xem dữ liệu (`Show as a table`)**: thêm `showDataTableVisualID: String?` trên `DocumentState` → mở `VisualDataTableSheet` (hiển thị `DataView` đã nạp của visual đang chọn thành bảng gọn gàng có thanh cuộn ngang/dọc, số định dạng đúng, nút **Xuất CSV** tái dùng `VisualCSVExporter`).

### Nhánh 4B — Mô hình hoá chuyên sâu, Bảo mật RLS & Menu DataPane
1. **Quick Measures (`QuickMeasureCatalog.swift` + `QuickMeasureSheet.swift`):**
   - Định nghĩa 8 template chuẩn Power BI tạo công thức DAX sạch (tự thoát tên bảng/cột bằng `DAXEngine.formatTableIdentifier` / `formatBracketIdentifier`):
     - `ytdTotal` (`TOTALYTD`), `runningTotal` (`CALCULATE(..., FILTER(ALLSELECTED(...), ...))`), `rollingAverage` (`AVERAGEX(DATESINPERIOD(...), ...)`), `percentOfGrandTotal` (`DIVIDE(..., CALCULATE(..., ALLSELECTED(...)))`), `filteredValue` (`CALCULATE(..., Table[Col] = ...)`), `weightedAverage` (`DIVIDE(SUMX(...), SUM(...))`), `yoyPercentChange` (`DIVIDE(Curr - Prev, Prev)` với `SAMEPERIODLASTYEAR`), `safeDivision` (`DIVIDE`).
   - Mở từ nút **Measure nhanh** trên Ribbon Home/Modeling → kiểm công thức qua `MeasureTyping.check` → gọi `modelEditor.apply(.addMeasure(...))` (1 bước `⌘Z`, lưu T2).
2. **Mark as Date Table (`TablePatch.dataCategory` + `ColumnPatch.isKey` + `MarkAsDateTableSheet.swift`):**
   - Mở rộng `TablePatch` thêm `dataCategory: Assignment<String>?` và `ColumnPatch` thêm `isKey: Bool?`, cập nhật `ModelMetadata+Edit.swift` và `MetadataWriter.swift` (ghi `UPDATE [Table] SET DataCategory = ?` và `UPDATE [Column] SET IsKey = ?, IsUnique = ?` khớp 100% `Dim_Date` của Desktop 2.159).
   - `DateTableValidator` kiểm tra cột `.dateTime` trên `ColumnStore`: không có dòng trống (blank/null) và mọi giá trị ngày là duy nhất (`distinctCount == rowCount`, `rowCount > 0`).
   - `MarkAsDateTableSheet` mở từ nút **Đánh dấu bảng ngày** trên `TableToolsCommands`: bật/tắt chỉ trong 1 bước `modelEditor.apply([...])` (`⌘Z` hoàn tác được).
3. **Row-Level Security (`ModelMetadata.Role` + `ModelEdit` + `MetadataWriter` + `ManageRolesSheet` + `ViewAsRoleSheet`):**
   - Mở rộng `ModelMetadata` thêm `public struct Role: Sendable, Hashable` (id, name, description, modelPermission, tablePermissions: `[TablePermission]`) và đọc đầy đủ `[Role]` + `[TablePermission]` trong `ModelMetadata.init(sqlite:)` (giữ nguyên `public let roles: [String]` để 0 phá vỡ mã cũ, bổ sung `public let roleDefinitions: [Role]`).
   - Thêm `ModelEdit.upsertRole(RoleDefinition)` và `ModelEdit.deleteRole(name: String)` vào `ModelEdit.swift`, `ModelMetadata+Edit.swift` và `MetadataWriter.swift` (ghi bảng `[Role]` với `ModelPermission = 2`, bảng `[TablePermission]` với `State = 1`, `MetadataPermission = 0`, cấp phát `ID = MAX(ID) + 1` theo đúng quy ước `MetadataWriter`).
   - **Manage Roles (`ManageRolesSheet`):** tạo/sửa/xoá vai trò, chọn bảng → nhập biểu thức DAX lọc từng bảng → kiểm bằng `DAXEngine` (`FILTER('Table', <expr>)`) trước khi lưu qua `modelEditor.apply`.
   - **View As (`ViewAsRoleSheet` + dải vàng trên `ReportWorkspace` + lọc trong `ReportInteraction`):**
     - `interaction.activeRLSRoles: Set<String>` (chỉ ở phiên hiện tại, không làm bẩn file).
     - Trong `ReportInteraction.load(...)`: khi `!activeRLSRoles.isEmpty`, gom tất cả `TablePermission` của các vai trò đang bật theo từng bảng → nối OR giữa các vai trò (`(expr1) || (expr2)`) → thêm `QueryFilter(tableExpression: "FILTER(KEEPFILTERS(\(tableRef)), \(combined))")` vào `spec.filters`!
     - Hiển thị dải vàng phía trên canvas trong `ReportWorkspace`: *"Đang xem dưới vai trò: \<tên\> [Dừng xem]"*.
4. **Menu chuột phải `DataPane`:**
   - Nối `onToggleHidden` cho Bảng (`state.setTableHidden`) và Cột (`state.updateColumn(..., patch: ColumnPatch(isHidden: !c.isHidden))`), nối `onUnhideAll` (bỏ ẩn toàn bộ bảng/cột/measure đang ẩn của mô hình trong 1 bước `modelEditor.apply(edits)`).

### Nhánh 4C — DAX Formatter, DAX Update Model, TMDL Ribbon, SQL Quick Connect & v1.2.0
1. **DAX Formatter (`Sources/DAXEngine/Syntax/Formatter.swift`):**
   - `public static func format(_ text: String) -> String` dùng `DAXLexer` (hoặc scanner giữ nguyên comment `--`, `//`, `/* */` và literal `"..."`): xuống dòng & thụt lề 4 khoảng trắng cho các từ khoá khối (`DEFINE`, `MEASURE`, `VAR`, `RETURN`, `EVALUATE`, `ORDER BY`, `START AT`) và lời gọi hàm có nhiều đối số / lồng ngoặc.
   - Nối vào nút **Định dạng** trên `DAXHomeCommands` (Ribbon DAX Query View).
2. **DAX Query → `Cập nhật mô hình` (`DAXModelSync.swift` + `DAXUpdateModelSheet.swift`):**
   - Quét các khối `DEFINE` → `MEASURE Table[Name] = <expr>` (tách theo ranh giới `MEASURE` / `VAR` / `EVALUATE` / `TABLE` / `COLUMN` qua token).
   - So với `workspace.metadata.measures` → liệt kê rõ từng measure *Mới* hoặc *Cập nhật biểu thức* kèm diff ngắn gọn → kiểm từng biểu thức bằng `MeasureTyping.check` → áp dụng 1 lần qua `modelEditor.apply(edits)` (hoàn tác `⌘Z`).
3. **TMDL Ribbon `Áp dụng thay đổi`:**
   - Thêm trạng thái nhẹ trên `DocumentState`: `var tmdlHasPendingChanges = false`, `var tmdlApplyRequestToken = 0` → `TMDLWorkspace` đồng bộ `tmdlHasPendingChanges` khi người dùng gõ và lắng nghe `tmdlApplyRequestToken` để gọi `apply()` (tái sử dụng trọn vẹn luồng `applyTMDL(drafts:)` sẵn có!).
4. **Ribbon `SQL` Quick Connect & Phiên bản 1.2.0:**
   - Đổi nút `SQL` trên `DataSourceCommands` thành `Menu` gồm **PostgreSQL** (`state.showGetData(kind: .postgres)`) và **SQLite** (`state.showGetData(kind: .sqlite)`), vô hiệu hoá chỉ khi `state.getDataBlocker != nil`.
   - Cập nhật chuỗi phiên bản **1.2.0** trong `Ribbon.swift` (*Giới thiệu*) và `scripts/build-app.sh` (`CFBundleShortVersionString = 1.2.0`, `CFBundleVersion = 120`).

---

## 2. Kiểm thử & Cổng nghiệm thu

- Unit & Integration tests mới:
  - `Tests/DAXEngineTests/V12DAXFormatterTests.swift` (định dạng DAX + giữ nguyên chuỗi/comment + parse lại thành AST hợp lệ).
  - `Tests/PBIXKitTests/V12ModelMetadataRLSTests.swift` (`TablePatch.dataCategory`, `ColumnPatch.isKey`, `RoleDefinition` + `TablePermission` ghi SQLite & đọc lại nguyên vẹn).
  - `Tests/BIProTests/V12FeaturesTests.swift` (Cut/Copy/Paste cross-page + Undo, Format Painter + Undo, Quick Measures 8 mẫu, Mark as Date Table + validation, RLS Manage Roles + View As lọc đúng giá trị DAX, DAX Update Model, Unhide All).
  - `Tests/BIProTests/Edit/V12GatePBIXTests.swift` (`BIPRO_V12_GATE=1` → sinh `build/v12-out/bipro-v12-gate.pbix` kiểm chứng mở trên **Power BI Desktop 2.159 VM**).
