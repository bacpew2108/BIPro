# Báo cáo Phase 8 (H4 / US6 — Thanh trang và thanh trạng thái toàn cửa sổ)

Ngày hoàn tất: 2026-11-21 · Phạm vi: `T061`–`T065` trong `specs/016-h-giao-dien-giong-powerbi/tasks.md`.

## 1. Tóm tắt thay đổi

- **T061 (`Tests/BIProTests/UIParity/StatusLineTests.swift`):** kiểm `StatusLine.text(mode:state:language:)` cho cả 5 view (`Page n of m`, `Table: … (n rows) Column: … (n distinct values)`, `Query n of m`, `Script n of m`, `n tables · m relationships`, kèm bản tiếng Việt) và kiểm giới hạn thu phóng `StatusBarZoom` trong khoảng 25%–400%.
- **T062 (`Sources/BIPro/Report/ReportWorkspace.swift` — `PageTabs`):** thiết kế lại thanh trang cao `UIMetrics.pageTabs` (35 pt) khớp `o_now.png`: biểu tượng Desktop (gạch chân `accentTeal`) + Phone (vô hiệu kèm tooltip), mũi tên ◂ ▸ chuyển trang, tab trang chữ thường (tab chọn nền trắng + gạch chân `accentTeal`, trang ẩn có `eye.slash`), nút `+` vuông nền `accentTeal`; bỏ bộ đếm trang và zoom lặp khỏi `PageTabs` (dời xuống `WindowStatusBar`); giữ đầy đủ hành vi thêm/đổi tên/nhân bản/di chuyển/xoá trang.
- **T063 (`Sources/BIPro/Shell/StatusLine.swift`, `Sources/BIPro/Shell/StatusBar.swift`):**
  - `StatusLine`: định dạng dòng trạng thái trái cho 5 chế độ, đọc `cardinality` (hoặc `dictionaryCount` cho bảng overlay trong phiên).
  - `WindowStatusBar`: thanh trạng thái toàn cửa sổ cao `UIMetrics.statusBar` (23 pt), trái là `StatusLine` + thông báo ngắn, phải là thanh trượt thu phóng `− ─ + n%` (25%–400%) + nút Fit ở Report; ở Model view có thêm nút đặt lại bố cục (`resetDiagramPositions()`) và Fit (`modelZoom = 0.6`), thanh trượt nối `modelZoom`.
  - Giữ shim tương thích rỗng cho `StatusBar`/`ZoomControl` cũ để không đụng `TableWorkspace`/`ModelWorkspace`/`QueryWorkspaces` trước Phase 10 (đúng phân khu sở hữu T064).
- **T064 (`Sources/BIPro/Shell/ShellView.swift`):** gắn `WindowStatusBar(state: state)` dưới toàn bộ vùng làm việc và gỡ `StatusBar`/`ZoomControl` cũ khỏi `ShellView.swift`.

## 2. Kiểm chứng tự động

- **TDD RED → GREEN:** `StatusLineTests` thất bại đỏ trước cài đặt, sau đó xanh 2/2 test (tổng `UIParity`: 41/41 passed).
- **Toàn repo (`swift test --no-parallel`):** **2.522 / 2.522 passed** (0 failures).

## 3. Kiểm tra ảnh chụp (`build/h-out/us6/`)

Đã xuất bằng `BIPRO_H_RENDER=1 swift test --no-parallel --filter UIParity` và mở xem trực tiếp cả 4 ảnh:

| Tệp | Kích thước | Nhận xét thị giác |
|---|---|---|
| `build/h-out/us6/report-bottom-light.png` | 18,785 bytes | Desktop/Phone, ◂ ▸, `Page 1 \| Page 2 \| Page 3` (gạch chân teal), nút `+` vuông teal; dưới là `Page 3 of 3` + thanh trượt `69%` + fit; khớp `o_now.png` |
| `build/h-out/us6/report-bottom-dark.png` | 18,865 bytes | Dark Mode sắc nét, gạch chân teal `#3FB59B` và nút `+` rõ ràng |
| `build/h-out/us6/table-status-light.png` | 11,376 bytes | `Table: Sales (2 rows) Column: Amount (2 distinct values)` khớp `t_colsel.png` |
| `build/h-out/us6/model-status-light.png` | 10,231 bytes | `1 tables · 0 relationships`, nút đặt lại bố cục `↺`, thanh trượt `85%`, nút fit |

## 4. Quyền sở hữu tệp

Toàn bộ tệp sửa/tạo nằm đúng trong `docs/phase-h-ownership.tsv`.
