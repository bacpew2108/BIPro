# Danh sách tác vụ triển khai: Đợt 4 (v1.2) — Mở khoá toàn bộ Ribbon, RLS, Mark as Date Table, Quick Measures & Công cụ DAX/TMDL

**Thư mục spec:** `specs/015-v12-hoan-thien-chuyen-nghiep/`
**Ngày lập:** 2026-11-21
**Trạng thái:** ✅ Hoàn tất 100% (16/16 tác vụ đạt cổng kiểm chứng & Power BI Desktop 2.159)
**Tham chiếu:** [spec.md](file:///Users/macprom114/Desktop/PowerBINative/specs/015-v12-hoan-thien-chuyen-nghiep/spec.md), [plan.md](file:///Users/macprom114/Desktop/PowerBINative/specs/015-v12-hoan-thien-chuyen-nghiep/plan.md), [data-model.md](file:///Users/macprom114/Desktop/PowerBINative/specs/015-v12-hoan-thien-chuyen-nghiep/data-model.md), [measurements.md](file:///Users/macprom114/Desktop/PowerBINative/specs/015-v12-hoan-thien-chuyen-nghiep/measurements.md)

---

## Nhánh 1 — Nền tảng `PBIXKit` & `DAXEngine` (RLS, Mark as Date Table & DAX Formatter)

- [x] **T001** `Sources/PBIXKit/ModelMetadata.swift`, `Writing/ModelEdit.swift`, `ModelMetadata+Edit.swift`, `Writing/MetadataWriter.swift` — Mở rộng `TablePatch.dataCategory`, `ColumnPatch.isKey`, `ModelMetadata.RoleDefinition` + `TablePermission` (đọc đầy đủ `[Role]` & `[TablePermission]`), `ModelEdit.upsertRole` / `.deleteRole`, và ghi SQLite khớp 100% Desktop 2.159 (`ModelPermission = 2`, `State = 1`, `MetadataPermission = 0`, `DataCategory = 'Time'`, `IsKey = 1`, `IsUnique = 1`).
- [x] **T002** `Sources/DAXEngine/Syntax/Formatter.swift` *(mới)* — Viết bộ định dạng DAX thuần Swift (`DAXEngine.format(_:)`) dựa trên scanner/lexer, bảo toàn 100% chuỗi literal `"..."`, nháy đơn `'...'`, ngoặc `[...]` và chú thích `--`/`//`/`/* */`, căn lề khối `DEFINE`/`MEASURE`/`VAR`/`RETURN`/`EVALUATE`/`ORDER BY` và hàm lồng.
- [x] **T003** `Tests/PBIXKitTests/V12ModelMetadataRLSTests.swift` *(mới)* & `Tests/DAXEngineTests/V12DAXFormatterTests.swift` *(mới)* — Kiểm thử round-trip SQLite cho Mark as Date Table & RLS (`[Role]`/`[TablePermission]`) và kiểm thử DAX Formatter (kèm kiểm tra parse lại AST không lỗi).

---

## Nhánh 2 — 4A: Cut/Copy/Paste Visual, Format Painter & Tab Data / Drill (`Show as a table`)

- [x] **T004** `Sources/BIPro/Report/Edit/LayoutEditor.swift`, `EditCommands.swift`, `Shell/Ribbon.swift` — Triển khai `VisualClipboardItem` (`copyVisuals`, `cutVisuals`, `pasteVisuals` hỗ trợ dán trên cùng trang lệch `+16,+16` và dán **sang trang khác** với mã 20 hex mới + Undo `⌘Z`), nối 3 nút *Cắt / Sao chép / Dán* trên `ReportHomeCommands` và phím tắt `⌘X`/`⌘C`/`⌘V`.
- [x] **T005** `Sources/BIPro/Report/Edit/LayoutEditor.swift`, `EditCanvasOverlay.swift`, `Shell/Ribbon.swift` — Triển khai **Format Painter (Sao định dạng)**: chép `visualContainerObjects` + nhóm `objects` tương thích từ visual nguồn sang visual đích khi bấm trên canvas, hiện banner gợi ý (`Esc` huỷ), Undo 1 bước `⌘Z`.
- [x] **T006** `Sources/BIPro/Panes/VisualDataTableSheet.swift` *(mới)*, `Shell/Ribbon.swift`, `Shell/ShellView.swift`, `DocumentState.swift`, `Report/ReportInteraction.swift` — Mở khoá toàn bộ tab **Data / Drill** (*Drill up*, *Drill down*, *Expand next level*, *Show as a table* kèm nút Xuất CSV nhanh).

---

## Nhánh 3 — 4B: Quick Measures, Mark as Date Table, RLS (Manage Roles & View As) & DataPane

- [x] **T007** `Sources/BIPro/Model/QuickMeasureCatalog.swift` *(mới)*, `Panes/QuickMeasureSheet.swift` *(mới)*, `Shell/Ribbon.swift`, `Shell/ShellView.swift` — Mở khoá nút **Measure nhanh (Quick measure)** với 8 mẫu chuẩn Power BI, xem trước DAX, kiểm bằng `DAXEngine` và thêm qua `ModelEditor` (Undo `⌘Z`).
- [x] **T008** `Sources/BIPro/Panes/MarkAsDateTableSheet.swift` *(mới)*, `DocumentState+Model.swift`, `Shell/Ribbon.swift`, `Shell/ShellView.swift` — Mở khoá nút **Đánh dấu bảng ngày (Mark as date table)** trên *Công cụ bảng*: kiểm tra cột `.dateTime` duy nhất & không trống qua `ColumnStore`, bật/tắt `DataCategory = "Time"` + `IsKey = true` trong 1 bước `⌘Z`.
- [x] **T009** `Sources/BIPro/Panes/ManageRolesSheet.swift` *(mới)*, `Panes/ViewAsRoleSheet.swift` *(mới)*, `Report/ReportInteraction.swift`, `Report/ReportWorkspace.swift`, `DocumentState+Model.swift`, `Shell/Ribbon.swift`, `Shell/ShellView.swift` — Mở khoá **Quản lý vai trò (Manage roles)** (CRUD vai trò + kiểm lọc DAX từng bảng, lưu T2) và **Xem dưới vai trò (View as)** (dải vàng cảnh báo trên canvas + tự tiêm `QueryFilter` RLS vào toàn bộ truy vấn DAX của `ReportInteraction`).
- [x] **T010** `Sources/BIPro/Panes/LeftContextMenu.swift`, `Panes/DataPane.swift`, `DocumentState+Model.swift` — Mở khoá **Ẩn/Hiện trong chế độ báo cáo** cho Bảng & Cột và **Hiện tất cả (Unhide all)** trong menu chuột phải `DataPane`.

---

## Nhánh 4 — 4C: DAX Formatter, DAX Update Model, TMDL Ribbon, SQL Quick Connect & v1.2.0

- [x] **T011** `Sources/BIPro/Query/DAXModelSync.swift` *(mới)*, `Panes/DAXUpdateModelSheet.swift` *(mới)*, `Shell/Ribbon.swift`, `Shell/ShellView.swift`, `DocumentState.swift` — Nối nút **Định dạng** (`DAXEngine.format`) và nút **Cập nhật mô hình (Update model)** (quét `DEFINE MEASURE ...`, xem trước diff, kiểm engine và ghi 1 bước `⌘Z`) trên Ribbon DAX Query View.
- [x] **T012** `Sources/BIPro/Query/QueryWorkspaces.swift`, `Shell/Ribbon.swift`, `DocumentState.swift`, `scripts/build-app.sh` — Nối nút **Áp dụng thay đổi** trên Ribbon TMDL View vào `TMDLWorkspace`; mở khoá nút **SQL** trên Ribbon Home thành menu nhanh **PostgreSQL / SQLite**; nâng phiên bản hiển thị & `Info.plist` lên **1.2.0**.
- [x] **T013** `Tests/BIProTests/V12FeaturesTests.swift` *(mới)* — Kiểm thử tích hợp đầy đủ 4A–4C (Cut/Copy/Paste sang trang khác + Undo, Format Painter + Undo, Quick Measures 8 mẫu, Mark as Date Table + kiểm cột lỗi/hợp lệ, RLS Manage Roles + View As lọc đúng số liệu DAX, DAX Update Model, Unhide All).

---

## Nhánh 5 — Nghiệm thu, Cổng Power BI Desktop 2.159 & Đóng gói Release 1.2.0

- [x] **T014** `Tests/BIProTests/Edit/V12GatePBIXTests.swift` *(mới)* — Tạo tệp kiểm chứng `build/v12-out/bipro-v12-gate.pbix` tích hợp đầy đủ Đợt 4 (visual đã Paste sang trang mới & Format Painter, Quick Measure mới, Mark as Date Table, và vai trò RLS `[Role]` + `[TablePermission]`) → mở kiểm chứng trên **Power BI Desktop 2.159 (VM Windows 11)** (0 cảnh báo hỏng/lỗi trường), chụp ảnh cắt sạch vùng canvas (0 email) vào `docs/phase-v12-evidence/vm-v12/gate-desktop.png`, đóng Desktop & dọn sạch VM (`SC-001`).
- [x] **T015** Chạy toàn bộ bộ kiểm thử không hồi quy & đóng gói phát hành **v1.2.0**:
  - `swift test --no-parallel` (2 471/2 471 xanh, 0 lỗi)
  - `BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --no-parallel` (119/119 xanh, 0 lỗi)
  - `zsh scripts/build-app.sh release` + `codesign --verify --deep --strict "build/BI Pro.app"` (v1.2.0 / 120 đạt).
- [x] **T016** Cập nhật `specs/015-v12-hoan-thien-chuyen-nghiep/tasks.md` (`[x]`), `specs/015-v12-hoan-thien-chuyen-nghiep/measurements.md`, `docs/STATE.md` và `docs/BIPRO_BUILD_PLAN.md`; báo cáo kết quả và chờ người dùng xác nhận commit.
