# Nhiệm vụ: Phase G — Hoàn thiện ứng dụng (v1.0)

Định dạng: `- [x] Txxx [P?] [USn] Mô tả (tệp)`. Toàn bộ thực hiện trực tiếp bằng `/tdd` theo `claude.md` (không tách gói `agy` chạy song song).

Kiểm: `swift build`; `swift test`; golden nặng `BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --no-parallel --filter "Nhom6|ORA|VIS|PhaseG|QuickLookSummary"`; `zsh scripts/build-app.sh`. Thiết kế: `plan.md`, `research.md` (R1–R6), `data-model.md`, `contracts/phase-g-contracts.md`.

Điều kiện chung:
- Không thêm thư viện ngoài (Hiến pháp III) và không tải từ mạng (Hiến pháp IV).
- File gốc trong `~/Downloads` chỉ đọc (`Nhom6_work.pbix`, `w8.3.pbix`, `tuan6.2.pbix`). Tệp xuất test vào `build/g-out/`; ảnh bằng chứng vào `docs/phase-g-evidence/`.
- Quy tắc chưa quan sát ghi `[SUY ĐOÁN]` trong mã.
- Không commit `.pbix` hay tệp xuất lớn trong `build/g-out/`.

---

## Giai đoạn 1: Đợt 0 — Nền, hợp đồng & spike

- [x] T001 Tạo `docs/phase-g-ownership.tsv` (danh mục phân khu tệp Phase G) và `docs/phase-g-evidence/README.md` + `build/g-out/` (ngoài git).
- [x] T002 `Sources/BIPro/Settings/AppPreferences.swift` + `Tests/BIProTests/PhaseG/AppPreferencesTests.swift`:
  - `AppAppearance` (`.system`, `.light`, `.dark`), `AppLanguage` (`.system`, `.vi`, `.en`), `ResolvedLanguage` (`.vi`, `.en`);
  - lưu/đọc bền vững trên `UserDefaults` (nhận `defaults` qua `init` để test cô lập); đồng bộ khoá `bipro.sqlite.odbcDriver` với `SQLiteODBC`;
  - tính `effectiveLanguage`, `preferredColorScheme`, `nsAppearance`, `applyAppearance()` lên `NSApp.appearance`.
- [x] T003 `Sources/BIPro/Settings/L10n.swift` (từ điển song ngữ đầy đủ cho Shell, Ribbon, Rail, Panes, Export, Settings, Onboarding, các hộp thoại chính, nhãn phép gộp ngầm) + `Tests/BIProTests/PhaseG/LocalizationTests.swift` (test 100% `L10n.Key.allCases` có đủ chuỗi `vi` và `en` không rỗng, khớp placeholder).
- [x] T004 `Sources/BIPro/DesignSystem/Tokens.swift`: chuyển `DS.Palette` sang màu động `Color.dynamic(light:dark:)` (`NSColor(name:dynamicProvider:)`) theo bảng màu macOS 15 Sequoia (`research.md` R2); thêm `DS.Palette.documentPaper`.
- [x] T005 Spike Quick Look `.appex` không cần Xcode (R4): kiểm chứng biên dịch `.appex` bằng `swiftc` + `codesign -s -` + `qlmanage -t/-p` trên macOS 15, ghi kết quả vào `docs/phase-g-evidence/ql-spike.md`.

---

## Giai đoạn 2: US2 — Dark Mode & Cài đặt (`⌘,`)

- [x] T006 [US2] `Sources/BIPro/Settings/SettingsView.swift` + `Tests/BIProTests/PhaseG/SettingsOnboardingTests.swift`:
  - 3 nhóm rõ ràng: **Chung** (Giao diện Sáng/Tối/Hệ thống, Ngôn ngữ Hệ thống/Việt/Anh, Xem lại hướng dẫn), **Chỉnh sửa** (Bám lưới mặc định, Cỡ lưới 8/16 px), **Dữ liệu & Sao lưu** (Driver ODBC SQLite mặc định có gợi ý + nhập tự do, đường dẫn thư mục sao lưu + nút Mở trong Finder).
- [x] T007 [US2] `Sources/BIPro/App.swift` & `Sources/BIPro/Shell/ShellView.swift`:
  - Thêm `Settings { SettingsView(preferences: AppPreferences.shared) }` (`⌘,`) trong `BIProApp`; đồng bộ `AppPreferences.shared.applyAppearance()`.
  - Mở khoá nút bánh răng ở đáy `Rail` gọi `openSettings()`.
  - Gỡ bỏ 5 chỗ ép `.environment(\.colorScheme, .light)` ở `ShellView.swift`, thay bằng `.preferredColorScheme(AppPreferences.shared.preferredColorScheme)`.
- [x] T008 [US2] Gỡ bỏ ép `.light` / `NSAppearance(named: .aqua)` và thay màu trắng cứng trên 4 workspace & hộp thoại:
  - `Sources/BIPro/Shell/FileOptionsView.swift`
  - `Sources/BIPro/Table/**`, `Sources/BIPro/Model/**`, `Sources/BIPro/Query/**` (`CodeEditor`, `ResultGrid`, `QueryResultsView`, `CompletionPopup`, `EnterDataView`, `Editor/**`)
  - `Sources/BIPro/Panes/**`
  - **Giữ nguyên** `.environment(\.colorScheme, .light)` tại ranh giới trang tài liệu trong `ReportCanvas.swift` và `DropdownSlicer.swift` (FR-013).
- [x] T009 [US2] Nối `AppPreferences.snapToGrid` và `gridSize` (8/16 px) vào `LayoutEditor` / `ReportCanvas` (`LayoutGeometry`). Rà soát `Color.white` và `.colorScheme` còn sót ngoài Report Canvas. Chạy `swift test`.

---

## Giai đoạn 3: US1 — Xuất báo cáo ra PDF, PNG và CSV

- [x] T010 [US1] `Sources/BIPro/Export/VisualCSVExporter.swift` + `Tests/BIProTests/PhaseG/ExportCSVTests.swift`:
  - Xuất `DataView` (`.single`, `.categorical`, `.matrix`, `.slicer`) ra CSV chuẩn RFC 4180 (`\r\n`) + UTF-8 BOM (`0xEF 0xBB 0xBF`), ném `ExportError.noData` cho `.empty`.
  - Test nặng so khớp 100% từng ô với kết quả DAX của Card, Biểu đồ cột/combo và Matrix trên `Nhom6_work.pbix`.
- [x] T011 [US1] `Sources/BIPro/Report/ReportCanvas.swift` & `Sources/BIPro/Report/LiveVisual.swift`:
  - Thêm chế độ vẽ tĩnh `preloadedData: [String: LiveVisualData]?` và `isExporting: Bool` (tắt lớp `HoverTracker` AppKit, bỏ viền chọn/tay nắm Sửa, ẩn visual bị ẩn).
  - Thêm mục "Xuất dữ liệu ra CSV…" vào menu chuột phải của visual có dữ liệu.
- [x] T012 [US1] `Sources/BIPro/Export/ReportPageExporter.swift` & `Sources/BIPro/Export/ExportSheet.swift` + `Tests/BIProTests/PhaseG/ExportRenderTests.swift`:
  - `preload` song song mọi visual hiển thị của trang; kết xuất PNG (1×/2×, đúng kích thước pixel) và PDF nhiều trang (`CGContext` PDF, đọc lại bằng `PDFKit`).
  - `ExportSheet`: chọn phạm vi PDF ("Tất cả trang hiển thị" / "Trang hiện tại") và tỉ lệ PNG (1× / 2×), thanh tiến trình, dùng `L10n` và `DS.Palette`.
- [x] T013 [US1] `Sources/BIPro/Shell/ShellView.swift`, `Sources/BIPro/Report/Edit/DocumentActions.swift`, `Sources/BIPro/DocumentState.swift`:
  - Mở khoá nút **Xuất** trên `TitleBar` (3 mục: `PDF…`, `Ảnh PNG của trang…`, `Dữ liệu visual ra CSV…`) và menu **Tệp ▸ Xuất**.
  - Mục CSV mờ kèm tooltip lý do khi chưa chọn visual hoặc visual không có dữ liệu.
  - Chạy kiểm nặng xuất PDF (tất cả trang hiển thị), PNG 2× (trang D1) và CSV trên `Nhom6_work.pbix` vào `build/g-out/`; kiểm ảnh PNG/PDF bằng mắt (SC-001).

---

## Giai đoạn 4: US3 — Song ngữ Tiếng Việt và Tiếng Anh

- [x] T014 [US3] Áp `L10n` (`tr(_:)`) vào toàn bộ vỏ giao diện chính:
  - `ShellView.swift`, `Ribbon.swift`, `DocumentActions.swift`, `EditCommands.swift`;
  - `ReportWorkspace.swift`, `AddDataPanel.swift`, `CanvasHint.swift`, `Panes/**`;
  - `FileOptionsView.swift`, `GetDataDialog.swift`, `DatabaseConnectView.swift`, `EnterDataView.swift`, `Query/Editor/**` (nhãn chính).
- [x] T015 [US3] Nhãn phép gộp ngầm theo ngôn ngữ (`AggregateFunction.displayLabel(column:language:)`: "Tổng của X" ↔ "Sum of X") trong khi giữ nguyên `nativeQueryRef` PBIR khi lưu.
- [x] T016 [US3] Mở rộng `Tests/BIProTests/PhaseG/LocalizationTests.swift`: kiểm chứng bất biến `.pbix` khi lưu ở `.vi` vs `.en` (PBIR/M/metadata giống hệt nhau, SC-003).

---

## Giai đoạn 5: US4 — Quick Look cho tệp `.pbix`

- [x] T017 [US4] `Sources/PBIXKit/QuickLookSummary.swift` & `Sources/PBIXKit/QuickLookRenderer.swift` + `Tests/PBIXKitTests/QuickLookSummaryTests.swift`:
  - `PBIXQuickLookSummary.load(from:)` đọc nhanh chỉ ZIP `Report/` + `metadata.sqlitedb` (`< 1 s` trên `Nhom6_work.pbix`, không giải mã VertiPaq), xử lý an toàn file lỗi/thiếu DataModel.
  - `PBIXQuickLookRenderer`: vẽ `CGImage` Thumbnail (sơ đồ trang đầu + huy hiệu `PBIX`) và ảnh/bố cục Preview (thông số báo cáo, danh sách trang, sơ đồ visual trang đầu, thích ứng Sáng/Tối).
  - Test trên `Nhom6_work.pbix`, `w8.3.pbix`, file định dạng cũ và file hỏng; xuất ảnh kiểm vào `build/g-out/ql/`.
- [x] T018 [US4] `Sources/PBIXQuickLook/PreviewViewController.swift` (`QLPreviewingController`) và `Sources/PBIXQuickLook/ThumbnailProvider.swift` (`QLThumbnailProvider`).

---

## Giai đoạn 6: US5 — VoiceOver & Trợ năng

- [x] T019 [US5] `Sources/BIPro/Report/AccessibilitySummary.swift` + `Tests/BIProTests/PhaseG/AccessibilitySummaryTests.swift`:
  - `VisualAccessibilitySummary.describe(visual:data:language:)` sinh `(label, value, hint)` cho mọi loại visual (cả `.vi` và `.en`);
  - `AccessibilityAnnouncer.announce(_:)` an toàn khi `NSApp == nil`.
- [x] T020 [US5] Gắn `.accessibilityLabel`, `.accessibilityValue`, `.accessibilityAddTraits` lên `ShellView`, `RibbonView`, `ReportWorkspace`, `LiveVisualView`, `ReportCanvas`, `DataPane`, `ReportPanes`; nối `AccessibilityAnnouncer.announce` khi đổi trang, đổi Xem/Sửa, lưu xong, xuất xong.

---

## Giai đoạn 7: US6 — App Icon, Onboarding, Đóng gói v1.0 & Hoàn thiện

- [x] T021 [US6] `Sources/BIPro/Settings/OnboardingView.swift` + nối vào `Sources/BIPro/App.swift` & `Sources/BIPro/Shell/ShellView.swift` (hiện 1 lần khi `!onboardingSeen`, mở lại từ Settings và menu Trợ giúp), bổ sung test trong `SettingsOnboardingTests.swift`.
- [x] T022 [US6] `scripts/make-icon.swift`: vẽ biểu tượng BI Pro native macOS Sequoia squircle (`#0A84FF` → `#5E5CE6`) đủ 10 kích cỡ (`16..1024`), gọi `iconutil -c icns` tạo `AppIcon.icns`.
- [x] T023 [US4/US6] Cập nhật `scripts/build-app.sh`:
  - gọi `scripts/make-icon.swift` đóng `AppIcon.icns` + `CFBundleIconFile = AppIcon`;
  - nâng `CFBundleShortVersionString` lên `1.0.0`;
  - biên dịch & đóng gói Quick Look extension (`Contents/PlugIns/*.appex` theo kết quả spike T005), ký ad-hoc.
- [x] T024 [US4/US6] Chạy `zsh scripts/build-app.sh` và kiểm chứng thực tế `build/BI Pro.app`:
  - xác nhận `CFBundleShortVersionString == 1.0.0` và `AppIcon.icns` hợp lệ;
  - chạy `qlmanage -t` và `qlmanage -p` trên `Nhom6_work.pbix`, `w8.3.pbix`, file cũ và file hỏng (SC-004);
  - mở `build/BI Pro.app` trên bản sao `Nhom6_work.pbix`, chụp bằng chứng Sáng và Tối (5 workspace + Query Editor + Settings + Onboarding) vào `docs/phase-g-evidence/`, kiểm nhãn VoiceOver/AX (SC-002, SC-005).
- [x] T025 Chạy toàn bộ `swift build`, `swift test`, và bộ golden nặng release (`BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --no-parallel --filter "Nhom6|ORA|VIS|PhaseG|QuickLookSummary"`), ghi số đo vào `specs/012-g-hoan-thien-v1/measurements.md` (SC-006).
- [x] T026 Tự rà soát `/code-review` trên toàn bộ thay đổi Phase G và `/speckit-converge` cho `specs/012-g-hoan-thien-v1/`, sửa hết lỗi phát hiện.
- [x] T027 Cập nhật `docs/BIPRO_BUILD_PLAN.md` (đánh dấu Phase G → **v1.0** xong) và `docs/STATE.md`. Không tự commit hay push.
