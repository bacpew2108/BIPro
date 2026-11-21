# Kế hoạch kỹ thuật: Đợt 3 (v1.1b) — Tương tác báo cáo, Định dạng có điều kiện, Analytics, Làm mới dữ liệu & Mở rộng DAX

**Thư mục spec:** `specs/014-v11-tinh-nang-nang-cao/`
**Ngày lập:** 2026-11-21
**Trạng thái:** Chờ duyệt (Cổng duyệt 2/3 — `plan.md` & `data-model.md`)
**Đặc tả gốc:** [spec.md](file:///Users/macprom114/Desktop/PowerBINative/specs/014-v11-tinh-nang-nang-cao/spec.md)
**Bằng chứng VM:** [QUAN-SAT.md](file:///Users/macprom114/Desktop/PowerBINative/docs/phase-v11-evidence/vm-v11b/QUAN-SAT.md) & [dax-golden.json](file:///Users/macprom114/Desktop/PowerBINative/docs/phase-v11-evidence/vm-v11b/dax-golden.json)

---

## 1. Kiểm tra tuân thủ Hiến pháp (Constitution Check)

| Điều khoản | Đánh giá tuân thủ trong Đợt 3 |
|---|---|
| **I. Quan sát trước — Không suy đoán** | Đã quan sát trực tiếp Power BI Desktop 2.159 (`VM-V11B`): 18 tệp PBIR JSON nguyên văn (`visualInteractions`, Matrix row `expansionStates`, `columnFormatting.dataBars`, `values.Conditional`, `y1AxisReferenceLine`, `referenceLine` Function `1/3/4`, `themeCollection`) + 21/21 truy vấn DAX golden trên `msmdsrv`. |
| **II. Không gian lận — Tính toán thật qua DAXEngine** | Mọi subtotal/chi tiết hàng Matrix, đường trung bình/min/max, định dạng có điều kiện (Rules/Gradient/Field value/Data bars) và ~56 hàm DAX mới đều tính thật qua `DAXEngine` & `ColumnStore`. Không hardcode giá trị test. |
| **III. Native macOS thuần tuý — Zero thư viện ngoài** | 100% Swift/SwiftUI/AppKit/CoreGraphics/Swift Charts, không thêm bất kỳ dependency SPM nào. |
| **IV. Zero mạng — Chỉ-đọc `~/Downloads`** | 100% ngoại tuyến (kể cả 6 preset Theme nhúng sẵn và Refresh dữ liệu nguồn cục bộ CSV/Excel/JSON/Parquet/SQLite/PostgreSQL localhost). Không ghi sửa các tệp `.pbix` trong `~/Downloads`. |
| **V. Cổng kiểm chứng Desktop 2.159** | Cuối đợt xuất tệp `.pbix` kiểm chứng tổng hợp mở trên Power BI Desktop 2.159 trên VM (0 cảnh báo hỏng/lỗi trường/lỗi tài nguyên) và dọn sạch VM sau kiểm chứng. |

---

## 2. Kiến trúc triển khai theo 4 nhánh (`3D` → `3A` → `3B` → `3C`)

> **Thứ tự thực thi tối ưu:** Triển khai **3D (DAX Engine)** trước (độc lập hoàn toàn, có bộ golden oracle 21/21 chạy ngay để khóa đúng ngữ nghĩa), sau đó lần lượt **3A (Tương tác & Báo cáo)**, **3B (CF, Theme & Analytics)**, **3C (Refresh, Cascade Rename & Query Editor)**, và cuối cùng **Cổng kiểm chứng VM Desktop 2.159 + Build Release**.

### Nhánh 3D — Mở rộng DAX Engine (~56 hàm mới)
- **Tệp sửa / thêm trong `Sources/DAXEngine/`:**
  1. `Functions/DateTime.swift`: bổ sung `TODAY`, `NOW`, `WEEKDAY` (type `1/2/3`), `WEEKNUM` (type `1/2/21` ISO 8601), `EOMONTH`, `EDATE`, `MINUTE`, `SECOND`, `TIME` (tràn modulo 24h), `YEARFRAC` (basis `0..4`), `CALENDARAUTO([fyEndMonth])` (quét toàn bộ cột `dateTime` trong `store.schema`, bỏ qua bảng tính toán không có dữ liệu).
  2. `Functions/TimeIntel.swift`: bổ sung 23 hàm trên lõi `DateSource` + lịch Gregorian đã có:
     - `DATESYTD`, `DATESQTD`, `DATESMTD` (hỗ trợ `year_end_date` như `"6/30"` hoặc `"3/31"`).
     - `TOTALYTD`, `TOTALQTD`, `TOTALMTD` (gọi `CALCULATE(expr, DATES*(dates), extraFilters...)`).
     - `DATESBETWEEN` (hỗ trợ `start`/`end` là `BLANK()` lấy min/max cột ngày), `DATESINPERIOD` (`DAY`/`MONTH`/`QUARTER`/`YEAR`, tiến & lùi).
     - `PREVIOUSDAY`, `PREVIOUSMONTH`, `PREVIOUSQUARTER`, `PREVIOUSYEAR`, `NEXTDAY`, `NEXTMONTH`, `NEXTQUARTER`, `NEXTYEAR`, `PARALLELPERIOD`.
     - `STARTOFMONTH`, `ENDOFMONTH`, `STARTOFQUARTER`, `ENDOFQUARTER`, `STARTOFYEAR`, `ENDOFYEAR`.
  3. `Functions/Information.swift` & `Functions/Logical.swift`: bổ sung `ERROR(msg)` (ném `DAXError(.runtime, msg)`), `IFERROR(val, alt)` (bắt `DAXError` trong đánh giá `val`), `ISERROR(val)` (trả `Bool`), `ISNUMBER`, `ISTEXT`, `ISLOGICAL`.
  4. `Functions/TableFns.swift`, `Functions/Aggregation.swift`, `Functions/Iterators.swift`:
     - `LOOKUPVALUE(resultCol, searchCol1, searchVal1, ..., [alternate])` (tra toàn bộ bảng bỏ filter context theo chuẩn DAX, hỗ trợ nhiều cặp điều kiện).
     - `SELECTCOLUMNS(table, name, expr, ...)`: chiếu bảng mới không giữ cột gốc.
     - `UNION(t1, t2, ...)` (giữ bản sao multiset, kiểm tra số cột khớp), `INTERSECT(left, right)` (giữ bản sao theo bảng trái), `EXCEPT(left, right)`.
     - `GENERATESERIES(start, end, [increment = 1])`: bảng 1 cột `[Value]` số nguyên/thực.
     - `DATATABLE(col1, TYPE1, ..., {{row1}, {row2}})`: hỗ trợ từ khoá kiểu `STRING`, `INTEGER`, `DOUBLE`, `BOOLEAN`, `DATETIME`, `CURRENCY` trong `Binder.swift` / `Parser.swift`.
     - `COUNTBLANK(col)` (trả `.blank` khi không có ô trống — đúng Desktop 2.159!), `COUNTX`, `COUNTAX`, `PRODUCTX`, `STDEV.S`, `VAR.S`.
  5. `Functions/WindowFns.swift` *(mới)* + đăng ký trong `Functions/Registry.swift` + mở rộng `Semantic/Binder.swift`:
     - Mệnh đề trợ giúp `ORDERBY(expr, [ASC|DESC], ...)` và `PARTITIONBY(col, ...)` được biểu diễn như đối số có cấu trúc cho `OFFSET`, `INDEX`, `WINDOW`.
     - `OFFSET(delta, [relation], [orderBy], [blanks], [partitionBy])`
     - `INDEX(position, [relation], [orderBy], [blanks], [partitionBy])` (hỗ trợ vị trí dương từ đầu và âm từ cuối như `-1`)
     - `WINDOW(from, fromType, to, toType, [relation], [orderBy], [blanks], [partitionBy])` (`ABS`/`REL`).
  6. `Sources/BIPro/Model/DAXAutocomplete.swift` (hoặc tệp gợi ý công thức hiện có): bổ sung toàn bộ chữ ký hàm mới.

### Nhánh 3A — Tương tác báo cáo, Matrix phân cấp hàng, Kéo-thả bộ lọc & Bookmark Data
- **PBIR (`Sources/PBIXKit/`):**
  1. `Writing/PBIRPagePatch.swift`: bổ sung `settingVisualInteractions(_ interactions: [PageVisualInteraction], in pageJSON: Data) throws -> Data` (ghép byte giữ nguyên phần còn lại, xoá khoá khi mảng rỗng).
  2. `ReportDefinition.swift`: đọc mảng `visualInteractions` của mỗi `ReportPage` thành `[PageVisualInteraction]`.
  3. `Writing/PBIRQueryPatch.swift`: bổ sung `settingExpansionStates(_ statesJSON: String?, in visualJSON: Data)` để lưu trạng thái mở/đóng hàng Matrix (`roles: ["Rows"]`).
- **Tương tác & Canvas (`Sources/BIPro/`):**
  4. `Report/ReportInteraction.swift` & `Visuals/Interaction/InteractionRules.swift`: nạp `page.visualInteractions` vào `InteractionOverride` (ưu tiên thay đổi trong phiên sửa), áp dụng nhất quán cho cả `DataFilter`, `HighlightFilter`, `NoFilter`.
  5. `Report/Edit/LayoutEditor.swift` + `Report/Edit/EditCanvasOverlay.swift` + `Shell/Ribbon.swift`: thêm chế độ `isEditingInteractions` (nút **Sửa tương tác** trên Ribbon khi đang ở chế độ Sửa và có visual nguồn được chọn); vẽ thanh huy hiệu nhỏ gọn (`Lọc` / `Tô sáng` nếu hỗ trợ / `Không`) ở góc trên phải từng visual đích; bấm để đổi và lưu undoable vào `page.json`.
  6. `Visuals/Query/VisualQuerySpec.swift`, `VisualQuerySpecReader.swift`, `DAXQueryBuilder.swift`, `DataViewMapper.swift` & `Visuals/Matrix/MatrixVisual.swift`:
     - Đọc `expansionStates` có `roles` chứa `"Rows"` thành tập đường dẫn hàng đang mở (`rowExpandedPaths: Set<[Value]>`).
     - `DAXQueryBuilder` + `DataViewMapper` xây dựng cây hàng phân cấp: luôn truy vấn cấp gốc (cấp 0), và với từng nút cha đang mở truy vấn các dòng con cấp tiếp theo kèm bộ lọc giá trị cha; chèn dòng con ngay dưới dòng cha với `indentLevel` tăng dần và đánh dấu `hasChildren`/`isExpanded`.
     - `MatrixVisualView`: vẽ nút `+`/`−` bên trái nhãn dòng cha (thụt lề theo cấp), bấm để gọi `context.actions.drill(.toggle(axis: .rows, path: ...))` (cập nhật ngay ở chế độ Xem, và lưu `expansionStates` vào `visual.json` khi ở chế độ Sửa).
  7. `Panes/ReportPanes.swift`, `Panes/DataPane.swift`, `Panes/FilterEditor.swift`, `Report/Edit/FilterExport.swift`:
     - Hỗ trợ kéo-thả trường (`draggable`/`dropDestination` bằng chuỗi payload JSON gọn `FieldDragPayload`) từ `DataPane` vào 3 vùng của `FiltersPane` (*Visual này*, *Trang này*, *Mọi trang*).
     - `FilterEditor.swift`: khi cột có kiểu `.dateTime`, chế độ `Advanced filtering` hiện bộ toán tử ngày (`là`, `không phải`, `sau`, `từ ngày trở đi`, `trước`, `đến ngày trở về trước`) + `DatePicker` native macOS, sinh `FilterRule` và ghi PBIR chuẩn `datetime'YYYY-MM-DDT00:00:00'` qua `PBIRFilterPatch`.
  8. `Report/UserBookmark.swift` & `Report/Edit/BookmarkExport.swift`: mở rộng `UserBookmark` chụp & khôi phục `crossFilter`, `drillLevels`, `matrixRowExpansion`, `matrixColumnExpansion` và slicer nhiều cấp.

### Nhánh 3B — Conditional Formatting, Theme Switcher & Analytics Pane
- **Mô hình & PBIR (`Sources/BIPro/Visuals/Format/` & `Sources/PBIXKit/Writing/`):**
  1. `VisualFormat.swift`: bổ sung 4 kiểu dữ liệu chuẩn `VM-V11B`:
     - `ConditionalColorRule` (`property`: `backColor`/`fontColor`, `target`, `cases`, `matchingOption`)
     - `DataBarRule` (`target`, `positiveColor`, `negativeColor`, `axisColor`, `reverseDirection`, `hideText`, `totalMatchingOption`)
     - `ConstantReferenceLine` (`id`, `displayName`, `value`, `color`, `style`, `transparency`, `show`)
     - `DynamicReferenceLine` (`id`, `displayName`, `kind: .average | .min | .max`, `target`, `color`, `style`, `show`)
  2. `PBIRFormatPatch.swift` & `LayoutEditor+Format.swift`: hỗ trợ cập nhật an toàn các mục `objects.values` (`FillRule` / `Conditional` / `Measure`), `objects.columnFormatting` (`dataBars`), `objects.y1AxisReferenceLine`, và `objects.referenceLine` (gồm thêm/sửa/xoá từng đường theo `selector.id`), có Undo/Redo.
  3. `PBIRResourcePatch.swift`: bổ sung `settingCustomTheme(name:path:to report: Data) throws -> Data` (cập nhật `themeCollection.customTheme` và danh sách `RegisteredResources` với `type: "CustomTheme"`).
- **Vẽ thật & Giao diện (`Sources/BIPro/`):**
  4. `Visuals/Matrix/MatrixVisual.swift` & `Visuals/Matrix/TableVisual.swift` & `Visuals/Matrix/CellFormatting.swift` *(mới)*:
     - Đánh giá thống nhất `backColor`, `fontColor` (ưu tiên Rules → Gradient → Field value) và `dataBars` (tính tỷ lệ chiều rộng theo `[min, max]` của cột, hỗ trợ âm/dương tách hai phía trục 0, tôn trọng `hideText` và `totalMatchingOption == 1`).
  5. `Visuals/Charts/CartesianChart.swift`, `ComboChart.swift`, `ChartReferenceLines.swift` *(mới)*:
     - Vẽ `y1AxisReferenceLine` (hằng số) và `referenceLine` (tính trực tiếp Mean/Min/Max từ dữ liệu biểu đồ đang hiển thị) bằng nét đứt/liền + nhãn nhỏ gọn, tự hoạt động cả trên canvas lẫn khi xuất PNG/PDF.
  6. `Panes/FormatPane.swift` + `Panes/ConditionalFormattingSheet.swift` *(mới)* + `Panes/AnalyticsPane.swift` *(mới)*:
     - Trong `FormatPane`, thêm mục **Định dạng có điều kiện** (cho `tableEx` & `pivotTable`) mở sheet cấu hình Màu nền / Màu chữ (Gradient 2–3 mốc, Rules nhiều điều kiện, Measure màu) & Data Bars.
     - Thêm tab **Phân tích (Analytics)** (biểu tượng kính lúp bên cạnh tab *Visual* và *Chung*) khi chọn biểu đồ trục: bật/tắt Trend line, Forecast, thêm/sửa/xoá Đường hằng số trục Y, Đường Trung bình / Min / Max.
  7. `Report/ThemeCatalog.swift` *(mới)* + `Panes/ThemePickerPopover.swift` *(mới)* + `Shell/Ribbon.swift` + `DocumentState.swift`:
     - 6 chủ đề dựng sẵn hợp lệ chuẩn Power BI theme JSON (`Power BI Default`, `Executive`, `City Park`, `Classic`, `High Contrast`, `BI Pro Native`).
     - Popover chọn chủ đề trên Ribbon + **Nhập chủ đề (.json)…** (`NSOpenPanel`, kiểm tra JSON hợp lệ trước khi áp dụng) + **Xuất chủ đề hiện tại…** (`NSSavePanel`). Áp dụng tức thời lên `ReportTheme`, lưu vào `RegisteredResources` + `report.json` và hỗ trợ Undo/Redo.

### Nhánh 3C — Làm mới dữ liệu một bấm, Cascade Rename & Power Query mở rộng
- **Làm mới dữ liệu (`Sources/BIPro/`):**
  1. `Query/RefreshCoordinator.swift` *(mới)* + `DocumentState+Refresh.swift` *(mới)* + `Panes/RefreshProgressSheet.swift` *(mới)* + `Shell/Ribbon.swift`:
     - Mở khoá nút **Làm mới (Refresh)** trên tab Trang chủ (`Ribbon.swift`) + phím tắt `⇧⌘R`.
     - Duyệt mọi bảng trong `workspace.metadata` có partition nguồn M (bỏ qua `Enter Data` và bảng tính toán DAX); chạy từng bảng trên tác vụ nền (`Task.detached`) qua `MQueryEvaluator` / `DataSourceConnector`; cập nhật trạng thái từng bảng (`đang chạy` / `thành công (+N dòng)` / `lỗi: <chi tiết>`).
     - Với các bảng thành công, ghi thay thế bảng dữ liệu mới thông qua `ModelEditor` (giữ nguyên toàn bộ quan hệ, measure, định dạng cột và báo cáo; tự xây dựng lại cột tính toán, bảng tính toán và chỉ mục `R$`/`U$`); đánh dấu cần lưu T3 và nạp lại toàn bộ visual. Bảng lỗi giữ nguyên dữ liệu cũ, không phá hỏng mô hình.
- **Đổi tên tự cập nhật tham chiếu (`Sources/BIPro/` & `Sources/PBIXKit/`):**
  2. `Model/CascadeRename.swift` *(mới)* (`DAXReferenceRewriter` dựa trên `DAXEngine.Lexer` + `PBIRReferenceRewriter` cập nhật `visual.json`/`page.json`/`report.json`) + `DocumentState+Model.swift` + `Panes/RenameConfirmationSheet.swift` *(mới)*:
     - Khi đổi tên bảng, cột hoặc measure đang có tham chiếu (`ModelReferences.usages(...)` không rỗng), hiện hộp thoại xác nhận liệt kê số measure/cột tính toán/visual/bộ lọc sẽ tự động cập nhật.
     - `DAXReferenceRewriter` dùng token của `Lexer` (chỉ đổi token `.table` / `.column` / `.identifier` khớp, **không bao giờ** đụng chuỗi `"..."` hay tiền tố tên khác).
     - `PBIRReferenceRewriter` cập nhật `SourceRef.Entity`, `Property`, `queryRef`, `nativeQueryRef`, `selector.metadata`, `filterConfig` trên toàn bộ trang & visual.
     - Gom cả sửa mô hình + sửa PBIR thành một thao tác có thể Undo/Redo (`⌘Z`).
- **Biến đổi Power Query mở rộng (`Sources/MEngine/` & `Sources/BIPro/Query/Editor/`):**
  3. `Sources/MEngine/Library/TableRows.swift`, `TableColumns.swift`, `ValueText.swift`, `ValueDate.swift`, `ValueReplacerSplitter.swift`:
     - Bổ sung / hoàn thiện: `Table.FillDown`, `Table.FillUp`, `Table.ReplaceErrorValues`, `Table.SplitColumn` (delimiter trái nhất/phải nhất/mỗi lần + theo độ dài cố định), `Text.Length`, `Text.Start`, `Text.End`, `Text.BeforeDelimiter`, `Text.AfterDelimiter`, `Text.BetweenDelimiters`, `Date.Year`, `Date.Month`, `Date.Day`, `Date.QuarterOfYear`, `Date.StartOfMonth`, `Date.EndOfMonth`, `Date.DayOfWeekName`, `Date.MonthName`.
  4. `Sources/MEngine/StepFactory.swift` + `Sources/BIPro/Query/Editor/QueryRibbonView.swift` & `QueryEditorWindow.swift` & `QueryEditorPopovers.swift`:
     - Nối đủ 5 nhóm lệnh (Tách cột nâng cao, Điền xuống/lên, Thay thế lỗi, Trích xuất văn bản, Trích xuất Ngày/Giờ) vào giao diện Query Editor song ngữ Việt/Anh.

---

## 3. Chiến lược kiểm thử (TDD & Golden Verification)

1. **DAX Golden Test (`Tests/DAXEngineTests/V11BDAXGoldenTests.swift`):** Đọc trực tiếp `docs/phase-v11-evidence/vm-v11b/dax-golden.json`, chạy toàn bộ 21 nhóm truy vấn trên `Nhom6_Dashboard_chiase.pbix` (và unit test độc lập cho từng hàm) so khớp tuyệt đối với kết quả Power BI Desktop 2.159.
2. **PBIR Patch & 3A/3B Unit Tests (`Tests/PBIXKitTests/V11BPBIRPatchTests.swift`, `Tests/BIProTests/V11BFeaturesTests.swift`):**
   - Byte-splice `visualInteractions`, Matrix row `expansionStates`, `columnFormatting.dataBars`, `values.Conditional`/`FillRule`, `y1AxisReferenceLine`, `referenceLine`, `themeCollection.customTheme`.
   - Kiểm thử render offscreen (NSHostingView/ImageRenderer) cho Matrix mở hàng + Data Bars + Rules CF + Analytics lines + đổi Theme.
3. **3C Refresh, Cascade Rename & M Transforms Tests (`Tests/MEngineTests/V11BMTransformsTests.swift`, `Tests/BIProTests/V11BRefreshAndRenameTests.swift`):**
   - Tạo tệp CSV tạm → nhập vào mô hình + tạo quan hệ + measure + visual → sửa tệp CSV thêm dòng mới → chạy `RefreshCoordinator` → xác nhận measure & visual cập nhật đúng số mới, quan hệ không mất, lưu T3 mở lại nguyên vẹn.
   - Tạo bảng + cột + measure dùng trong measure khác và visual → Cascade Rename cả 3 loại → xác nhận 0 lỗi DAX, 0 visual gãy, chuỗi `"..."` không bị sửa nhầm, Undo khôi phục 100%.
4. **Cổng Power BI Desktop 2.159 (`Tests/BIProTests/V11BGatePBIXTests.swift` + kiểm chứng VM):**
   - Xuất `build/v11-out/bipro-v11b-gate.pbix` tích hợp mọi tính năng Đợt 3 → mở bằng **Power BI Desktop 2.159 trên VM Windows 11** → xác nhận 0 cảnh báo hỏng, 0 lỗi trường, 0 lỗi tài nguyên, chụp ảnh cắt vùng canvas lưu làm bằng chứng, đóng Desktop & dọn VM.
5. **Hồi quy toàn diện & Đóng gói Release:**
   - `swift test --no-parallel` (0 lỗi)
   - `BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --no-parallel` (0 lỗi)
   - `zsh scripts/build-app.sh release` + `codesign --verify --deep --strict "build/BI Pro.app"`.
