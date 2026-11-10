---
description: "Danh sách việc: D2, sửa trường của visual bằng Build pane và lưu .pbix tầng T1"
---

# Việc cần làm: D2, sửa trường của visual và lưu T1

**Đầu vào**: `specs/003-d2-build-pane-field-well/` (spec.md, plan.md, research.md, data-model.md, contracts/field-editing.md, contracts/query-state-patch.md, quickstart.md)

**Kiểm thử**: spec yêu cầu (FR-008 đến FR-017, SC-001 đến SC-007): test thuần cho luật ô, thao tác trường, ghép byte, hoàn tác đan xen với D1; test nặng trên Nhom6 (sửa, lưu, mở lại, so với truy vấn DAX); golden Phase B/C chạy lại. Test viết trước, thấy trượt rồi mới viết mã.

**Người làm**: lead tự làm, tuần tự, không giao agy (xem `plan.md`, Hiến pháp V: `LayoutEditor`, `ReportPanes`, `LiveVisual` giao nhau). Vì vậy không có việc `[P]`.

**Quy ước**: `[US1]` đến `[US5]` là câu chuyện trong spec. Thứ tự giai đoạn: nền tảng, US1 (thêm/bỏ), US3 (hoàn tác), US2 (lưu), US4 (đổi thứ tự, chuyển ô), US5 (đổi tên, phép gộp). Lệnh build/test là các lệnh trong `CLAUDE.md`. Fixture: `~/Downloads/bipro-golden/Nhom6_work.pbix` hoặc `BIPRO_NHOM6`. Không commit trừ khi bạn bảo. File sinh ra nằm ở `build/d-out/`; không ghi vào `~/Downloads`.

**Phần cần bạn (VM-D2)**: buổi quan sát ngắn ở T004; chạy song song với giai đoạn 2 đến 5. Chỉ chặn: T032 (phép gộp), T033 (bỏ trường còn nằm trong sắp xếp/bộ lọc/định dạng), T034 (nâng ô từ `unverified` lên `observed`), sau khi T031 đọc kết quả. Chưa có kết quả thì các việc đó giữ trạng thái chặn, phần còn lại của lát vẫn xong được.

## Giai đoạn 1: Chuẩn bị

- [X] T001 Cổng R9, bước thử kéo thả: viết mã thử tạm `Sources/BIPro/Report/Edit/SpikeFieldDrag.swift` (xoá ở T041): một `FieldRef` (`NSItemProvider`) kéo từ một hàng của `DataPane` thả vào một ô của Build pane (`ReportPanes.swift`) trong cửa sổ `DocumentGroup(viewing:)` thật; thử cả kéo trong Build pane (đổi thứ tự). Chụp cửa sổ app, ghi kết quả vào `research.md` R9. **Cổng**: kéo từ pane Dữ liệu sang Build pane và kéo trong Build pane đều làm được. Một trong hai không làm được thì dừng, báo bạn kèm phương án (menu "Thêm trường" và ô tick làm đường chính), không tự đổi cách dựng cửa sổ.
- [X] T002 Rà soát nơi đọc `visual.fields` và `visual.raw`: `grep` trong `Sources/BIPro/` (`usedFields` của `DocumentState`, Selection pane, `ReportInteraction` cache theo visual, `VisualQuerySpecReader`, `VisualDataLoader`, `LiveVisualView`, Filters pane, drillthrough). Thêm mục `## R15. Nơi đọc trường của visual` vào `research.md` và lập danh sách ở đó: mỗi dòng ghi "đọc từ `state.page` (bản sửa)" hoặc "giữ bản gốc vì …", và nơi nào giữ cache cần xoá khi visual đổi trường.
- [X] T003 Đo mốc trước khi sửa: viết test nặng tạm trong `Tests/BIProTests/Edit/D2Nhom6Tests.swift` (giữ lại và mở rộng ở T025) đo thời gian nạp DataView (`VisualDataLoader`) của 5 visual nặng nhất trang D1 (combo, donut, matrix…), 5 lần mỗi visual; ghi bảng "Trước khi sửa" vào `specs/003-d2-build-pane-field-well/measurements.md` (file mới). Đây là mốc cho SC-005 (vẽ lại dưới 150 ms).
- [X] T004 Chuẩn bị buổi VM-D2: tạo `docs/phase-d-evidence/vm-d2/` (thư mục) và `build/d-out/D2/VM-D2-QUAN-SAT.md` (viết như `VM-D1-QUAN-SAT.md`: tám bước của `research.md` R14, mỗi bước làm trên bản gốc mới, đổi một thứ, Lưu thành `R-D2-<chữ>-<tên>.pbix`, chỗ ghi số liệu; bước 9: chép truy vấn Performance Analyzer của mỗi visual đã sửa vào `R-D2-<chữ>-query.txt`). Báo bạn bắt đầu làm; kết quả bạn đặt vào `docs/phase-d-evidence/vm-d2/`. Không chờ kết quả để làm các việc khác.

## Giai đoạn 2: Nền tảng ghi và luật (chặn mọi câu chuyện)

**Quan trọng**: chưa làm giao diện trước khi qua T014.

- [X] T005 Tạo `Tests/PBIXKitTests/PBIRQueryPatchTests.swift` (test trước, phải thấy trượt): trên `visual.json` mẫu (dạng gọn và dạng có thụt lề; lấy từ `SyntheticPBIX` và một `visual.json` thật trích từ Nhom6) kiểm theo `contracts/query-state-patch.md`: (a) `.keep` chép nguyên byte phần tử, giữ `active` và khoá lạ; (b) `.new` cột và measure sinh đúng mẫu R6, thoát ký tự đặc biệt (`"`, `\`, Unicode tiếng Việt); (c) thêm vào ô có sẵn, tạo ô mới (đúng dấu phẩy), ô thành trống thì bỏ khoá; (d) đổi thứ tự và chuyển phần tử giữa hai ô; (e) `renamed` đặt, đổi, bỏ `displayName` mà không đụng `queryRef`; (f) phần còn lại của tài liệu giữ nguyên từng byte (so với bản đã thay đúng đoạn); (g) lỗi `WriteError.invalid` cho đầu vào sai (không có `queryState`, chỉ số ngoài phạm vi, tên rỗng, trùng `queryRef` trong ô); (h) áp "đổi rồi đổi lại" ra đúng byte gốc.
- [X] T006 `Sources/PBIXKit/ReportDefinition.swift`: `ReportField` thêm `nativeQueryRef: String?` và `active: Bool?` (mặc định nil, không đổi chữ ký hiện có); `parseFields` đọc hai khoá. Test đọc trong `Tests/PBIXKitTests/` (một `visual.json` có và không có hai khoá; Nhom6: 171 trường, `nativeQueryRef` 171, `active` 115).
- [X] T007 Tạo `Sources/PBIXKit/Writing/PBIRQueryPatch.swift` theo `contracts/query-state-patch.md`: `apply(to:wells:)`, `WellEdit`/phần tử `.keep`/`.new`, sinh phần tử theo mẫu R6 với cách trình bày của tài liệu, thêm/bỏ khoá ô, kiểm lại bằng so cấu trúc (như `PBIRLayoutPatch`). Dùng lại `JSONCursor.children/string/removing`. T005 phải qua.
- [X] T008 Tạo `Tests/BIProTests/Edit/WellRulesTests.swift` (trước) rồi `Sources/BIPro/Report/Edit/WellRules.swift`: bảng `WellRule` theo `data-model.md`; 30 tổ hợp (loại visual, ô) của R1 đều `observed` và nhận đúng loại trường, số tối đa đúng; mọi tổ hợp khác của `VisualCatalog.wells` có trong bảng ở mức `unverified`; hàm `canAdd(field, to:)` trả lý do tiếng Việt khi từ chối (loại không nhận, ô đầy, trùng, chưa kiểm, cột số vào ô giá trị chờ phép gộp). `VisualCatalog.wells` lấy nhãn từ `WellRules`.
- [X] T009 Tạo `Tests/BIProTests/Edit/FieldReferencesTests.swift` (trước) rồi `Sources/BIPro/Report/Edit/FieldReferences.swift`: `find(in: visualJSON, for: field)` trả các `FieldReference` (sort, filter, format) theo R7; test trên đoạn `visual.json` thật trích từ Nhom6 (một visual có `sortDefinition`, visual có `filterConfig` dùng bí danh `Source`, visual có `selector.metadata`), visual không nhắc thì rỗng, trường cùng tên khác bảng không bị nhầm.
- [X] T010 Tạo `Tests/BIProTests/Edit/FieldEditorTests.swift` (trước) rồi `Sources/BIPro/Report/Edit/FieldEditor.swift`: các hàm thuần trên `QueryEdit` theo `contracts/field-editing.md`: thêm (cuối ô; ô một trường thì thay), bỏ (chặn khi `FieldReferences` còn nhắc và không còn phần tử cùng `queryRef`), đổi thứ tự, chuyển ô (giữ phần tử đã có), đổi tên (rỗng hoặc bằng tên gốc: bỏ `displayName`); mỗi thao tác trả kết quả hoặc lý do từ chối; không đổi gì thì trả "không đổi".
- [X] T011 `Sources/pbix-dump/main.swift`: lệnh phụ `add-field <in> <visualID> <ô> <bảng> <tên> <column|measure> <out>`, `remove-field <in> <visualID> <ô> <chỉ số> <out>`, `move-field <in> <visualID> <ôNguồn> <chỉ số> <ôĐích> <out>` (T1, dùng `PBIRQueryPatch`, như `move-visual` của D1) để làm file kiểm tay sớm.
- [X] T012 Dựng file kiểm tay sớm `build/d-out/D2/Nhom6_d2_pre.pbix` bằng ba lệnh ở T011 trên Nhom6 (thêm một measure vào Trục Y của một biểu đồ cột, bỏ một measure ở Tooltips, chuyển một measure giữa Y và Y2 của một combo) và `build/d-out/D2/CHECKLIST-pre.md` (mở được, ô đúng trường, số liệu đúng, Save không lỗi). Báo bạn thử trên VM. Đây là điểm dừng mềm: chưa chốt giai đoạn 5 trước khi biết file mở được; không chặn giai đoạn 3 và 4.
- [X] T013 Chạy lại `swift test`: T005 đến T010 qua, không test nào trượt thêm. Ghi số test vào `measurements.md`.
- [X] T014 Cổng nền tảng: T005 đến T013 xong. Không qua thì không sang giai đoạn 3.

## Giai đoạn 3: Câu chuyện 1 (P1): thêm và bỏ trường của visual

**Mục tiêu**: chọn một visual, kéo trường vào ô hoặc bỏ trường khỏi ô, visual vẽ lại ngay.

**Kiểm thử độc lập**: trên Nhom6 thêm một measure vào Trục Y của biểu đồ cột ở trang D1: biểu đồ đổi và số khớp truy vấn DAX tương ứng. Chưa cần lưu.

### Test trước

- [X] T015 [US1] Tạo `Tests/BIProTests/Edit/FieldEditingTests.swift` (trước): với `LayoutEditor` trên báo cáo mẫu (`SyntheticReport`): (a) `addField` thêm vào cuối ô, `ReportVisual.fields` và `raw["visual"]["query"]["queryState"]` cùng cập nhật; (b) `removeField` bỏ khỏi ô; bỏ trường còn dùng để sắp xếp thì từ chối với lý do và tài liệu không đổi; (c) ô một trường thì thay; (d) từ chối ô không nhận / ô `unverified`; (e) ô cuối cùng trống thì visual ở trạng thái "trống" (không ném lỗi); (f) mỗi thao tác đúng một bước hoàn tác; (g) chọn nhiều visual hoặc visual trong nhóm thì từ chối sửa.

### Cài đặt

- [X] T016 [US1] `Sources/BIPro/Report/Edit/LayoutEditor.swift`: `PageEdit` thêm `queries: [String: QueryEdit]`; hàm `addField(_:to:visual:)`, `removeField(at:in:visual:)`, `fieldRefusal` (lý do) qua `commit`; sau mỗi thao tác gọi `PBIRQueryPatch.apply` trên byte `visual.json` gốc (lấy bằng `json(of:page:)` của D1; nếu visual đã có sửa thì chạy từ cấu hình hiện tại) rồi phân tích lại để cập nhật `ReportVisual.raw` và `fields`. T015 phải qua.
- [X] T017 [US1] `Sources/BIPro/Report/LiveVisual.swift` và `Sources/BIPro/Report/ReportInteraction.swift`: `LoadKey` thêm băm của `visual.raw["visual"]["query"]`; xoá cache của visual đã đổi trường (theo kết quả T002); visual hết trường bắt buộc hiện placeholder "Thêm trường để vẽ" thay vì lỗi truy vấn. Test: đổi trường thì đúng visual đó nạp lại (đếm số lần nạp theo visual trên báo cáo mẫu).
- [X] T018 [US1] `Sources/BIPro/Panes/ReportPanes.swift` (Build pane): ô nhận thả (`onDrop`) và hiện lý do khi từ chối; mỗi trường có nút bỏ; mỗi ô có menu "Thêm trường" liệt kê trường của mô hình hợp lệ cho ô; chế độ chỉ xem kèm lý do (chọn nhiều visual, visual trong nhóm, định dạng cũ, chế độ Xem, không chọn visual).
- [X] T019 [US1] `Sources/BIPro/Panes/DataPane.swift`: hàng cột và measure kéo được (`FieldRef`), ô tick thêm hoặc bỏ trường vào ô mặc định của loại visual (đầu tiên nhận được, theo thứ tự trong `WellRules`); trường đang dùng tick theo `state.page` đã sửa.
- [X] T020 [US1] Chạy app, thao tác thật theo `quickstart.md` mục 2 bước 1 đến 4; chụp cửa sổ app (chỉ cửa sổ, theo quy ước) vào `docs/phase-d-evidence/vm-d2/`; đo thời gian vẽ lại của 5 visual nặng ở T003 sau khi đổi trường, ghi vào `measurements.md`; sửa nếu vượt ngưỡng của SC-005 (150 ms visual thường, 1 s visual nặng).

## Giai đoạn 4: Câu chuyện 3 (P1): hoàn tác và làm lại chung với D1

**Mục tiêu**: ⌘Z / ⇧⌘Z hoàn tác và làm lại sửa trường chung lịch sử với kéo, đổi cỡ, xoá, nhân bản.

- [X] T021 [US3] Tạo `Tests/BIProTests/Edit/FieldEditingUndoTests.swift` (trước): (a) thêm trường, dời visual, bỏ trường, ⌘Z ba lần quay về đúng trạng thái đầu từng bước, ⇧⌘Z đi lại; (b) một lần thả là một bước; (c) về trạng thái lúc mở thì `isDirty == false`; (d) chuỗi ngẫu nhiên 200 thao tác trộn của D1 (kéo, đổi cỡ, xoá, nhân bản) và D2 (thêm, bỏ, đổi thứ tự, chuyển ô, đổi tên) rồi hoàn tác hết: trạng thái bằng trạng thái đầu (cả `queries` và `visuals`), làm lại hết: bằng trạng thái cuối; (e) xoá hoặc nhân bản visual đã sửa trường rồi hoàn tác: trường quay lại đúng.
- [X] T022 [US3] Sửa `LayoutEditor` cho T021 qua (nếu cần): `queries` đi theo `duplicate`/`paste` (bản sao mang cấu hình trường của gốc) và `delete`; `makeCopies` dùng `visual.json` đã sửa khi có; `restore` đặt lại `visual.raw`/`fields` cùng `queries`. Build pane nhận ⌘Z, ⇧⌘Z khi tiêu điểm đang ở pane (không bị ô nhập tên ăn mất khi đang gõ).

## Giai đoạn 5: Câu chuyện 2 (P1): lưu và mở lại được trong Power BI Desktop

**Mục tiêu**: ⌘S ghi `queryState` của các visual đã sửa; mở lại trong BI Pro và Power BI Desktop đúng trường và cùng số.

### Test trước

- [X] T023 [US2] Mở rộng `Tests/BIProTests/Edit/LayoutEditorTests.swift` và `Tests/BIProTests/Edit/DocumentSaverTests.swift` (trước): (a) `makeChanges` có `reportParts` chỉ cho visual đã sửa trường; visual chưa sửa không có phần; (b) sửa trường kết hợp dời visual cho cùng một `visual.json`: cả hai đúng; (c) lưu rồi `loadReport()`: ô, trường, thứ tự, `displayName` khớp `LayoutEditor`; (d) lưu hai lần liên tiếp (lần hai chỉ đổi thêm một trường) đúng, vì `makeChanges` so với file đang có trên đĩa; (e) `verifyLayout` bắt được lệch trường (giả lập một phần ghi sai); (f) phần ngoài `queryState` của visual đã sửa giữ nguyên byte; (g) `SecurityBindings` bị bỏ như D1.

### Cài đặt

- [X] T024 [US2] `LayoutEditor.makeChanges`: với `queries[id]`, chạy `PBIRQueryPatch.apply` rồi mới ghép vị trí (nếu có) trên `visual.json` đang có trên đĩa. `DocumentSaver.verifyLayout`: kiểm cả trường theo `contracts/query-state-patch.md` mục "Kiểm tra khi lưu". T023 phải qua.
- [X] T025 [US2] Test nặng `Tests/BIProTests/Edit/D2Nhom6Tests.swift` (`BIPRO_HEAVY=1`, tên có "D2Nhom6"): trên Nhom6 thật sửa bốn loại visual (card không có thao tác được ngoài đổi tên; biểu đồ cột: thêm measure vào Y; combo: chuyển measure Y sang Y2; matrix: bỏ một measure ở Values và đổi thứ tự cột), lưu qua `DocumentSaver` vào `build/d-out/D2/Nhom6_d2.pbix`, mở lại, so ô/trường; chạy truy vấn của từng visual đã sửa qua engine và so với truy vấn DAX viết tay cho cùng cấu hình (SC-001), và, khi `docs/phase-d-evidence/vm-d2/` có `R-D2-*-query.txt`, so văn bản truy vấn sinh ra với mẫu của Desktop (FR-017); `unzip -t`; mọi thành viên không nằm trong thay đổi khớp CRC (trừ `SecurityBindings` và `[Content_Types].xml` như D1); đo thời gian lưu (SC-005, dưới 1 s).
- [X] T026 [US2] Viết `build/d-out/D2/CHECKLIST.md` (mô tả các thay đổi trong `Nhom6_d2.pbix`; mục cần kiểm: mở được, các ô đúng trường, số liệu cùng BI Pro, bookmark còn chạy, Save trong Desktop không lỗi, D2 D3 D4 không đổi; chỗ báo đạt/trượt như `CHECKLIST.md` của D1). Báo bạn mở file trên VM. Điểm dừng mềm: chốt lát khi bạn báo đạt.

## Giai đoạn 6: Câu chuyện 4 (P2): đổi thứ tự trường và chuyển trường giữa các ô

- [X] T027 [US4] Mở rộng `FieldEditingTests.swift` (trước): đổi thứ tự trong ô (thứ tự `projections` đổi, `queryRef` không đổi, nạp lại theo thứ tự mới); chuyển giữa Y và Y2 của combo (giữ nguyên byte phần tử); chuyển sang ô không nhận thì từ chối và trường ở chỗ cũ; chuyển trường làm ô cũ trống thì ô cũ bị bỏ khỏi `queryState`; hierarchy chuyển trong cùng loại ô thì giữ nguyên byte.
- [X] T028 [US4] `LayoutEditor` (`moveField`, `reorderField`) và Build pane: kéo trường lên xuống trong ô, kéo sang ô khác (một lần thả một bước); thêm kịch bản "đổi thứ tự và chuyển ô" vào `D2Nhom6Tests.swift` (T025 đã có chuyển Y → Y2) và chụp cửa sổ app.

## Giai đoạn 7: Câu chuyện 5 (P2): đổi tên hiển thị và phép gộp

**Mục tiêu**: đổi tên hiển thị riêng cho visual (không cần VM); phép gộp sau khi VM-D2 cho mẫu.

- [X] T029 [US5] Mở rộng `FieldEditingTests.swift` (trước): đổi tên đặt `displayName`; đổi tên rỗng hoặc bằng tên gốc bỏ khoá; `queryRef` không đổi; sắp xếp, bộ lọc, định dạng theo trường vẫn trỏ đúng sau đổi tên; lưu rồi mở lại giữ tên.
- [X] T030 [US5] `LayoutEditor.renameField` và Build pane (ô nhập tên trong menu ngữ cảnh của trường, "Rename for this visual"); `ReportField.label` đã dùng `displayName`. Thêm kịch bản đổi tên vào `D2Nhom6Tests.swift`.
- [x] T031 [US5] *VM-D2 đã đọc 2026-11-10 (research.md R16)*. Khi có `docs/phase-d-evidence/vm-d2/`: cập nhật `research.md` R6, R7, R8, R5 theo quan sát (cấu trúc `Aggregation`, mã `Function`, ô nhận gì, Desktop xử lý sắp xếp/bộ lọc/định dạng ra sao, ô trống, thêm trùng). Mỗi mục [SUY ĐOÁN] đã chốt thì đổi thành "đã quan sát" kèm tên file `R-D2-*.pbix`.
- [x] T032 [US5] *Kết luận 2026-11-10: Nhom6 bật discourage implicit measures nên Desktop không có phép gộp ngầm; BI Pro từ chối cột số ở ô giá trị với lý do đó*. Phép gộp (D2b): test trước (`PBIRQueryPatchTests`, `WellRulesTests`, `FieldEditingTests`: cột số thả vào ô giá trị có phép gộp mặc định theo `summarizeBy` của mô hình, đổi sang phép gộp hợp lệ cho kiểu dữ liệu, measure không có menu phép gộp, ghi đúng cấu trúc và mã `Function` quan sát được); rồi `PBIRQueryPatch` (`.newAggregated`), `FieldEditor`, `WellRules` (bỏ lý do "chờ phép gộp"), menu phép gộp ở Build pane; kịch bản mới trong `D2Nhom6Tests.swift` so số với `AVERAGE`/`SUM`… viết tay và văn bản truy vấn với mẫu `R-D2-*-query.txt` (FR-017). Nếu VM-D2 chưa có thì giữ chặn và ghi vào `STATE.md`, không đoán.
- [x] T033 [US5] *Xong 2026-11-10 (bỏ trường dọn định dạng, giữ bộ lọc, chỉ chặn khi có sắp xếp tường minh)*. Bỏ trường còn được nhắc ở sắp xếp, bộ lọc, định dạng (bỏ chặn của R7): làm đúng cách Desktop (ví dụ xoá `sortDefinition`, xoá thẻ lọc, xoá mục `metadata`); test trước trên đoạn `visual.json` thật, rồi `FieldReferences` và `PBIRQueryPatch`/`PBIRLayoutPatch` tương ứng. Loại tham chiếu nào VM-D2 chưa cho biết thì giữ chặn.
- [ ] T034 [US5] *Chặn bởi T031*. Nâng ô từ `unverified` lên `observed` trong `WellRules` cho mọi ô VM-D2 đã xác nhận Desktop nhận (kèm test); ô Desktop từ chối thì ghi lý do của Desktop.

## Giai đoạn 8: Hoàn thiện

- [X] T035 Cập nhật `docs/phase-d-ownership.tsv` (file D2 mới: `PBIRQueryPatch.swift`, `WellRules.swift`, `FieldReferences.swift`, `FieldEditor.swift`, các test), `docs/STATE.md` (mục D2 gọn, phần chờ bạn), `docs/BIPRO_BUILD_PLAN.md` (Phase D: tick lát D2 phần đã xong, ghi phần còn chặn).
- [X] T036 Chạy golden nặng: `BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --filter "Nhom6|ORA|VIS|D2Nhom6|EditNhom6"`; 30/30 golden Phase B và số khớp Phase C giữ nguyên; `D2Nhom6` qua. Ghi vào `measurements.md` (SC-005, SC-006).
- [X] T037 Chạy `swift test` toàn bộ: không test nào trượt thêm so với 914; xoá cảnh báo biên dịch mới.
- [X] T038 Visual không sửa, trang không sửa và mô hình dữ liệu khớp byte (SC-004): kiểm trong `D2Nhom6Tests.swift` (trừ `SecurityBindings` và `[Content_Types].xml`).
- [X] T039 Bấm thử toàn bộ `quickstart.md` mục 2 trong app thật; chụp cửa sổ app các bước chính vào `docs/phase-d-evidence/vm-d2/`; sửa lỗi gặp.
- [X] T040 Chạy `/speckit-converge` cho `specs/003-d2-build-pane-field-well/`; xử lý việc nó thêm vào.
- [X] T041 Xoá `Sources/BIPro/Report/Edit/SpikeFieldDrag.swift` và mọi mã thử tạm; `grep -rn "Spike" Sources/` rỗng.
- [X] T042 Báo bạn: kết quả, file `build/d-out/D2/Nhom6_d2.pbix` và `CHECKLIST.md`, việc còn chặn bởi VM-D2 (nếu có). Không commit trừ khi bạn bảo.

## Phụ thuộc và thứ tự

- Giai đoạn 1 (T001 đến T004) trước; T001 là cổng, T004 chạy nền (bạn làm VM-D2 song song).
- Giai đoạn 2 chặn mọi câu chuyện (T014). Trong giai đoạn 2, test trước mã (T005 → T007, T008, T009, T010).
- Giai đoạn 3 (US1) → 4 (US3) → 5 (US2) → 6 (US4) → 7 (US5). US1 và US3 độc lập nhau về mặt kiểm thử nhưng US3 dùng thao tác của US1 nên làm sau.
- T012 và T026 là điểm dừng mềm: cần bạn thử file trước khi chốt giai đoạn 5 và 8, nhưng không chặn các giai đoạn trước.
- T031 đến T034 chỉ chạy khi `docs/phase-d-evidence/vm-d2/` có kết quả; trước đó giữ chặn (không đoán), phần còn lại của lát vẫn hoàn tất.
- T040 (converge) sau khi mọi việc khác xong; T041, T042 cuối.

## Phủ yêu cầu

| Yêu cầu | Task |
|---|---|
| FR-001, FR-002, FR-003, FR-005 | T008, T010, T015, T016, T018, T019 |
| FR-004 | T027, T028 |
| FR-006 | T031, T032 |
| FR-007 | T029, T030 |
| FR-008 | T017, T020, T025 |
| FR-009, FR-010 | T021, T022 |
| FR-011, FR-012, FR-014, FR-015 | T005, T007, T023, T024, T038 |
| FR-013 | T009, T033 |
| FR-016 | T036, T037 |
| FR-017 | T025, T032 |
| SC-001 | T025, T032 |
| SC-002 | T023, T025 |
| SC-003 | T012, T026 (bạn kiểm tay) |
| SC-004 | T024, T038 |
| SC-005 | T003, T020, T025, T036 |
| SC-006 | T036, T037 |
| SC-007 | T021 |
| SC-008 | T020, T039 |

## Chiến lược

- **MVP** = giai đoạn 1 đến 5: thêm, bỏ, hoàn tác, lưu (chỉ phần đã quan sát trong Nhom6). Giai đoạn 6 và 7 thêm sau, mỗi giai đoạn dừng được.
- Phần cần VM-D2 (T031 đến T034) không chặn MVP.
- Nếu T001 hoặc T012 hoặc T026 trượt thì dừng và báo bạn, không tự đổi hướng. Nếu Power BI Desktop từ chối file: dùng cách chia đôi như D1 (`build/d-out/D1-bisect/`), đừng đoán.
