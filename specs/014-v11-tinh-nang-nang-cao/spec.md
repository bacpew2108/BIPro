# Đặc tả tính năng: Đợt 3 (v1.1b) — Tương tác báo cáo, Định dạng có điều kiện, Analytics, Làm mới dữ liệu & Mở rộng DAX

**Nhánh / Thư mục spec:** `specs/014-v11-tinh-nang-nang-cao/`
**Ngày tạo:** 2026-11-21
**Trạng thái:** Chờ duyệt (Cổng duyệt 1/3 — `spec.md`)
**Tài liệu cấp trên:** `docs/BIPRO_BUILD_PLAN.md`, `docs/STATE.md`, `specs/013-v11-bieu-do-visual/`
**Bằng chứng quan sát:** `docs/phase-v11-evidence/vm-v11b/QUAN-SAT.md` (18 tệp PBIR JSON nguyên văn + 21/21 truy vấn DAX golden từ `msmdsrv` Power BI Desktop 2.159 + 2 ảnh cắt canvas)

---

## 1. Quan sát Power BI Desktop 2.159 (`VM-V11B`)

Toàn bộ cấu trúc PBIR và ngữ nghĩa DAX trong Đợt 3 đều được xác nhận trực tiếp từ **Power BI Desktop 2.159** (`docs/phase-v11-evidence/vm-v11b/QUAN-SAT.md`), không suy đoán:

1. **Edit Interactions (`page.json` `visualInteractions`):**
   - Mảng các đối tượng `{"source": "<id>", "target": "<id>", "type": "NoFilter" | "DataFilter" | "HighlightFilter"}`.
   - Khi bật *Sửa tương tác*, các visual khác trên trang hiển thị huy hiệu Filter / Highlight / None ngay góc trên phải.
2. **Mở/đóng phân cấp hàng Matrix (`visual.json` `expansionStates`):**
   - Dùng `roles: ["Rows"]`, mảng `levels` (`queryRefs`, `isCollapsed`, `identityKeys`, `isPinned`) và cây `root.children` (`identityValues`, `isToggled: true`).
3. **Định dạng có điều kiện (Conditional Formatting):**
   - **Data Bars** ghi trong `objects.columnFormatting[].properties.dataBars` (`positiveColor`, `negativeColor`, `axisColor`, `reverseDirection`, `hideText`, `totalMatchingOption`), selector `{"metadata": "<queryRef>"}`.
   - **Rules** ghi trong `objects.values[].properties.{backColor|fontColor}` dạng `expr.Conditional.Cases[{Condition, Value}]` (`ComparisonKind` `0..4`, `And`), selector có `dataViewWildcard.matchingOption: 1`.
   - **Gradient** ghi trong `objects.values[].properties.{backColor|fontColor}` dạng `expr.FillRule` (`linearGradient2` / `linearGradient3`).
   - **Field Value** ghi `expr.Measure` trả chuỗi màu hex.
4. **Ngăn Analytics (`objects` trên biểu đồ trục):**
   - **Y-Axis Constant Line:** `objects.y1AxisReferenceLine` (`show`, `displayName`, `value`, `lineColor`, `style`, `transparency`).
   - **Min / Max / Average Line:** `objects.referenceLine` với `value.expr.Aggregation` (`Function: 1` = Average, `3` = Min, `4` = Max) tham chiếu `SelectRef.ExpressionName`.
   - **Trend line & Forecast:** `objects.trend` và `objects.forecast` (đã quan sát sẵn trong `Nhom6`).
5. **Chuyển Theme (`report.json` `themeCollection` & `resourcePackages`):**
   - Ghi tệp theme JSON vào `Report/StaticResources/RegisteredResources/<Name>.json`, đăng ký `{"name": "<Name>.json", "path": "<Name>.json", "type": "CustomTheme"}` trong `resourcePackages` và cập nhật `themeCollection.customTheme`.
6. **DAX Golden Oracle (`dax-golden.json`, 21/21 truy vấn trên `msmdsrv` 2.159):**
   - Đã ghi nhận toàn bộ ngữ nghĩa chuẩn bao gồm các điểm dễ nhầm: `UNION`/`INTERSECT` giữ bản sao (multiset), `COUNTBLANK` trả `BLANK()` khi không có ô trống, `WEEKNUM(..., 21)` theo ISO 8601, `TIME` tràn modulo 24 giờ, `CALENDARAUTO(fyEndMonth)` theo năm tài chính, và `OFFSET`/`INDEX`/`WINDOW` với `ORDERBY`/`PARTITIONBY`.

---

## 2. Câu chuyện người dùng & Kịch bản kiểm chứng

### Câu chuyện 1 (P1 — Nhóm 3A) — Sửa tương tác chéo, Matrix phân cấp hàng, Kéo thả bộ lọc & Lọc ngày nâng cao
Người dùng làm việc trên báo cáo cần kiểm soát visual nào lọc/tô sáng/bỏ qua visual nào, mở rộng từng nhánh hàng trong Matrix phân cấp, kéo thả nhanh trường dữ liệu vào ngăn Bộ lọc (kể cả lọc khoảng/điều kiện ngày nâng cao) và lưu đủ trạng thái tương tác vào Bookmark.

- **Kịch bản chấp nhận:**
  1. **Edit Interactions (`page.json`):** Ở chế độ Sửa (`⌘E`), chọn 1 visual và bật nút **Sửa tương tác (Edit interactions)** trên Ribbon → mọi visual khác trên trang hiện bộ huy hiệu **Lọc (Filter)** / **Tô sáng (Highlight)** / **Không (None)**; đổi trạng thái → ở chế độ Xem, lọc chéo/tô sáng tuân thủ đúng thiết lập; lưu `.pbix` ghi đúng `visualInteractions` (`DataFilter`/`HighlightFilter`/`NoFilter`) và hỗ trợ Undo/Redo (`⌘Z`).
  2. **Matrix phân cấp hàng (`expansionStates`):** Khi `pivotTable` có ≥ 2 trường trong ô `Rows`, hiển thị nút `+`/`−` bên trái từng dòng cha; bấm `+` mở ra các dòng con thụt lề ngay bên dưới (tính toán qua `DAXEngine`, dòng cha vẫn hiển thị subtotal); trạng thái mở/đóng lưu và khôi phục chuẩn `expansionStates` (`roles: ["Rows"]`).
  3. **Kéo thả vào Filters pane & Lọc ngày nâng cao:** Kéo bất kỳ cột/measure nào từ Data pane thả vào vùng *Bộ lọc trang này* / *Mọi trang* / *Visual này* để tạo thẻ lọc mới; với cột kiểu Ngày (`DateTime`), chọn *Lọc nâng cao (Advanced filtering)* hỗ trợ `is` / `is not` / `is after` / `is on or after` / `is before` / `is on or before` với DatePicker + lưu PBIR chuẩn `datetime'...'`.
  4. **Bookmark Data mở rộng:** Lưu và khôi phục trạng thái lọc chéo giữa các visual, cấp drill hiện tại, trạng thái mở/đóng hàng/cột Matrix và slicer nhiều cấp khi cập nhật/áp dụng bookmark.

### Câu chuyện 2 (P1 — Nhóm 3B) — Định dạng có điều kiện (CF), Chuyển Theme báo cáo & Ngăn Analytics
Người dùng cần trực quan hoá điểm nóng trên Bảng/Matrix bằng màu nền, màu chữ và thanh dữ liệu (Data Bars), đổi bảng màu toàn báo cáo bằng một cú bấm hoặc nhập file `.json` theme của doanh nghiệp, và bật đường tham chiếu/xu hướng/trung bình trên biểu đồ.

- **Kịch bản chấp nhận:**
  1. **Conditional Formatting UI & Vẽ thật:** Trong Format pane (hoặc menu trường giá trị) của `tableEx` và `pivotTable`, cấu hình:
     - **Màu nền / Màu chữ:** theo **Gradient** (2 hoặc 3 mốc màu, `FillRule`), theo **Quy tắc (Rules)** (`Conditional` với ngưỡng số/%), hoặc theo **Giá trị trường (Field value — measure màu)**.
     - **Thanh dữ liệu (Data bars):** bật/tắt, chọn màu dương/âm, ẩn số liệu (`hideText`), ghi đúng `objects.columnFormatting[].properties.dataBars`.
     - Cả `tableEx` và `pivotTable` vẽ tức thời màu nền/màu chữ/thanh dữ liệu, xuất đúng trong PNG/PDF, và lưu PBIR mở khớp trên Desktop 2.159.
  2. **Theme Switcher:** Nút **Chủ đề (Themes)** trên Ribbon mở thư viện ≥ 6 chủ đề dựng sẵn (Mặc định Power BI, Executive, City Park, Classic, High Contrast, BI Pro Native) + nút **Nhập chủ đề (.json)…** (`NSOpenPanel`) và **Xuất chủ đề hiện tại…**. Đổi chủ đề cập nhật ngay toàn bộ màu biểu đồ/nền/chữ trên canvas, hỗ trợ Undo/Redo và lưu chuẩn `themeCollection.customTheme` + `RegisteredResources`.
  3. **Ngăn Analytics (tab kính lúp trong Format/Inspector pane):** Khi chọn biểu đồ trục (`lineChart`, `clusteredColumnChart`, `columnChart`, `clusteredBarChart`, `barChart`, `areaChart`, `lineClusteredColumnComboChart`), người dùng thêm/sửa/xoá:
     - **Đường hằng số trục Y (Y-Axis Constant Line):** giá trị số, màu, kiểu nét, nhãn; lưu vào `objects.y1AxisReferenceLine`.
     - **Đường Trung bình / Nhỏ nhất / Lớn nhất (Average / Min / Max Line):** lưu vào `objects.referenceLine` (`Function: 1 / 3 / 4`), tự tính giá trị từ dữ liệu biểu đồ và vẽ đường đứt nét kèm nhãn.
     - **Đường xu hướng (Trend line)** & **Dự báo (Forecast)** bật/tắt nhanh ngay trong ngăn Analytics.

### Câu chuyện 3 (P1 — Nhóm 3C) — Làm mới dữ liệu một bấm (Refresh), Đổi tên tự cập nhật tham chiếu & Biến đổi Power Query nâng cao
Người dùng muốn bấm một nút **Làm mới (Refresh)** ngay trên Ribbon chính để nạp lại dữ liệu mới từ tệp CSV/Excel/JSON/Parquet/SQLite/PostgreSQL mà không mất biểu đồ hay measure, đổi tên bảng/cột/measure đang dùng mà không làm vỡ công thức DAX hay visual, và có thêm các phép biến đổi Power Query thường dùng.

- **Kịch bản chấp nhận:**
  1. **Nút Làm mới (Refresh) một bấm trên Ribbon chính:** Mở khoá nút **Làm mới** trên tab Trang chủ (`Ribbon.swift`) + phím tắt `⇧⌘R`. Khi bấm, hiển thị hộp thoại tiến trình từng bảng, chạy lại toàn bộ truy vấn M nguồn (`MQueryEvaluator` cho CSV, Excel, JSON, Parquet, SQLite, PostgreSQL; giữ nguyên bảng nhập tay `Enter Data` và bảng tính toán DAX), giữ nguyên toàn bộ quan hệ, measure, định dạng và visual; tự xây dựng lại cột tính toán, `R$`/`U$` và nạp lại toàn bộ visual trên trang; nếu nguồn tệp bị di chuyển/lỗi thì báo rõ tên bảng + nguyên nhân mà không làm hỏng dữ liệu cũ.
  2. **Đổi tên bảng / cột / measure đang được sử dụng (Cascade Rename):** Khi đổi tên bảng, cột hoặc measure đang có tham chiếu trong công thức DAX (measure, cột tính toán, bảng tính toán) hoặc trong PBIR (`visual.json` `queryState`/`sortDefinition`/`objects`/`filterConfig`, `page.json` `filterConfig`, `report.json` `filterConfig`), BI Pro hiển thị số lượng tham chiếu sẽ được cập nhật, tự động viết lại chính xác theo token (không thay nhầm chuỗi con bên trong tên khác hoặc trong chuỗi văn bản `"..."`), đánh dấu cần lưu và hỗ trợ Undo/Redo.
  3. **Biến đổi Power Query mở rộng trong Query Editor:** Bổ sung đủ 5 nhóm thao tác thường gặp với sinh mã M chuẩn Power BI Desktop:
     - **Tách cột nâng cao (Split Column):** theo ký tự phân cách (trái nhất / phải nhất / mỗi lần xuất hiện) và theo số ký tự.
     - **Điền xuống / Điền lên (Fill Down / Fill Up):** `Table.FillDown` / `Table.FillUp`.
     - **Thay thế lỗi (Replace Errors):** `Table.ReplaceErrorValues`.
     - **Trích xuất văn bản (Extract):** Độ dài (`Text.Length`), Ký tự đầu/cuối, Trước/Sau/Giữa dấu phân cách.
     - **Biến đổi Ngày/Giờ (Date/Time):** Năm, Tháng, Ngày, Quý, Đầu tháng (`Date.StartOfMonth`), Cuối tháng (`Date.EndOfMonth`), Tên thứ/tháng.

### Câu chuyện 4 (P1 — Nhóm 3D) — Mở rộng DAX Engine (~35+ hàm mới đối chiếu Golden Desktop 2.159)
Người dùng mở các tệp `.pbix` thực tế hoặc viết measure mới sử dụng nhóm hàm Ngày/Giờ, Time Intelligence, Bảng/Tập hợp, Tra cứu, Bắt lỗi và Hàm cửa sổ (Window) → `DAXEngine` phân tích, biên dịch và tính toán chính xác 100% khớp kết quả `msmdsrv` của Power BI Desktop 2.159.

- **Kịch bản chấp nhận:**
  1. **Ngày & Giờ (11 hàm):** `TODAY`, `NOW`, `WEEKDAY`, `WEEKNUM` (gồm loại 1, 2 và 21 ISO 8601), `EOMONTH`, `EDATE`, `MINUTE`, `SECOND`, `TIME` (tràn mod 24h), `YEARFRAC` (basis 0–4), `CALENDARAUTO([fiscal_year_end_month])`.
  2. **Time Intelligence (23 hàm):** `DATESYTD`, `DATESQTD`, `DATESMTD`, `TOTALYTD`, `TOTALQTD`, `TOTALMTD`, `DATESBETWEEN`, `DATESINPERIOD`, `PREVIOUSDAY`, `PREVIOUSMONTH`, `PREVIOUSQUARTER`, `PREVIOUSYEAR`, `NEXTDAY`, `NEXTMONTH`, `NEXTQUARTER`, `NEXTYEAR`, `PARALLELPERIOD`, `STARTOFMONTH`, `ENDOFMONTH`, `STARTOFQUARTER`, `ENDOFQUARTER`, `STARTOFYEAR`, `ENDOFYEAR`.
  3. **Bắt lỗi & Thông tin kiểu (6 hàm):** `IFERROR`, `ISERROR`, `ERROR`, `ISNUMBER`, `ISTEXT`, `ISLOGICAL`.
  4. **Tra cứu, Bảng, Tập hợp & Thống kê (13 hàm):** `LOOKUPVALUE`, `SELECTCOLUMNS`, `UNION`, `INTERSECT`, `EXCEPT`, `GENERATESERIES`, `DATATABLE`, `COUNTBLANK`, `COUNTX`, `COUNTAX`, `PRODUCTX`, `STDEV.S`, `VAR.S`.
  5. **Hàm cửa sổ — Window Functions (3 hàm + mệnh đề):** `OFFSET`, `INDEX`, `WINDOW` (hỗ trợ `ORDERBY`, `PARTITIONBY`, `ABS`/`REL`, `BLANKS`/`KEEP`/`DEFAULT`).
  6. **Cập nhật DAX IntelliSense / Autocomplete:** Toàn bộ hàm mới hiển thị chữ ký tham số và gợi ý tự động trong thanh công thức DAX.

---

## 3. Yêu cầu chức năng (Functional Requirements)

- **FR-001:** `PBIRPagePatch` bổ sung đọc/ghi `visualInteractions` trong `page.json` theo đúng byte-preserving splice; `ReportInteraction` áp dụng `NoFilter` / `DataFilter` / `HighlightFilter` cho mọi cặp visual trên trang.
- **FR-002:** `MatrixData`, `VisualQuerySpecReader`, `DAXQueryBuilder`, `DataViewMapper`, `MatrixVisualView` và `PBIRQueryPatch`/`PBIRLayoutPatch` hỗ trợ đầy đủ mở/đóng phân cấp hàng Matrix (`expansionStates` với `roles: ["Rows"]`), bao gồm truy vấn subtotal cha + chi tiết các nhánh đang mở.
- **FR-003:** `FiltersPane` hỗ trợ kéo-thả trường từ `DataPane` (drop target rõ ràng ở 3 vùng Visual / Page / Report) và `FilterEditor` hỗ trợ đầy đủ Advanced Filtering cho cột kiểu Ngày (`DateTime`) với `DatePicker` và ghi chuẩn `datetime'...'`.
- **FR-004:** `VisualFormat` & `FormatCatalog` & `PBIRFormatPatch` hỗ trợ đọc/ghi đầy đủ `objects.values` (`FillRule` 2/3 mốc, `Conditional` Rules, `Measure` Field value), `objects.columnFormatting.dataBars`, `objects.y1AxisReferenceLine`, và `objects.referenceLine` (`Function: 1, 3, 4`).
- **FR-005:** `TableVisualView` và `MatrixVisualView` vẽ nhất quán màu nền/màu chữ có điều kiện và Data Bars (cả dương/âm, tuỳ chọn `hideText`, không tô đè lên dòng Total khi `matchingOption == 1`).
- **FR-006:** `CartesianChartView` / `ComboChartView` vẽ các đường tham chiếu Analytics (`y1AxisReferenceLine`, `referenceLine` Min/Max/Average, `trend`, `forecast`) với nhãn giá trị gọn gàng, tương thích cả chế độ Xem và xuất PNG/PDF.
- **FR-007:** `PBIRResourcePatch` & `DocumentState` hỗ trợ đổi Theme toàn báo cáo (chủ đề dựng sẵn + nhập tệp `.json` kiểm tra hợp lệ + xuất `.json`), lưu chuẩn `themeCollection.customTheme` trong `report.json` và `Report/StaticResources/RegisteredResources/<Name>.json`, có Undo/Redo.
- **FR-008:** Nút **Làm mới (Refresh)** trên Ribbon chính thực thi lại các truy vấn M cho mọi bảng có nguồn ngoài, bảo toàn 100% quan hệ, measure, visual và định dạng, cập nhật lại chỉ mục `R$`/`U$` & cột tính toán, kèm báo cáo kết quả từng bảng và không làm mất dữ liệu khi nguồn lỗi.
- **FR-009:** Đổi tên bảng/cột/measure đang được dùng tự động viết lại công thức DAX (theo lexer token để không sửa nhầm chuỗi/tiền tố) và mọi tham chiếu PBIR (`SourceRef.Entity`, `Property`, `queryRef`, `selector.metadata`), có xác nhận trước khi áp dụng và hỗ trợ Undo/Redo.
- **FR-010:** `MEngine` và `QueryEditorWindow` hỗ trợ thêm các hàm M & thao tác giao diện: `Table.FillDown`, `Table.FillUp`, `Table.ReplaceErrorValues`, `Table.SplitColumn` (delimiter/position), `Text.Length`/`BeforeDelimiter`/`AfterDelimiter`/`BetweenDelimiters`, và các phép trích xuất `Date.Year`/`Month`/`Day`/`QuarterOfYear`/`StartOfMonth`/`EndOfMonth`/`DayOfWeekName`/`MonthName`.
- **FR-011:** `DAXEngine` (Lexer/Parser/Binder/Evaluator/FunctionRegistry) cài đặt đầy đủ ~56 hàm mới nêu ở US4, vượt qua toàn bộ bộ test đối chiếu với `docs/phase-v11-evidence/vm-v11b/dax-golden.json` (khớp tuyệt đối giá trị và kiểu).
- **FR-012:** Mọi thành phần UI mới đều song ngữ Việt/Anh (`bi(_:_:)` / `L10n`), dùng màu động `DS.Palette` tương thích Dark Mode (giữ nền sáng `.pbix` cho Report Canvas), 100% native macOS Swift/SwiftUI, không thêm thư viện ngoài, không gọi mạng (Hiến pháp III & IV).

---

## 4. Tiêu chí thành công (Success Criteria)

- **SC-001 (Cổng Power BI Desktop 2.159 trên VM Windows 11):** Xuất một tệp `.pbix` kiểm chứng từ BI Pro chứa đầy đủ thay đổi Đợt 3 (`visualInteractions` NoFilter/DataFilter/HighlightFilter, Matrix mở hàng `expansionStates`, Conditional Formatting Rules + Gradient + Data Bars, Analytics Constant/Min/Max/Average line, Theme mới trong `RegisteredResources`, Date Advanced filter, Refresh T3 và measure dùng các hàm DAX mới) → mở trên **Power BI Desktop 2.159** không có bất kỳ cảnh báo hỏng/lỗi trường/lỗi tài nguyên nào và hiển thị khớp.
- **SC-002 (Khớp 100% DAX Golden Oracle):** Toàn bộ 21 nhóm kiểm chứng trong `docs/phase-v11-evidence/vm-v11b/dax-golden.json` chạy trên `DAXEngine` với `Nhom6_Dashboard_chiase.pbix` (chỉ-đọc) cho kết quả khớp 100% Power BI Desktop 2.159 (sai số số thực ≤ `1e-12`).
- **SC-003 (An toàn Refresh & Cascade Rename):**
  - Refresh một tệp `.pbix` nguồn CSV/SQLite sau khi thêm/sửa dòng dữ liệu gốc → mọi số liệu biểu đồ và measure cập nhật đúng ngay, quan hệ & visual giữ nguyên 100%, lưu T3 mở lại không lỗi.
  - Đổi tên một bảng, một cột và một measure đang dùng trong nhiều measure & visual → không có visual hay measure nào gãy; Undo (`⌘Z`) khôi phục nguyên vẹn.
- **SC-004 (Không hồi quy & Đóng gói Release):**
  - `swift test --no-parallel` qua 100% (0 lỗi).
  - Bộ test nặng release (`BIPRO_HEAVY=1`, `-c release`) qua 100% (0 lỗi).
  - `zsh scripts/build-app.sh release` tạo `build/BI Pro.app` hợp lệ (`codesign --verify --deep --strict`).

---

## 5. Ngoài phạm vi Đợt 3 (v1.1b)
- Kết nối trực tuyến Power BI Service (Publish, OAuth/Azure AD, DirectQuery cloud, Web connector) — nằm ngoài Hiến pháp IV (ứng dụng 100% ngoại tuyến).
- Visual Calculations kiểu mới (`RUNNINGSUM` visual-level) và DAX Calculation Groups.
- Incremental Refresh / Composite Models / DirectLake.
