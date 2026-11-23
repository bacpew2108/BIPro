# Báo cáo Phase 6 (H4 / US4 — Khung cửa sổ, tiêu đề, rail, màu nhấn teal và R-02)

Ngày hoàn tất: 2026-11-21 · Phạm vi: `T045`–`T053` trong `specs/016-h-giao-dien-giong-powerbi/tasks.md`.

## 1. Tóm tắt thay đổi

- **T045 (`Tests/BIProTests/UIParity/ShellLayoutTests.swift`):** kiểm số đo `DS.Metrics` khớp `UIMetrics` (±2 pt), kiểm màu nhấn `DS.Palette.accent` chuyển sang teal (`#117865`), kiểm `Rail.modes` luôn đủ 5 biểu tượng và dựng `ShellView` 1600×1000 trên tài liệu không có mô hình ở đủ 5 view không lỗi.
- **T046 (`Tests/BIProTests/UIParity/EditModeDefaultTests.swift`):** kiểm Spike R-02 bằng `EditClickPolicy` trên `SyntheticReport` — dịch chuyển < 4 pt là `.click` (vừa chọn visual vừa áp lọc chéo `ReportInteraction`, không dời khung), dịch chuyển ≥ 4 pt là `.drag` (dời visual, không áp lọc chéo), và kiểm `DocumentState.editMode` mặc định `true` trừ khi bật `AppPreferences.shared.viewOnlyDefault`.
- **T047 (`Sources/BIPro/Shell/TitleBar.swift`):** tách `TitleBar` và `CommandResults` khỏi `ShellView.swift`; cao `UIMetrics.titleBar` (36 pt); traffic lights spacer 72 pt, Lưu/Hoàn tác/Làm lại, tên tệp + trạng thái lưu + menu ▾ (Save/Save as/File options + tạm giữ Export PDF/PNG/CSV cho đến US7), ô Search ở giữa (`⌘K`), bánh răng Cài đặt (`openSettings`), chuyển Sáng/Tối, nút Share vô hiệu; bỏ nút Export riêng.
- **T048 (`Sources/BIPro/Shell/Rail.swift`):** tách `Rail` rộng `UIMetrics.rail` (42 pt) với 5 biểu tượng cao `UIMetrics.railIconHit` (40 pt), vạch chọn dọc 3 pt `accentTeal` + nền nhạt, tooltip EN khớp Desktop (`Report view`, `Table view`, `Model view`, `DAX query view`, `TMDL View`), bỏ nút Cài đặt ở đáy rail, bỏ `.disabled` khi `metadata == nil`; thêm `EmptyViewState` song ngữ (`"Chưa có dữ liệu. Thêm dữ liệu để dùng chế độ này."` / `"No data yet. Add data to use this view."`).
- **T049 (`Sources/BIPro/Shell/ShellView.swift`):** gỡ `TitleBar`, `CommandResults`, `Rail` cũ và hiện `EmptyViewState` khi `state.mode != .report && state.workspace.metadata == nil`.
- **T050 (`Sources/BIPro/DesignSystem/Tokens.swift`):** chuyển `DS.Palette.{accent, accentHover, accentPressed, selectionSoft}` sang teal (`#117865` Sáng / `#3FB59B` Tối), `chrome` sang `#F5F5F5`, `backdrop` sang `canvasWell` (`#E6E6E6` / `#1C1C1E`), giữ nguyên `series` và `paper*`; cập nhật `DS.Metrics.*` theo `UIMetrics.*`.
- **T051 (`Sources/BIPro/Report/ReportWorkspace.swift`, `Sources/BIPro/Report/ReportCanvas.swift`):** nền canvas dùng `DS.Palette.canvasWell`, nền giấy giữ `DS.Palette.documentPaper`.
- **T052 (Spike R-02):** triển khai `EditClickPolicy` (ngưỡng 4 pt màn hình) trong `EditCanvasOverlay.swift`, cho cú bấm ngắn xuyên xuống `VisualContainerView` để vừa chọn visual vừa lọc chéo trong `ReportCanvas.swift`, đặt `DocumentState.editMode = canEdit && !AppPreferences.shared.viewOnlyDefault` làm mặc định, ẩn công tắc nổi `EditModeSwitch` khỏi canvas (giữ phím tắt `⌘E` và lối thoát "View-only mode" ở View → Page view ▾). **Kết luận R-02: ĐẠT** (T046 + toàn bộ 2.515 test + 119 Heavy Golden xanh, không cần fallback).

## 2. Kiểm chứng tự động

- **TDD RED → GREEN:** `ShellLayoutTests` & `EditModeDefaultTests` thất bại đỏ trước cài đặt (`cannot find 'EditClickPolicy'`, `EmptyViewState`, `Rail.modes`, `Rail.tooltip`), sau đó xanh 34/34 test trong `UIParity`.
- **Toàn repo (`swift test --no-parallel`):** **2.515 / 2.515 passed** (0 failures).
- **Heavy Golden (`BIPRO_HEAVY=1 swift test -c release ...`):** **119 / 119 passed** (0 regressions trên `Nhom6`, `ORA`, `VIS`, `ExportCSV`, `ExportRender`, `QuickLook`, `V11BDAXGolden`).

## 3. Kiểm tra ảnh chụp (`build/h-out/us4/`)

Đã xuất bằng `BIPRO_H_RENDER=1 swift test --no-parallel --filter UIParity` và mở xem trực tiếp cả 4 ảnh:

| Tệp | Kích thước | Nhận xét thị giác |
|---|---|---|
| `build/h-out/us4/shell-report-light.png` | 210,710 bytes | Tiêu đề 36 pt, Search ở giữa, rail 42 pt có vạch dọc teal 3 pt, nền canvas `#E6E6E6` nổi bật tờ giấy trắng; không biển cấm, không cắt chữ |
| `build/h-out/us4/shell-report-dark.png` | 209,179 bytes | Dark Mode tương phản rõ, teal `#3FB59B` sáng rõ, giấy báo cáo giữ nền sáng đúng FR-013 |
| `build/h-out/us4/shell-empty-table-light.png` | 204,468 bytes | Chọn Table view trên báo cáo trống hiện đúng `EmptyViewState` + nút teal "Get data...", rail đủ 5 biểu tượng |
| `build/h-out/us4/shell-empty-table-dark.png` | 204,843 bytes | Trạng thái trống ở Dark Mode rõ ràng, cân đối |

## 4. Quyền sở hữu tệp (`git status`)

Tất cả tệp thêm/sửa nằm trong danh mục cho phép của `docs/phase-h-ownership.tsv`; không chạm engine (`PBIXKit`, `ColumnStore`, `DAXEngine`, `Connectors`, `MEngine`), `Package.swift`, hay `.pbix`.
