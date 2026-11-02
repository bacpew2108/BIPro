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
| `get_data_dialog`, `navigator_dialog_fixed` | Modal | Danh mục connector, xem trước, Load / Transform Data | DuckDB / connector | F |
| `query_editor_1/2/3`, `_transform_tab` | Cửa sổ Query Editor | Ribbon File/Home/Transform/Add Column/View, cây query có nhóm, formula bar M, lưới có column quality/distribution/profile, Applied Steps, Close & Apply | M engine | F |
| `advanced_editor`, `custom_column`, `merge_dialog_1/2` | Modal | Editor M, công thức cột, join có thống kê độ khớp | M engine | F |
| `query_dependencies_exact_graph_coordinates` | Cửa sổ | Đồ thị 4 cột Sources → Staging → Final → Model | Lineage | F |

**Có trên giao diện nhưng ẩn hoặc thay thế:**

| Nút | Xử lý |
|---|---|
| Copilot, Model Copilot, Generate | **Ẩn** (đã chốt: chưa làm AI) |
| Publish, Collaborate, avatar | Không có server → đổi thành menu **Export** (PDF, PNG, CSV) |
| DirectQuery / DirectLake / "Execution target" | Chỉ hỗ trợ Import. Bỏ các nhãn này |
| Roles / View as, Calculation groups, Perspectives, Cultures | Hiển thị trong cây model và giữ nguyên khi lưu. Sửa thì để sau v1 |
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
│   ├── MEngine         parser M + các hàm Table.*; fold sang SQL khi được
│   └── Connectors      DuckDB (CSV, Parquet, JSON, Excel; Postgres/SQLite qua extension)
│
└── PBIXKit           đọc (đã có) + ghi: PBIRWriter, MetadataWriter (SQLite), ABFWriter,
                      VertiPaqWriter, XPress9 encoder
```

**Quyết định kỹ thuật:**
1. **`.pbix` là định dạng duy nhất** cho tài liệu (đọc và ghi). File Layout cũ (1.28) khi lưu sẽ được nâng lên PBIR, giống cách Power BI Desktop đời mới làm. Trước khi ghi đè, BI Pro hỏi người dùng hoặc tạo bản sao lưu.
2. **DuckDB** (`duckdb-swift`, MIT) lo nạp dữ liệu và thực thi các bước Power Query. DAX vẫn dùng engine tự viết. App nặng thêm khoảng 30–50 MB.
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

### Phase W: Spike ghi `.pbix` (2 tuần) ⚠️ quyết định cách lưu
> Plan chi tiết, cách chia việc cho agent song song và checklist test tay trên VM: [`PHASE_W_PLAN.md`](PHASE_W_PLAN.md).

- [x] Vendor encoder XPress9; viết `ABFWriter` + `DataModelStream.compress`. (WP1, WP3)
- [x] Offline: dựng lại ABF khớp từng byte; nén → giải nén khớp; ZIP copy raw khớp; metadata thêm measure đọc lại được.
- [x] **W1:** round-trip không đổi → mở được trong Power BI Desktop (VM). Người dùng xác nhận mở được, dữ liệu nạp đủ (2026-10-31).
- [ ] **W2 (T1):** sửa tiêu đề visual → mở được. Gate sẵn ở `build/w-out/W2/`, chờ test tay.
- [ ] **W3 (T2):** thêm measure → mở được và chạy đúng. Gate sẵn ở `build/w-out/W3/`, chờ test tay.
- [ ] **W4 (T3):** bảng mới 100 dòng → mở được, dữ liệu đúng. Writer xong và giải mã đúng offline; gate sẵn ở `build/w-out/W4/`, chờ test tay.
- [x] Lệnh `pbix-dump roundtrip`, `set-title`, `add-measure` (`PBIXWriter`). Test tự động 62/62 pass.
- **Xong khi:** W1–W3 đạt. Nếu W4 chưa đạt thì T3 dùng phương án dự phòng ở §2, và tiếp tục nghiên cứu song song với Phase B–E.

### Phase B: DAX engine và DAX Query View (6–7 tuần)
> Plan multi-agent chi tiết, oracle và lịch test tay: [`PHASE_B_PLAN.md`](PHASE_B_PLAN.md). Nghiên cứu: `docs/phase-b-research/`.
- [x] ColumnStore + quan hệ (lọc một chiều/hai chiều, active/inactive, `USERELATIONSHIP`, blank row).
- [x] DAX lexer/parser/binder/evaluator; **43 hàm** mà 119 measure Nhom6 cần (đo lại, kế hoạch cũ ghi khoảng 40), gồm `CALCULATE`, `REMOVEFILTERS`, `KEEPFILTERS`, `ALLSELECTED`, `TREATAS`, `ISFILTERED`, `SAMEPERIODLASTYEAR`.
- [x] Truy vấn: `EVALUATE`, `DEFINE MEASURE/VAR`, `SUMMARIZECOLUMNS`, `ORDER BY`, `TOPN`, `ROW`.
- [ ] DAX Query View theo `dax_query_view` (không có ô AI). Đã có UI1 (chạy, huỷ, lưới, Copy/CSV, lỗi có vị trí); còn UI2/UI3 (gạch chân lỗi, tự hoàn thành, tab, quick queries).
- [x] Oracle: golden từ DAX Query View của Power BI Desktop (bạn chạy tay trong VM), cộng oracle tự động (sqlite, cột tính toán đã lưu, test thuộc tính, bộ tí hon). Không dùng pbixray; DAX Studio chỉ dùng nếu bạn tự cài.
- **Xong khi:** 119 measure Nhom6 khớp golden G0–G3, G5, G6.
- **Trạng thái (2026-11-02):** **engine đạt tiêu chí xong**: 30/30 golden khớp Power BI (G0–G6, T1–T5; 3 buổi test tay). Còn UI2/UI3 của DAX Query View. Chi tiết: mục "Tiếp tục từ đây" đầu `PHASE_B_PLAN.md`.

### Phase C: Report có số liệu và tương tác (5 tuần) → **M1**
- [ ] Visual có số: card/KPI, bar/column/line/combo, donut, treemap, 100% stacked, table/matrix, slicer, shape map; định dạng số, conditional formatting.
- [ ] Filters pane, slicer lọc thật, cross-filter/highlight, drill, tooltip, Selection pane, Bookmarks pane.
- **Xong khi:** cả 4 trang Nhom6 tương tác như trên Power BI.

### Phase D: Sửa report + lưu T1 (5–6 tuần)
- [ ] Build pane (lưới visual, field well, kéo thả), Format pane (sinh từ schema), canvas (chọn, resize, di chuyển, snap 8 px), ribbon Insert, quản lý trang.
- [ ] **Lưu `.pbix` tầng T1**, Save As, undo/redo, bản sao lưu; app đăng ký là Editor của `.pbix`.
- **Xong khi:** sửa trang Nhom6 trong BI Pro, lưu, rồi mở lại được cả trong BI Pro lẫn Power BI Desktop.

### Phase E: Mô hình hoá + lưu T2 (4–5 tuần) → **M2**
- [ ] Table View đầy đủ (Column tools, formula bar, sort/filter, Column metadata).
- [ ] Model View sửa được (kéo card, tạo quan hệ bằng cách kéo cột, Relationship properties).
- [ ] Measure (tạo/sửa/xoá, format, folder), TMDL View sửa được.
- [ ] **Lưu tầng T2.** Cột tính toán cần tầng T3 nên sẽ dùng VertiPaqWriter của Phase W.
- **Xong khi:** thêm measure và quan hệ trong BI Pro, lưu, rồi Power BI Desktop đọc đúng.

### Phase F: Get Data, Power Query + lưu T3 (8–10 tuần) → **M3**
- [ ] Connector DuckDB: Excel, CSV, Parquet, JSON (đợt 1); PostgreSQL, SQLite (đợt 2).
- [ ] Get Data → Navigator → Query Editor (Applied Steps, formula bar, column profile, ribbon) → Close & Apply.
- [ ] M engine (khoảng 30 hàm `Table.*`), các hộp thoại Advanced Editor, Custom Column, Merge, Append, Group By, cửa sổ Query Dependencies.
- [ ] **Lưu tầng T3** (dữ liệu mới vào VertiPaq), tạo `.pbix` mới từ đầu.
- **Xong khi:** đi hết luồng `sales_2026.xlsx` → Query Editor → Close & Apply → report → lưu `.pbix` → mở được trong Power BI Desktop.

### Phase G: Hoàn thiện (2–3 tuần) → **v1.0**
- [ ] Export PDF/PNG/CSV, Quick Look cho `.pbix`, dark mode, VoiceOver, tiếng Việt và tiếng Anh, icon app, Settings, hướng dẫn lần đầu.

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
