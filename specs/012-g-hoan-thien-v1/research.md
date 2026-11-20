# Nghiên cứu kỹ thuật: Phase G — Hoàn thiện ứng dụng (v1.0)

Tất cả quyết định tuân thủ Hiến pháp III (chỉ dùng API hệ thống Apple trên macOS 15, không thêm package/thư viện ngoài) và Hiến pháp IV (không tải mạng).

## R1. Kết xuất PDF, PNG và CSV (US1)

- **CSV dữ liệu visual (`VisualCSVExporter`)**:
  - Đọc trực tiếp `DataView` (hợp đồng có sẵn ở `Sources/BIPro/Visuals/Query/DataView.swift`) đã được `ReportInteraction` nạp với đúng trạng thái bộ lọc/slicer/drill hiện hành — bảo đảm khớp 100% số liệu hiển thị và golden DAX (Hiến pháp II).
  - Bố cục từng loại `DataView`:
    - `.single(SingleValueData)`: 1 cột (`measure.displayName`), 1 dòng giá trị định dạng plain (hoặc số gốc theo định dạng hiển thị).
    - `.categorical(CategoricalData)`: các cột `categoryLevels` (nếu có) + cột `seriesField` (nếu có, dạng long table — mỗi cặp `(category, series)` một dòng, hoặc wide table khi 1 measure có series; chọn **long table** giống Power BI Desktop *Export data* khi nhiều measure/series, bỏ các dòng toàn BLANK) + các cột `measures` (bỏ vai trò `Tooltips` nếu không vẽ? Giữ theo danh sách trường visual như Desktop: mọi measure không ẩn).
    - `.matrix(MatrixData)`: các cột tiêu đề hàng (`rowFields`) + mỗi lá cột (`columnLeaves`) × mỗi measure đang hiện, giữ đúng các dòng đang mở.
    - `.slicer(SlicerData)`: danh sách giá trị đang hiển thị của slicer.
  - Định dạng: RFC 4180 (`"` nhân đôi `""`, bọc `"` khi chứa `,`, `"`, `\r`, `\n`), đầu tệp ghi UTF-8 BOM (`0xEF 0xBB 0xBF`) để Excel/Numbers mở đúng tiếng Việt.
- **PNG và PDF trang báo cáo (`ReportPageExporter`)**:
  - Trước khi vẽ mỗi trang: nạp sẵn `LiveVisualData` cho toàn bộ visual không bị ẩn của trang (dùng `VisualDataLoader` + `ReportInteraction` hiện tại, chờ song song với `TaskGroup`, timeout bảo vệ 30 s/trang).
  - Vẽ trang bằng `ExportablePageView` (tái dùng các renderer của `LiveVisualView` ở chế độ tĩnh: không tay nắm Sửa, không viền chọn, không hover/tooltip, ẩn các visual có `interaction.isHidden`).
  - **Phương thức kết xuất trên macOS**: dùng `ImageRenderer` cho khung thuần SwiftUI hoặc offscreen `NSHostingView` (`NSWindow` ẩn offscreen + `cacheDisplay(in:to:)` cho PNG 1×/2× và `CGContext` PDF `beginPDFPage` / `endPDFPage` cho PDF nhiều trang).
  - Lưu ý kỹ thuật: các view `Treemap`, `DonutChart`, `ShapeMap` có lớp `NSViewRepresentable` chỉ để bắt rê chuột (`HoverTracker`); khi xuất tĩnh (`isExporting = true`) bỏ lớp hover này → 100% view kết xuất là thuần SwiftUI (`Canvas`, `Chart`, `Text`, `Shape`), nên `ImageRenderer` chạy nhanh, sắc nét, cho ra PDF vectơ (nhỏ, phóng không vỡ chữ) và PNG đúng pixel `round(width * scale) × round(height * scale)` mà không cần mở cửa sổ thật!
  - Nếu visual nào rơi vào nhánh AppKit (ví dụ `NSTableView`), kiểm tra thực tế ở test nặng `Nhom6_work.pbix` (trang D1 có card, bar, combo, matrix, shape map, slicer) để bảo đảm không có ô nào trống.

## R2. Dark Mode & Cài đặt ứng dụng (US2)

- **Màu động (`NSColor(name:dynamicProvider:)`)**:
  - SwiftPM không yêu cầu `.xcassets` để có màu thích ứng Sáng/Tối: tạo helper `Color.dynamic(light:dark:)` bọc `Color(nsColor: NSColor(name: nil) { appearance in ... })` kiểm tra `appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua`.
  - Bảng màu Dark Mode chuẩn macOS 15 Sequoia:
    - `backdrop`: light `#EBEBF0` / dark `#1C1C1E`
    - `chrome`: light `#F5F5F7` / dark `#242426`
    - `canvas` (bề mặt control/panel/card UI, không phải nền trang `.pbix`): light `#FFFFFF` / dark `#2C2C2E`
    - `separator`: light `#E5E5EA` / dark `#3A3A3C`
    - `label`: light `#1C1C1E` / dark `#F5F5F7`
    - `secondaryLabel`: light `#636366` / dark `#AEAEB2`
    - `tertiaryLabel`: light `#8E8E93` / dark `#6E6E73`
    - `checkboxBorder`: light `#C7C7CC` / dark `#545458`
    - `accent`: `#0A84FF` (giữ nguyên cả hai chế độ theo HIG macOS)
  - Gỡ bỏ các `.environment(\.colorScheme, .light)` ở `ShellView` (cửa sổ chính và 4 sheet), `FileOptionsView`, `CodeEditor`, `ResultGrid`, `AppliedStepsView`, `CompletionPopup` và các `appearance = NSAppearance(named: .aqua)` không thuộc Report Canvas.
  - **Giữ nguyên** `.environment(\.colorScheme, .light)` tại đúng ranh giới trang báo cáo trong `ReportCanvas.swift` (`pageSurface`) và `DropdownSlicer` trên canvas, để trang `.pbix` giữ nguyên màu tác giả.
- **Áp dụng chế độ giao diện toàn app**:
  - `AppPreferences.appearance` (`system` / `light` / `dark`) đồng bộ lên `NSApp.appearance` (`nil` / `.aqua` / `.darkAqua`) và `.preferredColorScheme(...)` ở `ShellView` — mọi cửa sổ, sheet, popover và cửa sổ Settings đổi tức thì không cần khởi động lại.
- **Cửa sổ Settings (`⌘,`)**:
  - SwiftUI cung cấp `Settings { SettingsView() }` ngay trong `BIProApp.body` (tự nối menu chuẩn `BI Pro ▸ Settings…` / `Cài đặt…` với phím tắt `⌘,`). Nút bánh răng ở đáy `Rail` gọi `openSettings()` (`@Environment(\.openSettings)` có sẵn từ macOS 14+).

## R3. Song ngữ Tiếng Việt và Tiếng Anh (US3)

- **Kiến trúc `L10n` nhẹ, không phụ thuộc Xcode `.xcstrings`**:
  - Vì dự án build thuần SwiftPM (`swift build` + `scripts/build-app.sh`), một struct/enum `L10n` đọc `AppPreferences.shared.effectiveLanguage` (`.vi` hoặc `.en`) với từ điển tĩnh `[L10nKey: (vi: String, en: String)]` (hoặc hai bảng `vi` / `en` kiểu `enum Key: String, CaseIterable`) có ưu điểm vượt trội:
    1. Đổi ngôn ngữ trong Settings cập nhật **tức thì** mọi SwiftUI view đang mở nhờ `@Observable AppPreferences` (không cần khởi động lại app như `Bundle.main.localizedString`).
    2. **Kiểm thử tự động 100%**: unit test duyệt `L10n.Key.allCases` bảo đảm không khoá nào thiếu bản dịch `vi` hoặc `en`, không khoá nào rỗng, và khớp số placeholder `%@`/`%d`.
    3. Không bao giờ đụng vào `PBIXKit`/`DAXEngine`/`MEngine` hay chuỗi lưu trong `.pbix`.
  - Đồng thời cập nhật nhãn phép gộp ngầm (`AggregateFunction.displayLabel(column:language:)`) để hiện "Tổng của Amount" ở `.vi` và "Sum of Amount" ở `.en`, trong khi `nativeQueryRef` lưu vào PBIR vẫn luôn là `"Sum(Table.Amount)"` theo Power BI Desktop.

## R4. Quick Look cho tệp `.pbix` (US4)

- **Lõi đọc nhanh trong `PBIXKit` (`PBIXQuickLookSummary`)**:
  - Đọc ZIP trực tiếp bằng `ZipArchive`:
    1. Đọc `ReportDefinition` (PBIR hoặc `Report/Layout` cũ): lấy danh sách trang, trang đang hoạt động, kích thước trang đầu, danh sách khung visual (toạ độ x, y, w, h, loại visual, tiêu đề nếu có).
    2. Nếu có `DataModel`: giải nén XPress9 → mở `ABFBackup` → chỉ đọc `metadata.sqlitedb` để đếm `userTables`, `columns`, `measures`, `relationships` (không giải mã bất kỳ `.idf`/`.dictionary` nào). Với `Nhom6_work.pbix` (54 MB), đường đọc này chỉ mất ~250–400 ms ở bản release.
  - Có thể xuất ra `CGImage` (thumbnail) và HTML/NSAttributedString hoặc `NSView` (preview) bằng thuần CoreGraphics/AppKit — test được độc lập bằng `swift test`!
- **App Extension `.appex` trong `scripts/build-app.sh` (không cần Xcode)**:
  - Trên macOS 15, Quick Look Preview extension dùng `NSExtensionPointIdentifier = com.apple.quicklook.preview` (`QLPreviewingController` trong `QuickLookUI`) và Thumbnail extension dùng `com.apple.quicklook.thumbnail` (`QLThumbnailProvider` trong `QuickLookThumbnailing`), khai báo `QLSupportedContentTypes = ["com.microsoft.powerbi.pbix"]`.
  - Build trong `scripts/build-app.sh`: SwiftPM tạo thư viện tĩnh `PBIXKit` (hoặc biên dịch target helper), rồi `swiftc` liên kết `PBIXKit` thành nhị phân extension đặt trong `BI Pro.app/Contents/PlugIns/PBIXQuickLook.appex` và `PBIXThumbnail.appex`, ký ad-hoc `codesign --force --sign - --entitlements ...`, đăng ký qua `pluginkit -a`.
  - **Spike Đợt 0 (quan trọng)**: kiểm chứng ngay bằng `qlmanage -t` và `qlmanage -p` trên `Nhom6_work.pbix` xem macOS 15 có chấp nhận `.appex` build từ `swiftc` + ký ad-hoc không, và ghi kết quả đo thực tế vào `docs/phase-g-evidence/`.

## R5. VoiceOver & Trợ năng (US5)

- **Tách phần logic thuần có thể test được (`VisualAccessibilitySummary`)**:
  - Cho `ReportVisual` + `DataView?` + `L10n.Language`, sinh ra `(label: String, value: String, hint: String)`:
    - Label: `"<Loại visual>: <Tiêu đề hoặc trường>"` (ví dụ: `"Thẻ: Doanh thu thuần"` / `"Card: Net Revenue"`).
    - Value: với `.single` đọc thẳng giá trị đã định dạng (`"$197M"`); với `.categorical` đọc `"<N> danh mục, <M> chuỗi"` + giá trị lớn nhất/nhỏ nhất nếu 1 chuỗi; với `.matrix` đọc `"<R> hàng, <C> cột"`; với `.slicer` đọc số mục đang chọn hoặc `"Tất cả"`.
- **Áp lên UI**:
  - Gắn `.accessibilityLabel(...)`, `.accessibilityValue(...)`, `.accessibilityAddTraits(...)` trên `TitleBar`, `Rail`, `RibbonView`, `ZoomControl`, `CollapsedPaneStrip`, `PageTabs`, `DataPane`, `ReportPanes`, `LiveVisualView`, `ReportCanvas`.
  - Helper `AccessibilityAnnouncer.announce(_ text: String)` gọi `NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])`.

## R6. App Icon, Onboarding & Đóng gói v1.0 (US6)

- **Sinh `AppIcon.icns` hoàn toàn native (`scripts/make-icon.swift`)**:
  - Script Swift dùng `CoreGraphics` / `AppKit` vẽ biểu tượng BI Pro sắc nét (nền squircle gradient macOS `#0A84FF` → `#5E5CE6`, 3 cột biểu đồ bo góc màu trắng bán trong suốt + đường xu hướng ánh sáng), xuất đủ 10 kích thước chuẩn (`16, 32, 64, 128, 256, 512, 1024` @1x/@2x) vào `.iconset`, gọi `/usr/bin/iconutil -c icns` → `build/BI Pro.app/Contents/Resources/AppIcon.icns`.
  - Thêm `CFBundleIconFile = AppIcon` và `CFBundleShortVersionString = 1.0.0` trong `scripts/build-app.sh`.
- **Onboarding (`OnboardingView`)**:
  - 3 thẻ bước ngắn gọn (icon SF Symbols + minh hoạ nhỏ, hỗ trợ Sáng/Tối và Việt/Anh), lưu `AppPreferences.onboardingSeen = true` khi đóng/hoàn tất, mở lại được từ Settings hoặc menu Trợ giúp.
