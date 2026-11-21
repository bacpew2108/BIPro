# BI Pro: trạng thái làm việc

Cập nhật: 2026-11-21 (**v1.0.1 QA xong** — đã dọn dẹp dự án `104287e`, hoàn tất Đợt 1 Kiểm thử & Gia cố QA, đang bắt đầu quan sát Power BI Desktop trên VM Windows 11 cho **Đợt 2: Hệ Biểu đồ & Visual mới `specs/013`**).

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

- **Đợt 1 — Kiểm thử chi tiết & Gia cố v1.0.1 (2026-11-21, xong, chưa commit):**
  - Mở khoá lại 15 test nặng từng bị bỏ qua (`PBIXKitTests`, `ZipWriteTests`, `CompressTests`, `ABFWriteTests`, `MetadataWriteTests`, `PanesNhom6Tests`) nhờ fallback đường dẫn `BIPRO_NHOM6` / `Nhom6_work.pbix` và chuẩn hoá invariant.
  - Vá dứt điểm song ngữ `vi`/`en` cho toàn bộ pane/workspace phụ (`FilterEditor`, `FormatPane`, `BuildWells`, `ModelWorkspace`, `ColumnPropertiesEditor`, `MeasurePropertiesPanel`, `TableWorkspace`, `TMDLWorkspace`, `QueryResultsView`, `QueryToolbar`, `QueryTabBar`), sửa lưới `NSTableView` & `DotGrid` cho Dark Mode.
  - Bổ sung bộ test QA mới (`Tests/BIProTests/QA/AppEndToEndQATests.swift`, `VisualRegressionAndBilingualQATests.swift`): luồng E2E từ tài liệu mới → Enter Data 2 bảng + tự phát hiện quan hệ → Undo/Redo → Measure + Cột tính toán → Báo cáo + Trang + Bookmark → Lưu T3 → Mở lại → Xuất CSV/PNG/PDF; ca biên chống sập; hồi quy hình ảnh toàn bộ 14+ bộ vẽ visual + Dark Mode & song ngữ 7 pane phụ (**5/5 qua trong 0,8 s**).
  - Dựng lại `build/BI Pro.app` release (`codesign --verify --deep --strict` đạt), `e3-loop.sh` đạt 3/3 khớp byte (`0,575 s` / `0,434 s` / `0,096 s`).

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

1. **Kiểm thử toàn diện v1.0** (sau khi dọn dẹp):
   - Xác minh 100% unit test + golden nặng sau dọn dẹp.
   - Chạy kiểm thử ứng dụng thực tế (`build/BI Pro.app`): 5 workspace, Get Data / Query Editor / Enter Data, Edit / Format / Page / Bookmark / Filter, Model / Measure / Relationship / TMDL, Export PDF/PNG/CSV, Dark/Light Mode, Việt/Anh, Quick Look, VoiceOver, hiệu năng & ca biên.
2. **Lên kế hoạch & triển khai đợt nâng cấp v1.1** (theo Spec Kit, sau khi kiểm thử xong):
   - Mở khoá & bổ sung các biểu đồ/visual còn thiếu (`pieChart`, `stackedBarChart`, `hundredPercentStackedBarChart`, `scatterChart`, `gauge`, `kpi`, `multiRowCard`, `tableEx`, `map`/`filledMap`, Slicer nâng cao, phần tử chèn `shape`/`image`/`actionButton`/`pageNavigator`/`bookmarkNavigator`).
   - Bổ sung các tính năng còn thiếu (Edit Interactions, Matrix mở nút theo hàng, Conditional Formatting UI, mở rộng Format Pane/Theme/Analytics, Refresh nguồn dữ liệu một bấm, đổi tên đối tượng tự cập nhật tham chiếu, hàm DAX còn thiếu `TODAY`/`NOW`/`RANKX`/Window…).
3. **Git:** Đang ahead 86 commit so với `origin/main` + thay đổi dọn dẹp chưa commit (chờ lệnh bạn).
