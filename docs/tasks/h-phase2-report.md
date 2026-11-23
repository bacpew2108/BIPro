# Báo cáo Phase 2 (H0 — Nền tảng hợp đồng Ribbon, Token & Tuỳ chọn)

- **Ngày thực hiện:** 2026-11-21
- **Tác vụ đã hoàn thành:** T004, T005, T006, T007, T008, T009, T010, T011, T012, T013, T014 (đã tích `[x]` trong `specs/016-h-giao-dien-giong-powerbi/tasks.md`)

## Tệp đã tạo / sửa

- Tạo mới `Sources/BIPro/Shell/Ribbon/RibbonModel.swift` (T004): `Bilingual`, `RibbonTabID`, `RibbonTabSpec`, `RibbonGroupSpec`, `RibbonItemSpec`, `RibbonItemKind`, `FieldControl`, `GalleryKind`, `RibbonTint`, `Availability` (đúng 3 case `always`, `when(_:disabledReason:)`, `unsupported(_:)` + helper `pending(_:)` và kiểm ràng buộc `validationIssues`).
- Tạo mới `Sources/BIPro/Shell/Ribbon/RibbonCommandID.swift` (T005): đủ mọi ID lệnh trong `contracts/ribbon-catalog.md`.
- Tạo mới `Sources/BIPro/Shell/Ribbon/RibbonContext.swift` (T006): struct bất biến + `init(state: DocumentState)`.
- Tạo mới `Sources/BIPro/Shell/Ribbon/RibbonActions.swift` (T007): ánh xạ `RibbonCommandID` sang các hàm `DocumentState`/`LayoutEditor` hiện có và `.noop` cho `X`/`P` (không đổi thân hàm hiện có).
- Tạo mới `Sources/BIPro/Shell/Ribbon/RibbonCatalog.swift` (T008): `tabs(mode:visualSelected:)`, `resolvedTab`, `spec(for:mode:)`, `allRegisteredSpecs()`.
- Sửa `Sources/BIPro/DesignSystem/Tokens.swift` (T009): thêm `UIMetrics` (12 token đúng `contracts/ui-tokens.md`) và `DS.Palette.{accentTeal, accentTealPressed, canvasWell, tabUnderline}`; giữ nguyên `DS.Palette.accent`, `DS.Palette.series`, `DS.Metrics`.
- Sửa `Sources/BIPro/Settings/AppPreferences.swift` (T010): thêm 3 khoá `bipro.ribbon.collapsed`, `bipro.edit.viewOnlyDefault`, `bipro.tmdl.introSeen` (mặc định `false`).
- Tạo mới bộ test `Tests/BIProTests/UIParity/{UIMetricsTests,TokensColorTests,RibbonAvailabilityTests,RibbonBilingualTests}.swift` (T011–T013).
- Cập nhật `docs/tasks/h0-test-impact.md` và `specs/016-h-giao-dien-giong-powerbi/tasks.md`.

## Kết quả build & test

- TDD T011: đỏ trước T009 (`cannot find 'UIMetrics'`, `no member 'accentTeal'`), xanh sau T009.
- `swift build`: `Build complete! (0.49s)` (0 lỗi, 0 cảnh báo mới).
- `swift test --no-parallel --filter UIParity`: `✔ Test run with 12 tests passed after 0.052 seconds.`
- `swift test --no-parallel`: `✔ Test run with 2493 tests passed after 190.342 seconds.` (2 493/2 493 xanh, 0 trượt).
- `git status`: toàn bộ tệp thuộc `docs/phase-h-ownership.tsv`.

## Ảnh đã xuất

- Phase 2 là hợp đồng nền chưa đổi giao diện nên chưa xuất ảnh.

## Tồn đọng / Điểm chú ý

- Trong `data-model.md`, dòng giả mã `let clipboardHasVisual, pageCount: Int` đã được cài đặt chuẩn kiểu là `clipboardHasVisual: Bool` và `pageCount: Int`.
- Nút loại `P` (chưa làm) dùng `Availability.pending(...)` (bọc `.when({ _ in false }, disabledReason: ...)`) để giữ đúng 3 case enum của hợp đồng H0 đồng thời phân biệt được với `Availability.unsupported` (`X`).
- Chuyển sang Phase 3 (US1 — T015–T023).
