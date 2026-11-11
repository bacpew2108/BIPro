# Nhiệm vụ D7

Định dạng: `- [ ] Txxx [P?] [USn] Mô tả (tệp)`. `[P]` = làm song song được (khác tệp). Kiểm: `swift build`, `swift test`, golden nặng (xem `quickstart.md`).

## Giai đoạn 1: Chuẩn bị

- [X] T001 Thêm dòng D7 vào `docs/phase-d-ownership.tsv` (nhóm, căn lề, dán, định dạng cũ) và đánh dấu D7 "đang làm" ở `docs/BIPRO_BUILD_PLAN.md`
- [X] T002 [P] Chép mẫu Nhóm 2 và Nhóm 3 ra `build/d7-fixtures/` (chỉ đọc từ `~/Downloads`); thêm `DAXFixtures.legacy2`/`legacy3` hoặc biến `BIPRO_LEGACY2`, `BIPRO_LEGACY3`; test bỏ qua khi thiếu file (`Tests/BIProTests/Edit/D7Fixtures.swift`)

## Giai đoạn 2: Nền (chặn mọi câu chuyện)

- [X] T003 `PBIXKit/ReportDefinition.swift`: `ReportVisual.parentGroup`, PBIR cộng `x,y` nhóm vào toạ độ con, container nhóm vào danh sách trang với `type "visualGroup"` (không có `visual`); test đọc trên mẫu nhóm dựng tay (`Tests/PBIXKitTests/ReportGroupReadTests.swift`)
- [X] T004 `PBIXKit/Writing/PBIRLayoutPatch.swift`: `setPosition` nhận `Double` (số nguyên ghi không dấu chấm, số thập phân ghi nguyên văn ngắn nhất); giữ ràng buộc không âm và ≥ 1; cập nhật test `PBIRLayoutPatchTests`
- [X] T005 `BIPro/Report/Edit/LayoutEditor.swift`: danh sách visual cho phép `visualGroup` (không vẽ, không chọn bằng khung marquee con), `isLockedByGroup` chỉ còn khoá nhóm lồng; `PageEdit` ghi nhận nhóm mới; `makeChanges` so toạ độ con với `abs − nhóm` bằng dung sai 1e-6

## Giai đoạn 3: US1, căn lề và phân bố (P1)

- [X] T006 [P] [US1] `BIPro/Report/Edit/LayoutGeometry.swift`: `align` và `distribute` thuần theo R1 (Left/Right/Top/Bottom, Center/Middle trung bình tâm, Distribute, kẹp trong trang, kích thước không đổi) + `Tests/BIProTests/Edit/AlignGeometryTests.swift` dùng số đo VM-D7 (c1ed/e324, thẻ 24/338/1594 → 809)
- [X] T007 [US1] `LayoutEditor+Align.swift`: `align(_:)`, `distribute(_:)` qua `commit` (một bước, không đổi thì không tạo bước, vùng chọn dưới 2 hoặc 3 trả lý do, chỉ cùng cấp)
- [X] T008 [US1] `EditCommands.swift`, `ReportWorkspace.swift`, ribbon/menu chuột phải: menu Căn lề và Phân bố, mờ kèm lý do (`DocumentState` thêm `alignBlocker`)
- [X] T009 [P] [US1] Test `LayoutEditor` căn, hoàn tác, lưu (`Tests/BIProTests/Edit/AlignEditorTests.swift`): ghép byte chỉ part đổi, ⌘Z đúng, lưu lần hai không ghi

## Giai đoạn 4: US2, dán giữa trang (P1)

- [X] T010 [US2] `LayoutEditor.swift`: `paste` đặt +10n và `z` = max+1 (`LayoutGeometry.pasteOffset = 10`), `duplicate` giữ D1; phần không sao được (nút trỏ trang/bookmark không còn) bỏ kèm `notice`
- [X] T011 [P] [US2] Test dán sang trang khác, dán nhiều lần, dán sau khi đổi trang, hoàn tác, xoá trang đích; kiểm `query/objects/filterConfig` khớp nguồn từng byte (`Tests/BIProTests/Edit/PasteTests.swift`, cập nhật test D1 cũ về bước lệch)

## Giai đoạn 5: US3, nhóm visual (P2)

- [X] T012 [P] [US3] `PBIXKit/Writing/PBIRGroupPatch.swift` theo `contracts/group-editing.md` (`groupJSON`, `settingParent`, `clearingParent`) + test từng byte với `json/` của VM-D7 (`Tests/PBIXKitTests/PBIRGroupPatchTests.swift`)
- [X] T013 [US3] `LayoutEditor+Group.swift`: `group(ids:)`, `ungroup(id:)`, từ chối nhóm lồng và khác trang; mã 20 hex, tên "Group N", `z` = max+1
- [X] T014 [US3] Di chuyển, đổi cỡ (co tỷ lệ hai chiều), xoá, nhân bản, chép/dán nhóm; xoá con cuối thì xoá nhóm; con kẹp trong khung nhóm (R4); nhóm gỡ khỏi `visualContainers` của bookmark (`removedIDs` gồm nhóm và con)
- [X] T015 [US3] `makeChanges`: part nhóm thêm/xoá, ghi con tương đối + `parentGroupName` (R4), `PBIXWriter.insertionIndex` cho part nhóm; `DocumentSaver.verifyGroups` (R6)
- [X] T016 [US3] Canvas: chọn nhóm trước rồi con (`EditCanvasOverlay`, `ReportCanvas`), khung chọn nhóm, phím ⌘G/⇧⌘G và menu, mờ kèm lý do; Selection pane hiện cây nhóm (`ReportPanes.swift`)
- [X] T017 [P] [US3] Test nhóm: nhóm rồi bỏ nhóm giữ vị trí 0 điểm lệch, di chuyển, đổi cỡ, xoá, nhân bản, hoàn tác từng bước, lưu hai lần (`Tests/BIProTests/Edit/GroupEditorTests.swift`)
- [X] T018 [US3] D5 nhân bản trang có nhóm vẫn đúng với toạ độ tuyệt đối (cập nhật `PageOperations.swift` nếu cần) + test

## Giai đoạn 6: US4, báo cáo định dạng cũ (P3)

- [X] T019 [P] [US4] `PBIXKit/Writing/LegacyLayoutPatch.swift` theo `contracts/legacy-layout.md`: định vị container, ghép số ở hai chỗ, xoá/thêm phần tử, kiểm `escape(unescape(config))` + test trên Nhóm 2 và Nhóm 3 (round-trip không sửa = giống byte; một sửa chỉ đổi vùng sửa) (`Tests/PBIXKitTests/LegacyLayoutPatchTests.swift`)
- [X] T020 [US4] `LayoutEditor+Legacy.swift`: `isLegacy`, `makeLegacyChanges` (di chuyển, đổi cỡ, xoá, nhân bản, dán, căn) ghi `reportParts["Report/Layout"]`; visual trong nhóm cũ bị khoá
- [X] T021 [US4] Tách `canEditLayout` thành `canEditCanvas` và `canEditStructure` (`DocumentState.swift`, `DocumentState+Report.swift`, `PageOperations.swift`, `ReportWorkspace.swift`): định dạng cũ cho canvas, chặn Build/Format/trang/bookmark/bộ lọc kèm lý do
- [X] T022 [US4] `DocumentSaver.verifyLegacyLayout` (R6) + `PBIXWriter` bỏ `SecurityBindings` khi `Report/Layout` đổi (kiểm `changesReport`)
- [X] T023 [P] [US4] Test sửa/lưu/mở lại trên bản sao Nhóm 2 và Nhóm 3: dời, đổi cỡ, xoá, nhân bản, dán, hoàn tác (`Tests/BIProTests/Edit/LegacyEditorTests.swift`)

## Giai đoạn 7: US5, tích hợp, VM, review

- [X] T024 Test nặng `D7Nhom6Tests` ghi `build/d-out/D7/Nhom6_d7.pbix`, `Nhom6_d7_pre.pbix`, `Nhom2_d7.pbix`, `CHECKLIST.md`; đo thời gian từng lệnh và lưu (SC-001, SC-006)
- [X] T025 Chạy `swift test` và golden nặng; D1 đến D6 và Phase B/C vẫn qua
- [X] T026 VM vòng 2 (Claude điều khiển VM theo lời cho phép; hỏi lại nếu hết hiệu lực): mở `Nhom6_d7.pbix` và `Nhom2_d7.pbix` trong Desktop; kiểm nhóm hiện đúng, căn lề đúng, dán đúng, định dạng cũ mở không lỗi; thử xoá nhóm và co dọc; ghi `docs/phase-d-evidence/vm-d7/CHECKLIST-KET-QUA.md`; xoá file tạm VM và Mac
- [X] T027 Bấm thử trong app (`zsh scripts/build-app.sh`; chụp riêng cửa sổ app; tắt app bằng `pkill -f "BI Pro.app/Contents/MacOS"`): căn, phân bố, dán, nhóm, ⌘Z, ⌘S, mở lại; ảnh `docs/phase-d-evidence/vm-d7/app-d7-*.png`
- [X] T028 `/code-review medium` và `/speckit-converge`, sửa phát hiện
- [X] T029 Cập nhật `docs/STATE.md` (ngắn), `docs/BIPRO_BUILD_PLAN.md`, `specs/008-d7-nhom-can-le-cu/measurements.md`; đánh dấu mọi task `[X]`

## Phase 8: Convergence

- [X] T030 Menu chuột phải trên canvas ở chế độ Sửa (Căn lề, Phân bố, Nhóm, Bỏ nhóm; mờ kèm lý do) per FR-001 và plan T008 (partial) (`EditCanvasOverlay.swift`)
- [X] T031 Dán bỏ phần không sao được (nút điều hướng trỏ trang hoặc bookmark đã xoá sau khi chép) kèm thông báo per FR-002 (partial): chưa cài vì chưa biết dạng tham chiếu Desktop dùng; ghi thành hạn chế đã biết trong `docs/STATE.md`
- [X] T032 Test sửa trường và định dạng của một visual con trong nhóm giữ `parentGroupName`, vị trí tương đối và byte còn lại per FR-004 (missing) (`Tests/BIProTests/Edit/GroupTests.swift`)
- [X] T033 Test xoá nhóm gỡ nhóm và các con khỏi `visualContainers` của bookmark per spec Trường hợp biên và D1 R14 (missing) (`Tests/BIProTests/Edit/GroupTests.swift`)
- [X] T034 Ghi vào `docs/STATE.md` phần VM-D7 chưa quan sát được (xoá nhóm, co dọc) per spec Giả định (partial)
