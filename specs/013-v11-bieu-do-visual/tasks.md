# Nhiệm vụ: Đợt 2 (v1.1a) — Hoàn thiện Hệ Biểu đồ, Slicer nâng cao & Phần tử chèn

**Spec:** `specs/013-v11-bieu-do-visual/spec.md` | **Plan:** `specs/013-v11-bieu-do-visual/plan.md` | **Data model:** `specs/013-v11-bieu-do-visual/data-model.md`
**Bằng chứng Desktop:** `docs/phase-v11-evidence/vm-v11a/QUAN-SAT.md` (32 tệp JSON PBIR 2.14.0) & `gate-desktop.png` (19/19 visual đạt trên Desktop 2.159)
**Định dạng:** `- [x] Txxx [USn?] Mô tả (tệp)`. Triển khai trực tiếp theo `/tdd`.

Điều kiện chung:
- Không thêm thư viện ngoài (Hiến pháp III), không tải từ mạng (Hiến pháp IV).
- Tệp gốc trong `~/Downloads` chỉ đọc; tệp xuất test vào `build/v11-out/` (ngoài git); bằng chứng vào `docs/phase-v11-evidence/vm-v11a/`.
- Mọi nhãn UI mới song ngữ `vi`/`en` (`bi(_:_:)` / `L10n`), tương thích Dark Mode (`DS.Palette`), Report Canvas giữ nền tài liệu sáng `.pbix`.

---

## Giai đoạn 1: Đợt 0 — Hợp đồng, PBIR & Luật tạo mới

- [x] T001 `Sources/PBIXKit/Writing/PBIRNewVisual.swift` + `Tests/PBIXKitTests/Write/PBIRNewVisualV11Tests.swift`:
  - Mở rộng `sizes` & `makeJSON` cho đủ 17 loại visual mới theo `VM-V11A` (`barChart`, `hundredPercentStackedBarChart`, `pieChart`, `tableEx`, `scatterChart`, `gauge`, `kpi`, `advancedSlicerVisual`, `listSlicer`, `textSlicer`, `map`, `filledMap`, `shape`, `pageNavigator`, `bookmarkNavigator`, `actionButton`, `image`).
  - Hỗ trợ `shapeKind` (`rectangle`/`oval`/`line`) và `"howCreated": "InsertVisualButton"` khớp nguyên văn `insert-*.visual.json`.
- [x] T002 `Sources/PBIXKit/Writing/PBIRResourcePatch.swift`, `Sources/PBIXKit/Writing/PBIXWriter.swift` + `Tests/PBIXKitTests/Write/PBIRNewVisualV11Tests.swift`:
  - Thêm `addingRegisteredImage(name:path:to:)` chèn mục `Image` vào `resourcePackages` (`RegisteredResources`) của `report.json` bằng ghép byte.
  - Bổ sung `PBIXWriter.addingMissingExtensions(_:to:)` tự khai báo `<Default Extension="..." ContentType="" />` trong `[Content_Types].xml` khi nhúng phần mở rộng ảnh mới (`.png`, `.jpg`...) — phát hiện và xác minh trực tiếp qua cổng Power BI Desktop 2.159.
- [x] T003 `Sources/PBIXKit/Writing/PBIRQueryPatch.swift`, `Sources/BIPro/Report/Edit/FieldEditor.swift`, `Sources/BIPro/Report/Edit/LayoutEditor.swift` + test:
  - Áp quy tắc `"active": true` khớp `VM-V11A` (không gắn `active` cho cột trong `tableEx`, `multiRowCard`, `kpi`, `advancedSlicerVisual`, `listSlicer`, `textSlicer`).
  - Khi thêm cột số/ngày vào `slicer` cổ điển chưa có `objects.data`, ghi `objects.data[0].properties.mode = "'Between'"` khớp `pop-slicer.visual.json`.
- [x] T004 `Sources/BIPro/Visuals/Query/DataView.swift` & `Sources/BIPro/Visuals/Interaction/InteractionTypes.swift`:
  - Thêm 5 biến thể `DataView` (`.table(TableDataView)`, `.scatter(ScatterData)`, `.gauge(GaugeData)`, `.kpi(KPIData)`, `.multiRowCard(MultiRowCardData)`).
  - Mở rộng `SlicerData` (`domainRange`, `isDateColumn`) và `SlicerSelection` (`range: SlicerRange?`, `searchText: String?`).
- [x] T005 `Sources/BIPro/Panes/VisualCatalog.swift`, `Sources/BIPro/Report/Edit/VisualTypes.swift`, `Sources/BIPro/Report/Edit/WellRules.swift`, `Sources/BIPro/Report/Edit/TypeChange.swift`, `Sources/BIPro/Report/Edit/LayoutEditor.swift`, `Sources/BIPro/Visuals/Interaction/InteractionRules.swift` + test:
  - Chuyển slot Stacked bar sang `"barChart"` (kèm `VisualCatalog.matches` nhận cả `"stackedBarChart"`).
  - Đổi `WellRules.observed` sang `accepts: Set<WellKind>` và điền đủ 13 loại visual dữ liệu từ `VM-V11A`.
  - Cập nhật `VisualTypes.supported` (40 loại), `defaultSortRole`, `TypeChange`, và `InteractionRules`.

---

## Giai đoạn 2: US1 (Nhóm 2A) — Thanh xếp chồng, Thanh 100% & Biểu đồ tròn

- [x] T006 [US1] `Sources/BIPro/Visuals/Charts/CartesianChart.swift` + `Tests/BIProTests/Charts/StackedBarAndPieTests.swift`:
  - Thêm `.stackedBar` (`"barChart"`, `"stackedBarChart"`) và `.hundredPercentStackedBar` (`"hundredPercentStackedBarChart"`) vào `CartesianKind`, vẽ thanh ngang xếp chồng & chuẩn hoá 0–100% với trục X, nhãn dữ liệu, hover và lọc chéo.
- [x] T007 [US1] `Sources/BIPro/Visuals/Charts/DonutChart.swift`, `Sources/BIPro/Report/LiveVisual.swift`, `Sources/BIPro/Report/ReportCanvas.swift` + test:
  - Thêm `isPie: Bool = false` vào `DonutChartView` (`innerRadius = 0`, bỏ chữ tâm khi là `pieChart`); nối `barChart`, `stackedBarChart`, `hundredPercentStackedBarChart`, `pieChart` vào `VisualContentView.liveTypes` và `LiveVisualView`.

---

## Giai đoạn 3: US2 (Nhóm 2B) — Biểu đồ phân tích cốt lõi

- [x] T008 [US2] `Sources/BIPro/Visuals/Query/VisualQuerySpec.swift`, `VisualQuerySpecReader.swift`, `DAXQueryBuilder.swift`, `DataViewMapper.swift` + `Tests/BIProTests/VisualQuery/NewVisualQueryTests.swift`:
  - Hỗ trợ `QueryShape` `.table`, `.scatter`, `.gauge`, `.kpi`, `.multiRowCard`; mở rộng `roleOrder` thêm `X`, `Size`, `MinValue`, `MaxValue`, `TargetValue`, `Indicator`, `Goal`.
  - Sinh DAX chuẩn, chạy thật qua `DAXEngine` và ánh xạ đúng `DataView` (gồm dòng `Total` của `tableEx`, tổng scalar cho `gauge`, chuỗi tăng dần theo `TrendLine` cho `kpi`, toạ độ X/Y/Size cho `scatterChart`).
- [x] T009 [US2] `Sources/BIPro/Visuals/Matrix/TableVisual.swift` + `Tests/BIProTests/Charts/ScatterGaugeKPITests.swift`:
  - Dựng `TableVisualView`: tiêu đề cột bấm để sắp xếp tăng/giảm, căn lề theo kiểu dữ liệu, cuộn dọc/ngang (tắt cuộn khi `isExporting`), dòng `Total` in đậm ở cuối, bấm dòng lọc chéo.
- [x] T010 [US2] `Sources/BIPro/Visuals/Charts/ScatterChart.swift` + `Tests/BIProTests/Charts/ScatterGaugeKPITests.swift`:
  - Dựng `ScatterChartView` + `ScatterLayout`: trục X/Y tự chia vạch (`ChartAxis.niceTicks`), bán kính bong bóng theo `Size`, tô màu theo `Series` + chú giải, dải 1D khi chỉ có `X`, tooltip và lọc chéo.
- [x] T011 [US2] `Sources/BIPro/Visuals/Charts/GaugeVisual.swift` + test trong `ScatterGaugeKPITests.swift`:
  - Dựng `GaugeVisualView` + `GaugeLayout`: cung bán nguyệt 180°, mặc định `min = 0` và `max = 2 × value` (`VM-V11A`), vạch đích `target` đậm + nhãn, số lớn ở tâm và nhãn Min/Max hai đầu.
- [x] T012 [US2] `Sources/BIPro/Visuals/Cards/KPIVisual.swift` & `Sources/BIPro/Visuals/Cards/MultiRowCardVisual.swift` + test trong `ScatterGaugeKPITests.swift`:
  - `KPIVisualView`: vùng sparkline mờ phía sau từ `trendPoints`, giá trị điểm mới nhất lớn ở giữa (màu `good`/`bad` theo `goalValue`), dòng mục tiêu & % chênh lệch.
  - `MultiRowCardView`: lưới/danh sách thẻ nhiều hàng với vạch nhấn bên trái.
- [x] T013 [US2] Nối `tableEx`, `scatterChart`, `gauge`, `kpi`, `multiRowCard` vào `Sources/BIPro/Report/LiveVisual.swift` và `Sources/BIPro/Report/ReportCanvas.swift` (`liveTypes`).

---

## Giai đoạn 4: US3 (Nhóm 2C) — Slicer nâng cao & Bản đồ ngoại tuyến

- [x] T014 [US3] `Sources/BIPro/Visuals/Interaction/FilterTranslator.swift`, `Sources/BIPro/Report/ReportInteraction.swift`, `Sources/BIPro/Visuals/Query/VisualDataLoader.swift` + `Tests/BIProTests/Slicer/AdvancedSlicersTests.swift`:
  - Dịch `SlicerRange` (`min`/`max`) sang bộ lọc DAX `>= min && <= max` (số & ngày) và `searchText` sang `CONTAINSSTRING`.
  - Nạp `domainRange` (`MIN`/`MAX`) cho `slicer` ở chế độ `'Between'`.
- [x] T015 [US3] `Sources/BIPro/Visuals/Slicer/AdvancedSlicers.swift` + nối `LiveVisual.swift` & `ReportCanvas.swift` + test trong `AdvancedSlicersTests.swift`:
  - `TileSlicerView` (`advancedSlicerVisual`), `ListSlicerView` (`listSlicer`), `TextSlicerView` (`textSlicer`), và `RangeSlicerView` (`slicer` `'Between'` với 2 ô nhập + thanh trượt 2 đầu cho số và ngày).
- [x] T016 [US3] `Sources/BIPro/Visuals/Map/OfflineGeoAtlas.swift` & `Sources/BIPro/Visuals/Map/GeoMapView.swift` + nối `LiveVisual.swift` & `ReportCanvas.swift` + `Tests/BIProTests/Map/GeoMapTests.swift`:
  - Bảng toạ độ 50 bang Mỹ + DC & 50+ quốc gia/khu vực phổ biến 100% ngoại tuyến; `map` vẽ bong bóng tỉ lệ theo `Size` & màu theo `Series`; `filledMap` tô màu vùng địa lý (tái dùng `ShapeMapView` khi là ranh giới bang Mỹ hoặc vẽ vùng ngoại tuyến), hỗ trợ tooltip & lọc chéo.

---

## Giai đoạn 5: US4 (Nhóm 2D) — Phần tử chèn báo cáo & Format

- [x] T017 [US4] `Sources/BIPro/Report/ReportCanvas.swift`:
  - Thêm `BookmarkNavigatorVisual` (liệt kê bookmark, bấm áp bookmark ngay ở chế độ Xem, tô đậm bookmark đang hoạt động).
  - Nâng cấp `ShapeVisual` hỗ trợ đầy đủ `rectangle`, `oval`, `line`, màu tô, viền, bo góc và góc xoay (`shapeAngle`).
- [x] T018 [US4] `Sources/BIPro/Report/Edit/LayoutEditor.swift`, `Sources/BIPro/Report/Edit/LayoutEditor+Resources.swift`, `Sources/BIPro/Workspace.swift`, `Sources/BIPro/DocumentState.swift`, `Sources/BIPro/Shell/Ribbon.swift` + `Tests/BIProTests/Edit/InsertElementsTests.swift`:
  - Mở khoá nút trên tab **Chèn (Insert)** (song ngữ `vi`/`en`): *Trang mới*, *Hình khối* (`rectangle`/`oval`/`line`), *Nút* (`actionButton` trống, `pageNavigator`, `bookmarkNavigator`), *Ảnh…* (mở `NSOpenPanel` chọn PNG/JPEG/SVG, nhúng `RegisteredResources` + `PBIRResourcePatch`, hỗ trợ ⌘Z/⇧⌘Z và lưu T1).
- [x] T019 [US4] `Sources/BIPro/Report/Edit/FormatCatalog.swift` + test:
  - Bổ sung danh mục định dạng cho `shape` (kiểu hình, màu tô, viền, bo góc, xoay), `actionButton` (thẻ `visualLink` trong phạm vi `.container`), và các chart mới (`barChart`, `stackedBarChart`, `hundredPercentStackedBarChart`, `pieChart`, `tableEx`, `scatterChart`, `gauge`, `kpi`).

---

## Giai đoạn 6: Export, VoiceOver, Kiểm thử, Gate VM Desktop & Đóng gói

- [x] T020 `Sources/BIPro/Export/VisualCSVExporter.swift` + `Tests/BIProTests/PhaseG/ExportCSVTests.swift`:
  - Hỗ trợ xuất CSV chuẩn RFC 4180 + UTF-8 BOM cho đủ 5 `DataView` mới (`.table`, `.scatter`, `.gauge`, `.kpi`, `.multiRowCard`).
- [x] T021 `Sources/BIPro/Report/AccessibilitySummary.swift` & `Sources/BIPro/Settings/L10n.swift` + `Tests/BIProTests/PhaseG/AccessibilitySummaryTests.swift`:
  - Bổ sung nhãn & giá trị VoiceOver song ngữ Việt/Anh cho tất cả loại visual mới.
- [x] T022 `Tests/BIProTests/QA/VisualRegressionAndBilingualQATests.swift`:
  - Mở rộng test hồi quy vẽ ảnh (không trống, đủ sắc độ, hợp lệ PNG) cho toàn bộ 12 `CartesianKind` và 12 renderer mới của v1.1a (2A–2D).
- [x] T023 **Gate Power BI Desktop trên VM Windows 11 (SC-001):**
  - Sinh `build/v11-out/bipro-v11a-gate.pbix` (`Tests/BIProTests/Edit/V11AGatePBIXTests.swift`, 19 visual đủ 4 nhóm 2A–2D trên trang `v1.1a Gate`).
  - Mở trên Power BI Desktop 2.159 trong VM Windows 11: **0 lỗi hỏng tệp**, toàn bộ 19 visual (gồm ảnh PNG nhúng qua `RegisteredResources`) vẽ đúng dữ liệu & bố cục; lưu ảnh cắt sạch tại `docs/phase-v11-evidence/vm-v11a/gate-desktop.png`, đã đóng Desktop & dọn VM.
- [x] T024 Hoàn thiện: toàn bộ `swift test --no-parallel` (2 444/2 444 qua), bộ golden nặng release (112/112 qua), đóng gói `build/BI Pro.app` release (`codesign --verify --deep --strict` đạt), ghi số đo vào `specs/013-v11-bieu-do-visual/measurements.md` và cập nhật `docs/STATE.md` + `docs/BIPRO_BUILD_PLAN.md`.
