# Hợp đồng nội bộ: Phase G (v1.0)

Các ranh giới cố định chốt ở Đợt 0 để các lát việc (US1–US6) chạy độc lập, không giẫm chân lên nhau.

## 1. Hợp đồng `AppPreferences` & `L10n` (`Sources/BIPro/Settings/`)

- `AppPreferences.shared` là nguồn sự thật duy nhất cho cài đặt toàn cục (`appearance`, `language`, `snapToGrid`, `gridSize`, `onboardingSeen`, `sqliteOdbcDriver`).
- `DS.Palette` đọc trực tiếp từ màu động `NSColor(name:dynamicProvider:)` — bất kỳ view nào dùng `DS.Palette.*` tự động thích ứng Sáng/Tối mà không cần truyền thêm tham số.
- Mọi view ở Shell, Ribbon, Panes, Settings, Onboarding dùng `L10n` qua `tr(_:)`.
- **Bất biến lưu tệp**: `PBIXKit`, `DAXEngine`, `MEngine`, `PBIRQueryPatch`, `SourceQuery` KHÔNG ĐƯỢC đọc `AppPreferences.language`.

## 2. Hợp đồng `ReportExporter` (`Sources/BIPro/Export/`)

- `VisualCSVExporter.export(_ view: DataView) throws -> Data`:
  - Bắt đầu bằng 3 byte UTF-8 BOM `[0xEF, 0xBB, 0xBF]`.
  - Kết thúc mỗi dòng bằng `\r\n` (chuẩn RFC 4180 / Power BI Desktop).
  - Ném `ExportError.noData` cho `.empty`.
- `ReportPageExporter.renderPNG(...) throws -> Data`:
  - Bắt đầu bằng chữ ký PNG `[0x89, 0x50, 0x4E, 0x47]`.
  - Kích thước pixel = `Int((page.width * scale).rounded()) × Int((page.height * scale).rounded())`.
- `ReportPageExporter.renderPDF(...) throws -> Data`:
  - Bắt đầu bằng `%PDF-`, mở được bằng `PDFDocument(data:)` (`PDFKit`), số trang bằng `pages.count`.
  - Không bao giờ hiển thị tay nắm Sửa, khung chọn, hay visual bị ẩn.

## 3. Hợp đồng `PBIXQuickLookSummary` (`Sources/PBIXKit/QuickLookSummary.swift`)

- `PBIXQuickLookSummary.load(from: URL) throws -> PBIXQuickLookSummary` là hàm đồng bộ, thread-safe, đọc chỉ-đọc, không ghi tệp tạm nào ra thư mục người dùng.
- File không phải ZIP / hỏng → ném lỗi có mô tả ngắn, extension bắt lỗi và vẽ thẻ lỗi an toàn (không crash).
- `PBIXQuickLookRenderer` (trong `Sources/PBIXKit/QuickLookRenderer.swift`): vẽ `CGImage` thumbnail và hình/bố cục preview từ `PBIXQuickLookSummary`, nằm trong `PBIXKit` để `PBIXKitTests` kiểm thử trực tiếp không cần Finder và `Sources/PBIXQuickLook/` chỉ giữ 2 entry point mỏng (`PreviewViewController`, `ThumbnailProvider`).

## 4. Hợp đồng `VisualAccessibilitySummary` (`Sources/BIPro/Report/AccessibilitySummary.swift`)

- Luôn trả `label` không rỗng cho mọi `ReportVisual` (kể cả khi visual không có tiêu đề tường minh — rơi về loại visual + tên trường đầu tiên).
- Hỗ trợ cả `.vi` và `.en`.
- `AccessibilityAnnouncer.announce(_:)` chỉ gọi `NSAccessibility.post` khi `NSApp != nil` (an toàn trong môi trường `swift test` không có AppKit run loop).
