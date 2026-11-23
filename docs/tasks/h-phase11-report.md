# Báo cáo Phase 11 (H6 — Hoàn thiện & Cổng nghiệm thu v1.3.0)

Ngày: 2026-11-22  
Tác vụ: `T080`–`T085`, `T087` hoàn tất (`[x]`); `T086` đã chuẩn bị trọn bộ, để `[ ]` chờ con người duyệt cổng Desktop.

## 1. Nội dung thực hiện

- **T080 & T081 (Song ngữ & VoiceOver):**
  - Mở rộng `Tests/BIProTests/UIParity/RibbonBilingualTests.swift` với `phaseHFullBilingualAndVoiceOverAuditCoversAllSurfaces()` kiểm tra đủ 15 Ribbon đặc trưng (19 khe view×tab gồm 4 tab Help dùng chung), Rail 5 chế độ, VisualGallery 39 ô, StartScreen 6 thẻ, Backstage 11 mục, Options 22 mục, ModelPropertiesPanel 3 tuỳ chọn, DAX/TMDL chrome và chuỗi phiên bản `"1.3.0"`.
  - Qua kiểm tra ảnh thực tế phát hiện và vá triệt để 2 điểm sót tiếng Việt khi app ở chế độ Tiếng Anh:
    - `Sources/BIPro/Panes/BuildWells.swift`: ánh xạ `localizedWellLabel(_:)` chuyển nhãn well (`Trục X` → `X-axis`, `Trục Y` → `Y-axis`, `Chú giải` → `Legend`, `Chú thích công cụ` → `Tooltips`, v.v.) sang chuẩn Power BI Desktop khi ở chế độ `en`.
    - `Sources/BIPro/Table/TableWorkspace.swift`: song ngữ thanh công thức `Table/Bảng` và `data column (source: ...)` / `cột dữ liệu (nguồn: ...)`.
  - Toàn bộ bộ test VoiceOver Phase G (`PhaseG — VoiceOver AccessibilitySummary`) chạy xanh 100%.

- **T082 (Rà Dark Mode — 22 ảnh):**
  - Mở rộng `Tests/BIProTests/UIParity/ParityRenderTests.swift` (`renderH6DarkModeAuditAndDesktopGateBundle()`) xuất đủ 15 Ribbon Dark + 7 view toàn màn hình Dark vào `build/h-out/h6/dark/`.
  - Mở kiểm tra trực quan các ảnh đại diện và vá 2 lỗi thực tế phát hiện từ ảnh:
    1. `Sources/BIPro/Shell/RecentFilesList.swift`: nút pill `"Recent"` trước đó dùng `.foregroundStyle(.white)` trên nền `DS.Palette.label` khiến chữ trắng trên nền sáng bị chìm ở Dark Mode → sửa thành `.foregroundStyle(DS.Palette.canvas)` cho tương phản sắc nét ở cả Light và Dark.
    2. `Sources/BIPro/Shell/Ribbon/RibbonView.swift`: chế độ `scrollable: false` khi dựng Ribbon rộng (Model Home) làm giãn độ rộng `ShellView` vượt khung 1440 pt và cắt mép phải → bọc `Color.clear.overlay(alignment: .leading) { ... }.clipped()` để khung 1440 pt hiển thị trọn vẹn TitleBar, Properties, Data và StatusBar.
  - Xuất lại và xác nhận bằng mắt 6 ảnh sau sửa (`view-01-start-dark.png`, `view-02-report-dark.png`, `view-04-table-dark.png`, `view-05-model-dark.png`, `view-02-report.png`, `view-05-model.png`): rõ nét, 0 biểu tượng cấm, không cắt mép.

- **T083 (Ghi nhận `[SUY ĐOÁN]`):**
  - Tạo `docs/phase-ui-evidence/QUAN-SAT-H.md` liệt kê đầy đủ 11 mục `observed == false` trong `Sources/BIPro/Shell/Ribbon/` cùng 5 mục ngoài Ribbon chưa quan sát trên VM, kèm cách xử lý và đề xuất chụp bổ sung (nếu cần).

- **T084 (Nâng phiên bản 1.3.0):**
  - Cập nhật `scripts/build-app.sh` lên `CFBundleShortVersionString = 1.3.0`, `CFBundleVersion = 130` (ứng dụng chính + 2 `.appex` Quick Look).
  - Xác nhận `RibbonCatalog.aboutVersionString == "1.3.0"` trong `Sources/BIPro/Shell/Ribbon/Catalog+ViewOptimizeHelp.swift` và `build/BI Pro.app/Contents/Info.plist`.

- **T085 (Hồi quy toàn hệ thống, bất biến `.pbix` & đóng gói):**
  - Thêm `Tests/BIProTests/UIParity/RoundTripUnchangedTests.swift` xác minh cả `SyntheticReport` và tệp thực tế `Nhom6_work.pbix` giữ `isDirty == false` và **trùng khớp 100% từng byte** (`beforeBytes == afterBytes`) sau khi mở, duyệt đủ 5 workspace, toàn bộ 15 Ribbon, mở/đóng Backstage và gọi `state.save()`.
  - Kết quả kiểm thử:
    - `swift build`: đạt (`0,48 s`).
    - `BIPRO_H_RENDER=1 swift test --no-parallel --filter UIParity`: **55/55** đạt (`6,39 s`).
    - `swift test --no-parallel`: **2 537/2 537** đạt (`202,05 s`, 0 lỗi).
    - Golden nặng bản release (`BIPRO_HEAVY=1 swift test -c release ... --filter "Nhom6|ORA|VIS|ExportCSVTests|ExportRenderTests|QuickLookSummaryTests|V11BDAXGoldenTests"`): **119/119** đạt (`186,67 s`, 0 lỗi). *(Ghi chú: 5 bài `ColumnEditorTests` đã nằm trong lượt 2 537 unit test ở trên.)*
    - `zsh scripts/build-app.sh release`: tạo `build/BI Pro.app` (**v1.3.0**, `CFBundleVersion = 130`) kèm `AppIcon.icns`, `PBIXQuickLook.appex`, `PBIXThumbnail.appex`.
    - `codesign --verify --deep --strict "build/BI Pro.app"`: đạt (**exit 0**).

- **T086 (Chuẩn bị cổng Desktop — chờ con người):**
  - Xuất đủ 22 ảnh Light Mode vào `build/h-out/gate/bipro/` (15 Ribbon + 7 view toàn màn hình).
  - Soạn bảng đối chiếu cạnh nhau BI Pro ↔ Power BI Desktop 2.159 (`docs/phase-ui-evidence/vm-ui/`) và danh mục 10 lệnh kiểm tra thủ công (SC-004, SC-005) tại `build/h-out/gate/CHECKLIST.md`.
  - Không tự mở VM Windows; giữ nguyên `[ ]` cho T086 chờ người dùng xác nhận.

- **T087 (Đồng bộ tài liệu):**
  - Cập nhật `docs/STATE.md`, `docs/BIPRO_BUILD_PLAN.md`, `docs/PHASE_H_UI_PARITY.md`, `specs/016-h-giao-dien-giong-powerbi/tasks.md` và xuất `docs/tasks/h-final-report.md`.
  - Kiểm `git status --short`: 100% tệp nằm trong bảng sở hữu `docs/phase-h-ownership.tsv`; không chạm bất kỳ tệp OFF-LIMITS nào; không commit/push.
