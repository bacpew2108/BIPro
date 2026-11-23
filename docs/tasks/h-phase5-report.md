# Báo cáo Phase 5 (H3 / US3 — Tab ngữ cảnh, Table/Model/DAX/TMDL Ribbon & Xoá Ribbon.swift cũ)

- **Ngày thực hiện:** 2026-11-21
- **Tác vụ đã hoàn thành:** T036, T037, T038, T039, T040, T041, T042, T043, T044 (đã tích `[x]` trong `specs/016-h-giao-dien-giong-powerbi/tasks.md`) — **MVP US1–US3 (toàn bộ 15 Ribbon) hoàn tất!**

## Tệp đã tạo / sửa

- Sửa `Tests/BIProTests/UIParity/RibbonReference.swift` (T036), `RibbonCatalogTests.swift`, `Tests/BIProTests/Model/ColumnToolsRibbonTests.swift` (T037) — viết test đỏ trước khi cài đặt.
- Tạo mới `Sources/BIPro/Shell/Ribbon/Catalog+Contextual.swift` (T038): Format (`Interactions`, `Arrange` với Bring forward/Send backward vô hiệu do `LayoutEditor` chưa có thứ tự z, Selection, Align ▾, Group ▾ chứa Group/Ungroup/Merge) và Data / Drill (`Show`, `Interactions`, `Drill actions` 2×2 + Drill through, `Data groups` `observed: false` `[SUY ĐOÁN]`, `AI`).
- Tạo mới `Sources/BIPro/Shell/Ribbon/Catalog+Table.swift` (T039): Table Home, Table tools (`Name` + CascadeRename, Relationships, Calculations, Calendars), Column tools (`Name`, `Data type`, `Format` + hàng `$ % , .00 [Auto]`, `Summarization`, `Data category`, `Sort by column`, `Data groups`, `Relationships`, `Calculations`), di chuyển `dataTypeName` và `summarizeName` từ `Ribbon.swift`.
- Tạo mới `Sources/BIPro/Shell/Ribbon/Catalog+Code.swift` (T040): Model Home (không có Quick measure, có Calculation group/Parameters/Q&A), DAX Home (Clipboard + Editing gồm Format/Comment/Uncomment/Find/Replace/Command palette + Copilot), TMDL Home (Clipboard gồm Copy nối hành động sao chép TMDL hiện có + Editing).
- Tạo mới `Sources/BIPro/Query/CodeActionBar.swift` (T041) và gắn vào `Sources/BIPro/Query/QueryWorkspaces.swift` (T042): `DAXCodeActionBar` (`Run` teal + `Update model with changes (n)`) và `TMDLCodeActionBar` (`Apply` teal + `Preview` vô hiệu).
- Sửa `Sources/BIPro/Shell/Ribbon/{RibbonCatalog,RibbonActions,RibbonItemViews,RibbonView}.swift` (T043): gộp toàn bộ 15 Ribbon vào `RibbonCatalog`, bỏ hoàn toàn `LegacyRibbonBridge`, nối `comment`/`uncomment` DAX, xếp dọc nhóm field cho `Column tools`.
- Dọn sạch toàn bộ mã trong `Sources/BIPro/Shell/Ribbon.swift` (T043) — không còn ký hiệu hay mã chết (tệp trống chỉ còn 2 dòng ghi chú chờ lead xoá khỏi git vì lệnh `rm` không có trong `docs/tasks/h-master-allow.json`).
- Mở rộng `Tests/BIProTests/UIParity/ParityRenderTests.swift` (T044): xuất 8 ảnh US3 vào `build/h-out/us3/` và test thực thi các lệnh Edit interactions, Align/Group, Column quick format + Undo, DAX Format/Comment/Uncomment, TMDL Copy.

## Kết quả build & test

- TDD T037: đỏ trước khi cài đặt (`report.format` trả `nil`), xanh sau khi cài đặt.
- `swift build`: `Build complete! (0.47s)` (0 lỗi, 0 cảnh báo mới).
- `swift test --no-parallel --filter UIParity`: `✔ Test run with 29 tests passed after 1.121 seconds.`
- `swift test --no-parallel`: `✔ Test run with 2510 tests passed after 190.387 seconds.` (2 510/2 510 xanh, 0 trượt).
- Golden nặng (`BIPRO_HEAVY=1 ... --scratch-path .build-1a-rel`): `✔ Test run with 119 tests passed after 172.813 seconds.` (119/119 xanh, 0 hồi quy).
- `git status`: chỉ gồm các tệp thuộc `docs/phase-h-ownership.tsv`.

## Ảnh đã xuất và tự kiểm tra

- `build/h-out/us3/format-light-en.png` (đối chiếu `rb_vformat-2x.png`)
- `build/h-out/us3/data-drill-light-en.png` (đối chiếu `rb_vdata-2x.png`)
- `build/h-out/us3/table-home-light-en.png` (đối chiếu `rb_tv_home-2x.png`)
- `build/h-out/us3/table-tools-light-en.png` (đối chiếu `rb_tv_table-2x.png`)
- `build/h-out/us3/column-tools-light-en.png` (đối chiếu `rb_tv_column-2x.png`)
- `build/h-out/us3/model-home-light-en.png` (đối chiếu `v_model_1.png`)
- `build/h-out/us3/dax-home-light-en.png` (đối chiếu `v_dax_1.png`)
- `build/h-out/us3/tmdl-home-light-en.png` (đối chiếu `v_tmdl_2.png`)
- Tất cả 8 ảnh không trống, không có biểu tượng cấm, không cắt chữ, kích thước byte khác nhau hoàn toàn.

## Tồn đọng / Điểm lưu ý

- `Sources/BIPro/Shell/Ribbon.swift` đã được làm trống hoàn toàn (0 ký hiệu) thay vì chạy `rm` do `rm` không nằm trong `docs/tasks/h-master-allow.json`; lead xoá tệp khi commit.
- `Bring forward` / `Send backward` đặt vô hiệu có tooltip do `LayoutEditor` hiện chưa có thao tác đổi thứ tự z.
- Chuyển sang Phase 6 (US4 — T045–T053).
