# BI Pro: kế hoạch build app (v3, theo thư mục `UIdesign`)

> Cập nhật 2026-10-31 sau khi bạn chốt: tên **BI Pro**, định dạng lưu **`.pbix`**, màu theo macOS system blue, làm bản xem có số liệu trước, **chưa làm AI**.
> Thay cho §3 của `PORTING_PLAN.md`. Phần định dạng file và kết quả Phase 0 ở tài liệu cũ vẫn giữ nguyên giá trị.

## 0. Quyết định đã chốt

| # | Quyết định | Hệ quả |
|---|---|---|
| 1 | Tên app **BI Pro**, định dạng tài liệu **`.pbix`** | BI Pro vừa mở vừa **lưu** `.pbix`. Phải ghi được cả `DataModel` (ABF + VertiPaq + `metadata.sqlitedb`, nén XPress9) chứ không chỉ phần report. Đây là rủi ro kỹ thuật lớn nhất, nên được tách thành **Phase W** (spike) ngay sau Phase A |
| 2 | Màu theo phần mô tả trong `DESIGN.md` (system blue `#0A84FF`, chrome `#F5F5F7`, nền `#EBEBF0`) | Bỏ bảng màu Material 3 ở front-matter |
| 3 | Bản xem có số liệu (M1) trước, sau đó mới tới authoring và Power Query | Thứ tự A → W → B → C → D → E → F → G |
| 4 | Chưa làm AI | Ẩn các nút Copilot / Model Copilot / Generate trên UI. Bỏ khỏi Phase G |

*Lưu ý về tên:* "BI Pro" gần với tên gói license *Power BI Pro* của Microsoft. Dùng nội bộ thì không sao. Nếu sau này phát hành công khai thì nên tra nhãn hiệu trước.

## 1. Đọc bộ thiết kế

### 1.1 Design system (`DESIGN.md`)
- Phong cách macOS Sequoia, light mode, dùng vật liệu mờ (vibrancy), viền mảnh 1 px `#E5E5EA`, mật độ thông tin cao.
- **Màu (đã chốt):** accent `#0A84FF`, indigo `#5E5CE6`; nền cửa sổ `#EBEBF0`, chrome `#F5F5F7`, canvas `#FFFFFF`; chữ `#1C1C1E / #636366 / #8E8E93`. Bảng màu dữ liệu 6 màu: `#0A84FF #5E5CE6 #30B0C7 #34C759 #FF9F0A #FF453A`.
- **Chữ:** SF Pro / SF Mono (thay cho Inter / JetBrains Mono trong thiết kế), có số tabular, theo thang `display 28 → label-sm 10`, riêng KPI là `metric-display 24/700`.
- **Hình khối:** tile 8 px, nút/ô nhập 6 px, segmented 6/5 px, badge 4 px. Khoảng cách 4/8/12/16/24.
- **Bố cục 5 vùng:** title bar 52 px (gồm cả search ⌘K) · sidebar trái 240 px (200–360) · canvas trên nền `#EBEBF0`, lề 16 px, lưới 8 px · inspector phải 280 px · thanh filter/formula 32 px.
- **Component có spec:** nút primary/secondary/ghost, segmented pill, visual tile (viền chọn 1,5 px và 8 tay cầm resize), tree view (thụt 12 px, dòng 24/28 px), search field, checkbox 14 px, toggle 36×20, filter chip 22 px.
- Icon: chuyển Material Symbols sang SF Symbols. Token đặt tên theo ngữ nghĩa để thêm dark mode về sau.

### 1.2 Danh mục màn hình → tính năng

Các bản có hậu tố `_fixed` được coi là bản chuẩn. Một số ảnh là bản nháp có lỗi trình bày (Advanced Editor bị vỡ chữ, `formatting_panes_1` có vùng đen, model view bỏ trống nửa dưới); những lỗi này không làm theo. Thanh trái có 5 workspace: Report Canvas · Table View · Model View · DAX Query View · TMDL View.

| Màn hình | Workspace | Thành phần chính | Phụ thuộc engine | Phase |
|---|---|---|---|---|
| `report_view` | Report Canvas | Title bar, ribbon Home, rail trái, tile KPI, chart, Filters pane, Build pane (lưới visual, well X/Y/Legend), Data pane, tab trang, zoom | DAX, filter context | A, C, D |
| `report_view_formatting_panes_fixed` (+ `_1`, `_2`) | Report Canvas | Format pane (Visual/General, tìm thuộc tính, các card thuộc tính, toggle), Selection pane, Bookmarks pane, Filters thu gọn | Format schema theo visual type | C, D |
| `table_view_fixed` | Table View | Ribbon Table tools/Column tools, formula bar DAX, lưới có sort/filter từng cột, cột tính toán, Data pane, panel Column metadata, status bar | VertiPaq (đã có), DAX cột tính toán | A, E |
| `model_view` (+ 3 biến thể) | Model View | Sơ đồ bảng dạng card (PK/FK/DAX), đường quan hệ 1/\* có mũi tên, popover và side panel Relationship properties, cây Semantic model, tab layout, zoom | Metadata (đã có) | A, E |
| `dax_query_view` | DAX Query View | Tab query, Run/Cancel/Format/Comment/Update model, editor DAX, lưới kết quả + Copy/Export CSV, Data Model tree, Quick queries, DAX Quick Guide. *Ô "Generate" (AI) ẩn đi* | DAX query | B |
| TMDL View | TMDL View | Editor TMDL | Serialize/parse TMDL | A (chỉ đọc), E (sửa) |
| `get_data_dialog`, `navigator_dialog_fixed` | Modal | Danh mục connector, xem trước, Load / Transform Data | Connectors tự viết | F |
| `query_editor_1/2/3`, `_transform_tab` | Cửa sổ Query Editor | Ribbon File/Home/Transform/Add Column/View, cây query có nhóm, formula bar M, lưới có column quality/distribution/profile, Applied Steps, Close & Apply | M engine | F |
| `advanced_editor`, `custom_column`, `merge_dialog_1/2` | Modal | Editor M, công thức cột, join có thống kê độ khớp | M engine | F |
| `query_dependencies_exact_graph_coordinates` | Cửa sổ | Đồ thị 4 cột Sources → Staging → Final → Model | Lineage | F |

**Có trên giao diện nhưng ẩn hoặc thay thế:**

| Nút | Xử lý |
|---|---|
| Copilot, Model Copilot, Generate | **Ẩn** (đã chốt: chưa làm AI) |
| Publish, Collaborate, avatar | Không có server → đổi thành menu **Export** (PDF, PNG, CSV) |
| DirectQuery / DirectLake / "Execution target" | Chỉ hỗ trợ Import. Bỏ các nhãn này |
| Roles / View as | Đã triển khai ở Đợt 4 (v1.2): `ManageRolesSheet` (lưu T2) + `ViewAsRoleSheet` (dải vàng & tự tiêm lọc RLS vào DAX) |
| Calculation groups, Perspectives, Cultures | Hiển thị trong cây model và giữ nguyên khi lưu. Sửa thì để sau v1.2 |
| Q&A setup, tab Optimize | Sau v1 |

## 2. Lưu `.pbix`: chiến lược theo tầng

Một file `.pbix` gồm phần report (JSON PBIR, dễ ghi) và phần `DataModel` (khó ghi). Mỗi lần lưu, BI Pro chọn **tầng thấp nhất đủ dùng** cho những gì đã thay đổi. Phần không đổi được chép nguyên byte.

| Tầng | Khi nào | Ghi gì | Độ khó | Phase |
|---|---|---|---|---|
| **T1: chỉ report** | Sửa trang, visual, format, bookmark, filter | Viết lại `Report/**` (PBIR); chép nguyên `DataModel`, `SecurityBindings`, `Settings`, `Metadata`, `Version` | Thấp | D |
| **T2: metadata model** | Sửa/thêm measure, format string, quan hệ, đổi tên, ẩn cột, display folder | Sửa `metadata.sqlitedb` → dựng lại ABF (virtual directory, backup log, offset) → nén lại XPress9. Dữ liệu VertiPaq giữ nguyên | Trung bình | E |
| **T3: dữ liệu** | Thêm cột tính toán, bảng mới, Close & Apply sau Power Query, tạo file mới | Ghi VertiPaq: dictionary, IDF (RLE + bit-packing), idfmeta, hidx, quan hệ, thống kê; cập nhật metadata | Cao | F (một phần ở E) |

**Các điểm còn phải xác minh** (làm ở Phase W):
- Power BI Desktop có chấp nhận ABF do BI Pro dựng lại không, và có kiểm tra checksum hay chữ ký nào không.
- `SecurityBindings` là blob DPAPI gắn với máy Windows. Có cần giữ nguyên, bỏ đi, hay để trống với file tạo mới?
- Index của quan hệ và hash index (`hidx`, `R$…`, `H$…`) có bắt buộc phải có không, hay engine tự dựng lại khi mở.

**Phương án dự phòng nếu T3 không qua được:** với bảng mới, ghi dữ liệu vào biểu thức M dạng "Enter Data" (dữ liệu nén nhúng ngay trong M), giống cách Power BI lưu bảng Enter Data. Power BI Desktop sẽ nạp lại khi bấm Refresh; BI Pro vẫn đọc dữ liệu từ bộ nhớ đệm riêng của mình. Ngoài ra, xuất `.pbip` luôn là lối thoát an toàn.

## 3. Những gì dùng lại từ code hiện tại

| Đã có | Dùng cho |
|---|---|
| `PBIXKit`: ZIP, XPress9 (giải nén), ABF, VertiPaq, `ModelMetadata`, `ReportDefinition` (PBIR + Layout cũ), theme | Mở `.pbix`. Sẽ thêm phần *ghi*, đối xứng với từng bộ đọc |
| Bộ mã XPress9 đã tải (gồm cả encoder `Xpress9EncLz77.c`, `Xpress9EncHuffman.c`, MIT, của Microsoft) | Nén khi lưu (T2, T3). Chỉ cần vendor thêm 2 file |
| App hiện tại (render visual tĩnh, lưới NSTableView, Inspector) | Logic giữ lại; **shell sẽ được làm lại** theo bố cục 5 vùng |
| `pbix-dump`, 8 test | Chẩn đoán và test hồi quy. Sẽ thêm lệnh `roundtrip` để kiểm tra ghi |

## 4. Kiến trúc mục tiêu

```
BI Pro (SwiftUI + AppKit, macOS 15+)
├── DesignSystem      Token + component theo DESIGN.md
├── Shell             Title bar 52 px, ribbon (có tab theo ngữ cảnh), rail 5 workspace, pane phải,
│                     tab trang, status bar, ⌘K
├── Workspaces        ReportCanvas · TableView · ModelView · DAXQueryView · TMDLView
├── Windows           QueryEditor · QueryDependencies · Dialogs
│
├── PBIXDocument      ReferenceFileDocument (đọc và ghi .pbix) + UndoManager
│   ├── SemanticModel   sửa được; theo dõi thay đổi để chọn tầng lưu T1/T2/T3
│   ├── ReportModel     ánh xạ 1-1 với PBIR (file Layout cũ sẽ được nâng lên PBIR khi lưu)
│   └── QueryModel      các query M
│
├── Engines
│   ├── ColumnStore · DAXEngine · QueryPlanner
│   ├── MEngine         parser M + các hàm Table.* tự viết, chạy trên cột từ điển của ColumnStore (không fold sang SQL)
│   └── Connectors      tự viết, chỉ framework hệ thống (CSV, Excel xlsx, JSON, SQLite; Parquet và PostgreSQL tập con ở P3)
│
└── PBIXKit           đọc (đã có) + ghi: PBIRWriter, MetadataWriter (SQLite), ABFWriter,
                      VertiPaqWriter, XPress9 encoder
```

**Quyết định kỹ thuật:**
1. **`.pbix` là định dạng duy nhất** cho tài liệu (đọc và ghi). File Layout cũ (1.28) khi lưu sẽ được nâng lên PBIR, giống cách Power BI Desktop đời mới làm. Trước khi ghi đè, BI Pro hỏi người dùng hoặc tạo bản sao lưu.
2. **Nạp dữ liệu và chạy Power Query tự viết** (không DuckDB), chỉ dùng framework hệ thống (`Compression`, `XMLParser`, `JSONSerialization`, `sqlite3`, `Network`). Chốt 2026-11-15 khi duyệt `specs/010-f-get-data-power-query-t3/plan.md` (R1): DuckDB chỉ chạy SQL, không giải ngữ nghĩa M. Parquet đủ nén `zstd` và PostgreSQL đầy đủ để P3; cần thì hỏi lại về thư viện ngoài. DAX vẫn dùng engine tự viết.
3. DAX Query View được làm cùng engine, vừa là tính năng vừa là công cụ debug.
4. **AppKit cho các phần nặng:** lưới (NSTableView), editor DAX/M/TMDL (NSTextView + TextKit 2), sơ đồ model và đồ thị (Canvas).
5. **An toàn dữ liệu khi lưu:** ghi ra file tạm → đọc lại bằng chính PBIXKit để kiểm tra → mới thay file thật. Giữ một bản sao lưu `.pbix.bak` ở lần lưu đầu tiên.

## 5. Lộ trình

Ước lượng cho 1 dev toàn thời gian. Mỗi phase kết thúc bằng một bản app chạy được.

### Phase A: Design system và shell ✅ 2026-10-31
- [x] Đổi tên thành **BI Pro** (`build/BI Pro.app`, bundle `local.bipro.app`, target `BIPro`). `Info.plist` vẫn để role Viewer; chuyển sang Editor ở Phase D.
- [x] `DesignSystem/Tokens.swift` (màu, chữ, bo góc, khoảng cách, đổ bóng) và `Components.swift` (RibbonButton/Group/Stack, SegmentedPill, PaneHeader, CollapsedPaneStrip, SearchField, TreeRow, CheckboxMark, SwitchMark, FieldChip, Badge, các ButtonStyle).
- [x] Shell: title bar 52 px (tên file, badge "Chỉ xem", ⌘K tìm trang/bảng/cột/measure/visual, menu Xuất), ribbon với tab theo ngữ cảnh (Định dạng, Dữ liệu/Truy sâu, Công cụ bảng/cột), rail 5 workspace, status bar. Lệnh của phase sau hiện mờ, tooltip ghi phase.
- [x] **Báo cáo:** canvas zoom/fit, viền chọn 1,5 px và 8 tay cầm; các pane Bộ lọc / Trực quan hóa (Xây dựng: lưới visual + field well; Định dạng: card thuộc tính chỉ đọc) / Dữ liệu / Lựa chọn / Bookmark, gập được; tab trang, có đánh dấu trang ẩn.
- [x] **Bảng:** formula bar, lưới NSTableView (cột `#`, bấm tiêu đề để chọn cột, cột tính toán tô xanh), panel Thông tin cột, ribbon Công cụ cột đọc từ metadata.
- [x] **Mô hình:** sơ đồ card (PK/FK/DAX, cột ẩn), đường quan hệ 1/\* có mũi tên lọc, nét đứt cho quan hệ inactive, kéo card, panel thuộc tính quan hệ, cây Semantic model, tab layout, zoom.
- [x] **Truy vấn DAX:** tab, editor tô màu cú pháp có số dòng, Chú thích //, "Định nghĩa và đánh giá" từ menu measure (chạy truy vấn ở Phase B).
- [x] **TMDL:** 15 tệp sinh từ metadata (chỉ đọc), Sao chép, Xuất thư mục TMDL.
- [x] Kiểm tra bằng ảnh chụp REA trên Nhom6 (PBIR) và Nhóm 3 (Layout cũ + DiagramLayout); 15/15 test pass.

**Cách Power BI hoạt động, quan sát bằng REA và áp dụng ở Phase A** (từ file `.pbix` của bạn, không decompile Power BI):

| Quan sát | Nguồn | Áp dụng |
|---|---|---|
| `Column.IsHidden=1` cho mọi cột khoá; `SummarizeBy` 2 = none, 3 = sum; `SortByColumnID` (`month_name` → `month_num`); `DataCategory` City/StateOrProvince | `metadata.sqlitedb` (REA `inspect_sqlite_database`) | Data pane ẩn cột ẩn trong Báo cáo, Σ cho cột tóm tắt, icon bản đồ, ribbon Công cụ cột |
| Cả 168 measure đều có `DisplayFolder`; 6 hierarchy (`Thời gian`: Năm › Quý › Tháng › Ngày) | `metadata.sqlitedb` | Data pane gom theo folder, hiện hierarchy và các cấp |
| `DiagramLayout` (UTF‑16 JSON): tab "All tables", `zoomValue` 60, vị trí và kích thước card (rộng 234) | REA `extract_artifact` trên file Nhóm 3 | Model view dùng đúng layout và zoom của Power BI; file PBIR không có part này thì tự sắp hình sao |
| `pages.json` `activePageName` / `activeSectionIndex` | PBIR / Layout cũ | Mở lại đúng trang đang mở khi lưu |
| `filterConfig` cấp report/trang/visual (`Not In`…) | `report.json`, `page.json`, `visual.json` | Pane Bộ lọc: "year không phải 9999" |

### Phase W: Spike ghi `.pbix` ✅ 2026-10-31 (hoàn thiện gate T1/T2/T3 qua Phase D/E/F)
> Plan chi tiết, cách chia việc cho agent song song và checklist test tay trên VM: [`PHASE_W_PLAN.md`](PHASE_W_PLAN.md).

- [x] Vendor encoder XPress9; viết `ABFWriter` + `DataModelStream.compress`. (WP1, WP3)
- [x] Offline: dựng lại ABF khớp từng byte; nén → giải nén khớp; ZIP copy raw khớp; metadata thêm measure đọc lại được.
- [x] **W1:** round-trip không đổi → mở được trong Power BI Desktop (VM). Người dùng xác nhận mở được, dữ liệu nạp đủ (2026-10-31).
- [x] **W2 (T1):** sửa report/tiêu đề visual → mở được trong Power BI Desktop (xác nhận toàn diện qua cổng Phase D `Nhom6_d1..d7.pbix` và v1.1a/v1.1b/v1.2).
- [x] **W3 (T2):** thêm measure & sửa metadata model → mở được và chạy đúng trong Power BI Desktop (xác nhận qua cổng Phase E `docs/phase-e-evidence/vm-e2`, `vm-e3` và v1.2 `bipro-v12-gate.pbix`).
- [x] **W4 (T3):** bảng mới (dữ liệu VertiPaq) → mở được, dữ liệu khớp từng ô trong Power BI Desktop (thay bằng gate F-T3 của Phase F `docs/phase-f-evidence/CHECKLIST-M3.md` và `specs/011` 10M dòng nhiều đoạn + nén RLE).
- [x] Lệnh `pbix-dump roundtrip`, `set-title`, `add-measure` (`PBIXWriter`). Test tự động qua.
- **Xong khi:** W1–W4 đạt. **Đạt 100%.**

### Phase B: DAX engine và DAX Query View ✅ 2026-11-02
> Plan multi-agent chi tiết, oracle và lịch test tay: [`PHASE_B_PLAN.md`](PHASE_B_PLAN.md). Nghiên cứu: `docs/phase-b-research/`.
- [x] ColumnStore + quan hệ (lọc một chiều/hai chiều, active/inactive, `USERELATIONSHIP`, blank row).
- [x] DAX lexer/parser/binder/evaluator; **43 hàm** mà 119 measure Nhom6 cần (đo lại, kế hoạch cũ ghi khoảng 40), gồm `CALCULATE`, `REMOVEFILTERS`, `KEEPFILTERS`, `ALLSELECTED`, `TREATAS`, `ISFILTERED`, `SAMEPERIODLASTYEAR` (đã mở rộng thêm ~56 hàm ở v1.1b).
- [x] Truy vấn: `EVALUATE`, `DEFINE MEASURE/VAR`, `SUMMARIZECOLUMNS`, `ORDER BY`, `TOPN`, `ROW`.
- [x] DAX Query View theo `dax_query_view` (không có ô AI): UI1–UI4 hoàn tất (chạy/huỷ, lưới kết quả có lọc/sắp xếp, thanh trạng thái, tooltip measure, quick queries, ô Dữ liệu Bảng/Mô hình, menu chuột phải, gạch chân lỗi `EditorDiagnostics`, tự hoàn thành `DAXCompletion`/`CompletionPopup`, đổi tên tab tại chỗ `QueryTabBar`; mở rộng thêm `Định dạng` & `Cập nhật mô hình` ở v1.2).
- [x] Oracle: golden từ DAX Query View của Power BI Desktop (bạn chạy tay trong VM), cộng oracle tự động (sqlite, cột tính toán đã lưu, test thuộc tính, bộ tí hon).
- **Xong khi:** 119 measure Nhom6 khớp golden G0–G3, G5, G6. **Đạt 30/30 golden khớp Power BI.**

### Phase C: Report có số liệu và tương tác → **M1** ✅ 2026-11-06
> Kế hoạch chi tiết: [`PHASE_C_PLAN.md`](PHASE_C_PLAN.md); tối ưu hiệu năng: `specs/001-e3-cau-truc/` (trang D1 ~0,58 s).
- [x] Visual có số (72/72 truy vấn visual khớp Performance Analyzer): card/KPI, bar/column/line/combo, donut/pie, treemap, 100% stacked, table/matrix, slicer, shape map; định dạng số, conditional formatting (mở rộng đầy đủ 40 loại visual ở v1.1a và CF Rules/Gradient/Field/Data Bars ở v1.1b).
- [x] Filters pane, slicer lọc thật, cross-filter/highlight, drill/drillthrough, tooltip, Selection pane, Bookmarks pane (mở rộng Edit Interactions & Matrix phân cấp hàng ở v1.1b).
- **Xong khi:** cả 4 trang Nhom6 tương tác như trên Power BI. **Đạt.**

### Phase D: Sửa report + lưu T1 ✅ 2026-11-11 (bổ sung VM-D8/D10/D12/D15 & v1.1a/v1.1b)
- [x] Build pane (lưới visual, field well, kéo thả: **D2, D3**), Format pane (danh mục từ quan sát, sửa được và lưu T1: **D4**), ribbon Insert (**D3**, mở khoá đầy đủ Hình/Nút/Điều hướng/Ảnh ở **v1.1a**), quản lý trang (thêm/xoá/đổi tên/nhân bản/đổi thứ tự: **D5**).
- [x] **Lát D1** (2026-11-09, `specs/002-d1-canvas-luu-t1/`): canvas chọn (một và nhiều), di chuyển, đổi cỡ, snap 8 px, xoá, nhân bản, chép/dán, hoàn tác/làm lại; **lưu `.pbix` tầng T1** (Lưu, Lưu thành, bản sao lưu, chặn ghi vào Downloads); app đăng ký Editor; qua cổng Desktop `VM-D1`.
- [x] **Lát D2 (D2a + D2b)** (2026-11-10, `specs/003-d2-build-pane-field-well/` + `specs/011` US1): Build pane sửa trường (thêm, bỏ, đổi thứ tự, chuyển ô, đổi tên hiển thị; kéo từ pane Dữ liệu), vẽ lại ngay, hoàn tác chung, lưu T1 (`PBIRQueryPatch`); bỏ trường tự dọn định dạng theo quy tắc Desktop (`VM-D2`); phép gộp ngầm (`SUM`/`AVERAGE`/`COUNT`…) hoàn tất ở `specs/011` (`VM-F10`).
- [x] **Lát D3 (D3a + D3b)** (2026-11-10, `specs/004-d3-them-visual-doi-loai/` + `VM-D3/D12/D15` + `specs/013`): thêm visual mới (thư viện Build pane, ribbon Chèn), đổi loại visual giữ trường & lọc khoá `objects` theo Desktop, sửa chữ hộp văn bản, hỗ trợ 40 loại visual (`VisualTypes.supported`), lưu T1; qua cổng Desktop.
- [x] **D4 Format pane** (2026-11-10 + bổ sung `VM-D8/D12/D15`, `specs/006-d4-format-pane/`): sửa thuộc tính trong danh mục đã quan sát (gồm matrix `pivotTable` mới, `dataPoint` theo chuỗi/Chú giải `selector.metadata` & `selector.data`, phông chữ tiêu đề, nền, đổ bóng, `shape`, `actionButton`), ghi `objects` và `visualContainerObjects` bằng ghép byte, hoàn tác chung, lưu T1; qua cổng Desktop.
- [x] **D5 Quản lý trang** (2026-11-10 + `VM-D8`, `specs/005-d5-quan-ly-trang/`): thêm, đổi tên, đổi thứ tự (kéo tab), nhân bản, xoá trang; xoá trang gỡ bookmark trỏ tới và giữ nguyên nút `PageNavigation` kèm thông báo đúng hành vi Desktop (`VM-D8`); lưu T1; hoàn tác chung; qua cổng Desktop.
- [x] **D6 Bookmark và bộ lọc ghi vào file** (2026-11-11 + `VM-D8/D10` + v1.1b, `specs/007-d6-bookmark-filter/`): thêm, cập nhật, đổi tên, xoá, đổi thứ tự, gom nhóm bookmark và thêm, sửa, bỏ thẻ lọc Basic, Advanced (chữ, số, ngày `datetime'...'`, `Hoặc`, `là`/`không là`), Top N / Bottom N, thẻ measure ở cấp báo cáo/trang/visual, ghi `bookmarks/` và `filterConfig` bằng ghép byte; hoàn tác chung; qua cổng Desktop. *(Ghi chú phạm vi: Bookmark Data có lọc chéo, drill, mở nút matrix/slicer, slicer nhiều cấp hoạt động đầy đủ trong phiên từ v1.1b và báo rõ khi lưu `.pbix`.)*
- [x] **D7 Nhóm, căn lề và định dạng cũ** (2026-11-11 + `VM-D8`, `specs/008-d7-nhom-can-le-cu/`): căn lề và phân bố, chép dán giữa các trang, nhóm visual đầy đủ (Group, Ungroup, **Merge vào nhóm**, **nhóm lồng nhau**, di chuyển, co giãn ngang/dọc theo tỷ lệ, xoá nhóm & dọn bookmark, nhân bản), sửa bố cục báo cáo định dạng cũ `Report/Layout`; hoàn tác chung; lưu T1; qua cổng Desktop (`Nhom6_d7.pbix`, `Nhom2_d7.pbix`).
- **Xong khi:** sửa trang Nhom6 trong BI Pro, lưu, rồi mở lại được cả trong BI Pro lẫn Power BI Desktop. **Đạt.**

### Phase E: Mô hình hoá + lưu T2 (4–5 tuần) → **M2** ✅ 2026-11-14
> **Xong phần code và kiểm Desktop (2026-11-14)**: Spec Kit `specs/009-e-mo-hinh-hoa-luu-t2/`; bằng chứng ở `docs/phase-e-evidence/` (VM-E1 đến VM-E5). Cột tính toán và bảng tính toán hoàn tất ở Phase F (`specs/010`–`011`). Golden nặng bản release và `/code-review` đã xong; VM-E6 (tab bố cục, quan hệ hoạt động, tổng hợp và sắp xếp cột) đạt.
- [x] **Measure** (Câu chuyện 1): tạo, sửa, xoá ở Table view (thanh công thức `Tên = biểu thức`, kiểm bằng engine, suy kiểu và định dạng như Desktop), thuộc tính (mô tả, thư mục, định dạng, ẩn), đổi tên lan truyền (`CascadeRename`, v1.1b); menu ở ngăn Data (cả chế độ Báo cáo) và ngăn Properties ở Model view; hoàn tác chung; lưu T2.
- [x] **Quan hệ** (Câu chuyện 2): sửa hướng lọc và bật/tắt, tạo bằng kéo cột thả cột (hộp xác nhận, dò bản số, ghi đủ chỉ mục `R$` như Desktop), xoá; engine nạp lại tái dùng cột đã giải mã.
- [x] **Table View đầy đủ** (Câu chuyện 3): sửa thuộc tính cột (tên, mô tả, thư mục, định dạng, tổng hợp, loại dữ liệu, sắp xếp theo cột, ẩn) ở cả ngăn `ColumnPropertiesEditor` lẫn trực tiếp trên thanh Ribbon **Công cụ cột** (`Định dạng`, phím nhanh `$ % , .00`, `Tóm tắt`, `Danh mục`, `Sắp xếp theo cột`, `Tên`) và **Công cụ bảng** (`Tên` → Cascade Rename); lưới có sắp xếp và lọc chỉ để xem.
- [x] **Model View sửa được** (Câu chuyện 4): kéo thẻ bảng, thu phóng, ẩn/hiện bảng, ghi `DiagramLayout`, thêm/đổi tên/xoá tab bố cục và gỡ bảng khỏi tab (VM-E6, VM-E7, Desktop mở đúng). Đổi thứ tự tab: Desktop không kéo đổi được nên không làm.
- [x] **TMDL View sửa được** (Câu chuyện 5): áp dụng nguyên khối (measure, thuộc tính cột, bảng ẩn, quan hệ), lỗi theo dòng.
- [x] **Lưu tầng T2**: `PBIXChanges.modelEdits`, `MetadataWriter.apply`, kiểm đọc lại; lưu Nhom6 khoảng 2,5 s (bản release).
- **Xong khi:** thêm measure và quan hệ trong BI Pro, lưu, rồi Power BI Desktop đọc đúng. **Đạt** (`vm-e2`, `vm-e3`).

### Phase F: Get Data, Power Query + lưu T3 → **M3** ✅ 2026-11-17 (+ tồn đọng `specs/011` 2026-11-19)
- [x] Connector tự viết (không DuckDB): CSV, Excel (đợt 1, P1); JSON, SQLite; Parquet và PostgreSQL tập con (P3).
> **Gate M3 ĐẠT (2026-11-17)**: Spec Kit `specs/010-f-get-data-power-query-t3/`, bằng chứng `docs/phase-f-evidence/` (`CHECKLIST-M3.md`). Sửa/xoá cột và bảng tính toán (FR-060) xong, gate Desktop ĐẠT (`vm-f9/KET-QUA.md`, 2026-11-17). Tồn đọng sau Phase F (Spec Kit `specs/011-ton-dong-sau-phase-f/`, 2026-11-19, bằng chứng `docs/phase-f2-evidence/`): phép gộp ngầm,
Auto date/time và tự phát hiện quan hệ, màn "Thêm dữ liệu vào báo cáo", Enter Data, hàm văn bản DAX, sửa/xoá cột tính toán còn được dùng
(dựng lại `R$`/`U$`), lưu nhiều đoạn dữ liệu và nén RLE (T111), PostgreSQL thêm kiểu, chọn driver ODBC SQLite, Parquet lồng.
- [x] Get Data → Navigator → Query Editor (Applied Steps, formula bar, column profile, ribbon) → Close & Apply.
- [x] M engine (khoảng 30 hàm `Table.*`), các hộp thoại Advanced Editor, Custom Column, Merge, Append, Group By, cửa sổ Query Dependencies.
- [x] **Lưu tầng T3** (dữ liệu mới vào VertiPaq), tạo `.pbix` mới từ đầu.
- **Xong khi:** đi hết luồng `sales_2026.xlsx` → Query Editor → Close & Apply → report → lưu `.pbix` → mở được trong Power BI Desktop. **Đạt** (T100, 2026-11-17).

### Phase G: Hoàn thiện → **v1.0** ✅ 2026-11-21
> **Mốc v1.0 ĐẠT (2026-11-21)**: Spec Kit `specs/012-g-hoan-thien-v1/`, bằng chứng `docs/phase-g-evidence/`, số đo `specs/012-g-hoan-thien-v1/measurements.md`.
- [x] Export PDF/PNG/CSV (`VisualCSVExporter` RFC 4180 + UTF-8 BOM, `ReportPageExporter` PNG 1×/2× & PDF nhiều trang vectơ, `ExportSheet`, menu `Xuất` Title bar / `Tệp ▸ Xuất` / chuột phải visual).
- [x] Quick Look cho `.pbix` (`PBIXQuickLookSummary` `< 1 s`, `PBIXQuickLookRenderer`, `PBIXQuickLook.appex` + `PBIXThumbnail.appex` đóng gói trong `scripts/build-app.sh`, kiểm thực tế qua `QLThumbnailGenerator` trên macOS 15).
- [x] Dark Mode (`DS.Palette` màu động macOS 15 Sequoia cho toàn bộ 5 workspace/sheet/AppKit bridge; giữ nguyên nền tài liệu `.pbix` trên Report Canvas) & Cài đặt ứng dụng (`SettingsView`, `⌘,`, nút bánh răng Rail, `AppPreferences`).
- [x] Song ngữ Tiếng Việt và Tiếng Anh (`L10n`, nhãn phép gộp ngầm, bất biến byte `.pbix`).
- [x] VoiceOver & trợ năng (`VisualAccessibilitySummary`, nhãn trợ năng toàn vỏ ứng dụng & visual, `AccessibilityAnnouncer`).
- [x] Biểu tượng ứng dụng (`scripts/make-icon.swift` → `AppIcon.icns`), Hướng dẫn lần đầu (`OnboardingView` 3 bước) và đóng gói `build/BI Pro.app` phiên bản **1.0.0**.

### Đợt 2 (v1.1a): Hoàn thiện Hệ Biểu đồ, Slicer nâng cao & Phần tử chèn ✅ 2026-11-21
> **Đạt cổng Desktop 2.159 (2026-11-21)**: Spec Kit `specs/013-v11-bieu-do-visual/`, bằng chứng `docs/phase-v11-evidence/vm-v11a/` (`QUAN-SAT.md`, 32 tệp JSON PBIR, `gate-desktop.png` 19/19 visual), số đo `specs/013-v11-bieu-do-visual/measurements.md`.
- [x] **2A:** `barChart` / `stackedBarChart`, `hundredPercentStackedBarChart`, `pieChart` (đồng bộ quy ước Desktop 2.159).
- [x] **2B:** `tableEx` (bảng phẳng, sort cột, dòng `Total`, lọc chéo), `scatterChart` (1D/2D + bubble `Size` + `Series`), `gauge` (180°, mặc định `Max = 2 × Value`, vạch `Target`), `kpi` (sparkline + mục tiêu & % chênh lệch), `multiRowCard`.
- [x] **2C:** Slicer nâng cao (`advancedSlicerVisual` Tile, `listSlicer`, `textSlicer` `CONTAINSSTRING`, `slicer` `'Between'` 2 đầu cho số & ngày) và Bản đồ ngoại tuyến 100% (`OfflineGeoAtlas` & `GeoMapView` cho `map` / `filledMap`).
- [x] **2D:** Mở khoá ribbon **Chèn** (Trang mới, Hình khối `rectangle`/`oval`/`line`, Nút hành động, `pageNavigator`, `bookmarkNavigator`, Ảnh PNG/JPEG/SVG nhúng `RegisteredResources` + tự khai báo phần mở rộng vào `[Content_Types].xml`), `BookmarkNavigatorVisual`, mở rộng `FormatCatalog`, `VisualCSVExporter`, `AccessibilitySummary` song ngữ.

### Đợt 3 (v1.1b): Tương tác nâng cao, CF/Analytics/Theme, One-Click Refresh, Cascade Rename & DAX Engine ✅ 2026-11-21
> **Đạt cổng Desktop 2.159 (2026-11-21)**: Spec Kit `specs/014-v11-tinh-nang-nang-cao/`, bằng chứng `docs/phase-v11-evidence/vm-v11b/` (`QUAN-SAT.md`, `dax-golden.json` 21/21, `gate-desktop.png` 0 lỗi), số đo `specs/014-v11-tinh-nang-nang-cao/measurements.md`.
- [x] **3D (DAX Engine):** ~56 hàm mới (Date/Time, 23 Time Intelligence, Error/Type, Lookup/Set/Table/Stats, Window `OFFSET`/`INDEX`/`WINDOW` + `ORDERBY`/`PARTITIONBY`) khớp 100% oracle Desktop 2.159.
- [x] **3A (Tương tác & Matrix & Bộ lọc):** Edit Interactions (`visualInteractions`), Matrix phân cấp hàng (`expansionStates`), kéo-thả trường vào `FiltersPane`, Date Advanced Filter (`datetime'...'`), mở rộng Bookmark Data.
- [x] **3B (CF, Analytics & Theme):** Conditional Formatting (Rules/Gradient/Field value/Data Bars), Analytics Pane (Constant/Average/Min/Max + Trend/Forecast), Theme Switcher (6 preset + Nhập/Xuất JSON + `RegisteredResources` + Undo/Redo).
- [x] **3C (Refresh, Cascade Rename & PQ Extra):** One-Click Refresh (`⇧⌘R`, giữ quan hệ/measure/visual & dữ liệu cũ khi lỗi), Cascade Rename bảng/cột/measure đang dùng (DAX token + PBIR + ⌘Z), Power Query Extra Transforms (Split nâng cao, Fill Down/Up, Replace Errors, Extract, Date).

### Đợt 4 (v1.2): Mở khoá toàn bộ Ribbon, RLS, Mark as Date Table, Quick Measures & Công cụ DAX/TMDL ✅ 2026-11-21
> **Đạt cổng Desktop 2.159 (2026-11-21)**: Spec Kit `specs/015-v12-hoan-thien-chuyen-nghiep/`, bằng chứng `docs/phase-v12-evidence/vm-v12/` (`QUAN-SAT.md`, `gate-desktop.png` 0 lỗi), số đo `specs/015-v12-hoan-thien-chuyen-nghiep/measurements.md`.
- [x] **Nền tảng `PBIXKit` & `DAXEngine`:** Ghi/đọc `[Role]` + `[TablePermission]` (RLS) và `DataCategory = 'Time'` + `IsKey = 1` (Mark as Date Table) khớp 100% Desktop 2.159; bộ định dạng `DAXEngine.format(_:)` thuần Swift.
- [x] **4A (Report & Data/Drill):** Cut/Copy/Paste visual (cùng trang & sang trang khác, `⌘X`/`⌘C`/`⌘V`), Format Painter trên canvas, mở khoá tab **Data / Drill** (*Drill up*, *Drill down*, *Expand next level*, *Show as a table* + Xuất CSV).
- [x] **4B (Mô hình hoá & RLS):** **Quick Measures** (8 mẫu chuẩn Power BI), **Mark as Date Table** (kiểm cột ngày duy nhất/không trống), **Manage Roles** (lưu T2) & **View As** (dải vàng + tự tiêm lọc RLS vào DAX), **DataPane** Hide/Unhide bảng/cột & Unhide All.
- [x] **4C (DAX / TMDL / SQL & v1.2.0):** DAX Formatter & DAX Update Model (`DEFINE MEASURE` theo lô), nút Áp dụng trên Ribbon TMDL View, menu kết nối nhanh SQL (PostgreSQL / SQLite), đóng gói `build/BI Pro.app` **v1.2.0**.

### Mốc thời gian
| Mốc | Gồm | Tích luỹ |
|---|---|---|
| Shell mới + spike ghi `.pbix` | A + W | khoảng 5 tuần |
| **M1: Viewer có số liệu** | + B + C | khoảng 17 tuần |
| **M2: Authoring, lưu `.pbix` (T1, T2)** | + D + E | khoảng 28 tuần |
| **M3: Data prep, lưu T3** | + F | khoảng 38 tuần |
| **v1.0** | + G | khoảng 41 tuần (khoảng 9,5 tháng) |

## 6. Kiểm thử
- **Hình ảnh:** chụp từng màn hình đã dựng lại và đặt cạnh `UIdesign/*/screen.png`. Sai lệch bố cục cho phép dưới 4 px, màu phải đúng token.
- **Engine:** differential test DAX so với oracle; test M bằng golden file.
- **Ghi `.pbix`:** với cả 6 file hiện có: round-trip qua BI Pro → đọc lại bằng PBIXKit (distinct count, metadata khớp) → mở trong Power BI Desktop trong VM (kiểm thủ công ở mỗi mốc).
- **Hiệu năng:** mở Nhom6 dưới 2 giây, lưu tầng T1 dưới 1 giây, tương tác dưới 150 ms một trang.

## 7. Rủi ro
| Rủi ro | Mức | Giảm thiểu |
|---|---|---|
| **Power BI Desktop từ chối `.pbix` do BI Pro ghi** | Cao | Phase W làm sớm; luôn chọn tầng lưu thấp nhất; có phương án dự phòng "Enter Data" và xuất `.pbip`; ghi file tạm rồi kiểm tra trước khi thay; giữ bản sao lưu |
| Định dạng VertiPaq/ABF đổi giữa các phiên bản Power BI | Trung bình | Bám theo [MS-XLDM]; ghi đúng phiên bản đã đọc; test trên cả file 1.28 và 1.32 |
| Phạm vi rất lớn | Cao | Chia mốc M1–M3, mỗi mốc là một bản dùng được |
| M engine, ngữ nghĩa DAX | Cao | Chỉ hỗ trợ các bước UI sinh ra; bắt buộc đối chiếu oracle; gặp hàm chưa hỗ trợ thì báo rõ |
| Mất dữ liệu người dùng khi lưu đè | Cao | Ghi nguyên tử + đọc lại kiểm tra + bản `.bak` |
