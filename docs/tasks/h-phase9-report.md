# Báo cáo Phase 9 (H5 / US7 — Màn hình khởi động, File Backstage, hộp Options, báo cáo trống)

Ngày hoàn tất: 2026-11-21 · Phạm vi: `T066`–`T074` trong `specs/016-h-giao-dien-giong-powerbi/tasks.md`.

## 1. Tóm tắt thay đổi

- **T066 (`Tests/BIProTests/UIParity/StartAndBackstageTests.swift`):** kiểm `StartEntry.all` đúng 6 thẻ (OneLake, Learn with sample data vô hiệu kèm tooltip), `BackstageItem.all` đúng 11 mục theo thứ tự Desktop (ẩn Sign out), `RecentFileEntry` đánh dấu tệp không tồn tại (`exists == false`, `canOpen == false`), và `OptionsSection` đủ 15 mục `GLOBAL` + 7 mục `CURRENT FILE`.
- **T067 (`Tests/BIProTests/Edit/AppLaunchPolicyTests.swift`):** giữ nguyên 3 kịch bản mở app và bổ sung kiểm `UntitledDocuments.shouldShowStartScreenOnLaunch(...)` cho kịch bản mở trực tiếp không tệp.
- **T068 (`Sources/BIPro/Shell/RecentFilesList.swift`):** danh sách Name / Location / Opened hợp nhất từ `NSDocumentController.shared.recentDocumentURLs` và `RecentFiles.urls`, tệp mất trên đĩa hiện mờ không bấm được, kèm thanh lọc từ khoá.
- **T069 (`Sources/BIPro/Shell/StartScreen.swift`):** rail Home/Open + Options and settings/About (ẩn Sign out), khối 6 thẻ "Select a data source or start with a blank report" và `RecentFilesList`.
- **T070 (`Sources/BIPro/Shell/BackstageView.swift`):** mũi tên quay lại màu teal, 3 nhóm mục Desktop, màn Home (New ▸ Blank report + Recent), Save as, Export (PDF, PNG, CSV và **Export TMDL…** ghi toàn bộ kịch bản TMDL ra thư mục chọn), Options and settings, About.
- **T071 (`Sources/BIPro/Shell/OptionsDialog.swift`):** hộp 770×600 với cột trái `GLOBAL` (15 mục) / `CURRENT FILE` (7 mục), nối mục Data Load (`Auto date/time`, `Autodetect relationships` qua `FileOptions`), Regional Settings (ngôn ngữ), Report settings (Sáng/Tối, Snap to grid, View-only mode default), nút OK (`accentTeal`) và Cancel.
- **T072 (`Sources/BIPro/Report/AddDataPanel.swift`):** tiêu đề cỡ 26, dòng phụ có chữ **Data** đậm, 4 thẻ rộng đến 252 pt với nửa trên pastel xanh lục / xanh dương / vàng / xám, liên kết xanh lục teal; giữ nguyên hành vi 4 thẻ và toàn bộ test `F2AddDataPanelTests`.
- **T073 (`Sources/BIPro/App.swift`, `Sources/BIPro/Shell/UntitledDocuments.swift`, `Sources/BIPro/Shell/ShellView.swift`):** đăng ký cửa sổ `start-screen`, thêm `UntitledDocuments.showStartScreen()` / `shouldShowStartScreenOnLaunch(...)`, gắn `BackstageView` khi `state.showBackstage == true` và chuyển hộp tuỳ chọn tệp sang `OptionsDialog`.

## 2. Kiểm chứng tự động

- **TDD RED → GREEN:** `StartAndBackstageTests` + `AppLaunchPolicyTests` thất bại đỏ trước cài đặt, sau đó xanh 50/50 test.
- **Toàn repo (`swift test --no-parallel`):** **2.528 / 2.528 passed** (0 failures).

## 3. Kiểm tra ảnh chụp (`build/h-out/us7/`)

Đã xuất bằng `BIPRO_H_RENDER=1 swift test --no-parallel --filter ParityRenderTests` và mở xem trực tiếp cả 5 ảnh (và xuất lại sau khi nới rộng rail `StartScreen` thành 204 pt và căn lại hàng `OptionsDialog` để không bị cắt tiêu đề/nút đáy):

| Tệp | Nhận xét thị giác |
|---|---|
| `build/h-out/us7/start-screen-light.png` | Rail trái đủ rộng ("Options and settings" trọn dòng), 6 thẻ cân đối (2 thẻ unsupported mờ), bảng Recent rõ ràng |
| `build/h-out/us7/backstage-home-light.png` | Mũi tên quay lại teal, đủ 11 mục 3 nhóm, thẻ New ▸ Blank report + bảng Recent khớp `f_file.png` |
| `build/h-out/us7/backstage-export-light.png` | Đủ 4 mục PDF, PNG, CSV và Export TMDL… |
| `build/h-out/us7/options-dialog-light.png` | Khung 770×600 thấy rõ tiêu đề "Options", 15 GLOBAL + 7 CURRENT FILE, nội dung Data Load và nút OK (teal) / Cancel |
| `build/h-out/us7/add-data-panel-light.png` | Tiêu đề 26 pt, chữ **Data** đậm, 4 thẻ pastel xanh lục/xanh dương/vàng/xám, liên kết xanh teal |

## 4. Quyền sở hữu tệp

Toàn bộ tệp sửa/tạo nằm trong `docs/phase-h-ownership.tsv`.
