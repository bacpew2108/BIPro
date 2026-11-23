# Báo cáo Phase 4 (H2 / US2 — Nội dung Ribbon Report: Insert, Modeling, Design, View, Optimize, Help)

- **Ngày thực hiện:** 2026-11-21
- **Tác vụ đã hoàn thành:** T024, T025, T026, T027, T028, T029, T030, T031, T032, T033, T034, T035 (đã tích `[x]` trong `specs/016-h-giao-dien-giong-powerbi/tasks.md`)

## Tệp đã tạo / sửa

- Sửa `Tests/BIProTests/UIParity/RibbonReference.swift` (T024): bổ sung bảng chuẩn viết tay cho Insert, Modeling, Design, View, Optimize, Help.
- Sửa `Tests/BIProTests/UIParity/RibbonCatalogTests.swift` (T025) và tạo `Tests/BIProTests/UIParity/RibbonMenusTests.swift` (T026) — viết đỏ trước khi cài đặt.
- Tạo mới `Sources/BIPro/Shell/Ribbon/RibbonMenus.swift` (T027): cấu trúc và bộ vẽ menu Buttons ▾ (10 mục + menu con Navigator `observed: false` `[SUY ĐOÁN]`), Shapes ▾ (3 nhóm lưới 4 cột), New page ▾ (New page + Duplicate page), Page view ▾ (Fit to page / Fit to width / Actual size), Refresh ▾ (Schema and data / Schema / Data), Themes ▾ (banner + This report + Power BI 9 ô + Theme gallery).
- Tạo mới `Sources/BIPro/Shell/Ribbon/Catalog+Insert.swift` (T028): 6 nhóm Insert.
- Tạo mới `Sources/BIPro/Shell/Ribbon/Catalog+Modeling.swift` (T029): 7 nhóm Modeling (`markAsDateTable` ở nhóm Calendars).
- Tạo mới `Sources/BIPro/Shell/Ribbon/Catalog+Design.swift` (T030): 3 nhóm Design (Themes, Customize page, Help).
- Tạo mới `Sources/BIPro/Shell/Ribbon/Catalog+ViewOptimizeHelp.swift` (T031, T034): View (không còn Data/Visualizations/Themes, 3 hộp kiểm xếp dọc), Optimize (5 nút), Help (About `1.3.0` popover `RibbonAboutPopover`, Guided learning → `requestShowOnboarding`).
- Sửa `Sources/BIPro/Panes/ThemePickerPopover.swift` (T032): thêm `ThemeSwatchCard`, `ThemesRibbonGallery` (6 ô mẫu + mũi tên mở rộng trên tab Design) và cập nhật `ThemePickerPopover` thành dạng menu `Themes ▾` khớp `dd_themes.png`, giữ nguyên nhập/xuất `.json` và hoàn tác `⌘Z`.
- Sửa `Sources/BIPro/Shell/Ribbon/RibbonCatalog.swift`, `RibbonItemViews.swift`, `RibbonView.swift`, `Sources/BIPro/Shell/Ribbon.swift` (T033, T034): nối 6 catalog mới, thêm mục "Chế độ chỉ xem" vào menu `Page view ▾` (lưu `AppPreferences.viewOnlyDefault`), xếp dọc nhóm chỉ gồm checkbox (`Page options`), xoá `InsertCommands`, `HelpCommands`, `ReportViewCommands` khỏi `Ribbon.swift` (giữ `ModelingCommands` tạm cho `ModelHomeCommands` đến T043).
- Sửa `Tests/BIProTests/UIParity/ParityRenderTests.swift` (T035): thêm xuất ảnh 6 tab Report vào `build/h-out/us2/`.

## Kết quả build & test

- TDD T025–T026: đỏ trước khi cài đặt (`cannot find 'RibbonMenus'`), xanh sau khi cài đặt.
- `swift build`: `Build complete! (0.47s)` (0 lỗi, 0 cảnh báo mới).
- `swift test --no-parallel --filter UIParity`: `✔ Test run with 26 tests passed after 0.887 seconds.` (gồm kiểm thử thực thi Get data, Enter data, New visual, Text box, Buttons ▸ Blank, Shapes ▸ Rectangle, New page, Duplicate page, Manage roles, View as).
- `swift test --no-parallel`: `✔ Test run with 2507 tests passed after 196.029 seconds.` (2 507/2 507 xanh, 0 trượt).
- `git status`: chỉ gồm các tệp thuộc `docs/phase-h-ownership.tsv`.

## Ảnh đã xuất và tự kiểm tra

- `build/h-out/us2/insert-light-en.png` — đối chiếu `rb_insert-2x.png`: khớp 6 nhóm, đầy đủ nút và ▾.
- `build/h-out/us2/modeling-light-en.png` — đối chiếu `rb_modeling-2x.png`: khớp 7 nhóm, Mark as date table ở Calendars.
- `build/h-out/us2/design-light-en.png` — đối chiếu `rb_design-2x.png`: khớp dải 6 ô mẫu theme + mũi tên mở rộng, Theme gallery, 3 nút nhỏ Customize/Download/Import, Customize page, Help.
- `build/h-out/us2/view-light-en.png` — đối chiếu `rb_view-2x.png`: khớp Page view ▾, Mobile layout, 3 checkbox xếp dọc (Snap to grid tích teal), Show panes 5 nút (Filters nổi bật teal), không có Data/Visualizations.
- `build/h-out/us2/optimize-light-en.png` — đối chiếu `rb_optimize-2x.png`: khớp 4 nhóm 5 nút.
- `build/h-out/us2/help-light-en.png` — đối chiếu `rb_help-2x.png`: khớp 4 nhóm (Info, Help, Community, Resources).
- Toàn bộ 6 ảnh không trống, không có biểu tượng cấm, không cắt chữ, kích thước byte khác nhau hoàn toàn.

## Tồn đọng / Điểm suy đoán (`[SUY ĐOÁN]`)

- Menu con `Navigator` của `Buttons ▾` (`observed: false`): đặt 2 mục `Page navigator` và `Bookmark navigator` hiện có của BI Pro.
- Tên cụ thể 9 ô mẫu Power BI trong `Themes ▾` (`observed: false`): ánh xạ vào 6 preset hiện có của `ThemeCatalog` kèm biến thể màu tương ứng ảnh `dd_themes.png`.
- `Customize theme`, `Optimization presets`, `Language`, `Linguistic schema`, `Mobile layout` (`observed: false`): đặt vô hiệu có tooltip song ngữ.
- Chuyển sang Phase 5 (US3 — T036–T044).
