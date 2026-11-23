# Báo cáo Phase 1 (H0 — Chuẩn bị)

- **Ngày thực hiện:** 2026-11-21
- **Tác vụ đã hoàn thành:** T001, T002, T003 (đã tích `[x]` trong `specs/016-h-giao-dien-giong-powerbi/tasks.md`)

## Tệp đã tạo / sửa

- Tạo mới: `docs/tasks/h0-test-impact.md` — kết quả rà `grep -rnE "RibbonTab|state\.tabs|ribbonTab|RibbonButton|RibbonGroup"` trong `Sources/BIPro` và `Tests/BIProTests` kèm phân pha sửa.
- Tạo mới: `Tests/BIProTests/UIParity/RibbonReference.swift` — dữ liệu chuẩn viết tay từ `contracts/ribbon-catalog.md` (bảng tab theo 6 tình huống view + Report Home 8 nhóm / 21 mục top-level).
- Rà soát (không cần sửa): `docs/phase-h-ownership.tsv` — xác nhận vị trí thực tế của `PageTabs` (`Report/ReportWorkspace.swift`), `StatusBar` (`Shell/ShellView.swift`), khung DAX/TMDL (`Query/QueryWorkspaces.swift`) và toàn bộ các tệp `Panes/*`, `Shell/*`, `Report/*`, `Query/*` đều khớp 100%.
- Cập nhật dấu tích: `specs/016-h-giao-dien-giong-powerbi/tasks.md` (T001–T003).

## Kết quả build & test

- `swift build`: `Build complete! (0.64s)` (không có cảnh báo mới).
- `swift test --no-parallel`: `✔ Test run with 2481 tests passed after 192.267 seconds.` (2 481/2 481 xanh, 0 trượt).
- `git status`: chỉ gồm `specs/016-h-giao-dien-giong-powerbi/tasks.md`, `Tests/BIProTests/UIParity/`, `docs/tasks/h0-test-impact.md` (đúng `docs/phase-h-ownership.tsv`).

## Ảnh đã xuất

- Phase 1 không đổi giao diện nên chưa xuất ảnh.

## Tồn đọng / Điểm suy đoán

- Không có tồn đọng. Chuyển sang Phase 2 (T004–T014).
