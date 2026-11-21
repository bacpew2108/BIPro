# Nghiên cứu kỹ thuật: Phase H — Giao diện giống Power BI Desktop

Mỗi mục: **Quyết định**, **Lý do**, **Phương án đã loại**. Nguồn: mã nguồn hiện tại (đọc ngày 2026-11-21), `docs/PHASE_H_UI_PARITY.md`, ảnh VM.

## R-01 Ribbon là dữ liệu, không phải các view tay

- **Quyết định:** định nghĩa Ribbon bằng cấu trúc dữ liệu (`RibbonCatalog`) rồi một bộ vẽ chung dựng từ đó; nút gọi lại hàm `DocumentState` hiện có qua `RibbonCommandID`.
- **Lý do:** hiện `Ribbon.swift` (892 dòng) gồm nhiều `struct …Commands` private, không test được tên/thứ tự/trạng thái nếu không dựng giao diện. Dữ liệu cho phép test đối chiếu danh mục Desktop (SC-001), một nguồn cho song ngữ, và cho phép giao agy theo tệp catalog riêng từng tab.
- **Loại:** (a) giữ view tay và chỉ sắp lại: không test được, dễ lệch lại; (b) sinh Ribbon từ JSON ở bundle: thêm lớp tải/đồng bộ không cần thiết, mất kiểm kiểu của Swift.

## R-02 Chế độ Sửa mặc định (Q2) và lọc chéo

- **Hiện trạng:** `DocumentState.editMode = false`; trong `ReportCanvas` ở chế độ Sửa "nội dung bên trong visual không nhận chuột" và `EditCanvasOverlay` lo chọn/kéo/đổi cỡ. Chế độ Xem mới có lọc chéo và drill khi bấm.
- **Vấn đề:** Desktop không có hai chế độ; bấm điểm dữ liệu vừa chọn visual vừa lọc chéo. Đổi mặc định sang Sửa nguyên trạng sẽ mất lọc chéo khi bấm.
- **Quyết định:** làm spike ở H4: ở chế độ Sửa, cú bấm không kéo (di chuyển < ngưỡng) xuyên qua lớp chọn xuống visual để lọc chéo, cú kéo vẫn là di chuyển visual. Nếu đạt test hiện có (`Interaction`, `D*Nhom6Tests`) thì đặt mặc định Sửa và để "Chế độ chỉ xem" ở menu View. Nếu không đạt, giữ mặc định hiện tại, chỉ chuyển công tắc View/Edit vào menu View và báo người dùng.
- **Loại:** đổi mặc định không kiểm: phá hành vi đang có; bỏ hẳn chế độ Xem: mất cách bảo vệ tệp.

## R-03 Biểu tượng hai màu (Q3)

- **Quyết định:** SF Symbols với `.symbolRenderingMode(.palette)` hai màu, bảng màu cố định theo nhóm lệnh (dữ liệu: teal/xanh dương, tính toán: cam, trình bày: xanh dương/xám) lưu trong catalog (`tint`/`tint2`). Danh sách biểu tượng nằm ở catalog, không rải trong view.
- **Lý do:** không thêm thư viện, không vẽ bộ biểu tượng mới; đổi sau chỉ sửa catalog.
- **Loại:** tự vẽ bộ Fluent ngay: tốn công, rủi ro bản quyền hình dạng; nhúng SVG Fluent: là tài sản ngoài, cần duyệt riêng (hiến pháp III).

## R-04 Nút Windows/cloud hiện vô hiệu (Q4)

- **Quyết định:** `Availability.unsupported(reason:)` kèm tooltip cố định song ngữ; không có hành động. Sensitivity/Publish/Share/Copilot/Dataverse/OneLake/Power Apps/Power Automate/Q&A/Prep data for AI.
- **Lý do:** giữ đúng vị trí và số nút; hiến pháp nâng v1.2.0 đã cho phép.

## R-05 Màu và số đo

- **Quyết định:** thêm `UIMetrics` và token mới ở `DesignSystem/Tokens.swift`: `accent` teal `#117865` (nhấn chạm `#0E6655`; Dark `#3FB59B`), `canvasWell` `#E6E6E6`/`#1C1C1E`, chrome `#F5F5F5`. Số đo theo mục 3.1 của tài liệu cấp trên: titleBar 36, tabRow 32, ribbon 98, rail 42, pageTabs 35, statusBar 23, pane 181, collapsedPane 31. Giữ `DS.Palette.series` (màu biểu đồ) và các token `paper*` hiện có.
- **Rủi ro:** `accent` dùng ở nhiều nơi (`.tint`, vòng focus, chọn). Giảm bằng kiểm ảnh và test token; không đổi màu dữ liệu.
- **Loại:** đổi `AccentColor` của hệ thống: ảnh hưởng toàn hệ thống và không đồng nhất giữa Light/Dark.

## R-06 Trạng thái bật/tắt tính bằng `RibbonContext`

- **Quyết định:** `RibbonContext` là ảnh chụp bất biến của các điều kiện (`mode`, `hasModel`, `hasData`, `visualSelected`, `multiSelected`, `canEditModel`, `canEditCanvas`, `viewOnly`, `columnSelected`…) dựng từ `DocumentState`; `Availability` là hàm thuần của context. Test dựng context giả, không cần `DocumentState` thật.
- **Lý do:** test nhanh, không phụ thuộc UI; tách "khi nào bật" khỏi "làm gì".
- **Loại:** đọc thẳng `DocumentState` trong catalog: khó test, vòng phụ thuộc.

## R-07 Thanh trạng thái và pane

- **Quyết định:** một `StatusBar` toàn cửa sổ nhận nội dung theo `mode`; bỏ thanh trạng thái từng pane (`FiltersPane`, `VisualizationsPane`, `DataPane`). Filters thu gọn bằng `collapsedPane` 31 pt, ghi nhớ trạng thái trong `DocumentState` (không ghi `.pbix`).
- **Lý do:** khớp Desktop và bỏ trùng thông tin.

## R-08 Màn hình khởi động, File và Options

- **Quyết định:** `StartScreen` (khi chưa có tài liệu) và `BackstageView` (tab File) là hai view dùng chung thành phần `RecentFilesList` nhận danh sách từ `NSDocumentController.shared.recentDocumentURLs`. `OptionsDialog` dựng khung GLOBAL/CURRENT FILE, ghép các tuỳ chọn tệp đang có (`FileOptionsView`) và đặt mục chưa có tính năng ở trạng thái vô hiệu. Bánh răng tiêu đề mở cửa sổ Cài đặt (`⌘,`) như hiện nay.
- **Loại:** thay `FileOptionsView` hoàn toàn: mất luồng đã test.

## R-09 Cách kiểm "giống" mà không so từng điểm ảnh

- **Quyết định:** (1) test dữ liệu: duyệt catalog so với bảng chuẩn (tên, thứ tự, kiểu, Availability) cho từng tab/context; (2) test số đo/màu: so `UIMetrics`/token với hằng số chuẩn; (3) test song ngữ: mọi tiêu đề có `vi` và `en` không rỗng, `en` đúng chữ Desktop; (4) xuất ảnh cửa sổ ở Light/Dark vào `build/h-out/` (khi `BIPRO_H_RENDER=1`) để người duyệt đặt cạnh ảnh Desktop. Không đặt golden điểm ảnh (font và co giãn khác nền tảng).
- **Loại:** so điểm ảnh tự động: sai vì SF Pro ≠ Segoe UI.

## R-10 Quản lý thay đổi ở các test cũ

- **Quyết định:** H0 chạy `grep` các test dùng `RibbonTab`, `state.tabs`, `ribbonTab` và lên danh sách cập nhật; cập nhật chung với pha đổi hành vi (H1 cho tab, H3 cho Table/Model).
- **Lý do:** tránh đỏ kéo dài; `ColumnToolsRibbonTests` và `AppLaunchPolicyTests` là hai test gần nhất.

## R-11 Phần chưa quan sát

- **Quyết định:** các menu/hộp thoại chưa quan sát (xem `docs/PHASE_H_UI_PARITY.md` mục 2) làm theo suy luận, mọi mục trong catalog có cờ `observed: Bool`; nút `observed == false` mang chú thích `[SUY ĐOÁN]` trong mã và bảng bằng chứng. H6 liệt kê chúng cho người dùng quyết định có chụp bổ sung không.

## R-12 Giao agy

- **Quyết định:** brief theo từng gói tệp (xem plan, bảng pha) viết ở `docs/tasks/h<N>-<tên>.md`, kèm bảng sở hữu `docs/phase-h-ownership.tsv`; mọi worker phải tự chạy `swift build`, `swift test --no-parallel`, xuất ảnh `build/h-out/`. Lead rà theo `agy-delegation`.
