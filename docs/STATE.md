# BI Pro: trạng thái làm việc

Cập nhật: 2026-11-22 (**Phase H — Giao diện giống Power BI Desktop 2.159 (v1.3.0) đã hoàn tất 86/87 tác vụ tự động**, còn cổng con người **T086** tại `build/h-out/gate/CHECKLIST.md`; qua **2 537/2 537** unit test, **119/119** golden nặng release, đóng gói `build/BI Pro.app` **v1.3.0** + `codesign --verify --deep --strict` đạt; đã commit 73e0019 + sửa 5 lỗi phát hiện khi bấm thử app thật: nút Share lặp, Ribbon cụt/đè nút `^` ở Model, lệch song ngữ, nhãn nút menu bị ngang; chưa push). 2026-11-23: sửa khởi động — mở app trực tiếp giờ hiện màn hình Khởi động (thẻ Blank report/Excel/nguồn khác) thay vì tự tạo "Không tên.pbix"; lỗi app chạy mà không có cửa sổ do `launchIsDefaultUserInfoKey` đôi khi `false` nên thêm lần kiểm chốt sau 1,5 s.

*(Nhật ký chi tiết Phase A–G trước ngày 2026-11-21 đã được lưu trữ nguyên văn tại `docs/HISTORY.md`.)*

## Mục tiêu và tiến độ

- **v1.0 (Phase A → W → B → C → D → E → F → `specs/011` → Phase G + G2):** ✅ **Hoàn tất 100%**.
  - **Phase A & W:** Design System macOS Sequoia, Shell 5 workspace, spike ghi `.pbix` (XPress9/ABF).
  - **Phase B:** DAX Engine + DAX Query View (30/30 golden khớp Power BI).
  - **Phase C:** Report có số liệu (72/72 truy vấn visual), tương tác lọc chéo/tô sáng/drill/drillthrough/tooltip, tối ưu engine (`specs/001`, trang D1 ~1,04 s).
  - **Phase D (D1–D7, `specs/002`–`008`):** Chỉnh sửa canvas, field well, thêm/đổi visual, Format pane, quản lý trang, bookmark/filter, nhóm lồng, định dạng cũ & lưu **T1**.
  - **Phase E (`specs/009`):** Mô hình hoá (Measure, Quan hệ kèm chỉ mục `R$`, Table/Model/TMDL View) & lưu **T2**.
  - **Phase F + Tồn đọng (`specs/010`–`011`):** Get Data (CSV, Excel, JSON, SQLite, Parquet lồng, PostgreSQL), Power Query (M Engine ~80+ hàm), Enter Data, Auto date/time, tự phát hiện quan hệ, hàm văn bản DAX, cột/bảng tính toán, lưu **T3** nhiều đoạn (10M dòng) & nén RLE (90,5% Desktop).
  - **Phase G + G2 (`specs/012`):** Export PDF/PNG/CSV, Dark Mode & Settings (`⌘,`), song ngữ sâu Việt/Anh (bất biến byte `.pbix`), Quick Look `.pbix` (2 `.appex`), VoiceOver mọi cấp `DataPane`/Shell/Canvas, AppIcon, Onboarding & đóng gói `build/BI Pro.app` **v1.0.0**.
- **Dọn dẹp dự án (2026-11-21):**
  - Giải phóng ~5,8 GB (`build/` 4,2 GB → 369 MB; `docs/` 2,2 GB → 215 MB bằng cách gỡ 39 tệp `.pbix` cũ không còn test dùng dưới `docs/phase-d-evidence/` và dọn thư mục tạm trong `build/`).
  - Thêm `docs/phase-*-evidence/**/*.pbix` vào `.gitignore` để giữ 11 tệp golden Desktop cho test mà `git status` vẫn sạch.
  - Tách lịch sử dài sang `docs/HISTORY.md`.

- **Đợt 1 — Kiểm thử chi tiết & Gia cố v1.0.1 (2026-11-21, commit `32daa53`):**
  - Mở khoá lại 15 test nặng từng bị bỏ qua (`PBIXKitTests`, `ZipWriteTests`, `CompressTests`, `ABFWriteTests`, `MetadataWriteTests`, `PanesNhom6Tests`) nhờ fallback đường dẫn `BIPRO_NHOM6` / `Nhom6_work.pbix` và chuẩn hoá invariant.
  - Vá dứt điểm song ngữ `vi`/`en` cho toàn bộ pane/workspace phụ (`FilterEditor`, `FormatPane`, `BuildWells`, `ModelWorkspace`, `ColumnPropertiesEditor`, `MeasurePropertiesPanel`, `TableWorkspace`, `TMDLWorkspace`, `QueryResultsView`, `QueryToolbar`, `QueryTabBar`), sửa lưới `NSTableView` & `DotGrid` cho Dark Mode.
  - Bổ sung bộ test QA mới (`Tests/BIProTests/QA/AppEndToEndQATests.swift`, `VisualRegressionAndBilingualQATests.swift`): luồng E2E từ tài liệu mới → Enter Data 2 bảng + tự phát hiện quan hệ → Undo/Redo → Measure + Cột tính toán → Báo cáo + Trang + Bookmark → Lưu T3 → Mở lại → Xuất CSV/PNG/PDF; ca biên chống sập; hồi quy hình ảnh toàn bộ 14+ bộ vẽ visual + Dark Mode & song ngữ 7 pane phụ (**5/5 qua trong 0,8 s**).
  - Dựng lại `build/BI Pro.app` release (`codesign --verify --deep --strict` đạt), `e3-loop.sh` đạt 3/3 khớp byte (`0,575 s` / `0,434 s` / `0,096 s`).
- **Đợt 2 — v1.1a Hệ Biểu đồ, Slicer nâng cao & Phần tử chèn (2026-11-21, `specs/013-v11-bieu-do-visual/`, commit `b7a257a`):**
  - Quan sát Power BI Desktop 2.159 (`VM-V11A`, 32 tệp JSON PBIR 2.14.0 tại `docs/phase-v11-evidence/vm-v11a/QUAN-SAT.md`).
  - Mở rộng `VisualTypes.supported` từ 21 → **40 loại** (`PBIRNewVisual`, `PBIRResourcePatch.addingRegisteredImage`, `PBIXWriter.addingMissingExtensions` cho `[Content_Types].xml`, `PBIRQueryPatch.settingSlicerModeIfUnset`, `WellRules` đa kiểu).
  - Triển khai đầy đủ 4 nhóm: **2A** (`barChart`/`stackedBarChart`, `hundredPercentStackedBarChart`, `pieChart`), **2B** (`tableEx` + sort/Total, `scatterChart` 1D/2D + bubble, `gauge` 180° + `Max = 2×Value`, `kpi` sparkline + goal delta, `multiRowCard`), **2C** (`advancedSlicerVisual` Tile, `listSlicer`, `textSlicer` `CONTAINSSTRING`, `slicer` `'Between'` 2 đầu số/ngày, `OfflineGeoAtlas` & `GeoMapView` ngoại tuyến 100% cho `map`/`filledMap`), **2D** (mở khoá ribbon **Chèn** cho Hình khối `rectangle`/`oval`/`line`, Nút `actionButton`/`pageNavigator`/`bookmarkNavigator`, Ảnh PNG/JPEG/SVG nhúng `RegisteredResources` + hoàn tác, `BookmarkNavigatorVisual`, mở rộng `FormatCatalog`, `VisualCSVExporter`, `AccessibilitySummary` song ngữ).
  - Kiểm chứng: **2 444/2 444** unit test qua, **112/112** golden nặng release qua, **Cổng Power BI Desktop 2.159 (T023)** đạt **19/19 visual** với 0 lỗi (`docs/phase-v11-evidence/vm-v11a/gate-desktop.png`), dựng lại `build/BI Pro.app` release + `codesign` đạt.
- **Đợt 3 — v1.1b Tính năng nâng cao, One-Click Refresh, Cascade Rename & Mở rộng DAX (2026-11-21, `specs/014-v11-tinh-nang-nang-cao/`, commit `02c2bab`):**
  - Quan sát Power BI Desktop 2.159 (`VM-V11B`: 18 JSON PBIR + 21/21 truy vấn DAX golden trên `msmdsrv` tại `docs/phase-v11-evidence/vm-v11b/QUAN-SAT.md` & `dax-golden.json`).
  - **3D (DAX Engine):** Bổ sung ~56 hàm mới khớp 100% Desktop 2.159 (`TODAY`, `NOW`, `WEEKDAY`, `WEEKNUM` ISO 8601 type 21, `EOMONTH`, `EDATE`, `MINUTE`, `SECOND`, `TIME`, `YEARFRAC`, `CALENDARAUTO`, 23 hàm Time Intelligence `DATESYTD`/`QTD`/`MTD`/`TOTALYTD`/`QTD`/`MTD`/`DATESBETWEEN`/`DATESINPERIOD`/`PREVIOUS*`/`NEXT*`/`PARALLELPERIOD`/`STARTOF*`/`ENDOF*`, `ERROR`/`IFERROR`/`ISERROR`/`ISNUMBER`/`ISTEXT`/`ISLOGICAL`, `LOOKUPVALUE`, `SELECTCOLUMNS`, `UNION`/`INTERSECT`/`EXCEPT`, `GENERATESERIES`, `DATATABLE`, `COUNTBLANK`/`COUNTX`/`COUNTAX`/`PRODUCTX`/`STDEV.S`/`VAR.S`, hàm cửa sổ `OFFSET`/`INDEX`/`WINDOW` + `ORDERBY`/`PARTITIONBY`).
  - **3A (Tương tác & Matrix & Bộ lọc):** Chế độ **Edit interactions** (vẽ huy hiệu Filter/Highlight/None, lưu `visualInteractions` trong `page.json` + Undo), **Matrix phân cấp hàng** (`+`/`−` theo `DAXEngine` + `expansionStates`), kéo-thả trường từ `DataPane` vào `FiltersPane`, **Date Advanced Filter** (`DatePicker` + `datetime'...'`), mở rộng Bookmark Data.
  - **3B (CF & Theme & Analytics):** Conditional Formatting đầy đủ (Rules, Gradient 2–3 mốc, Field value, Data Bars trong `columnFormatting.dataBars`) cho Table/Matrix + `ConditionalFormattingSheet`; **Analytics Pane** (Constant Line `y1AxisReferenceLine`, Average/Min/Max `referenceLine`, Trend/Forecast); **Theme Switcher** (6 preset chuẩn Power BI + Nhập/Xuất `.json` + lưu `RegisteredResources` + Undo/Redo).
  - **3C (Refresh, Cascade Rename & PQ Extra):** Mở khoá **Làm mới (Refresh, `⇧⌘R`)** (`RefreshCoordinator` + `RefreshProgressSheet`, giữ quan hệ/measure/visual & dữ liệu cũ khi nguồn lỗi); **Cascade Rename** bảng/cột/measure đang dùng (viết lại DAX bằng token `DAXLexer` + PBIR JSON + `RenameConfirmationSheet` + Undo 1 bước); bổ sung **Power Query Extra Transforms** (`Text.BeforeDelimiter`/`AfterDelimiter`/`BetweenDelimiters`/`Range`, `Date.QuarterOfYear`/`StartOfMonth`/`EndOfMonth`/`MonthName`/`DayOfWeekName`, `Splitter.SplitTextByRepeatedLengths`/`SplitTextByPositions`, `Replace Errors`, Extract & Date trên Ribbon).
  - Kiểm chứng: **2 466/2 466** unit test qua (`190,26 s`), **119/119** golden nặng release qua (`164,56 s`), **Cổng Power BI Desktop 2.159 (T024)** đạt 0 lỗi (`docs/phase-v11-evidence/vm-v11b/gate-desktop.png`), dựng lại `build/BI Pro.app` release + `codesign --verify --deep --strict` đạt.
- **Đợt 4 — v1.2 Mở khoá toàn bộ Ribbon, RLS, Mark as Date Table, Quick Measures & Công cụ DAX/TMDL (2026-11-21, `specs/015-v12-hoan-thien-chuyen-nghiep/`, commit `8504d9c`):**
  - Quan sát Power BI Desktop 2.159 (`VM-V12`: schema SQLite `metadata.sqlitedb` + reflection `Microsoft.AnalysisServices.Server.Tabular.dll` tại `docs/phase-v12-evidence/vm-v12/QUAN-SAT.md`).
  - **Nền tảng `PBIXKit` & `DAXEngine`:** Đọc/ghi `[Role]` + `[TablePermission]` (`ModelPermission=2`, `State=1`, `MetadataPermission=0`) và **Mark as Date Table** (`[Table].DataCategory='Time'`, `[Column].IsKey=1`, `IsUnique=1`); viết bộ định dạng `DAXEngine.format(_:)` thuần Swift bảo toàn chuỗi/chú thích & toán tử trừ đơn ngôi.
  - **4A (Report & Drill):** Cut/Copy/Paste visual (cùng trang & sang trang khác, `⌘X`/`⌘C`/`⌘V` + Undo `⌘Z`), **Format Painter** chép `visualContainerObjects` + `objects` trực tiếp trên canvas, mở khoá đầy đủ tab **Data / Drill** (*Drill up*, *Drill down*, *Expand next level*, **Show as a table** + Xuất CSV).
  - **4B (Mô hình hoá & RLS):** **Quick Measures** (8 mẫu chuẩn Power BI + kiểm `DAXEngine`), **Mark as Date Table** (kiểm cột `.dateTime` duy nhất/không trống qua `ColumnStore`), **Row-Level Security (Manage Roles & View As)** (CRUD vai trò lưu T2, dải vàng cảnh báo trên canvas & tự tiêm `QueryFilter` RLS vào toàn bộ truy vấn DAX), **DataPane** Hide/Unhide bảng/cột & **Unhide All**.
  - **4C (DAX / TMDL / SQL & v1.2.0):** Nút **Định dạng** & **Cập nhật mô hình (`DEFINE MEASURE ...` theo lô)** trên Ribbon DAX Query View, nút **Áp dụng thay đổi** trên Ribbon TMDL View, menu **SQL** (PostgreSQL / SQLite) trên Ribbon Home, nâng phiên bản lên **1.2.0** (`CFBundleVersion = 120`).
  - Kiểm chứng: **2 471/2 471** unit test qua, **119/119** golden nặng release qua, **Cổng Power BI Desktop 2.159 (T014)** đạt 0 lỗi (`docs/phase-v12-evidence/vm-v12/gate-desktop.png`).
- **Rà soát & dọn nốt tồn đọng `BIPRO_BUILD_PLAN.md` + sửa mở cửa sổ khi khởi động (2026-11-21, đã commit):** *Lưu ý: ảnh `ImageRenderer` bỏ qua `Menu` nên không lộ lỗi bố cục nút menu; luôn bấm thử app thật.*
  - Mở khoá hoàn toàn thanh Ribbon **Công cụ cột (`ColumnToolsCommands`)** & **Công cụ bảng (`TableToolsCommands`)** trong `Sources/BIPro/Shell/Ribbon.swift` cùng `Sources/BIPro/Table/ColumnFormatShortcut.swift`: đổi tên bảng (`CascadeRename`), đổi tên cột, menu `Định dạng` + 4 phím nhanh **`$`, `%`, `,`, `.00`**, `Tóm tắt`, `Danh mục`, `Sắp xếp theo cột`, bỏ toàn bộ tooltip `"Phase E"` cũ (hoàn tác ⌘Z & lưu T2).
  - Sửa lỗi mở trực tiếp `BI Pro.app` không hiện cửa sổ (chỉ thấy chấm chạy trên Dock): bổ sung `AppLaunchPolicy` / `DocumentOpenTracker` và `applicationShouldOpenUntitledFile` / `applicationOpenUntitledFile` / `applicationShouldHandleReopen` + kiểm tra `launchIsDefaultUserInfoKey` trong `DocumentActions.swift`, `App.swift`, `UntitledDocuments.swift` (kèm 3 test `AppLaunchPolicyTests` và kiểm chứng thực tế trên macOS cho cả 3 kịch bản: mở trực tiếp, bấm lại trên Dock sau khi đóng hết cửa sổ, và mở kèm file `.pbix`).
  - Dọn thông báo lỗi nhắc phase cũ trong `TMDLParser.swift`, `FieldEditor.swift`, `TypeChange.swift`; đồng bộ **694/694** mục `[x]` (0 mục `[ ]`) trên `docs/BIPRO_BUILD_PLAN.md`, `specs/003` (T034) và `specs/010` (T111).
  - Kiểm chứng: **2 481** unit test (2 478 toàn bộ + 3 `AppLaunchPolicyTests`), **124/124** golden nặng release + `ColumnEditorTests` qua, đóng gói `build/BI Pro.app` **v1.2.0** + `codesign --verify --deep --strict` đạt.

- **Phase H — v1.3.0 Giao diện giống Power BI Desktop 2.159 (2026-11-22, `specs/016-h-giao-dien-giong-powerbi/`, working tree chưa commit):**
  - **Nền tảng & 15 thanh Ribbon (Phase 1–5, T001–T044):** Tách sạch kiến trúc Ribbon khai báo theo dữ liệu (`Sources/BIPro/Shell/Ribbon/`), bỏ `Ribbon.swift` cũ (làm rỗng 0 biểu tượng, sẵn sàng `git rm`), giữ 100% hành vi lệnh qua `RibbonActions`. Đủ 15 Ribbon đặc trưng (19 khe view×tab gồm 4 tab Help dùng chung) cho cả 5 workspace (`Report`: Home, Insert, Modeling, Design, View, Optimize, Help, Format, Data/Drill; `Table`: Home, Table tools, Column tools; `Model`: Home; `DAX`: Home; `TMDL`: Home), tách `CodeActionBar` cho DAX (`Run`, `Update model with changes`) và TMDL (`Apply`, `Preview`).
  - **Khung cửa sổ, Token Teal & R-02 Edit Mode mặc định (Phase 6, T045–T053):** Chuyển `accent` sang màu nhấn riêng tím chàm (`#5B4BDB` Light / `#9A8EFF` Dark; ban đầu teal, đổi 2026-11-23 để không giống Power BI; token `accentBrand`), chrome `#F5F5F5`, `canvasWell #E6E6E6`; tách `TitleBar` (36 pt) + `Rail` (42 pt, luôn đủ 5 biểu tượng + `EmptyViewState`); xác nhận thành công spike **R-02** (`EditClickPolicy`: bấm < 4 pt chọn + lọc chéo, kéo ≥ 4 pt di chuyển visual; bật `editMode` mặc định trừ khi `viewOnlyDefault`).
  - **Pane & Thanh đáy (Phase 7–8, T054–T065):** `Filters` thu gọn mặc định (31 pt), `Visualizations` 3 tab biểu tượng + lưới 6 cột 39 ô chuẩn Desktop + `BuildWells` nét đứt song ngữ + `Drill through`, `Format` Search + Visual/General, `Data` hai tab `Tables`/`Model` với cây `Semantic model` 9 nhóm; `PageTabs` (Desktop/Phone, ◂ ▸, tab chữ thường gạch chân teal, nút `+` vuông teal) và `WindowStatusBar` 23 pt hợp nhất cho cả 5 workspace.
  - **Khởi động, File Backstage, Options & View đặc thù (Phase 9–10, T066–T079):** `StartScreen` (6 thẻ + `RecentFilesList`), `BackstageView` (11 mục chuẩn Desktop), `OptionsDialog` (15 mục Global + 7 mục Current File), cập nhật `AddDataPanel` (26 pt, 4 thẻ pastel); bổ sung `ModelPropertiesPanel` (Cards: No/Yes/No), dải thông báo & màn hình Results trống cho DAX, `Problems (n)`/`Output` + hộp thoại giới thiệu lần đầu cho TMDL, tiêu đề cột có ` ▾` cho Table view.
  - **Hoàn thiện v1.3.0 & Cổng Desktop (Phase 11, T080–T087):** Rà song ngữ + VoiceOver toàn bề mặt (`RibbonBilingualTests`), rà Dark Mode 22 ảnh (`build/h-out/h6/dark/` — vá tương phản nút `Recent`, giới hạn độ rộng snapshot Ribbon rộng, song ngữ BuildWells & thanh công thức Table), ghi `docs/phase-ui-evidence/QUAN-SAT-H.md`, nâng bản `1.3.0` (`CFBundleVersion = 130`), kiểm bất biến byte `.pbix` (`RoundTripUnchangedTests` qua trên cả `SyntheticReport` và `Nhom6_work.pbix`), chuẩn bị sẵn bộ đối chiếu cổng Desktop tại `build/h-out/gate/CHECKLIST.md` + 22 ảnh `build/h-out/gate/bipro/`.
  - **Kiểm chứng:** `swift build` đạt, **2 537/2 537** unit test xanh (100%), **119/119** golden nặng release xanh (100%), đóng gói `build/BI Pro.app` **v1.3.0** + `codesign --verify --deep --strict` đạt (exit 0). **T086** (duyệt ảnh cạnh nhau & thử 10 lệnh trên Desktop/BI Pro) chờ con người xác nhận.

## Quyết định đã chốt

- **Định dạng tài liệu duy nhất:** `.pbix` (đọc & ghi phân tầng T1/T2/T3 nguyên tử, kiểm đọc lại, có bản sao lưu).
- **Native macOS, không thư viện ngoài:** SwiftUI + AppKit + Swift Charts + framework hệ thống Apple; chỉ dùng code vendor mở được duyệt (XPress9 encoder).
- **Power BI Desktop là chuẩn cuối cùng (golden):** Visual sinh văn bản DAX giống Performance Analyzer rồi chạy qua engine; quy tắc chưa quan sát ghi `[SUY ĐOÁN]`.
- **Song ngữ & Dark Mode:** `AppPreferences` + `L10n`/`bi(_:_:)` song ngữ Việt/Anh bất biến byte `.pbix`; `DS.Palette` màu động macOS 15 Sequoia, giữ nền giấy sáng tài liệu `.pbix` trên Report Canvas.
- **Quy trình:** Spec Kit (`docs/` là cấp trên, `specs/NNN-.../` là cấp dưới; dừng duyệt sau `spec.md`, `plan.md`, `tasks.md`), `/tdd`, `/diagnosing-bugs`, `/code-review`, `/speckit-converge`.

## Lệnh build / test

- Build & unit test: `swift build`; `swift test --no-parallel` (2 537 test).
- Golden nặng (release, gồm 30 golden DAX + 72 truy vấn visual + Phase G + v1.1b DAX golden):
  ```
  BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --no-parallel --filter "Nhom6|ORA|VIS|ExportCSVTests|ExportRenderTests|QuickLookSummaryTests|V11BDAXGoldenTests"
  ```
- Xuất ảnh đối chiếu Phase H: `BIPRO_H_RENDER=1 swift test --no-parallel --filter ParityRenderTests` (xuất vào `build/h-out/`).
- Đo hiệu năng truy vấn chậm: `zsh scripts/e3-loop.sh` (so byte với `build/e3-base/`).
- Đóng gói ứng dụng: `zsh scripts/build-app.sh release` (tạo `build/BI Pro.app` v1.3.0 kèm `AppIcon.icns` và 2 extension Quick Look).
- Lỗi SIGBUS sau khi sửa struct dùng chung: xoá `.build` rồi build lại.

## Việc tiếp theo

1. **Cổng con người Phase H (T086):** Mở `build/h-out/gate/CHECKLIST.md` đối chiếu 15 Ribbon + 7 màn hình BI Pro (`build/h-out/gate/bipro/`) với Desktop (`docs/phase-ui-evidence/vm-ui/`), thử 10 lệnh mẫu (SC-004, SC-005), rồi đánh dấu `[x]` T086.
2. **Git:** Phase H đã commit (chưa push; còn nhiều commit chưa đẩy).
3. **Định hướng sau đó (tuỳ chọn):** đóng gói `.dmg`, thêm connector mới khi cần.
