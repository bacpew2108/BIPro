---
description: "Danh sách việc: D3, thêm visual mới và đổi loại visual, lưu .pbix tầng T1"
---

# Việc cần làm: D3, thêm visual mới và đổi loại visual

**Đầu vào**: `specs/004-d3-them-visual-doi-loai/` (spec.md, plan.md, research.md, data-model.md, contracts/insert-and-retype.md, contracts/visual-json-patches.md, quickstart.md)

**Kiểm thử**: spec yêu cầu (FR-012 đến FR-018, SC-001 đến SC-007): test thuần cho mẫu visual mới, ghép byte, ánh xạ ô khi đổi loại, vị trí thêm, hoàn tác đan xen với D1 và D2; test nặng trên Nhom6 (thêm, đổi loại, lưu, mở lại, so số với DAX viết tay); golden Phase B/C chạy lại. Test viết trước, thấy trượt rồi mới viết mã.

**Người làm**: lead tự làm, tuần tự, không giao agy (xem `plan.md`, Hiến pháp V: `LayoutEditor`, `ReportPanes`, `VisualCatalog`, `PBIRQueryPatch` giao nhau với D1 và D2). Vì vậy không có việc `[P]`.

**Quy ước**: `[US1]` đến `[US5]` là câu chuyện trong spec (US1 thêm visual, US2 lưu, US3 đổi loại, US4 hộp văn bản và ribbon, US5 hoàn tác chung). Thứ tự giai đoạn: nền tảng, US1, US3, US2, US4, US5. Lệnh build/test là các lệnh trong `CLAUDE.md`. Fixture: `~/Downloads/bipro-golden/Nhom6_work.pbix` hoặc `BIPRO_NHOM6`. Không commit trừ khi bạn bảo. File sinh ra nằm ở `build/d-out/`; không ghi vào `~/Downloads`. Khi chạy app để thử: dùng bản sao Nhom6 ở Desktop (xoá sau), chụp ảnh chỉ cửa sổ app (`screencapture -x -o -l <windowID>`), dừng app bằng `pkill -f "BI Pro.app/Contents/MacOS"`; điều khiển chuột bằng `cliclick` với toạ độ âm phải viết `=-N`; kéo thả cần gửi sự kiện chuột bằng `Quartz` (xem ghi chú D2).

**Phần cần bạn (VM-D3)**: buổi quan sát ở T003; chạy song song với giai đoạn 2 đến 6. Chỉ chặn T033 đến T035 (chốt khoá `visual.json` mới, mở thêm loại cột/thanh/vùng, chỉnh cỡ mặc định, ánh xạ ô và giữ `objects` theo Desktop). Chưa có kết quả thì các việc đó giữ trạng thái chặn (phương án thận trọng của R2 đến R8), phần còn lại vẫn xong được.

## Giai đoạn 1: Chuẩn bị

- [X] T001 Cổng mềm R6, thử vùng nhìn thấy của canvas: thêm tạm vào `Sources/BIPro/Report/ReportCanvas.swift` một `onScrollGeometryChange` ghi `visibleRect` (toạ độ trang) ra `/tmp/d3-viewport.log`; chạy app, thử zoom vừa trang, zoom 200% rồi cuộn; ghi kết quả vào `research.md` R6 (xoá mã tạm khi xong T017). Không báo đúng vùng thì dùng tâm trang và ghi rõ vào R6; không chặn các việc khác.
- [X] T002 Rà soát nơi đọc `visual.type`, `visual.objects`, `visual.containerObjects` và `visual.raw`: `grep` trong `Sources/BIPro/` (`TextboxVisual` đọc `objects`, `VisualCatalog.displayTitle`, `DataPlaceholders`, `LiveVisualView.categoricalView`/`placeholder`, `ReportCanvas.isStatic`, Format pane, `VisualQuerySpecReader`). Thêm mục `## R15. Nơi đọc loại và định dạng của visual` vào `research.md`: mỗi dòng ghi "đọc từ `state.page` (bản sửa)" hoặc "giữ bản gốc vì …", và nơi nào phải cập nhật `objects`/`containerObjects` khi đổi loại hoặc sửa văn bản (hộp văn bản vẽ từ `objects`, không từ `raw`).
- [X] T003 Chuẩn bị buổi VM-D3: tạo `docs/phase-d-evidence/vm-d3/README.md` và `build/d-out/D3/VM-D3-QUAN-SAT.md` (viết như `VM-D2-QUAN-SAT.md`: sáu bước của `research.md` R14, mỗi bước làm trên bản gốc mới, đổi một thứ, Lưu thành `R-D3-<chữ>-<tên>.pbix`, chỗ ghi số liệu và `ghichu.txt`; bước 6 chép truy vấn Performance Analyzer vào `R-D3-<chữ>-query.txt`). Báo bạn bắt đầu làm; kết quả bạn đặt vào `docs/phase-d-evidence/vm-d3/`. Không chờ kết quả để làm các việc khác.

## Giai đoạn 2: Nền tảng ghi và luật (chặn mọi câu chuyện)

**Quan trọng**: chưa làm giao diện trước khi qua T014.

- [X] T004 Tạo `Tests/PBIXKitTests/PBIRNewVisualTests.swift` (test trước, phải thấy trượt) theo `contracts/visual-json-patches.md`: (a) mẫu card/slicer/biểu đồ có đúng thứ tự khoá một dòng, `drillFilterOtherVisuals`, `tabOrder` = `z`; (b) `textbox` có `objects.general[0].properties.paragraphs` một đoạn "Hộp văn bản" và không có `drillFilterOtherVisuals`; (c) `$schema` lấy từ visual có sẵn, mặc định 2.13.0 khi không có; (d) tên không hợp lệ, loại không có cỡ mặc định, `width`/`height` < 1, `x`/`y` < 0 → `WriteError.invalid`; (e) kết quả đọc lại được qua `PBIXFile.loadReport()` trên một `.pbix` mẫu (`SyntheticPBIX`) cùng `PBIRLayoutPatch.position`; (f) cỡ mặc định đúng bảng R3 (card 302×108, slicer 364×64, biểu đồ/treemap/bản đồ hình/matrix 616×380, hộp văn bản 400×100).
- [X] T005 Tạo `Sources/PBIXKit/Writing/PBIRNewVisual.swift`: `makeJSON(name:type:x:y:width:height:z:schema:)`, `defaultSize(for:)`, `schemaURL(from:)`; dùng `PBIRPatch.jsonStringToken` cho chuỗi; kiểm lại bằng phân tích và so cấu trúc. T004 phải qua.
- [X] T006 Tạo `Tests/PBIXKitTests/PBIRVisualPatchTests.swift` (trước): (a) `setVisualType` đổi đúng chuỗi, mọi byte khác giữ nguyên; đổi rồi đổi lại ra đúng byte gốc; (b) `dropObjectKeys` bỏ đúng khoá (đầu, giữa, cuối, tất cả) kèm dấu phẩy, khoá không có thì bỏ qua, bỏ hết thì còn `"objects":{}`, `visualContainerObjects`/`query`/`position` không đổi; (c) `objectKeys`, `paragraphs` đọc đúng trên `visual.json` thật trích từ Nhom6 (một hộp văn bản nhiều đoạn); (d) `setText`: đoạn một lượt đổi `value` giữ `textStyle`, đoạn nhiều lượt, thêm dòng nhân bản byte đoạn cuối, bớt dòng, thoát ký tự (`"`, `\`, xuống dòng, Unicode); (e) lỗi cho đầu vào sai (không có `visualType`, không có `paragraphs`).
- [X] T007 Tạo `Sources/PBIXKit/Writing/PBIRVisualPatch.swift` theo hợp đồng: `visualType(in:)`, `setVisualType`, `objectKeys(in:)`, `paragraphs(in:)`, `setText`. Dùng lại `JSONCursor.children/string/removing`. T006 phải qua.
- [X] T008 Mở rộng `Tests/PBIXKitTests/PBIRQueryPatchTests.swift` (trước): `visual` không có `query` + ô mới → chèn `"query":{"queryState":{…}}` ngay sau `visualType`, byte khác giữ nguyên; thêm nhiều ô cùng lúc; ô thành trống ở visual vốn không có `query` thì không tạo `query`; `queryState` có mà bỏ hết ô → `"queryState":{}`; `wells(in:)` của visual không có `queryState` trả `[]`. Rồi sửa `Sources/PBIXKit/Writing/PBIRQueryPatch.swift` cho qua.
- [X] T009 Tạo `Tests/BIProTests/Edit/VisualTypesTests.swift` (trước) rồi `Sources/BIPro/Report/Edit/VisualTypes.swift`: `VisualTypeInfo`, `info(for:)`, `supported` (11 loại có ô `observed` + `textbox`), `refusal(for:)` (lý do tiếng Việt: chưa hỗ trợ / chưa kiểm / cần tài nguyên), `defaultSize` khớp `PBIRNewVisual`; mọi loại trong `supported` có `WellRules` `observed` cho ít nhất một ô (trừ `textbox`); mọi loại của `VisualCatalog.gallery` không thuộc `supported` có lý do từ chối.
- [X] T010 Tạo `Tests/BIProTests/Edit/TypeChangeTests.swift` (trước) rồi `Sources/BIPro/Report/Edit/TypeChange.swift` theo R7 và R8: ánh xạ ô cho các cặp thanh ↔ đường ↔ cột 100% ↔ combo (cùng tên ô: chuyển nguyên, giữ byte phần tử), `Y2` → `Y` khi loại mới không có `Y2`, ô một trường chỉ giữ trường đầu, donut ↔ treemap (Category ↔ Group, Y ↔ Values), card ↔ slicer (measure bị bỏ vì slicer chỉ nhận cột: ca thử "trường bị bỏ và báo"), hierarchy khi đổi loại (cấp hierarchy ở ô `Category` của combo Năm › Quý › Tháng: giữ byte nếu ô mới nhận cột, bỏ và báo nếu ô mới không nhận), trường bị bỏ trả về đầy đủ, chặn khi trường bị bỏ còn được nhắc ở sắp xếp/bộ lọc/định dạng (`FieldReferences`) và không còn phần tử nào khác cùng `queryRef`, tỉa `objects` theo khoá thấy trên visual cùng loại đích trong báo cáo (loại đích không có mẫu thì bỏ cả `objects`, trừ `textbox`), đổi sang chính loại hiện tại → "không đổi".
- [X] T011 `Sources/pbix-dump/main.swift`: lệnh phụ `add-visual <in> <pageID> <type> <x> <y> <out>` (cỡ mặc định theo loại), `set-visual-type <in> <visualID> <type> <out>` (đổi `visualType` và tỉa `objects` theo khoá thấy trên cùng loại trong file; không ánh xạ trường), `set-text <in> <visualID> <dòng1|dòng2…> <out>` (T1, như `add-field` của D2) để làm file kiểm tay sớm.
- [X] T012 Dựng file kiểm tay sớm `build/d-out/D3/Nhom6_d3_pre.pbix` bằng ba lệnh ở T011 trên Nhom6 (thêm một card và một biểu đồ thanh nhóm vào trang D1, đổi loại một biểu đồ đường sang thanh nhóm, sửa chữ một hộp văn bản có sẵn) và `build/d-out/D3/CHECKLIST-pre.md` (mở được, visual mới có mặt đúng loại, biểu đồ đã đổi loại vẽ được, hộp văn bản đúng chữ, Save không lỗi). Xoá file `.bak` do CLI tạo. Báo bạn thử trên VM. Điểm dừng mềm: chưa chốt giai đoạn 5 trước khi biết file mở được; không chặn giai đoạn 3, 4, 6.
- [X] T013 Chạy lại `swift test`: T004 đến T010 qua, không test nào trượt thêm. Ghi số test vào `specs/004-d3-them-visual-doi-loai/measurements.md` (file mới).
- [X] T014 Cổng nền tảng: T004 đến T013 xong. Không qua thì không sang giai đoạn 3.

## Giai đoạn 3: Câu chuyện 1 (P1): thêm một visual mới từ thư viện

**Mục tiêu**: bỏ chọn rồi bấm biểu tượng trong thư viện thì một visual trống xuất hiện, chọn sẵn, nhận trường bằng Build pane của D2.

**Kiểm thử độc lập**: ở chế độ Sửa bỏ chọn, bấm biểu tượng card, thả `Net_Cashflow` vào ô Field: card hiện số. Chưa cần lưu.

### Test trước

- [X] T015 [US1] Tạo `Tests/BIProTests/Edit/InsertVisualTests.swift` (trước): với `LayoutEditor` trên báo cáo mẫu (`SyntheticReport`, `withChart`): (a) `insertVisual(.card)` thêm một visual vào `visuals` và `added`, mã mới hợp lệ không trùng, cỡ mặc định, `z` = lớn nhất + 1000, `tabOrder` = `z`, đang được chọn, đúng một bước hoàn tác; (b) vị trí: tâm trùng tâm `visibleRect` (làm tròn lưới 8, kẹp trang); lần thêm thứ hai cùng vùng lệch +16; không có `visibleRect` thì tâm trang; (c) từ chối loại chưa hỗ trợ (scatter, image) và loại không có trong báo cáo định dạng cũ, `fieldRefusal` có lý do, không đổi gì; (d) visual dữ liệu mới có `fields` rỗng, `raw` không có `query`, `fieldEditingBlocker` là nil và `addField` thả được trường vào ô hợp lệ (tạo `query.queryState`); (e) xoá visual mới rồi hoàn tác; nhân bản visual mới; mã của visual mới đã hoàn tác không bao giờ dùng lại; (f) thêm khi đang chọn visual khác (gọi từ ribbon) vẫn thêm và chọn visual mới.

### Cài đặt

- [X] T016 [US1] `Sources/BIPro/Report/Edit/LayoutEditor.swift`: `insertVisual(type:visibleRect:)` theo `contracts/insert-and-retype.md` (mã, cỡ, vị trí R5, `z`, `PBIRNewVisual.makeJSON` với `schema` lấy từ một visual có sẵn, `commit` thêm vào `visuals`, `added`, `createdIDs`, chọn visual mới, xoá `notice`, `fieldRefusal`); `fieldEditingBlocker` cho phép visual dữ liệu chưa có `query` (D2 từng từ chối); `LayoutEditor.notice` mới. T015 phải qua.
- [X] T017 [US1] `Sources/BIPro/Report/ReportCanvas.swift` và `Sources/BIPro/DocumentState.swift`: `DocumentState.visibleRect` do `ReportCanvas` cập nhật bằng `onScrollGeometryChange` (R6; kết quả T001; xoá mã tạm của T001); `DocumentState.insertVisual(_:)` gọi `layout.insertVisual` với trang hiện tại và `visibleRect`, cập nhật `visualID`.
- [X] T018 [US1] `Sources/BIPro/Panes/ReportPanes.swift` và `Sources/BIPro/Panes/VisualCatalog.swift`: thư viện biểu tượng bấm được: không chọn visual và đang Sửa → `insertVisual`; loại không hỗ trợ hoặc chế độ Xem → biểu tượng mờ, `.help` nêu lý do (`VisualTypes.refusal`), bấm vào đặt `layout.notice`; `notice` hiện ở Build pane (`BuildWells`) và tự xoá ở thao tác kế.
- [X] T019 [US1] Chạy app, thao tác thật theo `quickstart.md` mục 2 bước 1 đến 3; chụp cửa sổ app vào `docs/phase-d-evidence/vm-d3/`; đo thời gian vẽ lại sau khi thả trường vào visual mới (ghi vào `measurements.md`); sửa nếu vượt ngưỡng SC-005 (150 ms visual thường, 1 s visual nặng).

## Giai đoạn 4: Câu chuyện 3 (P1): đổi loại visual đã chọn

**Mục tiêu**: chọn một visual rồi bấm biểu tượng loại khác thì visual đổi loại tại chỗ, trường chuyển sang ô tương ứng, trường không có chỗ được báo.

**Kiểm thử độc lập**: chọn combo của Nhom6 ở D1, bấm biểu tượng đường: đổi loại, trường còn ở ô cũ hoặc được báo là bỏ, ⌘Z trả lại.

### Test trước

- [X] T020 [US3] Tạo `Tests/BIProTests/Edit/ChangeTypeTests.swift` (trước): (a) `changeType` đổi `visualType`, giữ `x`, `y`, `width`, `height`, `z`; `fields` và `raw` cùng cập nhật; một bước hoàn tác, hoàn tác trả đủ trường và `objects`; (b) cặp thanh ↔ đường ↔ cột 100% giữ nguyên ô và thứ tự; combo → đường: `Y2` → `Y` hoặc bỏ theo R7 và `notice` liệt kê; (c) trường bị bỏ còn được nhắc ở sắp xếp → chặn, tài liệu không đổi, `fieldRefusal` có lý do; (d) đổi sang chính loại hiện tại không tạo bước; (e) từ chối ở chế độ chọn nhiều visual, visual trong nhóm, loại đích chưa hỗ trợ, và khi visual nguồn thuộc loại chưa hỗ trợ (image, nút, điều hướng trang, hình): chọn rồi bấm biểu tượng khác thì không đổi gì và nêu lý do; (e2) đổi combo có hierarchy ở `Category` sang đường (giữ cấp hierarchy nếu nhận) và sang donut (bỏ và báo nếu ô không nhận); (f) `objects` chỉ giữ khoá thấy trên visual cùng loại đích trong báo cáo, `notice` nói khoá nào bị bỏ; (g) đổi loại visual mới (trong `added`) cập nhật `added[id]`.

### Cài đặt

- [X] T021 [US3] `LayoutEditor.swift`: `PageEdit.retyped`, `changeType(of:to:)` theo hợp đồng (dùng `TypeChange.plan`, `PBIRVisualPatch.setVisualType`, `PBIRQueryPatch.apply`, phân tích lại để cập nhật `type`, `objects`, `containerObjects`, `fields`, `raw` của `ReportVisual`; `commit` đặt `retyped[id]` và `queries[id]` cho visual trong file, `added[id]` cho visual mới); `json(of:)` áp `retyped` để nhân bản và dán dùng đúng bản đã đổi; khoá `objects` thấy trong báo cáo lấy từ `baseline` (tính một lần). T020 phải qua.
- [X] T022 [US3] `DocumentState.swift`, `ReportPanes.swift`, `BuildWells.swift`: khi chọn đúng một visual, bấm biểu tượng khác trong thư viện gọi `changeType`; biểu tượng của loại hiện tại được chọn sẵn; loại không hỗ trợ mờ; thông báo (`notice`, `fieldRefusal`) hiện dưới các ô trường.
- [X] T023 [US3] Chạy app, thao tác thật theo `quickstart.md` mục 2 bước 4 và 5; chụp cửa sổ app vào `docs/phase-d-evidence/vm-d3/`; sửa lỗi gặp.

## Giai đoạn 5: Câu chuyện 2 (P1): lưu và mở lại được trong Power BI Desktop

**Mục tiêu**: ⌘S ghi visual mới và visual đã đổi loại; mở lại trong BI Pro và Power BI Desktop đúng loại, chỗ, trường và cùng số.

### Test trước

- [X] T024 [US2] Mở rộng `Tests/BIProTests/Edit/DocumentSaverTests.swift` và tạo `Tests/BIProTests/Edit/NewVisualSavingTests.swift` (trước): (a) `makeChanges` thêm một `addedParts` cho mỗi visual mới (đặt sau `visual.json` cuối của trang), mọi phần khác chỉ đổi khi có sửa; (b) lưu rồi `loadReport()`: loại, khung, `z`, ô và trường của visual mới giống `LayoutEditor`; (c) visual đã có đổi loại: `visualType`, `queryState`, `objects` đúng, `visualContainerObjects` và `position` không đổi, phần còn lại giữ byte; (d) thêm rồi xoá visual mới trước khi lưu: không có trong file; (e) lưu lần hai sau khi sửa thêm (thả trường, đổi loại tiếp, dời) đúng, vì `makeChanges` so với byte trên đĩa; (f) `verifyLayout` bắt được lệch `type` (giả lập phần ghi sai); (g) `SecurityBindings` bị bỏ như D1; (h) visual mới chưa có trường vẫn được ghi (không ghi ô rỗng).

### Cài đặt

- [X] T025 [US2] `LayoutEditor.makeChanges`: với visual có trong file áp theo thứ tự R10 (`setVisualType` + tỉa `objects` → `setText` → `PBIRQueryPatch.apply` → `setPosition`), kết quả khác byte đang có thì vào `reportParts`; visual mới đã đi qua `added` (D1) nên chỉ ghép vị trí. `DocumentSaver.verifyLayout`: kiểm thêm `type` và (hộp văn bản) văn bản theo hợp đồng. T024 phải qua.
- [X] T026 [US2] Test nặng trong `Tests/BIProTests/Edit/D3Nhom6Tests.swift` (`BIPRO_HEAVY=1`, tên có "D3Nhom6"): trên Nhom6 thật thêm một card và một biểu đồ thanh nhóm vào trang D1, thả trường (measure vào card, cột và measure vào biểu đồ), đổi loại ba cặp giữ được trường (đường → thanh nhóm, combo → đường, donut → treemap), sửa chữ một hộp văn bản, lưu qua `DocumentSaver` vào `build/d-out/D3/Nhom6_d3.pbix`, mở lại, so loại/ô/trường/vị trí; chạy truy vấn của từng visual đã sửa qua engine và so với truy vấn trước khi lưu (giống hệt); số card mới khớp truy vấn DAX viết tay (như `soLieuCardSauKhiDoiTruongKhopDAXVietTay` của D2); `unzip -t`; mọi thành viên không nằm trong thay đổi khớp CRC (trừ `SecurityBindings` và `[Content_Types].xml` như D1); đo thời gian lưu (dưới 1 s, thử lại tối đa hai lần như D2 khi máy tải).
- [X] T027 [US2] Viết `build/d-out/D3/CHECKLIST.md` (mô tả các thay đổi trong `Nhom6_d3.pbix`; mục cần kiểm: mở được, visual mới đúng loại và vị trí, visual đổi loại vẽ đúng, số liệu cùng BI Pro, hộp văn bản đúng chữ, bookmark còn chạy, D2 D3 D4 không đổi, Save trong Desktop không lỗi). Báo bạn mở file trên VM. Điểm dừng mềm: chốt lát khi bạn báo đạt.

## Giai đoạn 6: Câu chuyện 4 (P2): hộp văn bản và các nút ribbon

- [X] T028 [US4] Tạo `Tests/BIProTests/Edit/TextboxEditingTests.swift` (trước): (a) `insertVisual(.textbox)` có một đoạn mặc định, `objects` của `ReportVisual` có `general`; (b) `setText` đổi nội dung, `objects` và `raw` cùng cập nhật (hộp văn bản vẽ từ `objects`), giữ kiểu chữ của đoạn một lượt; thêm và bớt dòng; một bước hoàn tác; (c) nhiều lần gõ liên tiếp trong 0,5 s gộp thành một bước (nếu có gộp) hoặc mỗi lần "xong chỉnh" một bước; (d) lưu rồi mở lại giữ nội dung; (e) từ chối khi visual không phải hộp văn bản.
- [X] T029 [US4] `LayoutEditor.setText(_:visual:)` và `PageEdit.texts`; cập nhật `ReportVisual.objects` từ byte mới (không chỉ `raw`); `BuildWells`: ô `TextEditor` "Nội dung" khi chọn hộp văn bản ở chế độ Sửa, `commit` khi mất tiêu điểm hoặc ⌘↩, chế độ Xem chỉ đọc. T028 phải qua.
- [X] T030 [US4] `Sources/BIPro/Shell/Ribbon.swift`: nút "Visual mới" (card) và "Hộp văn bản" ở Trang chủ và Chèn gọi `DocumentState.insertVisual`; mờ kèm `.help` ở chế độ Xem; bỏ nhãn "Phase D" ở hai nút này. Chạy app thử và chụp cửa sổ app (hộp văn bản mới, sửa chữ, lưu, mở lại).

## Giai đoạn 7: Câu chuyện 5 (P2): hoàn tác chung

- [X] T031 [US5] Mở rộng `Tests/BIProTests/Edit/FieldEditingUndoTests.swift` (trước): chuỗi ngẫu nhiên 150 thao tác trộn D1 (kéo, đổi cỡ, xoá, nhân bản), D2 (thêm, bỏ, đổi thứ tự, chuyển ô, đổi tên trường) và D3 (thêm visual loại ngẫu nhiên, đổi loại ngẫu nhiên, sửa văn bản hộp văn bản), hoàn tác hết về trạng thái đầu (`page` và `edited` bằng nhau, không còn dấu sửa), làm lại hết về trạng thái cuối; thêm ca: thêm visual, thả trường, đổi loại, dời, xoá rồi ⌘Z từng bước; nhân bản và xoá visual mới; lưu rồi sửa tiếp visual mới đã lưu. Sửa `LayoutEditor` cho qua nếu có lỗi.

## Giai đoạn 8: Phần chặn bởi VM-D3

- [x] T033 [US3] *VM-D3 đã xong 2026-11-10 (xem research.md R16)*. Khi `docs/phase-d-evidence/vm-d3/` có kết quả: cập nhật `research.md` R3, R4, R5, R7, R8, R9 theo quan sát (khoá `visual.json` mới Desktop ghi, `queryState` rỗng, cỡ và vị trí mặc định, ánh xạ ô khi đổi loại, giữ hay bỏ `objects`, hộp văn bản mặc định). Mỗi mục [SUY ĐOÁN] đã chốt thì đổi thành "đã quan sát" kèm tên file `R-D3-*.pbix`.
- [x] T034 [US1] *Xong một phần 2026-11-10: cột nhóm `clusteredColumnChart` và cột xếp chồng `columnChart`; các loại thanh xếp chồng/vùng/… chờ bộ vẽ*. Mở thêm loại cột/thanh/vùng (cột nhóm, cột và thanh xếp chồng, 100% thanh, vùng, vùng xếp chồng, ribbon, waterfall, funnel, pie…) mà VM-D3 đã cho tên ô: thêm vào bảng `observed` của `WellRules`, `VisualTypes.supported`, cỡ mặc định, kèm test trước (`WellRulesTests`, `VisualTypesTests`, `TypeChangeTests` thêm cặp cột nhóm ↔ thanh nhóm ↔ đường); loại nào VM-D3 chưa cho thì giữ chặn.
- [x] T035 [US3] *Xong một phần 2026-11-10: ô `Y2` của đường, giữ Y2, giữ cấp Category/Group, giữ `objects` trừ khoá không hợp lệ; chưa đổi: cỡ/vị trí mặc định (giữ thiết kế riêng của BI Pro), `sortDefinition` mặc định, `cardVisual`*. Chỉnh theo quan sát: `PBIRNewVisual` (khoá bắt buộc, cỡ mặc định, hộp văn bản), `PBIRQueryPatch` (ô rỗng), `TypeChange` (bảng cặp ô cho phép, giữ `objects`), vị trí đặt visual mới; mỗi chỗ có test trước. Chỗ nào VM-D3 chưa cho biết thì giữ phương án thận trọng và ghi vào `STATE.md`.

## Giai đoạn 9: Hoàn thiện

- [X] T036 Cập nhật `docs/phase-d-ownership.tsv` (file D3 mới: `PBIRNewVisual.swift`, `PBIRVisualPatch.swift`, `VisualTypes.swift`, `TypeChange.swift`, các test), `docs/STATE.md` (mục D3 gọn, phần chờ bạn), `docs/BIPRO_BUILD_PLAN.md` (Phase D: tick lát D3 phần đã xong, ghi phần còn chặn).
- [X] T037 Chạy golden nặng: `BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --filter "Nhom6|ORA|VIS|D3Nhom6|D2Nhom6|EditNhom6|BatchedSerial"`; 30/30 golden Phase B và số khớp Phase C giữ nguyên; `D3Nhom6`, `D2Nhom6`, `EditNhom6` qua. Ghi vào `measurements.md` (SC-005, SC-006).
- [X] T038 Chạy `swift test` toàn bộ: không test nào trượt thêm so với 968; không cảnh báo biên dịch mới.
- [X] T039 Visual không sửa, trang không sửa và mô hình dữ liệu khớp byte (SC-004): kiểm trong `D3Nhom6Tests.swift` (trừ `SecurityBindings` và `[Content_Types].xml`).
- [X] T040 Bấm thử toàn bộ `quickstart.md` mục 2 trong app thật; chụp cửa sổ app các bước chính vào `docs/phase-d-evidence/vm-d3/`; sửa lỗi gặp.
- [X] T041 Chạy `/speckit-converge` cho `specs/004-d3-them-visual-doi-loai/`; xử lý việc nó thêm vào.
- [X] T042 Xoá mọi mã thử tạm (`/tmp/d3-viewport.log`, ghi log của T001); `grep -rni "d3-viewport\|spike" Sources/` rỗng; xoá bản sao Nhom6 ở Desktop.
- [X] T043 Báo bạn: kết quả, file `build/d-out/D3/Nhom6_d3.pbix` và `CHECKLIST.md`, việc còn chặn bởi VM-D3 (nếu có). Không commit trừ khi bạn bảo.

## Phụ thuộc và thứ tự

- Giai đoạn 1 (T001 đến T003) trước; T001 là cổng mềm, T003 chạy nền (bạn làm VM-D3 song song).
- Giai đoạn 2 chặn mọi câu chuyện (T014). Trong giai đoạn 2, test trước mã (T004 → T005, T006 → T007, T008, T009, T010).
- Giai đoạn 3 (US1) → 4 (US3) → 5 (US2) → 6 (US4) → 7 (US5). US3 dùng `insertVisual` của US1 để thử trên visual mới.
- T012 và T027 là điểm dừng mềm: cần bạn thử file trước khi chốt giai đoạn 5 và 9, nhưng không chặn các giai đoạn trước.
- T033 đến T035 chỉ chạy khi `docs/phase-d-evidence/vm-d3/` có kết quả; trước đó giữ chặn (không đoán), phần còn lại của lát vẫn hoàn tất. Số hiệu T032 bỏ trống có chủ ý (không có việc T032).
- T041 (converge) sau khi mọi việc khác xong; T042, T043 cuối.

## Phủ yêu cầu

| Yêu cầu | Task |
|---|---|
| FR-001, FR-002 | T004, T005, T015, T016, T017, T018 |
| FR-003 | T030 |
| FR-004 | T009, T018, T034 |
| FR-005 | T008, T015, T016 |
| FR-006, FR-007 | T010, T020, T021, T022 |
| FR-008 | T010, T020, T021 |
| FR-009 | T006, T007, T010, T020, T035 |
| FR-010 | T020, T022 |
| FR-011 | T006, T007, T028, T029 |
| FR-012, FR-013 | T015, T031 |
| FR-014, FR-015 | T004 đến T008, T024, T025, T026 |
| FR-016 | T024, T025 |
| FR-017 | T026, T039 |
| FR-018 | T037, T038 |
| SC-001 | T026 |
| SC-002 | T024, T026 |
| SC-003 | T012, T027 (bạn kiểm tay) |
| SC-004 | T025, T039 |
| SC-005 | T019, T026, T037 |
| SC-006 | T037, T038 |
| SC-007 | T031 |
| SC-008 | T019, T040 |

## Chiến lược

- **MVP** = giai đoạn 1 đến 5: thêm visual, đổi loại, lưu, mở lại được. Giai đoạn 6 (hộp văn bản, ribbon) và 7 (hoàn tác chung mở rộng) thêm sau, mỗi giai đoạn dừng được.
- Phần cần VM-D3 (T033 đến T035) không chặn MVP.
- Nếu T012 hoặc T027 trượt thì dừng và báo bạn, không tự đổi hướng. Nếu Power BI Desktop từ chối file: dùng cách chia đôi như D1 (`build/d-out/D1-bisect/`), đừng đoán.
