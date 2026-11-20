# Kiểm chứng Trợ năng VoiceOver & Điều hướng bàn phím (US5, SC-005)

**Ngày kiểm**: 2026-11-21

## 1. Kiểm thử đơn vị tự động (`AccessibilitySummaryTests`)

- `VisualAccessibilitySummary.describe(visual:data:slicerSelectedCount:language:)` kiểm qua 100% ở cả `.vi` và `.en` cho:
  - Card (`"Thẻ số liệu: Tổng doanh thu"` / `"Card: Tổng doanh thu"`, giá trị định dạng)
  - Biểu đồ cột/trục/donut/treemap/map (`"Biểu đồ cột"` / `"Column chart"`, `"2 danh mục, 1 chuỗi"` / `"2 categories, 1 series"`)
  - Ma trận/Bảng (`"<R> hàng, <C> cột"` / `"<R> rows, <C> columns"`)
  - Slicer (`"Tất cả"` / `"All"` hoặc `"Đã chọn N mục"` / `"N selected"`)
- `AccessibilityAnnouncer.announce(_:)` an toàn khi `NSApp == nil` trong môi trường `swift test` và gọi `NSAccessibility.post(element: NSApp, notification: .announcementRequested, userInfo: [.announcement, .priority: .high])` khi chạy thật.

## 2. Danh mục điều khiển đã gắn nhãn trợ năng trên `BI Pro`

| Vùng giao diện | Tệp | Nhãn / Giá trị / Thuộc tính đã gắn |
|---|---|---|
| Title Bar | `Sources/BIPro/Shell/ShellView.swift` | Nút Xuất (`accessibilityLabel`), ô tìm kiếm `⌘K` (`accessibilityLabel`) |
| Rail trái | `Sources/BIPro/Shell/ShellView.swift` | 5 nút chế độ làm việc (`accessibilityLabel` song ngữ + `.isSelected`), nút bánh răng Cài đặt (`a11yRailSettings`) |
| Ribbon | `Sources/BIPro/Shell/Ribbon.swift`, `DesignSystem/Components.swift` | Tab Ribbon (`localizedTitle` + `.isSelected`), mọi `RibbonButton` (`accessibilityLabel(title)`) |
| Thanh Zoom | `Sources/BIPro/Shell/ShellView.swift` | Nút Thu nhỏ, phần trăm zoom, Phóng to, Vừa khung (`zoomOut`/`zoomIn`/`zoomFit`) |
| Pane & Collapse | `Sources/BIPro/DesignSystem/Components.swift`, `Panes/ReportPanes.swift` | Nút thu gọn / mở rộng ngăn (`a11yCollapsePaneFormat` / `a11yExpandPaneFormat`), thư viện loại visual (`.isSelected`), nút mắt ẩn/hiện trong Selection pane (`a11yHidden` / `a11yVisible` + `.isButton`) |
| Report Canvas & Page Tabs | `Sources/BIPro/Report/ReportCanvas.swift`, `Report/ReportWorkspace.swift` | Mỗi visual dùng `VisualAccessibilitySummary.describe` (`.accessibilityElement(children: .contain)`, `Label`/`Value`/`Hint`); tab trang (`a11yPageTabFormat`, trạng thái ẩn/đang chọn, `.isButton`/`.isSelected`); công tắc Xem/Sửa (`menuEditMode`) |
| Thông báo VoiceOver (`announcementRequested`) | `DocumentState.swift`, `DocumentActions.swift`, `DocumentState+Export.swift` | Đổi trang báo cáo, bật/tắt chế độ Sửa (`⌘E`), lưu tài liệu xong (`⌘S`), xuất PDF/PNG/CSV xong |
