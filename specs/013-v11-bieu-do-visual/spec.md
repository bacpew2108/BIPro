# Đặc tả tính năng: Đợt 2 (v1.1a) — Hoàn thiện Hệ Biểu đồ, Slicer nâng cao & Phần tử chèn

**Nhánh / Thư mục spec:** `specs/013-v11-bieu-do-visual/`
**Ngày tạo:** 2026-11-21
**Trạng thái:** Chờ duyệt (Cổng duyệt 1 — `spec.md`)
**Tài liệu cấp trên:** `docs/BIPRO_BUILD_PLAN.md`, `docs/STATE.md`
**Bằng chứng quan sát:** `docs/phase-v11-evidence/vm-v11a/QUAN-SAT.md` (28 tệp JSON nguyên văn + 2 ảnh cắt Desktop 2.159)

---

## 1. Quan sát Power BI (VM-V11A)

Toàn bộ tên loại visual, tên ô trường (`queryState`), quy tắc `active`/`sortDefinition`, kích thước mặc định và `objects` đều được lấy trực tiếp từ **Power BI Desktop 2.159** trong buổi quan sát `VM-V11A` (`docs/phase-v11-evidence/vm-v11a/QUAN-SAT.md`), không suy đoán:

1. **Thanh xếp chồng & 100% thanh & Biểu đồ tròn (Nhóm 2A):**
   - Stacked bar chart ghi `visualType: "barChart"` (chứ không phải `"stackedBarChart"`, tuy nhiên bộ đọc vẫn tương thích ngược với `"stackedBarChart"`).
   - 100% stacked bar chart ghi `"hundredPercentStackedBarChart"`; Pie chart ghi `"pieChart"`.
   - Cả ba nhận `Category` (`active: true`), `Y`, `Series`, `Tooltips`; tự thêm `sortDefinition` giảm dần theo `Y`.
   - `pieChart` vẽ hình tròn đặc (bán kính trong = 0), có nhãn callout (giá trị + %) và chú giải; `barChart` / `hundredPercentStackedBarChart` vẽ thanh ngang xếp chồng (và chuẩn hoá 0–100%).
2. **Biểu đồ phân tích cốt lõi (Nhóm 2B):**
   - **`tableEx` (Bảng phẳng):** nhận một ô duy nhất `Values` (trộn cột & measure, không có `active: true`, không `sortDefinition`); hiển thị bảng phẳng có tiêu đề cột, cuộn dọc/ngang, sắp xếp khi bấm tiêu đề, và **dòng `Total` in đậm ở cuối** cho các cột measure/số tổng hợp.
   - **`scatterChart` (Phân tán / Bong bóng):** các ô `Category` (Values), `Series` (Legend), `X`, `Y`, `Size`, `Tooltips`; không tự thêm `sortDefinition`. Vẽ trục X/Y số, điểm tròn (kích thước tỉ lệ theo `Size` nếu có, tô màu theo `Series` hoặc màu mặc định), hỗ trợ hover tooltip và lọc chéo.
   - **`gauge` (Đồng hồ đo):** các ô `Y` (Value), `MinValue`, `MaxValue`, `TargetValue`, `Tooltips`; tự thêm `sortDefinition` giảm dần theo `Y`. Vẽ cung bán nguyệt 180°, khi thiếu `MinValue` dùng `0`, khi thiếu `MaxValue` dùng **`2 × Value`** (đã quan sát `5,369 → 0K..11K`), vẽ vạch đích khi có `TargetValue`, hiển thị giá trị lớn ở tâm và nhãn Min/Max ở hai đầu cung.
   - **`kpi` (KPI):** các ô `Indicator` (Value), `TrendLine` (Trend axis), `Goal` (Target); không `sortDefinition`. Vẽ giá trị điểm mới nhất của `Indicator` (theo thứ tự `TrendLine`) thật lớn ở giữa, phía sau là biểu đồ vùng sparkline nền nhạt theo `TrendLine`, và dòng mục tiêu + % chênh lệch (xanh/đỏ theo theme `good`/`bad`) khi có `Goal`.
   - **`multiRowCard` (Thẻ nhiều hàng):** đọc & vẽ dữ liệu thật cho các tệp `.pbix` có `multiRowCard` (ô `Values`), hiển thị nhiều hàng thẻ có thanh nhấn bên trái.
3. **Slicer nâng cao & Bản đồ (Nhóm 2C):**
   - **`advancedSlicerVisual` (Button/Tile slicer):** ô `Values`, hiển thị lưới các nút bo góc cho phép chọn 1 hoặc nhiều giá trị, lọc chéo toàn trang như slicer cổ điển.
   - **`listSlicer` (List slicer):** ô `Values`, hiển thị danh sách chọn trực tiếp (checkbox/radio).
   - **`textSlicer` (Text slicer):** ô `Values`, hiển thị ô nhập văn bản tìm kiếm lọc chứa (`CONTAINSSTRING`) giá trị cột.
   - **Numeric & Date Range Slicer (`slicer` với `objects.data[0].properties.mode = "'Between'"`):** khi thả cột số hoặc cột ngày vào `slicer`, vẽ 2 ô Min/Max + thanh trượt 2 đầu (`1931..2007`), áp điều kiện khoảng `>= min AND <= max` vào bộ lọc trang.
   - **`map` & `filledMap`:** `map` nhận `Category`, `Size`, `Series`, `Tooltips`; `filledMap` nhận `Category`, `Series`, `Y`, `Tooltips`. Trên macOS vẽ bằng **bộ vẽ bản đồ địa lý native** (hỗ trợ toạ độ hoặc ánh xạ tên bang/quốc gia có sẵn ngoại tuyến như `usa.states.topo` + đường biên bản đồ thế giới/tọa độ, hoạt động 100% ngoại tuyến không tải từ mạng theo Hiến pháp IV).
4. **Phần tử chèn báo cáo (Nhóm 2D):**
   - Tất cả ghi `"howCreated": "InsertVisualButton"` ở cấp gốc `visual.json` và cho phép chèn từ tab Ribbon **Chèn (Insert)**:
   - **`shape`** (`280×280`, `objects.shape[0].tileShape = "'rectangle'"` / `'oval'` / `'line'`, `rotation[0].shapeAngle = "0L"`): vẽ hình chữ nhật/elip/đường thẳng với màu tô/viền/bo góc theo `objects` và sửa được trong Format pane.
   - **`pageNavigator`** (`1000×50`): thanh nút tự động liệt kê các trang hiển thị, bấm để chuyển trang ngay ở chế độ Xem.
   - **`bookmarkNavigator`** (`600×50`): thanh nút tự động liệt kê các bookmark của báo cáo, bấm để áp bookmark ngay ở chế độ Xem.
   - **`actionButton`** (`100×40`, `icon[0].shapeType = "'blank'"`): chèn nút trống mới và gắn hành động (Điều hướng trang / Bookmark / Quay lại) trong Format pane.
   - **`image`**: chèn tệp ảnh PNG/JPEG/SVG từ máy vào `Report/StaticResources/RegisteredResources/` + cập nhật `resourcePackages` trong `report.json` (tái dùng `PBIRResourcePatch`).

---

## 2. Câu chuyện người dùng & Kịch bản kiểm chứng

### Câu chuyện 1 (P1) — Mở khoá Thanh xếp chồng (`barChart`), Thanh 100% và Biểu đồ tròn (`pieChart`)
Người dùng đang ở chế độ Sửa (`⌘E`) chọn **Biểu đồ thanh xếp chồng**, **Thanh xếp chồng 100%**, hoặc **Biểu đồ tròn** từ Build pane (hoặc đổi loại từ biểu đồ khác sang) → gắn `Category`, `Y`, `Series` → thấy biểu đồ vẽ đúng ngay (thanh ngang xếp chồng / 100% / tròn đặc không lỗ), tương tác lọc chéo/tooltip, xuất CSV/PNG/PDF, và lưu `.pbix` mở được trong Power BI Desktop không lỗi.

- **Kịch bản chấp nhận:**
  1. Thêm mới `barChart` (từ biểu tượng Stacked bar), gắn `client_region` + `Total_Clients`: `visual.json` ghi đúng `"visualType": "barChart"`, `sortDefinition` giảm dần theo `Y`, thanh ngang xếp chồng đúng giá trị.
  2. Thêm mới `hundredPercentStackedBarChart` với `Category` + `Series` + `Y`: tổng mỗi thanh đạt 100%, trục X ghi `0%..100%`.
  3. Thêm mới `pieChart`: vẽ hình tròn đặc (innerRadius = 0), tỷ lệ góc và nhãn % khớp chính xác `DataView` DAX.
  4. Lưu `.pbix` và kiểm chứng mở trong Power BI Desktop trên VM (không báo hỏng, vẽ khớp).

### Câu chuyện 2 (P1) — Biểu đồ phân tích cốt lõi (`tableEx`, `scatterChart`, `gauge`, `kpi`, `multiRowCard`)
Người dùng mở báo cáo có sẵn hoặc tự tạo mới các visual **Bảng phẳng**, **Phân tán/Bong bóng**, **Đồng hồ đo**, **KPI**, **Thẻ nhiều hàng** → BI Pro sinh truy vấn DAX chuẩn, vẽ dữ liệu thật sắc nét (không còn placeholder), hỗ trợ tooltip, lọc chéo, xuất CSV/PNG/PDF, VoiceOver và lưu PBIR chuẩn Desktop.

- **Kịch bản chấp nhận:**
  1. `tableEx`: gắn 2 cột + 1 measure vào `Values` → hiển thị đủ cột, sắp xếp khi bấm tiêu đề, dòng `Total` cuối bảng khớp chính xác tổng của measure DAX (`5,369` trên `Dim_Client`).
  2. `scatterChart`: gắn `Category`, `X`, `Y`, `Size`, `Series` → vẽ đúng vị trí toạ độ X/Y, kích thước bong bóng theo `Size`, hover hiện tooltip đủ X/Y/Size, bấm điểm lọc chéo được các visual khác.
  3. `gauge`: gắn `Y` (không có Min/Max) → vẽ cung 180° từ `0` đến `2 × Value`, số trung tâm định dạng theo measure; gắn thêm `MinValue`/`MaxValue`/`TargetValue` → vẽ đúng vạch mục tiêu.
  4. `kpi`: gắn `Indicator` + `TrendLine` (+ `Goal`) → hiển thị giá trị điểm mới nhất của `TrendLine`, nền vùng sparkline phía sau, hiển thị Goal & % chênh lệch xanh/đỏ.
  5. `multiRowCard`: mở báo cáo chứa `multiRowCard` → vẽ đủ các thẻ hàng kèm giá trị thật từ DAX.

### Câu chuyện 3 (P2) — Slicer nâng cao (`advancedSlicerVisual`, `listSlicer`, `textSlicer`, Numeric/Date `Between`) & Bản đồ (`map`, `filledMap`)
Người dùng tạo hoặc mở báo cáo chứa **Tile slicer**, **List slicer**, **Text slicer**, **Slicer thanh trượt khoảng số/ngày (`Between`)**, hoặc **Bản đồ `map` / `filledMap`** → tương tác lọc thật toàn trang và vẽ bản đồ ngoại tuyến mượt mà.

- **Kịch bản chấp nhận:**
  1. `advancedSlicerVisual`: hiển thị lưới nút bo góc, bấm chọn/bỏ chọn lọc toàn bộ visual khác trên trang.
  2. `listSlicer`: hiển thị danh sách tick trực tiếp trên canvas, lọc trang chính xác.
  3. `textSlicer`: gõ chuỗi và nhấn Enter lọc theo điều kiện chứa (`CONTAINSSTRING`), có nút xoá lọc.
  4. `slicer` chế độ `'Between'` trên cột số/ngày: kéo 2 đầu thanh trượt hoặc gõ Min/Max lọc đúng khoảng giá trị; khi tạo slicer mới với cột số tự ghi `mode = "'Between'"` như Desktop.
  5. `map` / `filledMap`: vẽ vùng địa lý hoặc điểm bong bóng tỉ lệ `Size` từ dữ liệu bản đồ ngoại tuyến tích hợp (không tải mạng).

### Câu chuyện 4 (P2) — Phần tử chèn báo cáo (`shape`, `pageNavigator`, `bookmarkNavigator`, `actionButton`, `image`)
Người dùng bấm các nút trên tab Ribbon **Chèn (Insert)** (Hình khối, Nút, Điều hướng trang, Điều hướng bookmark, Ảnh) → phần tử xuất hiện trên canvas, di chuyển/đổi cỡ/hoàn tác được, hoạt động thật ở chế độ Xem, và lưu `.pbix` đúng cấu trúc `InsertVisualButton` của Desktop.

- **Kịch bản chấp nhận:**
  1. Chèn `shape` (Rectangle / Oval / Line): vẽ đúng hình, sửa màu tô/viền/góc bo trong Format pane, lưu ra `visual.json` khớp `insert-shape.visual.json`.
  2. Chèn `pageNavigator`: tự động hiển thị danh sách trang hiện có; ở chế độ Xem bấm vào tên trang chuyển ngay sang trang đó.
  3. Chèn `bookmarkNavigator`: tự động hiển thị danh sách bookmark; ở chế độ Xem bấm áp bookmark ngay.
  4. Chèn `actionButton` (nút trống) và `image` (chọn file PNG/JPEG/SVG từ máy): lưu ảnh vào `RegisteredResources` + `resourcePackages`, mở lại vẫn hiện sắc nét, xoá trang dọn tài nguyên thừa đúng như `PBIRResourcePatch`.

---

## 3. Yêu cầu chức năng (Functional Requirements)

- **FR-001:** `CartesianKind` hỗ trợ đầy đủ `.stackedBar` (ánh xạ `"barChart"` và `"stackedBarChart"`) và `.hundredPercentStackedBar` (`"hundredPercentStackedBarChart"`), vẽ thanh ngang xếp chồng & 100% đúng trục và nhãn dữ liệu.
- **FR-002:** `DonutChartView` (hoặc `PieChartView`) vẽ hình tròn đặc (`innerRadius = 0`) cho `"pieChart"` và giữ nguyên lỗ giữa cho `"donutChart"`.
- **FR-003:** `VisualTypes`, `WellRules`, `PBIRNewVisual` mở khoá tạo mới, đổi loại và lưu PBIR khớp 100% `VM-V11A` cho: `barChart`, `hundredPercentStackedBarChart`, `pieChart`, `tableEx`, `scatterChart`, `gauge`, `kpi`, `advancedSlicerVisual`, `listSlicer`, `textSlicer`, `map`, `filledMap`, `shape`, `pageNavigator`, `bookmarkNavigator`, `actionButton`, `image`.
- **FR-004:** `DataView` & `VisualQuerySpecReader` & `DAXQueryBuilder` & `DataViewMapper` hỗ trợ sinh DAX và nạp dữ liệu cho:
  - `tableEx` (`.table(TableDataView)` gồm danh sách cột + dòng dữ liệu + dòng tổng cộng tuỳ chọn);
  - `scatterChart` (`.scatter(ScatterData)` gồm điểm `(category, series, x, y, size)`);
  - `gauge` (`.gauge(GaugeData)` gồm `value, min, max, target`);
  - `kpi` (`.kpi(KPIData)` gồm `latestValue, goalValue, trendPoints[]`);
  - `multiRowCard` (`.multiRowCard` gồm nhiều hàng giá trị).
- **FR-005:** `ReportInteraction` & `FilterTranslator` hỗ trợ thêm hai kiểu lọc từ slicer: lọc khoảng (`Between`: `>= min && <= max` cho số & ngày) và lọc chuỗi chứa (`TextSearch`: `CONTAINSSTRING`).
- **FR-006:** `VisualCSVExporter`, `ReportPageExporter` (PNG/PDF), và `VisualAccessibilitySummary` (VoiceOver song ngữ Việt/Anh) hỗ trợ đầy đủ mọi loại `DataView` và visual mới — không để visual mới rơi về placeholder khi xuất hoặc đọc VoiceOver.
- **FR-007:** Toàn bộ nhãn UI mới (tên visual, tên ô well, Ribbon Chèn, thông báo) dùng song ngữ `bi(_:_:)` / `L10n` và màu động `DS.Palette` tương thích Dark Mode; Report Canvas giữ nền tài liệu sáng `.pbix`.
- **FR-008:** Giữ nguyên 100% không hồi quy toàn bộ 2 414 unit test và 122+ golden test nặng hiện có; không thêm thư viện ngoài và không gọi mạng (Hiến pháp III & IV).

---

## 4. Tiêu chí thành công (Success Criteria)

- **SC-001 (Khớp PBIR & Mở được trong Power BI Desktop):** Tạo tệp `.pbix` mới từ BI Pro chứa đầy đủ các visual của 4 nhóm (2A–2D), lưu T1/T3 → mở trong **Power BI Desktop 2.159 trên VM Windows 11** không lỗi, tất cả visual hiển thị đúng dữ liệu và bố cục.
- **SC-002 (Khớp số liệu DAX golden):** Số liệu của `barChart`, `hundredPercentStackedBarChart`, `pieChart`, `tableEx` (kể cả dòng `Total`), `scatterChart`, `gauge`, `kpi`, `multiRowCard` khớp 100% truy vấn DAX trên `Nhom6_work.pbix`.
- **SC-003 (Tương tác Slicer & Navigator):** Tile slicer, List slicer, Text slicer, Numeric/Date Between slider lọc chính xác các visual cùng trang; Page navigator & Bookmark navigator chuyển trang / áp bookmark tức thời ở chế độ Xem.
- **SC-004 (Export & VoiceOver & Visual Regression):** Mọi visual mới xuất được PNG/PDF (không trống, không lỗi layout), xuất được CSV chuẩn RFC 4180 + UTF-8 BOM, có nhãn VoiceOver Việt/Anh, và có bài test hồi quy hình ảnh trong `Tests/BIProTests/`.
- **SC-005 (Không hồi quy & Đóng gói):** `swift test --no-parallel` qua 100%, bộ golden nặng release qua 100%, `zsh scripts/build-app.sh release` dựng `build/BI Pro.app` hợp lệ (`codesign --verify --deep --strict`).

---

## 5. Ngoài phạm vi Đợt 2 (để Đợt 3 `specs/014`)
- Edit Interactions UI, Matrix mở nút theo hàng, Conditional Formatting UI, Analytics Pane, đổi Theme báo cáo, Refresh dữ liệu một bấm, đổi tên tự viết lại tham chiếu, mở rộng hàm DAX mới (`TODAY`, `TOTALYTD`…) → thuộc **Đợt 3 (`specs/014`)**.
- AI visuals (`keyInfluencers`, `decompositionTree`, `narrative`), `azureMap` online, `R`/`Python` script visuals, `ganttChart` custom visual → không nằm trong phạm vi v1.1.
