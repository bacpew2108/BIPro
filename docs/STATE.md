# BI Pro: trạng thái làm việc

Cập nhật: 2026-11-21 (**Đợt 3 — v1.1b `specs/014` HOÀN TẤT 100%** — đã qua toàn bộ **2 466/2 466** unit test, **119/119** golden nặng release, cổng Power BI Desktop 2.159 tại `docs/phase-v11-evidence/vm-v11b/gate-desktop.png` với 0 lỗi, và đóng gói `build/BI Pro.app` release + `codesign` đạt).

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
- **Đợt 3 — v1.1b Tính năng nâng cao, One-Click Refresh, Cascade Rename & Mở rộng DAX (2026-11-21, `specs/014-v11-tinh-nang-nang-cao/`, xong chưa commit):**
  - Quan sát Power BI Desktop 2.159 (`VM-V11B`: 18 JSON PBIR + 21/21 truy vấn DAX golden trên `msmdsrv` tại `docs/phase-v11-evidence/vm-v11b/QUAN-SAT.md` & `dax-golden.json`).
  - **3D (DAX Engine):** Bổ sung ~56 hàm mới khớp 100% Desktop 2.159 (`TODAY`, `NOW`, `WEEKDAY`, `WEEKNUM` ISO 8601 type 21, `EOMONTH`, `EDATE`, `MINUTE`, `SECOND`, `TIME`, `YEARFRAC`, `CALENDARAUTO`, 23 hàm Time Intelligence `DATESYTD`/`QTD`/`MTD`/`TOTALYTD`/`QTD`/`MTD`/`DATESBETWEEN`/`DATESINPERIOD`/`PREVIOUS*`/`NEXT*`/`PARALLELPERIOD`/`STARTOF*`/`ENDOF*`, `ERROR`/`IFERROR`/`ISERROR`/`ISNUMBER`/`ISTEXT`/`ISLOGICAL`, `LOOKUPVALUE`, `SELECTCOLUMNS`, `UNION`/`INTERSECT`/`EXCEPT`, `GENERATESERIES`, `DATATABLE`, `COUNTBLANK`/`COUNTX`/`COUNTAX`/`PRODUCTX`/`STDEV.S`/`VAR.S`, hàm cửa sổ `OFFSET`/`INDEX`/`WINDOW` + `ORDERBY`/`PARTITIONBY`).
  - **3A (Tương tác & Matrix & Bộ lọc):** Chế độ **Edit interactions** (vẽ huy hiệu Filter/Highlight/None, lưu `visualInteractions` trong `page.json` + Undo), **Matrix phân cấp hàng** (`+`/`−` theo `DAXEngine` + `expansionStates`), kéo-thả trường từ `DataPane` vào `FiltersPane`, **Date Advanced Filter** (`DatePicker` + `datetime'...'`), mở rộng Bookmark Data.
  - **3B (CF & Theme & Analytics):** Conditional Formatting đầy đủ (Rules, Gradient 2–3 mốc, Field value, Data Bars trong `columnFormatting.dataBars`) cho Table/Matrix + `ConditionalFormattingSheet`; **Analytics Pane** (Constant Line `y1AxisReferenceLine`, Average/Min/Max `referenceLine`, Trend/Forecast); **Theme Switcher** (6 preset chuẩn Power BI + Nhập/Xuất `.json` + lưu `RegisteredResources` + Undo/Redo).
  - **3C (Refresh, Cascade Rename & PQ Extra):** Mở khoá **Làm mới (Refresh, `⇧⌘R`)** (`RefreshCoordinator` + `RefreshProgressSheet`, giữ quan hệ/measure/visual & dữ liệu cũ khi nguồn lỗi); **Cascade Rename** bảng/cột/measure đang dùng (viết lại DAX bằng token `DAXLexer` + PBIR JSON + `RenameConfirmationSheet` + Undo 1 bước); bổ sung **Power Query Extra Transforms** (`Text.BeforeDelimiter`/`AfterDelimiter`/`BetweenDelimiters`/`Range`, `Date.QuarterOfYear`/`StartOfMonth`/`EndOfMonth`/`MonthName`/`DayOfWeekName`, `Splitter.SplitTextByRepeatedLengths`/`SplitTextByPositions`, `Replace Errors`, Extract & Date trên Ribbon).
  - Kiểm chứng: **2 466/2 466** unit test qua (`190,26 s`), **119/119** golden nặng release qua (`164,56 s`), **Cổng Power BI Desktop 2.159 (T024)** đạt 0 lỗi (`docs/phase-v11-evidence/vm-v11b/gate-desktop.png`), dựng lại `build/BI Pro.app` release + `codesign --verify --deep --strict` đạt.

## Quyết định đã chốt

- **Định dạng tài liệu duy nhất:** `.pbix` (đọc & ghi phân tầng T1/T2/T3 nguyên tử, kiểm đọc lại, có bản sao lưu).
- **Native macOS, không thư viện ngoài:** SwiftUI + AppKit + Swift Charts + framework hệ thống Apple; chỉ dùng code vendor mở được duyệt (XPress9 encoder).
- **Power BI Desktop là chuẩn cuối cùng (golden):** Visual sinh văn bản DAX giống Performance Analyzer rồi chạy qua engine; quy tắc chưa quan sát ghi `[SUY ĐOÁN]`.
- **Song ngữ & Dark Mode:** `AppPreferences` + `L10n`/`bi(_:_:)` song ngữ Việt/Anh bất biến byte `.pbix`; `DS.Palette` màu động macOS 15 Sequoia, giữ nền giấy sáng tài liệu `.pbix` trên Report Canvas.
- **Quy trình:** Spec Kit (`docs/` là cấp trên, `specs/NNN-.../` là cấp dưới; dừng duyệt sau `spec.md`, `plan.md`, `tasks.md`), `/tdd`, `/diagnosing-bugs`, `/code-review`, `/speckit-converge`.

## Lệnh build / test

- Build & unit test: `swift build`; `swift test --no-parallel` (2 409 test).
- Golden nặng (release, gồm 30 golden DAX + 72 truy vấn visual + Phase G):
  ```
  BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --no-parallel --filter "Nhom6|ORA|VIS|ExportCSVTests|ExportRenderTests|QuickLookSummaryTests"
  ```
- Đo hiệu năng truy vấn chậm: `zsh scripts/e3-loop.sh` (so byte với `build/e3-base/`).
- Đóng gói ứng dụng: `zsh scripts/build-app.sh release` (tạo `build/BI Pro.app` v1.0.0 kèm `AppIcon.icns` và 2 extension Quick Look).
- Lỗi SIGBUS sau khi sửa struct dùng chung: xoá `.build` rồi build lại.

## Việc tiếp theo

1. **Git:** Toàn bộ thay đổi **Đợt 3 (`v1.1b`, `specs/014-v11-tinh-nang-nang-cao/`)** đang ở working tree và đã qua 100% các cổng kiểm thử + VM Desktop 2.159 + Release Build (chờ lệnh commit/push của bạn).
2. **Mở rộng sau v1.1b (tuỳ chọn):** Theo dõi phản hồi thực tế khi sử dụng `build/BI Pro.app` trên các bộ dữ liệu lớn; bổ sung thêm connector hoặc tính năng mới nếu cần.
