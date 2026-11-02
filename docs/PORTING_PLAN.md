# PowerBINative: kế hoạch port Power BI sang SwiftUI (macOS native)

> **2026-10-31:** Lộ trình build (§3) đã được thay bằng [`BIPRO_BUILD_PLAN.md`](BIPRO_BUILD_PLAN.md), viết theo bộ thiết kế trong `UIdesign/`. Phần phân tích định dạng file và kết quả Phase 0 dưới đây vẫn còn giá trị.

> Ngày lập: 2026-10-30. Cơ sở: phân tích REA trên các file `.pbix` của chính bạn (không decompile Power BI Desktop).

## 0. Định nghĩa "port" và phạm vi

Power BI Desktop là app Windows đóng mã (.NET/WPF + Analysis Services `msmdsrv` + Power Query M + web renderer).
Giấy phép của Microsoft cấm reverse engineering binary, và việc chép nguyên app là không khả thi. Vì vậy dự án này là
**một app macOS mới, tương thích định dạng**: mở được `.pbix`/`.pbip`, tính đúng số liệu và vẽ lại report bằng SwiftUI.
REA chỉ dùng để phân tích **định dạng file của bạn** và để kiểm chứng app mình làm ra.

| Mức | Nội dung | Ước lượng (1 dev) |
|---|---|---|
| **MVP: Viewer** | Mở `Nhom6_Dashboard.pbix`, hiện 4 trang, số liệu đúng, slicer/cross-filter chạy | ~4–5 tháng |
| **v1: Interactive** | Bookmark, drill, tooltip, conditional format, cả 2 định dạng report (PBIR + Layout cũ) | +2 tháng |
| **v2: Authoring** | Sửa visual/trang, lưu ra `.pbip` (PBIR JSON) | +2–3 tháng |
| Ngoài phạm vi | Power Query M đầy đủ, connector, gateway, publish lên Service, ghi lại `DataModel` vào `.pbix` | — |

## 1. Những gì REA đã quan sát được

Target chính: `~/Downloads/Nhom6_Dashboard.pbix` (54 MB, sha256 `0d8c1675…5b7d`).

### 1.1 Container (Evidence `ev_4e00c45b…`, `ev_bea1e4f8…`)
`.pbix` là ZIP theo chuẩn OPC (`[Content_Types].xml`). Các part:

| Part | Định dạng quan sát được | Ý nghĩa cho port |
|---|---|---|
| `Version` | UTF‑16LE, `1.32` (file mới) / `1.28` (file cũ) | Dùng để chọn parser |
| `Settings`, `Metadata` | JSON UTF‑16LE; `"CreatedFrom":"Cloud"`, `"CreatedFromRelease":"2026.10"` | Đọc, không cần render |
| `SecurityBindings` | Blob bắt đầu bằng GUID provider DPAPI `df9d8cd0-1501-11d1-8c7a-00c04fc297eb` | **Suy luận:** là credential nguồn dữ liệu được mã hoá bằng DPAPI của Windows. Bỏ qua, không giải mã được trên Mac |
| `DataModel` | 54,18 MB, entropy 7,9959 trên toàn file (Evidence `ev_a27737b2…`), header UTF‑16 `This backup was created using XPress9 compression.` | Là backup Analysis Services (ABF) nén XPress9; chứa toàn bộ dữ liệu + DAX |
| `Report/definition/**` | **PBIR**: JSON theo schema công khai `developer.microsoft.com/json-schemas/fabric/item/report/definition/...` | Định dạng chính cần hỗ trợ |
| `Report/StaticResources/**` | Theme base `Fluent2-CY26SU09.json`, theme riêng `Nhom6Theme.json`, 16 icon SVG, `usa.states.topo.json` | Theme engine + tài nguyên ảnh + bản đồ |

**Hai thế hệ report** có mặt trên máy bạn:
- PBIR (`Version 1.32`): `Nhom6_Dashboard`, `tuan61`, `tuan6.2`: mỗi visual là một file `visual.json`.
- Layout cũ (`Version 1.28`): `Nhóm 2 - Financial Service`, `dashboard_DW&BI_nhom_3`: một file `Report/Layout` duy nhất, kèm `DiagramLayout`, `Connections`, `LinguisticSchema`.

→ Cần 2 parser cùng đổ về **một ReportModel chung**.

### 1.2 Cấu trúc DataModel
Mình tự phân tích thêm bằng script (không phải Evidence REA): sau header 102 byte là chuỗi block
`[u32 uncompressedSize][u32 compressedSize][payload]`. Có 46 block, mỗi block giải nén ra 2 MiB, tổng **≈94,4 MB giải nén**,
và byte cuối khớp đúng EOF. Mức tin cậy cao, nhưng **nội dung sau giải nén chưa được quan sát**.

### 1.3 Report của Nhom6 (thứ MVP phải vẽ được)
- 4 trang, `1920×1080`, `displayOption: FitToPage`: `d1_giaodich`, `d2_khoanvay`, `d3_cskh`, `d4_chinhanh`.
- 134 visual, định vị tuyệt đối (`x, y, z, width, height, tabOrder`):

| visualType | Số lượng | Cách vẽ native |
|---|---|---|
| card | 50 | SwiftUI `Text` + định dạng số |
| image | 30 | `Image` từ SVG/PNG trong RegisteredResources |
| slicer | 17 | List/Dropdown/Range → `Picker`, `Toggle`, `Slider` |
| textbox | 7 | `AttributedString` từ paragraphs/textRuns |
| actionButton | 5 | `Button` → bookmark / chuyển trang |
| pageNavigator | 3 | `HStack` button theo `pages.json` |
| lineClusteredColumnCombo / lineStackedColumnCombo | 4 + 3 | Swift Charts `BarMark` + `LineMark`, tự làm trục phụ |
| clusteredBarChart | 4 | `BarMark` ngang |
| lineChart | 3 | `LineMark` |
| donutChart | 3 | `SectorMark(innerRadius:)` |
| pivotTable | 2 | `NSOutlineView` qua `NSViewRepresentable` (hiệu năng) |
| treemap | 1 | Thuật toán squarified + `Canvas` |
| shapeMap | 1 | Parse TopoJSON → `Path` trong `Canvas` |
| hundredPercentStackedColumnChart | 1 | `BarMark(stacking: .normalized)` |

- Biểu thức truy vấn trong visual: `Literal` 1315, `Measure` 140, `Column` 69, `ResourcePackageItem` 31, `HierarchyLevel` 18, `Comparison` 16, `FillRule` 4, `Not`/`In` (filter cấp report).
- Ngữ nghĩa: 95 measure khác nhau trên `Fact_Loan`, `Fact_Transaction`, `Fact_CRM_Complaint`, `Dim_District`, `Dim_Client`; khoảng 30 cột từ `Dim_Date`, `Dim_Account`, `Dim_Client`, `Dim_CRM_*`, `Dim_District`, `Dim_Loan_Profile`, `Dim_Trans_Type`, `Fact_*`.
- Filter cấp report: `Dim_Date[year] NOT IN {9999}`, `Dim_Client[client_region] NOT IN {'Unknown'}`.
- 2 bookmark (`Q1.3 · Tháng trong năm`, `…GioThu`), dùng `applyOnlyToTargetVisuals`, `suppressData`, `explorationState`.

### 1.4 Chưa biết (phải làm rõ ở Phase 0)
1. Bên trong ABF sau giải nén có gì: `metadata.sqlitedb` hay định dạng metadata khác, cùng danh sách file `.idf/.idfmeta/.dictionary/.hidx`.
2. **Biểu thức DAX của 95 measure** (nằm trong DataModel), từ đó biết cần hỗ trợ những hàm DAX nào.
3. Format string, quan hệ giữa các bảng, cột tính toán, bảng tính toán (calculated table).
4. Thư viện XPress9 nào dùng được với license hợp lệ để gọi từ Swift.

## 2. Kiến trúc

```
PowerBINative (Xcode workspace, macOS 15+, Swift 6, strict concurrency)
├── PBIXKit          ZIP/OPC, UTF-16, phát hiện Version, PBIR vs Layout
├── ReportModel      Codable: Report, Page, Visual, Query (SemanticQuery AST), Theme, Bookmark, Filter
│   ├── PBIRDecoder      Report/definition/**  → ReportModel
│   └── LegacyLayoutDecoder  Report/Layout (JSON lồng chuỗi JSON) → ReportModel
├── CXPress9 (C target)  giải nén XPress9 (wrapper)
├── ABFKit           đọc backup ABF: danh mục file, BackupLog
├── VertiPaqKit      dictionary, IDF (RLE + bit-packing), hidx → cột in-memory
├── SemanticModel    bảng, cột, quan hệ, measure, format string (từ metadata)
├── DAXEngine        Lexer → Parser → AST → Evaluator (filter context, context transition)
├── QueryEngine      VisualQuery → kế hoạch dạng SUMMARIZECOLUMNS → DataFrame
│   └── Backend: Local (DAXEngine) | Remote (Power BI REST executeQueries)
├── VisualKit        mỗi visualType là một SwiftUI View + FormatResolver (theme ⊕ objects)
├── InteractionKit   slicer, cross-filter/highlight, drill, bookmark, page nav
└── App              DocumentGroup, Sidebar trang, Fields/Filters pane, Inspector, Quick Look ext.
```

### Các quyết định thiết kế chính
1. **Một ReportModel chung, nhiều decoder.** PBIR và Layout cũ khác nhau về hình thức nhưng cùng ngữ nghĩa (SemanticQuery `From/Select/Where`, `objects`). Cả renderer lẫn engine chỉ biết ReportModel.
2. **Visual query biên dịch thành "DAX query plan"**, không biên dịch thẳng sang SQL. Ngữ nghĩa filter context của DAX (CALCULATE, context transition, lan truyền filter theo quan hệ, auto-exist) không ánh xạ sạch sang SQL. Cùng một plan có thể:
   - chạy **local** bằng DAXEngine trên dữ liệu VertiPaq đã giải mã;
   - được render thành chuỗi DAX `EVALUATE SUMMARIZECOLUMNS(...)` để chạy **remote** qua Power BI REST API `datasets/{id}/executeQueries` (đăng nhập MSAL). Metadata cho thấy file tạo từ Cloud, nên nhiều khả năng bạn có workspace để dùng cách này.
3. **Remote backend làm oracle kiểm thử.** Mỗi visual chạy cả local lẫn remote rồi so từng ô (differential testing). Đây là cách duy nhất chứng minh engine tự viết tính đúng. Nếu không có Service, dùng Power BI Desktop + DAX Studio trong VM Parallels `Windows 11` (đã có trên máy) để xuất kết quả chuẩn ra CSV.
4. **Lưu trữ cột tự viết**, dictionary-encoded giống VertiPaq (`[UInt32]` index + dictionary), giữ nguyên encoding đọc được, không phải bung ra chuỗi. ~94 MB ABF vừa thoải mái trong RAM. DuckDB chỉ cân nhắc sau nếu scan quá chậm.
5. **Canvas tuyệt đối:** mỗi page là `ZStack` 1920×1080, visual đặt bằng `.frame` + `.position`, sắp theo `z`, rồi `.scaleEffect` theo FitToPage/FitToWidth. Swift Charts cho chart chuẩn, `Canvas` cho treemap/shape map, AppKit (`NSOutlineView`) cho pivot lớn.
6. **Chỉ đọc `.pbix`; ghi ra `.pbip`.** Ghi lại DataModel đòi nén XPress9 và dựng ABF hợp lệ, rủi ro rất cao. Bản v2 chỉ ghi phần report (PBIR là JSON có schema công khai).

## 3. Lộ trình chi tiết

### Phase 0: Spike giảm rủi ro ✅ HOÀN THÀNH 2026-10-30 (GO)
- [x] XPress9: dùng mã gốc của Microsoft (MIT), lấy qua `xpress9-python`. Chỉ vendor phần decoder vào C target `CXPress9`, có CLI `pbix-dump`.
- [x] Giải nén ra ABF: Nhom6 có 46 block → 90 MiB trong khoảng 0,4 giây, 835 file. Đọc được header, virtual directory và backup log.
- [x] Metadata nằm trong `metadata.sqlitedb`, mở in-memory bằng `sqlite3_deserialize`. Đọc được bảng, cột, 168 measure, 14 quan hệ (1 inactive) và M query.
- [x] VertiPaq: idfmeta, IDF (RLE + bit-packing), dictionary số, dictionary chuỗi (thường và Huffman), cột value-encoded.
- [x] Chạy trên cả 6 file `.pbix` (3 file 1.32/PBIR, 3 file 1.28/Layout cũ): giải mã hết mọi bảng, `verify` khớp distinct count 308/308 cột.
- [x] DAX: report dùng trực tiếp 95 measure, tính cả phụ thuộc là 119. Khoảng 40 hàm, xem kết quả bên dưới.
- **Exit đạt:** `pbix-dump rows Fact_Loan` in đúng dữ liệu trên Mac (682 dòng), `Fact_Transaction` 1.056.320 dòng giải mã trong 0,6 giây.

**Kết quả Phase 0**
- Tiếng Việt trong dictionary Huffman giải mã đúng (`Đã tất toán`, `Nợ tốt`, `Chưa có thẻ`).
- 7 cột tính toán đã được Power BI lưu sẵn kết quả trong VertiPaq, nên engine **không cần** tự tính lại khi mở file.
- Hàm DAX mà report cần, theo tần suất: `IF, ISBLANK, CALCULATE, INT, MOD, DATE, REMOVEFILTERS, MAX, ISFILTERED, YEAR, MONTH, SWITCH, TRUE, VALUES, BLANK, DIVIDE, ABS, TREATAS, FILTER, FORMAT, SAMEPERIODLASTYEAR, KEEPFILTERS, SUMMARIZE, ALLSELECTED, SELECTEDVALUE, SUM, SUMX, RELATED, DISTINCTCOUNT, COALESCE, HASONEVALUE, COUNTROWS, CROSSJOIN, TOPN, CONCATENATEX, MINX, MAXX, PERCENTILEX.INC, CALCULATETABLE, AVERAGEX, AVERAGE, DATEDIFF, ADDCOLUMNS`. Riêng `TREATAS`, `ALLSELECTED`, `ISFILTERED` và `KEEPFILTERS` đòi hỏi mô hình filter context đầy đủ ngay từ Phase 3.
- DAX đầy đủ: `docs/measures.nhom6.dax`.
- Chưa có oracle từ bên ngoài: lệnh chạy pbixray trong venv bị hệ thống quyền chặn, nên đối chiếu số liệu đang dựa vào distinct count do engine lưu. Phase 3 vẫn cần oracle cho kết quả DAX.

### App shell (bản đầu): ✅ 2026-10-30
- `scripts/build-app.sh` tạo `build/PowerBI Native.app` (SwiftUI, không cần Xcode), đăng ký kiểu file `.pbix`.
- **Báo cáo:** render đúng vị trí và màu theme của textbox, image (cả kiểu cũ lẫn mới), shape, action button, page navigator (bấm để chuyển trang). Card, slicer, bảng và biểu đồ hiện khung, field, tiêu đề và hình mờ, còn số liệu chờ DAX engine. Inspector hiện field và công thức DAX của measure.
- **Dữ liệu:** lưới NSTableView xem được 1 triệu dòng. **Mô hình:** bảng quan hệ, measure theo bảng, có tìm kiếm.
- Đã kiểm tra bằng ảnh chụp trên Nhom6 (PBIR) và Nhóm 2 (Layout cũ).

### Phase 1: PBIXKit + ReportModel (2 tuần), đã làm một phần (`ReportDefinition.swift`)
- [ ] ZIP: dùng `ZIPFoundation` hoặc `Compression` + tự đọc central directory; stream `DataModel`, không nạp cả 54 MB một lần.
- [ ] Codable cho PBIR: `report.json`, `pages.json`, `page.json`, `visual.json`, `bookmarks/*.json`, `version.json`. Giữ field lạ trong `[String: JSONValue]` để round-trip không mất dữ liệu.
- [ ] SemanticQuery AST: `Column`, `Measure`, `Aggregation`, `HierarchyLevel`, `Literal` (parse hậu tố kiểu `9999L`, `'text'`, `true`, `datetime'…'`, `1D`, `1M`), `Comparison`, `And/Or/Not/In/Between/Contains`, `FillRule`, `ThemeDataColor`, `ResourcePackageItem`.
- [ ] `LegacyLayoutDecoder`: `sections[].visualContainers[].config` là chuỗi JSON lồng, phải parse 2 lần.
- [ ] Unit test: decode toàn bộ 134 visual của Nhom6 + 2 file Layout cũ, không có field nào bị bỏ sót (đếm key trước và sau).

### Phase 2: ABF + VertiPaq (3–5 tuần)
- [ ] `ABFKit`: header, BackupLog, bảng file, offset.
- [ ] `VertiPaqKit`: dictionary chuỗi/số, `.idf` (segment RLE + bit-packed), `.idfmeta` (bit width, min data id), `.hidx`. Cột số không có dictionary (value encoding: `base + value/factor`).
- [ ] `SemanticModel`: bảng, cột (kể cả cột ẩn và `RowNumber`), quan hệ (1–n, chiều lọc single/both, active/inactive), hierarchy (Date).
- [ ] Kiểm thử: số dòng mỗi bảng và tổng các cột số khớp với oracle.

### Phase 3: DAXEngine + QueryEngine (4–6 tuần)
- [ ] Lexer/Parser DAX đầy đủ cú pháp (`VAR/RETURN`, `'Table'[Col]`, `[Measure]`, toán tử, `IN { }`).
- [ ] Evaluator: row context, filter context, `CALCULATE`/`CALCULATETABLE`, context transition, lan truyền filter theo quan hệ, `ALL/ALLEXCEPT/REMOVEFILTERS/KEEPFILTERS`, `USERELATIONSHIP`.
- [ ] Bộ hàm MVP chốt theo kết quả Phase 0. Thường gặp: `SUM, COUNTROWS, DISTINCTCOUNT, DIVIDE, AVERAGE, MIN/MAX, IF, SWITCH, FILTER, VALUES, SELECTEDVALUE, HASONEVALUE, FORMAT, SUMX/AVERAGEX`, time intelligence (`SAMEPERIODLASTYEAR, DATESYTD, DATEADD`).
- [ ] QueryEngine: role (`Category`, `Y`, `Y2`, `Series`, `Tooltips`, `Values`, `Rows/Columns`) → group-by + measure; xếp chồng filter report → page → visual → slicer → cross-filter; `sortDefinition`; TopN; giới hạn data window.
- [ ] Cache theo khoá (visual, filterState); tính song song bằng `TaskGroup`; huỷ khi filter đổi.
- [ ] **Differential test:** mọi visual của Nhom6 so với oracle, sai số tương đối dưới 1e‑9.

### Phase 4: VisualKit, vẽ tĩnh (4 tuần)
- [ ] `ThemeResolver`: base theme ⊕ custom theme ⊕ `visualStyles` ⊕ `objects` của visual. Bảng màu `dataColors`.
- [ ] `FormatResolver`: format string .NET (`#,0.00`, `0.0%`, `"₫"#,0`) sang `FormatStyle`, locale `vi-VN`, hiển thị đơn vị K/M/bn.
- [ ] Làm theo thứ tự tần suất: card → image → textbox → slicer → bar/column → line → combo (trục phụ) → donut → 100% stacked → pivot → treemap → shapeMap → pageNavigator/actionButton.
- [ ] `visualContainerObjects`: title, background, border, shadow, padding, header.
- [ ] Snapshot test: render từng page ra PNG (`ImageRenderer`) rồi so với ảnh export từ Power BI (dùng REA `compare_web_screenshots` hoặc so pixel diff).

### Phase 5: InteractionKit (3 tuần)
- [ ] Slicer → cập nhật `FilterState` (`@Observable`), mọi visual chạy lại query bất đồng bộ.
- [ ] Cross-filter / cross-highlight khi click data point; tôn trọng `visualInteractions` của page.
- [ ] Drill up/down theo `HierarchyLevel`; tooltip mặc định (`.popover`/overlay).
- [ ] Bookmark: áp `explorationState` (filter, visibility, `targetVisualNames`, `suppressData`), action button, page navigator.
- [ ] Phím tắt, VoiceOver (`accessibilityLabel` cho data point), Dark Mode theo theme.

### Phase 6: App shell và hoàn thiện (2–3 tuần)
- [ ] `DocumentGroup(viewing:)` + `UTType` cho `.pbix`/`.pbip`; tab trang ở sidebar; Filters pane; Inspector.
- [ ] Mở 54 MB trong vòng 2 giây: giải nén song song từng block, nạp cột lười (lazy), hiện progress.
- [ ] Quick Look extension (`QLPreviewProvider`) hiện thumbnail trang đầu.
- [ ] Export PDF/PNG trang, copy dữ liệu visual ra CSV.
- [ ] Dùng REA `capture_native_ui_scenario` / `observe_native_ui` để kiểm thử UI tự động trên app đã build.

### Phase 7 (v2): Authoring
- [ ] Kéo thả field vào well, đổi visualType, chỉnh `objects` qua Inspector, undo/redo.
- [ ] Ghi `.pbip` (PBIR JSON + giữ nguyên semantic model gốc), validate bằng JSON schema công khai, mở lại được trong Power BI Desktop.
- [ ] Remote mode: mở dataset trên Service, không cần `.pbix`.

## 4. Kiểm thử và chỉ số hoàn thành

| Lớp | Cách kiểm | Ngưỡng |
|---|---|---|
| Parser | 6 `.pbix` trên máy + round-trip JSON | 100% visual decode, 0 key bị mất |
| Dữ liệu | Số dòng, tổng cột so với oracle | Khớp tuyệt đối |
| DAX | 95 measure × mọi ngữ cảnh visual, so oracle | Sai số dưới 1e‑9 |
| Hình ảnh | Pixel diff so với export của Power BI | Bố cục lệch dưới 2 px, màu đúng theme |
| Hiệu năng | Mở file, đổi slicer | Mở dưới 2 s, query lại dưới 150 ms/trang |

## 5. Rủi ro và phương án dự phòng

| Rủi ro | Mức | Giảm thiểu / Plan B |
|---|---|---|
| Không có XPress9 với license dùng được | Cao | Plan B1: trong VM Windows, Power BI Desktop → *Save as .pbip* + DAX Studio xuất bảng ra Parquet/CSV; app Mac đọc PBIR + TMDL + Parquet. Plan B2: chỉ remote mode (executeQueries) |
| Định dạng VertiPaq/ABF đổi giữa các bản | Trung bình | Dựa trên [MS-XLDM] + test trên cả file 1.28 và 1.32; báo lỗi rõ khi gặp phiên bản lạ |
| DAX semantics sai ở góc khuất (blank, auto-exist, sort-by-column) | Cao | Differential test bắt buộc; hàm nào chưa hỗ trợ thì hiện "Unsupported" thay vì ra số sai |
| Swift Charts thiếu trục phụ / tuỳ biến | Trung bình | Overlay 2 `Chart` cùng plot area, hoặc vẽ trục bằng `Canvas` |
| Custom visual (.pbiviz, JS) | Thấp (Nhom6 không dùng) | Hiện placeholder; về sau nhúng `WKWebView` |
| `SecurityBindings`/refresh dữ liệu | — | Ngoài phạm vi; chỉ dùng dữ liệu đã cache trong `DataModel` |
| Pháp lý | — | Không decompile Power BI Desktop; chỉ dùng định dạng file của mình, schema/đặc tả công khai |

## 6. Việc tiếp theo ngay
1. Phase 0 spike: CLI `pbix-dump` (Swift Package + C target XPress9) chạy trên `Nhom6_Dashboard.pbix`.
2. Xuất DAX của 95 measure ra `docs/measures.dax` để chốt phạm vi DAXEngine.
3. Khởi tạo Xcode project và `Package.swift` theo cây module ở §2.

## Phụ lục: Evidence REA
| Evidence ID | Thao tác | Nội dung |
|---|---|---|
| `ev_4e00c45bdbe89ef2db83ff0d094de42f459deaec5bb10e348458e36b13828bc2` | `inspect_artifact` | Inventory ZIP, kích thước DataModel 54.181.200 B, hash đã verify |
| `ev_bea1e4f8ad99a0b598e075547ea8ae15af3fa34e15171c3cdc82f33633a64d28` | `extract_artifact` | Giải nén toàn bộ part để đọc JSON |
| `ev_a27737b2706bf7b93d7e0631df22f363753d6065816ea4a130dec7ef0aa4756f` (parent `ev_96df5548…`) | `inspect_byte_entropy` | DataModel entropy 7,9959, một run "high" phủ toàn file |

Giới hạn: entropy không phân biệt được nén với mã hoá. Phần bố cục block XPress9 và nhận định DPAPI là suy luận từ byte header, chưa được REA xác nhận. Nội dung ABF và DAX chưa quan sát được.
