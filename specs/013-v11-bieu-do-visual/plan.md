# Kế hoạch kỹ thuật: Đợt 2 (v1.1a) — Hoàn thiện Hệ Biểu đồ, Slicer nâng cao & Phần tử chèn

**Spec:** `specs/013-v11-bieu-do-visual/spec.md`
**Bằng chứng Desktop:** `docs/phase-v11-evidence/vm-v11a/QUAN-SAT.md` (32 tệp JSON PBIR 2.14.0 + 2 ảnh cắt)
**Ngày lập:** 2026-11-21
**Trạng thái:** Chờ duyệt (Cổng duyệt 2 — `plan.md`)

---

## 1. Kiểm tra Hiến pháp (Constitution Check)

| Nguyên tắc | Đánh giá | Cách bảo đảm trong kế hoạch này |
|---|---|---|
| **I. Quan sát Power BI trước** | ✅ Đạt | Toàn bộ `visualType`, tên ô well, `active`, `sortDefinition`, `objects`, kích thước mặc định lấy từ `VM-V11A` (`QUAN-SAT.md`). |
| **II. Power BI là chuẩn golden** | ✅ Đạt | Mọi visual dữ liệu đi qua `VisualQuerySpecReader → DAXQueryBuilder → DAXEngine → DataViewMapper`, không tạo đường tính thứ hai. Có gate mở `.pbix` sinh ra trong Power BI Desktop 2.159 trên VM (SC-001). |
| **III. Native macOS, không thư viện ngoài** | ✅ Đạt | 100% SwiftUI + Canvas + Swift Charts + CoreGraphics; bản đồ dùng ranh giới địa lý tích hợp ngoại tuyến (`usa.states.topo` + world/country centroids nội bộ), **không** thêm package ngoài. |
| **IV. Ranh giới dữ liệu & mạng** | ✅ Đạt | Bản đồ & mọi visual chạy 100% ngoại tuyến, không gọi tile server/Bing/MapKit online; chỉ đọc tệp gốc trong `~/Downloads`; tệp thử nghiệm ra `build/v11-out/`. |
| **V. Hợp đồng trước, ranh giới rõ** | ✅ Đạt | Đợt 0 chốt `DataView` mới (`table`, `scatter`, `gauge`, `kpi`, `multiRowCard`), `SlicerSelection` mở rộng (`range`, `searchText`), và `PBIRNewVisual`; renderer chỉ đọc `DataView` + `VisualRenderContext`. |

---

## 2. Kiến trúc & Các mô-đun chạm tới

### 2.1 Tầng PBIXKit (Tạo mới, Chèn tài nguyên & Lưu T1)
- **[PBIRNewVisual.swift](file:///Users/macprom114/Desktop/PowerBINative/Sources/PBIXKit/Writing/PBIRNewVisual.swift):**
  - Mở rộng `sizes` và `makeJSON` cho đủ 17 loại mới từ `VM-V11A`:
    - `barChart`, `hundredPercentStackedBarChart`, `pieChart`, `tableEx`, `scatterChart`, `gauge`, `kpi`, `advancedSlicerVisual`, `listSlicer`, `textSlicer`, `map`, `filledMap` (mặc định `616×380` hoặc theo bảng cỡ chuẩn Desktop; riêng slicer `300×240`, gauge/kpi `360×240`).
    - Phần tử chèn có `"howCreated": "InsertVisualButton"`:
      - `shape` (`280×280`, mặc định `objects.shape[0].tileShape = "'rectangle'"`, `rotation[0].shapeAngle = "0L"` — nhận tham số `shapeKind`: `'rectangle'`, `'oval'`, `'line'`).
      - `pageNavigator` (`1000×50`).
      - `bookmarkNavigator` (`600×50`).
      - `actionButton` (`100×40`, `icon[0]{shapeType: "'blank'", selector: {id: "default"}}`).
      - `image` (`320×240`, `objects.general[0].properties.imageUrl` trỏ `ResourcePackageItem` trong `RegisteredResources`).
- **[PBIRResourcePatch.swift](file:///Users/macprom114/Desktop/PowerBINative/Sources/PBIXKit/Writing/PBIRResourcePatch.swift):**
  - Bổ sung hàm thêm mục ảnh mới (`addingRegisteredImage(name:path:to:)`) vào `resourcePackages` của `report.json` (đối xứng với phần dọn tài nguyên đã có) + ghi byte ảnh vào `Report/StaticResources/RegisteredResources/<file>` trong `PBIXChanges`.
- **[PBIRQueryPatch.swift](file:///Users/macprom114/Desktop/PowerBINative/Sources/PBIXKit/Writing/PBIRQueryPatch.swift):**
  - Tôn trọng quy tắc `active: true` theo từng loại visual từ `VM-V11A`: **không** gắn `"active": true` cho cột trong `tableEx`, `kpi`, `advancedSlicerVisual`, `listSlicer`, `textSlicer`; giữ `"active": true` cho `barChart`, `hundredPercentStackedBarChart`, `pieChart`, `scatterChart`, `slicer`, `map`, `filledMap`.
  - Khi thêm cột số hoặc cột ngày vào `slicer` cổ điển chưa có `objects.data`, tự thêm `objects.data[0].properties.mode = "'Between'"` như Desktop (`pop-slicer.visual.json`).

### 2.2 Tầng Hợp đồng truy vấn & Dữ liệu Visual (`Sources/BIPro/Visuals/Query/` & `Interaction/`)
- **[DataView.swift](file:///Users/macprom114/Desktop/PowerBINative/Sources/BIPro/Visuals/Query/DataView.swift):**
  - Mở rộng `enum DataView` thêm 5 biến thể sạch (chi tiết trong `data-model.md`):
    - `.table(TableDataView)` — dùng cho `tableEx` (danh sách `columns: [FieldInfo]`, `rows: [[DataCell]]`, `totals: [DataCell]?`, `isReduced: Bool`).
    - `.scatter(ScatterData)` — dùng cho `scatterChart` (`categoryField`, `seriesField`, `xField`, `yField`, `sizeField`, `points: [ScatterPoint]`, `isReduced`).
    - `.gauge(GaugeData)` — dùng cho `gauge` (`valueField`, `value`, `min`, `max`, `target`).
    - `.kpi(KPIData)` — dùng cho `kpi` (`indicatorField`, `trendField`, `goalField`, `latestValue`, `goalValue`, `trendPoints: [(label, value)]`).
    - `.multiRowCard(MultiRowCardData)` — dùng cho `multiRowCard` (`fields: [FieldInfo]`, `rows: [[DataCell]]`).
- **[VisualQuerySpec.swift](file:///Users/macprom114/Desktop/PowerBINative/Sources/BIPro/Visuals/Query/VisualQuerySpec.swift), [VisualQuerySpecReader.swift](file:///Users/macprom114/Desktop/PowerBINative/Sources/BIPro/Visuals/Query/VisualQuerySpecReader.swift), [DAXQueryBuilder.swift](file:///Users/macprom114/Desktop/PowerBINative/Sources/BIPro/Visuals/Query/DAXQueryBuilder.swift), [DataViewMapper.swift](file:///Users/macprom114/Desktop/PowerBINative/Sources/BIPro/Visuals/Query/DataViewMapper.swift):**
  - Mở rộng `QueryShape` thêm `.table`, `.scatter`, `.gauge`, `.kpi`, `.multiRowCard`.
  - `VisualQuerySpecReader`:
    - `tableEx`: tách projection trong `Values` thành cột nhóm (`primary`) và measure (`measures`), giữ đúng thứ tự hiển thị ban đầu `columnOrder`, bật `rowTotals = true` để sinh thêm dòng tổng `Total` (trừ khi Format tắt).
    - `scatterChart`: đọc `Category`, `Series`, và các vai measure/gộp `X`, `Y`, `Size`, `Tooltips`.
    - `gauge`: đọc `Y`, `MinValue`, `MaxValue`, `TargetValue`, `Tooltips` (tất cả dạng scalar `SUMMARIZECOLUMNS` như card).
    - `kpi`: đọc `TrendLine` (cột trục thời gian sắp tăng dần), `Indicator` (measure chính), `Goal` (measure mục tiêu).
    - `multiRowCard`: đọc `Values` (cột + measure).
    - `advancedSlicerVisual`, `listSlicer`, `textSlicer`: dùng `.slicer(top: 501)` giống slicer; riêng `slicer` chế độ `'Between'` chạy thêm `MIN`/`MAX` của cột để lấy biên toàn miền `[domainMin, domainMax]`.
    - `map`, `filledMap`: đọc `Category` (Location), `Series`, `Size`/`Y`/`Value`, `Tooltips`.
- **[InteractionTypes.swift](file:///Users/macprom114/Desktop/PowerBINative/Sources/BIPro/Visuals/Interaction/InteractionTypes.swift) & [FilterTranslator.swift](file:///Users/macprom114/Desktop/PowerBINative/Sources/BIPro/Visuals/Interaction/FilterTranslator.swift) & [ReportInteraction.swift](file:///Users/macprom114/Desktop/PowerBINative/Sources/BIPro/Report/ReportInteraction.swift):**
  - Mở rộng `SlicerSelection` thêm `range: SlicerRange? = nil` (`min: Value?`, `max: Value?`) và `searchText: String? = nil` (`isEmpty` kiểm cả 3 trường).
  - `FilterTranslator` chuyển `range` thành biểu thức DAX `>= min && <= max` (số & `DATE(...)`) và `searchText` thành `CONTAINSSTRING(col, "...")`.

### 2.3 Tầng Renderer Visual (`Sources/BIPro/Visuals/`)
1. **Nhóm 2A (cập nhật renderer sẵn có):**
   - `CartesianChart.swift`: thêm `.stackedBar` (`"barChart"`, `"stackedBarChart"`) và `.hundredPercentStackedBar` (`"hundredPercentStackedBarChart"`), vẽ thanh ngang xếp chồng & chuẩn hoá 0–100% tái dùng `StackLayout` + trục ngang `BarMark`.
   - `DonutChart.swift`: thêm tham số `isPie: Bool = false`; khi `isPie == true`, vẽ hình tròn đặc (`innerRadius = 0`), không vẽ chữ tâm, giữ nguyên nhãn callout + legend + hover + lọc chéo.
2. **Nhóm 2B (5 tệp renderer mới trong `Sources/BIPro/Visuals/`):**
   - `Matrix/TableVisual.swift` (`TableVisualView` + `TableSortState`): bảng phẳng SwiftUI/LazyVStack (hoặc vẽ tĩnh khi `isExporting`), bấm tiêu đề cột để sắp xếp tăng/giảm, căn phải cho số / căn trái cho chữ, dòng `Total` in đậm ghim cuối bảng, bấm dòng để lọc chéo.
   - `Charts/ScatterChart.swift` (`ScatterChartView` + `ScatterLayout`): trục X/Y số tự chia vạch (`ChartAxis.fittingTicks`), điểm tròn với bán kính tỉ lệ `Size` (hoặc đồng nhất khi không có `Size`), tô màu theo `Series` + chú giải + tooltip + lọc chéo.
   - `Charts/GaugeVisual.swift` (`GaugeVisualView` + `GaugeLayout`): cung bán nguyệt 180° (`Path.addArc`), màu cung theo `theme.dataColors[0]`, nền xám nhạt, `min = data.min ?? 0`, `max = data.max ?? (value * 2)` (khớp `VM-V11A`), vạch đích `target` đậm + nhãn, số lớn ở tâm và nhãn Min/Max hai đầu.
   - `Cards/KPIVisual.swift` (`KPIVisualView` + `KPILayout`): vùng sparkline mờ phía sau từ `trendPoints`, giá trị mới nhất cỡ lớn ở tâm (tô `theme.good` / `theme.bad` khi so với `goalValue`), dòng mục tiêu `Goal: ... (+X.X%)` ở dưới.
   - `Cards/MultiRowCardVisual.swift` (`MultiRowCardView`): danh sách thẻ hàng có đường nhấn dọc trái (`theme.dataColors[0]`), mỗi thẻ hiển thị cặp nhãn/giá trị rõ ràng.
3. **Nhóm 2C (Slicer nâng cao & Bản đồ ngoại tuyến):**
   - `Slicer/AdvancedSlicers.swift`:
     - `TileSlicerView` (`advancedSlicerVisual`): lưới nút bo góc thích ứng chiều rộng (`LazyVGrid`), đổi màu nền/viền khi được chọn.
     - `ListSlicerView` (`listSlicer`): danh sách chọn trực tiếp không cần mở dropdown.
     - `TextSlicerView` (`textSlicer`): ô nhập chữ + nút `→` áp dụng + nút `×` xoá lọc.
     - `RangeSlicerView` (`slicer` chế độ `'Between'`): hai ô nhập Min/Max + thanh trượt 2 đầu tự vẽ bằng SwiftUI `DragGesture` hỗ trợ cả số (`Int`/`Double`) lẫn ngày (`Date`).
   - `Map/GeoMapView.swift` & `Map/OfflineGeoAtlas.swift`:
     - Tích hợp sẵn toạ độ trung tâm & đường biên nhẹ cho 50 bang Hoa Kỳ (tái dùng `AlbersUSA`/`TopoJSON` có sẵn khi file có `usa.states.topo` hoặc fallback bảng toạ độ 50 bang + các quốc gia/khu vực phổ biến hoàn toàn ngoại tuyến).
     - `map`: vẽ khung bản đồ nền sạch + bong bóng tỉ lệ theo `Size`, tô màu theo `Series`, tooltip + lọc chéo.
     - `filledMap`: tô màu vùng địa lý theo thang bão hoà hoặc `Series` (tái dùng `ShapeMapView` khi là bản đồ Mỹ có ranh giới bang).
4. **Nhóm 2D (Phần tử chèn & Format):**
   - `ReportCanvas.swift`: thêm `BookmarkNavigatorVisual` (đối xứng `PageNavigatorVisual`), nâng cấp `ShapeVisual` hỗ trợ `rectangle`, `oval`, `line` và thuộc tính màu tô/viền/góc bo/góc xoay; cập nhật `VisualContentView.liveTypes` bao gồm toàn bộ loại mới.
   - `Shell/Ribbon.swift`: mở khoá các nút trên tab **Chèn (Insert)**: *Hình khối* (menu Chữ nhật / Elip / Đường thẳng), *Nút* (Nút trống / Điều hướng trang / Điều hướng bookmark), *Ảnh…* (mở `NSOpenPanel` chọn PNG/JPEG/SVG).
   - `Report/Edit/FormatCatalog.swift`: bổ sung thẻ định dạng cho `shape` (màu tô, viền, góc bo), `actionButton` (loại hành động Điều hướng trang / Bookmark + đích chọn), và bổ sung danh mục cơ bản cho các chart mới (`barChart`, `pieChart`, `tableEx`, `gauge`, `kpi`, `scatterChart`).

### 2.4 Tầng Authoring, Export & Trợ năng
- `VisualCatalog.swift`, `VisualTypes.swift`, `WellRules.swift`, `TypeChange.swift`, `LayoutEditor.swift`:
  - Đổi loại `stackedBarChart` trong gallery Build pane thành `"barChart"` (kèm `VisualCatalog.matches` ghép `"stackedBarChart"` và `"barChart"`), cập nhật `WellRules.observed` cho đủ 13 loại có dữ liệu, cập nhật `defaultSortRole` khớp `VM-V11A` (`barChart`, `hundredPercentStackedBarChart`, `pieChart`, `gauge` tự sắp; `tableEx`, `scatterChart`, `kpi`, các slicer & map không tự sắp).
- `VisualCSVExporter.swift`: hỗ trợ xuất CSV chuẩn RFC 4180 + UTF-8 BOM cho cả 5 `DataView` mới (`.table`, `.scatter`, `.gauge`, `.kpi`, `.multiRowCard`).
- `AccessibilitySummary.swift` & `L10n.swift`: bổ sung mô tả VoiceOver song ngữ Việt/Anh cho tất cả loại visual & `DataView` mới.

---

## 3. Chiến lược kiểm thử & Gate Power BI Desktop (SC-001 .. SC-005)

1. **Unit tests theo `/tdd` (từng nhóm 2A → 2D):**
   - `PBIRNewVisualTests` & `WellRulesTests`: đối chiếu JSON sinh ra với 32 tệp mẫu trong `docs/phase-v11-evidence/vm-v11a/json/`.
   - `TableVisualTests`, `ScatterGaugeKPITests`, `AdvancedSlicersTests`, `InsertElementsTests`: kiểm toán layout thuần (cung Gauge `2×`, tổng bảng `Total`, điểm Scatter, KPI sparkline + % mục tiêu, `FilterTranslator` cho `Between` & `CONTAINSSTRING`).
   - Mở rộng `ExportCSVTests`, `AccessibilitySummaryTests`, `VisualRegressionAndBilingualQATests`: phủ đủ 100% loại visual mới (PNG không rỗng, CSV khớp DAX, VoiceOver song ngữ).
2. **Gate mở trong Power BI Desktop trên VM Windows 11 (SC-001):**
   - Sinh 1 tệp `build/v11-out/bipro-v11a-gate.pbix` (từ bản sao `Nhom6_work.pbix`) chứa 1 trang mới với đầy đủ: `barChart`, `hundredPercentStackedBarChart`, `pieChart`, `tableEx`, `scatterChart`, `gauge`, `kpi`, `advancedSlicerVisual`, `listSlicer`, `textSlicer`, numeric `Between` slicer, `shape`, `pageNavigator`, `bookmarkNavigator`, `actionButton`, `image`.
   - Mở trực tiếp trong Power BI Desktop 2.159 trên VM, xác minh **0 lỗi hỏng tệp**, chụp ảnh đối chiếu (cắt sạch vùng canvas) vào `docs/phase-v11-evidence/vm-v11a/gate-desktop.png`, rồi đóng Desktop & dọn VM.
3. **Không hồi quy:** `swift test --no-parallel`, bộ golden nặng release, `zsh scripts/build-app.sh release` + `codesign --verify --deep --strict`.
