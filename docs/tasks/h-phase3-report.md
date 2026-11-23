# Báo cáo Phase 3 (H1 / US1 — Khung Ribbon và bộ tab)

- **Ngày thực hiện:** 2026-11-21
- **Tác vụ đã hoàn thành:** T015, T016, T017, T018, T019, T020, T021, T022, T023 (đã tích `[x]` trong `specs/016-h-giao-dien-giong-powerbi/tasks.md`)

## Tệp đã tạo / sửa

- Tạo mới `Tests/BIProTests/UIParity/RibbonTabsTests.swift` (T015) và mở rộng `Tests/BIProTests/UIParity/RibbonCatalogTests.swift` (T016) — viết đỏ trước khi cài đặt.
- Tạo mới `Sources/BIPro/Shell/Ribbon/RibbonItemViews.swift` (T017): bộ vẽ nút lớn (`UIMetrics.ribbonIcon` = 28 pt, nhãn 2 dòng cân bằng không cắt giữa từ), nút nhỏ xếp dọc tối đa 3 hàng, mũi tên `▾`, hộp kiểm, nút bật/tắt (`isOn`), chỗ giữ field/gallery, `MoreVisualsPopoverView`, `RibbonMenuButton` (dùng `Menu` native trong app và vẽ thẳng `label` khi chụp `ImageRenderer`), SF Symbols hai màu `.symbolRenderingMode(.palette)`, mờ đồng nhất 45% + `.help`, nhãn VoiceOver.
- Tạo mới `Sources/BIPro/Shell/Ribbon/Catalog+Home.swift` (T018): Report Home đủ 8 nhóm (Clipboard, Data, Queries, Insert, Calculations, Sensitivity, Share, Copilot), 21 dòng top-level khớp `contracts/ribbon-catalog.md`.
- Tạo mới `Sources/BIPro/Shell/Ribbon/RibbonView.swift` (T019): hàng tab chữ thường 13 pt, gạch chân `UIMetrics.tabUnderline` màu `accentTeal`, tab ngữ cảnh chữ `accentTeal` không vạch phân cách, nút `Share ▾` vô hiệu neo phải có tooltip, panel nổi bo `ribbonCorner` cao `ribbonPanel`, cuộn ngang khi hẹp (`scrollable: Bool = true`), nút `^` thu gọn lưu `AppPreferences.ribbonCollapsed`, cầu `LegacyRibbonBridge` cho tab chưa chuyển sang catalog.
- Sửa `Sources/BIPro/Shell/Ribbon/RibbonCatalog.swift`: đăng ký `reportHome`.
- Sửa `Sources/BIPro/DocumentState.swift` (T020): `RibbonTab` thêm `file`, `design`, `optimize`; nối `tabs` sang `RibbonCatalog.tabs`; thêm `showBackstage` & `selectRibbonTab(_:)`; tự về `.home` khi đổi view hoặc mất lựa chọn visual.
- Sửa `Sources/BIPro/Shell/Ribbon.swift` (T021): bỏ `RibbonView` cũ và các nhóm Home/ModelView/GenericView đã thay, giữ `LegacyRibbonBridge` tạm cho tab chưa có catalog. `ShellView.swift` (T022) gọi trực tiếp `RibbonView(state: state)` mới.
- Tạo mới `Tests/BIProTests/UIParity/ParityRenderTests.swift` (T023): kiểm bề rộng > 1000 pt ở cửa sổ hẹp và xuất 4 ảnh PNG (`BIPRO_H_RENDER=1`).

## Kết quả build & test

- TDD T015–T016: đỏ trước khi cài đặt (`RibbonTab` thiếu `file`/`design`/`optimize`, `showBackstage`, `spec(.home, .report) == nil`), xanh sau khi cài đặt.
- `swift build`: `Build complete! (0.49s)` (0 lỗi, 0 cảnh báo mới).
- `swift test --no-parallel --filter UIParity`: `✔ Test run with 19 tests passed after 0.520 seconds.`
- `swift test --no-parallel`: `✔ Test run with 2500 tests passed after 189.101 seconds.` (2 500/2 500 xanh, 0 trượt; `ColumnToolsRibbonTests` vẫn xanh nguyên vẹn).
- `git status`: toàn bộ tệp thuộc `docs/phase-h-ownership.tsv`.

## Ảnh đã xuất và tự kiểm tra

- `build/h-out/us1/home-light-en.png`
- `build/h-out/us1/home-dark-en.png`
- `build/h-out/us1/home-light-vi.png`
- `build/h-out/us1/home-selected-en.png`
- Quá trình tự mở ảnh phát hiện và đã sửa ngay 3 lỗi thực tế trước khi chốt phase: (1) hàng tab bị giãn đều ngang do `Rectangle` gạch chân thiếu `overlay`, (2) nhãn nút bị cắt `...` / gãy giữa từ do `maxWidth: 74`, (3) `Menu` bị `ImageRenderer` vẽ thành biểu tượng cấm vàng/đỏ (đã bọc bằng `RibbonMenuButton` + `EnvironmentValues.isSnapshotRender`). Ảnh cuối cùng sạch hoàn toàn, khớp bố cục `docs/phase-ui-evidence/vm-ui/rb_home-2x.png`.

## Tồn đọng / Điểm chú ý

- Không có tồn đọng. Chuyển sang Phase 4 (US2 — T024–T035).
