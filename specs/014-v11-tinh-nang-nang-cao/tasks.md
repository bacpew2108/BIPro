# Danh sách tác vụ triển khai: Đợt 3 (v1.1b) — Tương tác báo cáo, Định dạng có điều kiện, Analytics, Làm mới dữ liệu & Mở rộng DAX

**Thư mục spec:** `specs/014-v11-tinh-nang-nang-cao/`
**Ngày lập:** 2026-11-21
**Trạng thái:** ✅ Hoàn tất 100% (2026-11-21 — đạt toàn bộ cổng kiểm chứng `SC-001`–`SC-004`)
**Tham chiếu:** [spec.md](file:///Users/macprom114/Desktop/PowerBINative/specs/014-v11-tinh-nang-nang-cao/spec.md), [plan.md](file:///Users/macprom114/Desktop/PowerBINative/specs/014-v11-tinh-nang-nang-cao/plan.md), [data-model.md](file:///Users/macprom114/Desktop/PowerBINative/specs/014-v11-tinh-nang-nang-cao/data-model.md), [measurements.md](file:///Users/macprom114/Desktop/PowerBINative/specs/014-v11-tinh-nang-nang-cao/measurements.md)

---

## Nhánh 1 — 3D: Mở rộng DAX Engine (~56 hàm mới đối chiếu Golden Desktop 2.159)

- [x] **T001** `Sources/DAXEngine/Functions/DateTime.swift` — Bổ sung 11 hàm Ngày/Giờ (`TODAY`, `NOW`, `WEEKDAY`, `WEEKNUM` gồm loại 1/2/21 ISO 8601, `EOMONTH`, `EDATE`, `MINUTE`, `SECOND`, `TIME` tràn mod 24h, `YEARFRAC` basis 0–4, `CALENDARAUTO([fyEndMonth])`).
- [x] **T002** `Sources/DAXEngine/Functions/TimeIntel.swift` — Bổ sung 23 hàm Time Intelligence (`DATESYTD`/`QTD`/`MTD`, `TOTALYTD`/`QTD`/`MTD`, `DATESBETWEEN`, `DATESINPERIOD`, `PREVIOUSDAY`/`MONTH`/`QUARTER`/`YEAR`, `NEXTDAY`/`MONTH`/`QUARTER`/`YEAR`, `PARALLELPERIOD`, `STARTOFMONTH`/`QUARTER`/`YEAR`, `ENDOFMONTH`/`QUARTER`/`YEAR`).
- [x] **T003** `Sources/DAXEngine/Functions/Information.swift` & `Logical.swift` — Bổ sung 6 hàm bắt lỗi & kiểm tra kiểu (`ERROR`, `IFERROR`, `ISERROR`, `ISNUMBER`, `ISTEXT`, `ISLOGICAL`).
- [x] **T004** `Sources/DAXEngine/Functions/TableFns.swift`, `Aggregation.swift`, `Iterators.swift`, `Semantic/Binder.swift` — Bổ sung 13 hàm tra cứu, bảng, tập hợp & thống kê (`LOOKUPVALUE`, `SELECTCOLUMNS`, `UNION` multiset, `INTERSECT` multiset, `EXCEPT`, `GENERATESERIES`, `DATATABLE` kèm từ khoá kiểu, `COUNTBLANK` trả `BLANK` khi không có ô trống, `COUNTX`, `COUNTAX`, `PRODUCTX`, `STDEV.S`, `VAR.S`).
- [x] **T005** `Sources/DAXEngine/Functions/WindowFns.swift` *(mới)*, `Functions/Registry.swift`, `Semantic/Binder.swift` — Cài đặt 3 hàm cửa sổ `OFFSET`, `INDEX`, `WINDOW` cùng mệnh đề `ORDERBY`, `PARTITIONBY` và từ khoá `ABS`/`REL`/`BLANKS`/`KEEP`/`DEFAULT`/`FIRST`/`LAST`.
- [x] **T006** `Sources/BIPro/Model/` (DAX Autocomplete đọc trực tiếp `FunctionRegistry.all`) + `Tests/DAXEngineTests/V11BDAXGoldenTests.swift` *(mới)* — Đối chiếu 100% 21/21 nhóm trong `docs/phase-v11-evidence/vm-v11b/dax-golden.json` (7/7 test qua trong 0,091 s).

---

## Nhánh 2 — 3A: Sửa tương tác chéo, Matrix phân cấp hàng, Kéo-thả bộ lọc & Bookmark Data

- [x] **T007** `Sources/PBIXKit/ReportDefinition.swift`, `Writing/PBIRPagePatch.swift`, `Writing/PBIRQueryPatch.swift` — Đọc/ghi byte-preserving cho `visualInteractions` (`DataFilter`/`HighlightFilter`/`NoFilter`) trong `page.json` và `expansionStates` (`roles: ["Rows"]`) trong `visual.json`.
- [x] **T008** `Sources/BIPro/Report/ReportInteraction.swift`, `Report/Edit/LayoutEditor.swift`, `Report/Edit/EditCanvasOverlay.swift`, `Shell/Ribbon.swift` — Bật chế độ **Sửa tương tác (Edit interactions)** ở chế độ Sửa (`⌘E`), vẽ huy hiệu Filter/Highlight/None ở góc trên phải từng visual đích, áp dụng thực tế ở chế độ Xem, hỗ trợ Undo/Redo và lưu `page.json`.
- [x] **T009** `Sources/BIPro/Visuals/Query/VisualQuerySpec.swift`, `VisualQuerySpecReader.swift`, `DAXQueryBuilder.swift`, `DataViewMapper.swift`, `Visuals/Matrix/MatrixVisual.swift` — Hỗ trợ đầy đủ phân cấp hàng Matrix (`+`/`−` bên trái dòng cha, thụt lề dòng con tính qua `DAXEngine`, giữ subtotal cha, đồng bộ `expansionStates` khi lưu).
- [x] **T010** `Sources/BIPro/Panes/DataPane.swift`, `Panes/ReportPanes.swift`, `Panes/FilterEditor.swift`, `Report/Edit/FilterExport.swift` — Kéo-thả trường từ `DataPane` vào 3 vùng của `FiltersPane` (*Visual này*, *Trang này*, *Mọi trang*) và bổ sung Advanced Filtering cột Ngày (`DatePicker` + toán tử `is`/`is not`/`is after`/`is on or after`/`is before`/`is on or before` ghi chuẩn `datetime'...'`).
- [x] **T011** `Sources/BIPro/Report/UserBookmark.swift`, `Report/Edit/BookmarkExport.swift` — Mở rộng Bookmark Data lưu & khôi phục trạng thái lọc chéo, cấp drill hiện tại, mở/đóng hàng/cột Matrix và slicer nhiều cấp.
- [x] **T012** `Tests/PBIXKitTests/V11BPBIRPatchTests.swift` *(mới)* & `Tests/BIProTests/V11BInteractionsAndMatrixTests.swift` *(mới)* — Kiểm thử đơn vị & tích hợp cho `visualInteractions`, Matrix phân cấp hàng, Date Advanced filter và Bookmark Data mở rộng.

---

## Nhánh 3 — 3B: Conditional Formatting, Theme Switcher & Analytics Pane

- [x] **T013** `Sources/BIPro/Visuals/Format/VisualFormat.swift`, `Sources/PBIXKit/Writing/PBIRFormatPatch.swift`, `Sources/BIPro/Report/Edit/LayoutEditor.swift` — Đọc/ghi đầy đủ `ConditionalColorRule` (`objects.values[].Conditional`), `GradientRule` (`FillRule` 2/3 mốc), `MeasureDrivenProperty` (Field value), `DataBarRule` (`objects.columnFormatting[].dataBars`), `ConstantReferenceLine` (`objects.y1AxisReferenceLine`) và `DynamicReferenceLine` (`objects.referenceLine` Function `1/3/4`).
- [x] **T014** `Sources/BIPro/Visuals/Matrix/CellFormatting.swift` *(mới)*, `MatrixVisual.swift`, `TableVisual.swift` — Vẽ nhất quán màu nền/màu chữ có điều kiện (Rules, Gradient, Field value) và Data Bars (dương/âm, `hideText`, bỏ qua Total khi `matchingOption == 1`) trên cả `tableEx` và `pivotTable`, hỗ trợ xuất PNG/PDF.
- [x] **T015** `Sources/BIPro/Panes/ConditionalFormattingSheet.swift` *(mới)* & `Panes/FormatPane.swift` — Giao diện cấu hình Conditional Formatting (Gradient 2–3 mốc, Rules nhiều nhánh, Field value chọn measure màu, Data Bars) cho các trường giá trị của `tableEx` và `pivotTable`, song ngữ Việt/Anh & Dark Mode.
- [x] **T016** `Sources/BIPro/Visuals/Charts/ChartReferenceLines.swift` *(mới)*, `CartesianChart.swift`, `Panes/AnalyticsPane.swift` *(mới)*, `Panes/FormatPane.swift` — Vẽ các đường tham chiếu Analytics (`y1AxisReferenceLine`, `referenceLine` Average/Min/Max) lên biểu đồ trục; bổ sung tab **Phân tích (Analytics)** (biểu tượng kính lúp) để thêm/sửa/xoá Constant/Average/Min/Max và bật/tắt Trend/Forecast.
- [x] **T017** `Sources/PBIXKit/Writing/PBIRResourcePatch.swift`, `Sources/BIPro/Report/ThemeCatalog.swift` *(mới)*, `Panes/ThemePickerPopover.swift` *(mới)*, `Shell/Ribbon.swift`, `DocumentState.swift`, `Workspace.swift` — Bổ sung `PBIRResourcePatch.settingCustomTheme`, 6 chủ đề dựng sẵn hợp lệ chuẩn Power BI, popover chọn chủ đề + **Nhập chủ đề (.json)…** + **Xuất chủ đề…**, cập nhật tức thời canvas, lưu `RegisteredResources` + `report.json`, hỗ trợ Undo/Redo.
- [x] **T018** `Tests/BIProTests/V11BFormattingThemeAnalyticsTests.swift` *(mới)* — Kiểm thử CF (Rules/Gradient/Field value/Data Bars), đường tham chiếu Analytics, và đổi/nhập/xuất Theme + round-trip PBIR.

---

## Nhánh 4 — 3C: Làm mới dữ liệu một bấm, Cascade Rename & Power Query mở rộng

- [x] **T019** `Sources/BIPro/Query/RefreshCoordinator.swift` *(mới)*, `DocumentState+Refresh.swift` *(mới)*, `Panes/RefreshProgressSheet.swift` *(mới)*, `Shell/Ribbon.swift`, `EditCommands.swift` — Mở khoá nút **Làm mới (Refresh)** (`⇧⌘R`) trên Ribbon chính, chạy lại truy vấn M cho mọi bảng nguồn, giữ nguyên quan hệ/measure/visual, xây lại cột tính toán & chỉ mục `R$`/`U$`, báo cáo từng bảng và giữ nguyên dữ liệu cũ khi nguồn lỗi.
- [x] **T020** `Sources/BIPro/Model/CascadeRename.swift` *(mới)*, `Panes/RenameConfirmationSheet.swift` *(mới)*, `Sources/DAXEngine/Syntax/References.swift`, `DocumentState+Model.swift`, `DataPane.swift`, `LeftContextMenu.swift` — Tự động viết lại công thức DAX (theo token `DAXLexer`, không đụng chuỗi `"..."`) và mọi tham chiếu PBIR (`SourceRef.Entity`, `Property`, `queryRef`, `nativeQueryRef`, `selector.metadata`, `filterConfig`) khi đổi tên bảng/cột/measure đang được dùng, kèm hộp xác nhận số lượng tham chiếu và Undo/Redo nguyên khối.
- [x] **T021** `Sources/MEngine/Library/` (`ValueText.swift`, `ValueDate.swift`, `ValueReplacerSplitter.swift`) & `StepFactory.swift` — Bổ sung hoàn chỉnh các hàm M (`Text.BeforeDelimiter`/`AfterDelimiter`/`BetweenDelimiters`/`Range`, `Date.QuarterOfYear`/`StartOfMonth`/`EndOfMonth`/`DayOfWeekName`/`MonthName`, `Splitter.SplitTextByRepeatedLengths`/`SplitTextByPositions`, `StepCommand` cho Extract/Date/Split nâng cao; `Table.FillDown`/`FillUp`/`ReplaceErrorValues`/`SplitColumn` đã sẵn).
- [x] **T022** `Sources/BIPro/Query/Editor/` (`QueryRibbonCommand.swift`, `QueryRibbonView.swift`, `QueryEditorWindow.swift`, `QueryCommandPopovers.swift`) — Nối đủ 5 nhóm biến đổi mới vào Ribbon Query Editor (Tách cột nâng cao, Điền xuống/lên, Thay thế lỗi, Trích xuất văn bản, Biến đổi Ngày/Giờ), song ngữ Việt/Anh & Dark Mode.
- [x] **T023** `Tests/MEngineTests/V11BMTransformsTests.swift` *(mới)* & `Tests/BIProTests/V11BRefreshAndRenameTests.swift` *(mới)* — Kiểm thử end-to-end Refresh CSV (giữ quan hệ/measure/visual, lưu T3 mở lại, chịu lỗi mất file), Cascade Rename bảng/cột/measure + Undo, và toàn bộ phép biến đổi Power Query mới.

---

## Nhánh 5 — Nghiệm thu, Cổng Desktop 2.159 & Đóng gói Release

- [x] **T024** `Tests/BIProTests/Edit/V11BGatePBIXTests.swift` *(mới)* — Tạo tệp kiểm chứng `build/v11-out/bipro-v11b-gate.pbix` tích hợp đầy đủ Đợt 3 → mở kiểm chứng trên **Power BI Desktop 2.159 (VM Windows 11)** (0 cảnh báo hỏng/lỗi trường/lỗi tài nguyên, `VISIBLE_WINDOWS_COUNT: 1`), lưu ảnh cắt vùng canvas sạch tài khoản vào `docs/phase-v11-evidence/vm-v11b/gate-desktop.png`, đóng Desktop & dọn sạch VM (`SC-001`).
- [x] **T025** Chạy toàn bộ bộ kiểm thử không hồi quy & đóng gói phát hành:
  - `swift test --no-parallel`: **2 466 / 2 466 qua** (190,26 s, 0 lỗi)
  - `BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --no-parallel`: **119 / 119 qua** (164,56 s, 0 lỗi)
  - `zsh scripts/build-app.sh release` + `codesign --verify --deep --strict "build/BI Pro.app"`: **ĐẠT** (`195,23 s`).
- [x] **T026** Cập nhật `specs/014-v11-tinh-nang-nang-cao/tasks.md` (`[x]`), `specs/014-v11-tinh-nang-nang-cao/measurements.md`, `docs/STATE.md` và `docs/BIPRO_BUILD_PLAN.md`; báo cáo kết quả và chờ người dùng xác nhận commit.
