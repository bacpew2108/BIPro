---
description: "Danh sách việc: D1, sửa bố cục trang trên canvas và lưu .pbix tầng T1"
---

# Việc cần làm: D1, sửa bố cục và lưu T1

**Đầu vào**: `specs/002-d1-canvas-luu-t1/` (spec.md, plan.md, research.md, data-model.md, contracts/layout-editing.md, contracts/save-pipeline.md, quickstart.md)

**Kiểm thử**: spec yêu cầu (FR-020, FR-021, SC-001 đến SC-007): có test thuần cho hình học, hoàn tác, ghép byte, đường lưu; test nặng trên Nhom6; golden Phase B/C chạy lại. Test viết trước, thấy trượt rồi mới viết mã.

**Người làm**: lead tự làm, tuần tự, không giao agy (xem `plan.md`, Hiến pháp V và `docs/phase-d-ownership.tsv`). Vì vậy không có việc `[P]`.

**Quy ước**: `[US1]` đến `[US5]` là câu chuyện trong spec. Thứ tự giai đoạn theo ưu tiên và phụ thuộc: US1 (chọn, di chuyển), US3 (hoàn tác), US2 (lưu), US4 (xoá, nhân bản), US5 (Editor). Lệnh build/test là các lệnh trong `CLAUDE.md`. Fixture: `~/Downloads/bipro-golden/Nhom6_work.pbix` hoặc `BIPRO_NHOM6`. Không commit trừ khi bạn bảo. File sinh ra nằm ở `build/d-out/`; không ghi vào `~/Downloads`.

## Giai đoạn 1: Chuẩn bị

- [X] T001 Cổng R2, bước thử `DocumentGroup(viewing:)`: viết mã thử tạm trong `Sources/BIPro/Report/Edit/SpikeDocumentWindow.swift` (xoá ở T040) để (a) đặt `NSWindow.isDocumentEdited = true` cho cửa sổ tài liệu, (b) chặn đóng cửa sổ bằng uỷ quyền cửa sổ và hiện hộp thoại Lưu/Không lưu/Huỷ, (c) chặn ⌘Q khi còn cửa sổ chưa lưu (`applicationShouldTerminate`), (d) lệnh menu ⌘S, ⇧⌘S, ⌘Z, ⇧⌘Z gắn qua `CommandGroup` và `focusedSceneValue`. Chạy app, chụp cửa sổ app, ghi kết quả vào `research.md` R2. **Cổng**: chỉ qua khi cả (a), (b), (c), (d) đều làm được. Một trong bốn không làm được, kể cả làm được một phần (ví dụ chặn đóng cửa sổ được nhưng ⌘Q không chặn được), thì dừng, báo bạn kèm phương án (b) của R2, không tự đổi sang `FileDocument`.
- [X] T002 Rà soát chỗ đọc bố cục trang: `grep` mọi nơi trong `Sources/BIPro/` gọi `workspace.page(id:)`, `workspace.report.pages`, `.visuals` (Selection pane, `ReportInteraction`, bookmark, drillthrough, hit-test tương tác, `VisualDataLoader`). Lập danh sách vào `research.md` R3, mỗi dòng ghi rõ "chuyển sang `state.page`" hoặc "giữ bản gốc vì …".
- [X] T003 Đo mốc trước khi sửa: chạy `swift build -c release --product pbix-dump --scratch-path .build-1a-rel` rồi `pbix-dump roundtrip` trên Nhom6 (nếu lệnh không có tuỳ chọn ghi tạm thì đo `PBIXWriter.build` không đổi gì bằng một test tạm); ghi thời gian dựng và ghi 90 MB, 5 lần, vào `specs/002-d1-canvas-luu-t1/measurements.md` (file mới, bảng "Trước khi sửa"). Đây là mốc cho SC-004.

## Giai đoạn 2: Nền tảng ghi (chặn mọi câu chuyện)

**Quan trọng**: chưa làm giao diện trước khi qua T011.

- [X] T004 Tạo `Tests/PBIXKitTests/PBIXWriterEditTests.swift` (test trước, phải thấy trượt): dùng `tuan6.2.pbix` hoặc fixture nhỏ có sẵn trong `Tests/PBIXKitTests/`; kiểm (a) `addedParts` thêm một phần mới, đặt ngay sau `visual.json` cuối của cùng trang; (b) `removedParts` bỏ phần và chỉ phần đó; (c) mọi thành viên không nằm trong `changes` (gồm `DataModel`, `SecurityBindings`) có nội dung và CRC giống nguồn; (d) thêm phần đã có hoặc bỏ phần không có → ném `WriteError.invalid`; (e) `tier == .report`; (f) chính sách sao lưu `.directory(URL)` ghi bản trước vào thư mục chỉ định và KHÔNG tạo `.pbix.bak` cạnh file.
- [X] T005 Sửa `Sources/PBIXKit/Writing/Contracts.swift`: `PBIXChanges` thêm `addedParts: [String: Data]` và `removedParts: Set<String>`; thêm `enum BackupPolicy { case sideBak, directory(URL), none }`. `tier` giữ `.report` khi chỉ có ba trường phần. Không đổi gì khác.
- [X] T006 Sửa `Sources/PBIXKit/Writing/PBIXWriter.swift`: `build` xử lý `addedParts` (chèn sau phần `visual.json` cuối cùng cùng trang; phần chèn dùng `.bytes(method: 8)`) và `removedParts` (bỏ); `verify` kiểm phần thêm đọc lại đúng, phần bỏ không còn, và mọi thành viên khác khớp nguồn; `save(...)` nhận `backup: BackupPolicy = .sideBak` (CLI giữ hành vi cũ). T004 phải qua; `swift test --filter PBIXKitTests` không trượt thêm.
- [X] T007 Tạo `Tests/PBIXKitTests/PBIRLayoutPatchTests.swift` (test trước): trên `visual.json` thật trích từ Nhom6 (hoặc chuỗi mẫu cùng cấu trúc) kiểm (a) `setPosition` đổi đúng các số `x, y, width, height, z, tabOrder` được yêu cầu và mọi byte khác giữ nguyên (so bằng cách thay lại số cũ phải ra đúng byte gốc); (b) giá trị âm hoặc không nguyên → ném lỗi; (c) `duplicated(json, newName:, position:)` đổi `name` và `position`, giữ nguyên phần còn lại; mã mới phải 20 hex; (d) `removingVisualReferences(ids, fromBookmark:)` bỏ phần tử trong `targetVisualNames` và khoá trong `explorationState.sections.<trang>.visualContainers`, kết quả vẫn là JSON hợp lệ và các phần khác không đổi; mã không có trong bookmark thì trả đúng byte vào; (e) `removingVisualReferences(ids, fromPage:)` cho `visualInteractions` (dùng mẫu tự dựng vì Nhom6 không có).
- [X] T008 Tạo `Sources/PBIXKit/Writing/PBIRLayoutPatch.swift`: `setPosition(in:x:y:width:height:z:tabOrder:)`, `duplicated(_:newName:position:)`, `removingVisualReferences(_:fromBookmark:)`, `removingVisualReferences(_:fromPage:)`. Dùng lại `JSONCursor.locate` của `PBIRPatch` để ghép byte, và kiểm lại sau mỗi lần ghép bằng so cấu trúc (cách của `setVisualTitle`). T007 phải qua.
- [X] T009 Sửa `Sources/pbix-dump/main.swift`: thêm lệnh thử `move-visual <pbix> <trang> <mã> <x> <y> [-o ra.pbix]`, `remove-visual`, `dup-visual` dùng `PBIXWriter` mới, để kiểm đường ghi bằng tay và cho gói test VM sớm. Không đụng lệnh hiện có. Đây là công cụ phụ (ngoài spec), chỉ để kiểm đường ghi bằng tay và dựng gói VM sớm.
- [X] T010 Test tích hợp nặng `Tests/PBIXKitTests/EditRoundTripTests.swift` trên Nhom6: dời 3 visual D1, nhân bản 1, xoá 1 (một visual có trong bookmark Q1.3) bằng `PBIRLayoutPatch` + `PBIXWriter.build`, ghi vào `build/d-out/D1/Nhom6_pre.pbix`. Kiểm: `unzip -t` qua (gọi `Process`), hai trang không sửa khớp từng byte, `DataModel` khớp từng byte, `loadReport()` cho đúng vị trí mới, `loadBookmarks()` đọc được và không còn nhắc mã đã xoá. Không ghi đè nguồn.
- [X] T011 Cổng nền tảng: ghi `build/d-out/D1/CHECKLIST-pre.md` (mở `Nhom6_pre.pbix` trong Power BI Desktop: mở không lỗi, 4 trang, các visual đã dời/nhân bản/xoá đúng, bookmark Q1.3 chạy, không đòi sửa file) và báo bạn kết quả T010. **Không chặn**: tiếp tục giai đoạn 3 trong lúc chờ bạn thử trên VM; nếu Power BI từ chối file thì dừng và quay lại R5/R6 trước khi làm tiếp phần lưu (giai đoạn 5).

**Điểm kiểm tra**: PBIXKit ghi được thêm, bớt, đổi vị trí; test qua. Mới bắt đầu câu chuyện 1.

## Giai đoạn 3: Câu chuyện 1 (P1): chọn, di chuyển, đổi cỡ visual

**Mục tiêu**: FR-001 đến FR-004, FR-007; SC-005.

**Kiểm thử độc lập**: mở Nhom6, ⌘E, kéo một thẻ card, đổi cỡ một biểu đồ; số liệu vẫn chạy, tắt ⌘E thì lọc chéo như cũ. Chưa cần lưu.

### Test trước

- [X] T012 [US1] Tạo `Tests/BIProTests/Edit/LayoutGeometryTests.swift`: theo `contracts/layout-editing.md`: `snap`; `move` bám lưới và kẹp trong trang (4 cạnh); `move` nhóm giữ vị trí tương đối và kẹp theo khung bao nhóm; `resize` đủ 8 tay nắm, cạnh đối diện đứng yên, không đảo chiều, `minSize`, kẹp trang; mọi kết quả là số nguyên; giữ Option (không bám lưới) cho giá trị tự do; `hit` chọn visual hiện thấy có `z` lớn nhất, bỏ qua visual ẩn; `marquee` chọn theo giao.
- [X] T013 [US1] Tạo `Tests/BIProTests/Edit/LayoutEditorTests.swift` (phần chọn, di chuyển, đổi cỡ): chọn một, Shift thêm/bớt, bỏ chọn, đổi trang xoá vùng chọn; `move`/`resize` cập nhật `edited[page]` và để trang khác nguyên vẹn; trang chưa đụng tới không có bản sao; visual có `parentGroupName` (dựng bằng `ReportVisual` mẫu có `raw` chứa trường này) vẫn chọn được nhưng `move`/`resize`/`delete`/`duplicate` bỏ qua nó và báo lý do (vì vị trí của visual con trong nhóm là tương đối theo nhóm, chưa hỗ trợ ở D1).

### Cài đặt

- [X] T014 [US1] Tạo `Sources/BIPro/Report/Edit/LayoutGeometry.swift`: hằng số (`grid`, `minSize`, `nudge`, `duplicateOffset`, `zStep`) và hàm thuần theo hợp đồng. T012 phải qua.
- [X] T015 [US1] Tạo `Sources/BIPro/Report/Edit/LayoutEditor.swift` (phần lõi): `@MainActor @Observable`, `edited`, `selection`, `primary`, `commit(page:)` đẩy snapshot (ngăn xếp hoàn tác để T021), `move`, `resize`, `select`; thuộc tính `isLockedByGroup(visual)` (đọc `parentGroupName` từ `raw`) để các thao tác sửa bỏ qua visual trong nhóm. Overlay (T017) hiện chú thích "Nằm trong nhóm, chưa sửa được ở D1" khi chọn visual như vậy. T013 phải qua.
- [X] T016 [US1] Sửa `Sources/BIPro/DocumentState.swift`: giữ `layout: LayoutEditor`, `fileURL`, `editMode: Bool`; `page` trả `ReportPage` với `visuals` lấy từ `layout.edited[pageID]` nếu có; `visualID` đồng bộ với `layout.primary`. Áp kết quả rà soát T002 (chuyển các chỗ ghi "chuyển sang `state.page`").
- [X] T017 [US1] Tạo `Sources/BIPro/Report/Edit/EditCanvasOverlay.swift`: lớp phủ chế độ Sửa trên `ReportPageView`: bấm chọn, Shift-bấm, khung chọn trên vùng trống, 8 tay nắm kéo được, kéo thân (đổi biến tạm trong lúc kéo, `commit` một lần khi thả), phím mũi tên (1 px, Shift 8 px), giữ Option bỏ bám lưới, tạm hiện đường gióng khi bám lưới (nét mảnh). Phím Esc bỏ chọn.
- [X] T018 [US1] Sửa `Sources/BIPro/Report/ReportCanvas.swift`: ở chế độ Sửa dùng overlay, `allowsHitTesting(false)` cho nội dung bên trong visual, vẽ vùng chọn nhiều (khung bao nhóm); ở chế độ Xem giữ nguyên mã cũ (so sánh ảnh chụp trước/sau). Sửa `Sources/BIPro/Report/ReportWorkspace.swift`: nút Xem/Sửa (đủ thấy, có tooltip) và phím ⌘E; đổi trang xoá vùng chọn.
- [X] T019 [US1] Sửa `Sources/BIPro/Panes/ReportPanes.swift`: Selection pane sáng nhiều dòng theo vùng chọn, bấm dòng chọn visual (kể cả visual ẩn, FR-007).
- [X] T020 [US1] Kiểm tay trong app: `zsh scripts/build-app.sh`, mở bản sao Nhom6 ở Desktop, thao tác theo `quickstart.md` mục 2 bước 1–3 và 10; chụp cửa sổ app (chỉ cửa sổ) vào `docs/phase-d-evidence/`, xem bằng mắt: chọn, chọn nhiều, tay nắm. Đo thời gian phản hồi khi kéo/đổi cỡ trên D1 (37 visual); nếu đổi cỡ vượt 150 ms mỗi khung hình thì chuyển sang vẽ khung xem trước và áp khi thả (R9). Ghi số vào `measurements.md`. Sau bước này tạo `build/d-out/D1/VM-D1-QUAN-SAT.md` (thao tác quan sát ở `quickstart.md` mục 4) và gửi bạn ngay, để buổi VM-D1 chạy song song với các giai đoạn sau.

**Điểm kiểm tra**: US1 dùng được độc lập, chế độ Xem không đổi.

## Giai đoạn 4: Câu chuyện 3 (P1): hoàn tác và làm lại

**Mục tiêu**: FR-008, FR-009; dấu "chưa lưu" (một phần FR-010).

**Kiểm thử độc lập**: kéo một visual, đổi cỡ, ⌘Z hai lần về đúng ban đầu và dấu "chưa lưu" mất; ⇧⌘Z hai lần về trạng thái sau cùng.

- [X] T021 [US3] Mở rộng `Tests/BIProTests/Edit/LayoutEditorTests.swift` (test trước): một cử chỉ = một bước; không tạo bước khi vị trí cuối bằng đầu; `undo`/`redo` khôi phục bố cục và vùng chọn, chuyển tới trang liên quan; thao tác mới sau `undo` xoá `redo`; `isDirty` đúng khi quay về `cleanMark` (undo rồi redo, và undo về mức đã lưu); mũi tên nhấn liên tục trong 0,5 s cùng nhóm chọn gộp một bước; giới hạn 200 bước và `cleanMark = −1` khi mất mốc.
- [X] T022 [US3] Hoàn thiện `LayoutEditor`: ngăn xếp `undo`/`redo` theo `data-model.md` (snapshot cả trang), `cleanMark`, `markSaved()`, `isDirty`, gộp mũi tên, giới hạn 200. T021 phải qua.
- [X] T023 [US3] Sửa `Sources/BIPro/App.swift`: `CommandGroup(replacing: .undoRedo)` ⌘Z / ⇧⌘Z (bật/tắt theo `canUndo`/`canRedo` của tài liệu đang chọn) qua `focusedSceneValue`; đặt `NSWindow.isDocumentEdited` theo `isDirty` bằng cách đã thử ở T001; tiêu đề cửa sổ thể hiện trạng thái. Kiểm tay: bước 5 của `quickstart.md`.

**Điểm kiểm tra**: US1 + US3 dùng được; sửa rồi hoàn tác không để lại dấu vết.

## Giai đoạn 5: Câu chuyện 2 (P1): lưu và mở lại được trong Power BI Desktop

**Mục tiêu**: FR-010 đến FR-016, FR-018, FR-021; SC-001 đến SC-004, SC-007.

**Kiểm thử độc lập**: sửa bố cục D1 trên bản sao ở Desktop, ⌘S, thoát app, mở lại: bố cục giữ nguyên; `unzip -t` qua; DataModel khớp byte.

### Test trước

- [X] T024 [US2] Tạo `Tests/BIProTests/Edit/DocumentSaverTests.swift`: dùng fixture nhỏ ghi vào thư mục tạm của test (không dùng `~/Downloads`): (a) lưu một thay đổi di chuyển → đọc lại bằng `PBIXFile(url:).loadReport()` đúng; (b) đích nằm dưới thư mục "gốc chỉ đọc" cấu hình được (test truyền thay cho `~/Downloads`) → ném `readOnlyOriginal`, đích nguyên vẹn; (c) đích đổi sau `openedStamp` → ném `modifiedExternally`; (d) bản sao lưu xuất hiện ở thư mục sao lưu chỉ định, bản mới ghi đè bản cũ của cùng file; (e) ghi lỗi (đích là thư mục không ghi được) → đích nguyên vẹn và không còn `.tmp`; (f) kiểm tra đọc lại không khớp (cố ý đưa `LayoutEditor` lệch) → `verificationFailed`, đích nguyên vẹn; (g) Lưu thành tạo file mới và không đổi nguồn (so băm); (h) sau lưu `isDirty == false` và `openedStamp` mới; (i) không có thay đổi (`!isDirty`) thì `save` không ghi gì: ngày sửa và băm của đích không đổi, không tạo bản sao lưu.
- [X] T025 [US2] Mở rộng `LayoutEditorTests`: `makeChanges()` cho thay đổi vị trí chỉ gồm `reportParts` của visual đã dời (không phần của trang khác, không phần của visual không dời), với `visual.json` ghép bằng `PBIRLayoutPatch.setPosition` (chỉ trường đổi).

### Cài đặt

- [X] T026 [US2] Sửa `LayoutEditor`: `makeChanges(report:archive:) -> PBIXChanges` cho phần dời/đổi cỡ (xoá, nhân bản thêm ở giai đoạn 6). T025 phải qua.
- [X] T027 [US2] Tạo `Sources/BIPro/Report/Edit/DocumentSaver.swift`: `FileStamp`, `save(editor:source:destination:readOnlyRoots:backupDirectory:)` theo `contracts/save-pipeline.md` (chặn đường dẫn, kiểm file đổi, dựng, kiểm trong bộ nhớ gồm so `loadReport()` với `LayoutEditor`, ghi tạm, mở lại, sao lưu, `replaceItemAt`, `markSaved`). `readOnlyRoots` mặc định là `~/Downloads` (sau khi giải liên kết). Không có thay đổi thì trả về ngay, không ghi gì (spec, trường hợp biên). T024 phải qua.
- [X] T028 [US2] Sửa `Sources/BIPro/App.swift` và `DocumentState`: lệnh ⌘S và ⇧⌘S (`CommandGroup(replacing: .saveItem)`), `NSSavePanel`; ⌘S trên file dưới `~/Downloads` hoặc không có URL → mở Lưu thành kèm lý do; hộp thoại lỗi theo bảng thông báo trong hợp đồng; Lưu thành xong thì mở file đích bằng `NSDocumentController` rồi đóng cửa sổ cũ không hỏi; hỏi Lưu/Không lưu/Huỷ khi đóng cửa sổ và khi ⌘Q (cách đã thử ở T001).
- [X] T029 [US2] Test nặng `Tests/BIProTests/Edit/EditNhom6Tests.swift` : đọc Nhom6, sửa D1 như SC-001 (dời ≥ 3, đổi cỡ 1; xoá và nhân bản bổ sung ở T036), lưu bằng `DocumentSaver` vào `build/d-out/D1/Nhom6_d1.pbix`, mở lại và so từng visual; trang khác và `DataModel` khớp byte; đo thời gian lưu (SC-004, dưới 1 s) và in ra; nguồn không bị đổi (băm trước/sau).
- [X] T030 [US2] Kiểm tay trong app theo `quickstart.md` mục 2 bước 6–9, trên bản sao ở Desktop và một file ở `~/Downloads` (chỉ để xem yêu cầu Lưu thành; không lưu vào đó). Chụp hộp thoại. Nếu SC-004 vượt 1 s thì tối ưu theo R7 (ánh xạ bộ nhớ) và đo lại.

**Điểm kiểm tra**: US1 + US3 + US2 dùng được; MVP của D1 (sửa, hoàn tác, lưu) xong.

## Giai đoạn 6: Câu chuyện 4 (P2): xoá và nhân bản visual

**Mục tiêu**: FR-005, FR-006, FR-017; SC-001 (phần xoá/nhân bản).

**Kiểm thử độc lập**: nhân bản một card, thấy bản sao chạy số thật; xoá bản sao; lưu; mở lại.

- [X] T031 [US4] Mở rộng `LayoutEditorTests` (test trước): xoá một/nhiều visual → biến khỏi `edited`, ghi vào `deletedByPage` (visual có sẵn) hoặc bỏ khỏi `addedByPage` (bản sao); hoàn tác trả đúng chỗ và đúng `z`; nhân bản: mã mới 20 hex không trùng mọi mã trong báo cáo kể cả sau undo/redo rồi nhân bản lại (chạy 1000 lần, không trùng), vị trí +16 và kẹp trang, `z = tabOrder = max + 1000`, nhân bản nhiều giữ vị trí tương đối, vùng chọn chuyển sang bản sao; `makeChanges()` có `addedParts` cho bản sao, `removedParts` cho bản xoá, và phần bookmark/page đã dọn tham chiếu chỉ khi có nhắc mã bị xoá.
- [X] T032 [US4] Cài `delete`, `duplicate` (và `copy`/`paste` trong cùng tài liệu cho ⌘C/⌘V) trong `LayoutEditor`; mở rộng `makeChanges` dùng `PBIRLayoutPatch.duplicated` và `removingVisualReferences`; trang không đụng tới không được xuất hiện. T031 phải qua.
- [X] T033 [US4] Sửa `EditCanvasOverlay` và `Sources/BIPro/App.swift`: phím Delete/⌫, ⌘D, ⌘C, ⌘V (Edit menu, bật/tắt theo vùng chọn); sau nhân bản bản sao được chọn.
- [X] T034 [US4] Mở rộng `EditNhom6Tests` (T029): thêm xoá một visual có trong bookmark Q1.3 và nhân bản một card; lưu, mở lại, kiểm bookmark không còn nhắc mã đã xoá và vẫn đọc được, mã bản sao duy nhất, `unzip -t` qua. Cập nhật `build/d-out/D1/Nhom6_d1.pbix`.
- [X] T035 [US4] Kiểm tay trong app theo `quickstart.md` mục 2 bước 4–5; chụp cửa sổ app.

**Điểm kiểm tra**: sửa bố cục trọn vẹn (dời, đổi cỡ, xoá, nhân bản) và lưu.

## Giai đoạn 7: Câu chuyện 5 (P3): app là trình sửa `.pbix`

**Mục tiêu**: FR-019.

- [X] T036 [US5] Sửa `scripts/build-app.sh`: `CFBundleTypeRole` `Viewer` → `Editor`, giữ `LSHandlerRank = Default` và UTI nhập. Dựng lại app; chạy `plutil -p "build/BI Pro.app/Contents/Info.plist"` xác nhận; chạy `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump | grep -A3 "BI Pro"` và ghi kết quả; kiểm "Mở bằng → BI Pro" từ Finder mở đúng file và menu Lưu sáng. Không đổi app mặc định của hệ thống.

## Giai đoạn 8: Hoàn thiện

- [X] T037 Gói test VM: tạo `build/d-out/D1/CHECKLIST.md` (mở `Nhom6_d1.pbix` trong Power BI Desktop: mở không lỗi, 4 trang, visual đã sửa đúng chỗ, bản nhân bản chạy số, visual đã xoá không còn, bookmark Q1.3 chạy, số liệu không đổi, lưu lại trong Power BI Desktop không báo lỗi); cập nhật `VM-D1-QUAN-SAT.md` đã gửi ở T020 nếu cần. Báo bạn.
- [X] T038 Chạy toàn bộ: `swift build`, `swift test` (không trượt thêm), golden nặng `BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --filter "Nhom6|ORA|VIS|EditNhom6|BatchedSerial"` (30/30 Phase B, 72 truy vấn visual, các test E3 vẫn qua). Ghi số vào `measurements.md` (SC-004, SC-005, SC-006).
- [X] T039 Chụp lại các trang Nhom6 ở chế độ Xem và so với ảnh trước khi sửa (`docs/phase-c-evidence/` hoặc ảnh chụp mới của chính mốc `710daaf`): không khác ở chế độ Xem (FR-007, FR-020).
- [X] T040 Dọn: xoá `Sources/BIPro/Report/Edit/SpikeDocumentWindow.swift` và mọi mã thử; `grep` không còn nhãn debug; `git status` chỉ có file trong `docs/phase-d-ownership.tsv`, `specs/002-d1-canvas-luu-t1/`, `docs/phase-d-evidence/`, `docs/STATE.md`, `docs/BIPRO_BUILD_PLAN.md`.
- [X] T041 Cập nhật tài liệu: `docs/STATE.md` (D1 xong phần code, chờ VM-D1-mở và VM-D1; ngắn gọn), `docs/BIPRO_BUILD_PLAN.md` mục Phase D (tick các ô đã làm: canvas chọn/di chuyển/đổi cỡ, lưu T1, undo/redo, Editor; ghi phần còn lại của Phase D), `docs/phase-d-evidence/README.md` (mục tiêu, các quan sát đã có và [SUY ĐOÁN] còn lại).
- [X] T042 Chạy `/speckit-converge` để đối chiếu mã với spec, plan, tasks; xử lý các task bổ sung nếu có. Báo bạn kết quả cuối (số test, số đo, việc chờ bạn: bấm thử, VM-D1, VM-D1-mở). Chờ bạn bảo thì mới commit.

---

## Phụ thuộc và thứ tự

- Giai đoạn 1 → 2 (T001 là cổng cho T023 và T028) → 3 → 4 → 5 → 6 → 7 → 8.
- Giai đoạn 4 dùng lõi của T015; giai đoạn 5 dùng ngăn xếp của T022 (`markSaved`, `isDirty`).
- T029 và T034 cùng sửa `EditNhom6Tests.swift`: làm tuần tự.
- T011 là điểm dừng mềm: cần bạn thử `Nhom6_pre.pbix` trước khi chốt giai đoạn 5 và 6, nhưng không chặn giai đoạn 3 và 4.

## Phủ yêu cầu

| Yêu cầu | Task |
|---|---|
| FR-001 đến FR-004 | T012–T019 |
| FR-005, FR-006 | T031–T033 |
| FR-007 | T018, T019, T039 |
| FR-008, FR-009 | T021–T023 |
| FR-010, FR-015 | T001, T023, T028 |
| FR-011, FR-012, FR-013, FR-016 | T004–T006, T024, T027 |
| FR-014 | T024 (b), T027, T028, T030 |
| FR-017 | T007, T008, T031, T034 |
| FR-018 | T004, T010, T025, T029 |
| FR-019 | T036 |
| FR-020, FR-021 | T029, T038, T039 |
| SC-001 | T029, T034 |
| SC-002 | T011, T037 (bạn kiểm tay) |
| SC-003 | T004, T010, T029 |
| SC-004 | T003, T029, T030, T038 |
| SC-005 | T020, T038 |
| SC-006 | T038 |
| SC-007 | T024 (e), (f) |
| SC-008 | T020, T030, T035 |

## Chiến lược

- **MVP** = giai đoạn 1 đến 5: sửa, hoàn tác, lưu. Giai đoạn 6 và 7 thêm sau, mỗi giai đoạn dừng được.
- Nếu T001 hoặc T011 trượt thì dừng và báo bạn, không tự đổi hướng.
