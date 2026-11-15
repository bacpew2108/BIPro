# Nhiệm vụ Phase E: mô hình hoá và lưu tầng T2

Định dạng: `- [ ] Txxx [P?] [USn] Mô tả (tệp)`. `[P]` = làm song song được (khác tệp, không phụ thuộc việc chưa xong). Kiểm: `swift build`, `swift test`, golden nặng (xem `quickstart.md`). Lead tự làm toàn bộ bằng `/tdd` (việc đụng sâu engine, metadata và hoàn tác chung nên không giao agy). Mỗi buổi VM-E cần bạn cho phép lần đó (hỏi lại khi bắt đầu); không có thì bạn làm tay theo checklist Claude chuẩn bị. Quan sát chưa có thì tính năng đó chỉ đọc "(chưa kiểm)" (FR-019).

Điều kiện chung cho mọi task đụng mô hình: ghi đúng như `contracts/model-editing.md`; tên, kiểu theo `data-model.md`; không thêm thư viện ngoài; file gốc `~/Downloads` chỉ đọc, thử trên bản sao `build/e-out/`.

## Giai đoạn 1: Chuẩn bị

- [X] T001 Tạo `docs/phase-e-ownership.tsv` (mô hình sửa được, ghi T2, Table/Model/TMDL View; mỗi tệp một chủ); đánh dấu Phase E "đang làm" ở `docs/BIPRO_BUILD_PLAN.md`
- [X] T002 [P] `Tests/BIProTests/Model/EFixtures.swift` và `Tests/PBIXKitTests/EFixtures.swift`: hàm chép `Nhom6_work.pbix` (`DAXFixtures.nhom6`/`BIPRO_NHOM6`) ra `build/e-out/` và bỏ qua test khi thiếu file; `docs/phase-e-evidence/` đã có `vm-e1/`

## Giai đoạn 2: Nền (chặn mọi câu chuyện)

- [X] T003 `Sources/PBIXKit/Writing/ModelEdit.swift`: `ModelEdit` (addMeasure, updateMeasure, deleteMeasure, updateRelationship, updateColumn, setDiagramLayout; chỗ cho add/deleteRelationship), `MeasurePatch`, `RelationshipPatch`, `ColumnPatch`, `ModelEdits` (có `merging`, `isEmpty`, `tier`), `ModelEditError(reason, objects)` theo `data-model.md` (trường `??` là đặt-hoặc-xoá); test `Tests/PBIXKitTests/ModelEditTests.swift`
- [X] T004 `Sources/PBIXKit/ModelMetadata.swift`: `applying(_ edits:) throws -> ModelMetadata`; kiểm hợp lệ đúng "Quy tắc kiểm hợp lệ" của `data-model.md` (tên measure không rỗng, không NUL, không trùng measure/cột/bảng không phân biệt hoa thường; cột sắp xếp cùng bảng và không phải chính nó; đối tượng tồn tại); test từng quy tắc và khôi phục về mô hình gốc khi `edits` rỗng
- [X] T005 `Sources/PBIXKit/Writing/MetadataWriter.swift`: `apply(_:)` và `updateMeasure`, `deleteMeasure`, `updateRelationship`, `updateColumn` đúng QUAN-SAT mục 1 đến 3 (UPDATE tại chỗ giữ `ID`, `LineageTag`, `StructureModifiedTime`; đặt `ModifiedTime`; cập nhật bốn `DBPROPERTIES`; không bắt chước tác dụng phụ `SummarizeBy`/`Annotation` của Desktop); `PRAGMA integrity_check` và `MAXID`; test `Tests/PBIXKitTests/MetadataWriterUpdateTests.swift` dùng `metadata.sqlitedb` của Nhom6 (đọc lại bằng `ModelMetadata` khớp `applying`)
- [X] T006 `Sources/PBIXKit/Writing/Contracts.swift`, `PBIXWriter.swift`: `PBIXChanges.modelEdits` (giữ `measures` chuyển thành `addMeasure`), `diagramLayout: Data?` (`build` thay member `DiagramLayout` giữ nguyên phương thức nén và `verify` đọc lại đúng bằng bytes đã ghi, không đụng `SecurityBindings` nếu chỉ bố cục đổi); `rebuiltDataModel` áp `ModelEdits`; `tier` đúng; `verify` thêm kiểm mô hình đọc lại bằng `applying` và các tệp ABF còn lại không đổi byte; test `Tests/PBIXKitTests/PBIXWriterEditTests.swift` (cập nhật)
- [X] T007 **Spike S0** (chạy song song với T003 đến T006, dùng `pbix-dump add-measure` sẵn có; chỉ chặn T017 và T018, không chặn US2 đến US5): lưu T2 một measure trên bản sao Nhom6 (51 MB): đo thời gian dựng/nén (mục tiêu dưới 3 s, SC-004), ghi `specs/009-e-mo-hinh-hoa-luu-t2/measurements.md`; mở file trong Desktop (buổi VM-E1b, cần bạn cho phép) kiểm không báo hỏng và `SecurityBindings` còn giữ được; nếu Desktop từ chối, bỏ `SecurityBindings` khi đổi `DataModel` như R13 của D1 (cập nhật `changesReport`/`dropsBinding` trong `PBIXWriter.build`)
- [X] T008 `Sources/BIPro/Model/Edit/ModelRuntime.swift`: giữ `ColumnStore` của `Workspace` và `ModelEdits`; `metadata` hiệu lực, `engine` (`DAXEngine(store:catalog:)` với `Catalog(metadata: hiệu lực)`), `version` tăng khi đổi; chỉ tạo lại engine khi `edits` đổi; test `Tests/BIProTests/Model/ModelRuntimeTests.swift` (đổi biểu thức measure → cùng store, `MeasureCache` mới, số mới đúng)
- [X] T009 `Sources/BIPro/Report/Edit/LayoutEditor.swift`, `Sources/BIPro/Model/Edit/ModelEditor.swift`: `LayoutSnapshot.model: ModelEdits`; `ModelEditor.commit(_:)` đi qua `pushUndo` (gộp cùng thuộc tính trong cửa sổ gộp); `isDirty` tính cả mô hình; ⌘Z/⇧⌘Z khôi phục `ModelEdits` và `ModelRuntime`; test ngăn xếp chung (sửa visual, sửa measure, hoàn tác xen kẽ) `Tests/BIProTests/Model/ModelUndoTests.swift`
- [X] T010 `Sources/BIPro/Report/Edit/DocumentSaver.swift`, `DocumentState.swift`: rẽ nhánh `modelEdits` → `makeChanges` thêm `modelEdits`; `verifyModel` (R10: mô hình đọc lại = hiệu lực, `integrity_check`, `MAXID`, `Report/**` không đổi nếu chỉ sửa mô hình); lưu lần hai trong phiên dựng lại từ file đã lưu; test `Tests/BIProTests/Model/ModelSaveTests.swift` gồm: (a) SC-005: sửa measure rồi ⌘Z rồi lưu, mọi phần của file giống byte file gốc trừ mốc thời gian trong `metadata.sqlitedb`; (b) file có RLS/`SecurityBindings` giữ nguyên vai trò sau lưu T2; (c) file không có `DataModel` hoặc `modelError` thì mọi lệnh sửa mô hình tắt kèm lý do
- [X] T011 [P] `Sources/BIPro/Model/Edit/ModelReferences.swift` (+ mở rộng `FieldReferences.find` cho measure và tên bảng): `usages(of:)` quét visual, bộ lọc, bookmark, DAX của measure/cột tính toán khác bằng `Lexer` (token `[Tên]`, `Bảng[Tên]`, `'Bảng'[Tên]`), quan hệ, `SortByColumnID`, hierarchy; test trên Nhom6 (measure dùng bởi measure khác, bởi visual) `Tests/BIProTests/Model/ModelReferencesTests.swift`
- [X] T012 [P] `Sources/BIPro/Model/Edit/MeasureTyping.swift`: suy `DataType` và `FormatString` mặc định từ kết quả `EVALUATE ROW("x", biểu thức)` (R3); nguyên → `'0'` (đã quan sát), kiểu khác chỉ ghi khi VM-E2 xác nhận, còn lại `NULL` kèm `[SUY ĐOÁN]`; test `Tests/BIProTests/Model/MeasureTypingTests.swift`

## Giai đoạn 3: US1, tạo, sửa, xoá measure (P1)

- [X] T013 [US1] **VM-E2** (cần bạn cho phép): trên bản sao Nhom6 quan sát: xoá measure (Desktop dọn gì, `DBPROPERTIES`), measure kiểu số thực/tiền tệ/chuỗi/ngày/phần trăm (`DataType` và `FormatString` Desktop đặt), biểu thức lỗi cú pháp (có cho lưu, `State`/`ErrorMessage`), đổi tên measure có dùng ở nơi khác, hiển thị trong ngăn Dữ liệu; `docs/phase-e-evidence/vm-e2/QUAN-SAT.md` và `rows.txt`; cập nhật R2, R3 của `research.md` và T012
- [X] T014 [US1] `Sources/BIPro/Table/MeasureEditorView.swift`, `TableWorkspace.swift`: thanh công thức thật (gõ, kiểm lỗi ngay bằng `DAXEngine.validate` + chạy thử, vị trí lỗi, nút áp dụng/huỷ), "Measure mới" tạo bản nháp (chỉ vào mô hình khi áp dụng, R11), sửa biểu thức, xem thử giá trị; cột tính toán và bảng tính toán chỉ đọc kèm lý do (FR-012)
- [X] T015 [US1] Thuộc tính measure ở Table View và ngăn Properties của Model View: tên (chặn khi còn nơi dùng, FR-020), định dạng (`FormatCatalog`), thư mục hiển thị, mô tả, ẩn; ngăn Dữ liệu nhóm measure theo `DisplayFolder`; menu chuột phải "Measure mới/Sửa/Xoá/Đổi tên" (`Sources/BIPro/Panes/*`, `ReportPanes.swift`, `ModelWorkspace.swift`); chế độ Xem chỉ đọc và file không có `DataModel` thì tắt lệnh kèm lý do (FR-018)
- [X] T016 [US1] Xoá measure (chặn kèm danh sách nơi dùng, FR-004), áp dụng qua `ModelEditor`, vẽ lại visual dùng measure đổi (khoá "phiên bản mô hình" trong khoá nạp của `LiveVisual`, so tập tên đổi); test `Tests/BIProTests/Model/MeasureEditorTests.swift` (tạo, sửa, xoá, trùng tên, lỗi cú pháp, hoàn tác từng bước, đổi tên bị chặn, hai measure phụ thuộc nhau, measure ở bảng ngày tự động `LocalDateTable_*`); đo áp dụng một measure dưới 300 ms (kiểm bind, chạy thử) và vẽ lại visual dưới 1 s, ghi vào `measurements.md` (R12, SC-004)
- [X] T017 [US1] Test nặng `Tests/BIProTests/Model/E1Nhom6Tests.swift`: thêm `= SUM(Fact_Loan[loan_amount])` và một measure trong `measures.nhom6.dax`; số khớp DAX viết tay; lưu T2 qua `DocumentSaver`; mở lại trong BI Pro: tên, biểu thức, định dạng, thư mục, mô tả, ẩn còn nguyên; `pbix-dump verify` 110 cột, 0 lệch; đo thời gian lưu và áp dụng vào `measurements.md` (SC-004)
- [X] T018 [US1] Gate Desktop: `build/e-out/E1/Nhom6_e1.pbix` + `CHECKLIST.md`; VM mở file BI Pro lưu (buổi VM-E2b) (measure đúng, số card khớp); kết quả vào `docs/phase-e-evidence/vm-e2/CHECKLIST-KET-QUA.md`

## Giai đoạn 4: US2, quan hệ (P1)

- [X] T019 [P] [US2] `Sources/BIPro/Model/ModelWorkspace.swift`: `RelationshipPanel` sửa được (cardinality nếu quan sát cho phép, hướng lọc đơn/hai chiều, hoạt động hay không, "Assume referential integrity" chỉ đọc nếu chưa quan sát); chọn đường quan hệ; chế độ Xem chỉ đọc
- [X] T020 [US2] **Spike S2** (đo chi phí engine nạp lại khi đổi quan hệ): `Workspace.daxEngine()` với `ModelSchema` mới và dùng lại `ColumnStore` đã giải mã, hoặc `RelationshipOverride`; ghi vào `measurements.md`; chọn đường rẻ nhất (< 1 s vẽ lại, SC-004) và cập nhật R4
- [X] T021 [US2] `ModelRuntime`: áp `updateRelationship` (hoạt động, hướng lọc) vào engine; `ModelEditor.updateRelationship`; vẽ lại mọi visual (quan hệ đổi ảnh hưởng mọi truy vấn); test `Tests/BIProTests/Model/RelationshipEditorTests.swift` (đổi sang hai chiều đổi số truy vấn đúng như DAX `CROSSFILTER` viết tay; hoàn tác)
- [X] T022 [US2] Test nặng trong `E1Nhom6Tests.swift`: đổi hướng lọc và `IsActive` một quan hệ, lưu T2, đọc lại, golden Phase B không đổi; dòng `Relationship` ghi đúng QUAN-SAT mục 3 (`CrossFilteringBehavior` 1→2, `ModifiedTime`); đo sửa thuộc tính quan hệ gồm vẽ lại dưới 1 s, ghi vào `measurements.md` (R12)
- [X] T023 [US2] **VM-E3** (cần bạn cho phép): quan sát tạo quan hệ trong Desktop (hộp thoại New, kéo cột nếu có cách), dò cardinality/hướng lọc mặc định, quan hệ thứ hai giữa hai bảng, từ chối kiểu cột khác nhau/vòng, xoá quan hệ (diff `Relationship`, `RelationshipStorage`, `RelationshipIndexStorage`, bảng `R$`, tệp ABF); `docs/phase-e-evidence/vm-e3/QUAN-SAT.md`
- [X] T024 [US2] **Spike S1** (R7): ba thử nghiệm tạo quan hệ: (i) dòng `Relationship` không có storage, (ii) bỏ cờ cần tính lại, (iii) viết `INDEX.idf` bằng `VertiPaqWriter` (đọc định dạng từ các `R$…idf` của Nhom6 bằng `pbix-dump`); mỗi phương án mở trong Desktop (VM, xin phép); ghi kết quả vào `research.md` R7; **nếu cả ba thất bại thì dừng và báo bạn** trước khi bỏ 2b
- [X] T025 [US2] (sau T024 thành công) `Sources/BIPro/Model/Edit/RelationshipDraft.swift` và kéo cột sang cột ở Model View (`ModelWorkspace.swift`) + hộp thoại xác nhận (cả khi xoá quan hệ, có ⌘Z): dò cardinality bằng đếm distinct qua engine, hướng lọc mặc định theo quan sát, kiểm kiểu cột, vòng, trùng cặp bảng hoạt động (R7); `MetadataWriter.addRelationship`/`deleteRelationship` và ghi chỉ mục theo phương án đã chọn; test quan hệ xoá rồi tạo lại cho số visual trở về đúng như trước (`E1Nhom6Tests`)
- [X] T026 [US2] Gate Desktop: `Nhom6_e2.pbix` + `CHECKLIST.md`; VM mở file BI Pro lưu (quan hệ đúng hai đầu, hướng lọc, hoạt động; số khớp); `docs/phase-e-evidence/vm-e3/CHECKLIST-KET-QUA.md`

## Giai đoạn 5: US3, Table View đầy đủ: Column tools và Column metadata (P2)

- [X] T027 [US3] (gộp vào gate T031: thay vì quan sát Desktop ghi từng thuộc tính, ghi theo các cột `Column` tự nhiên rồi kiểm Desktop đọc đúng; `Annotation SummarizationSetBy` của Desktop không bắt chước) **VM-E4a** (cần bạn cho phép): quan sát sửa thuộc tính cột trong Desktop (tên, ẩn, định dạng, tổng hợp mặc định, loại dữ liệu hiển thị, sắp xếp theo cột, thư mục, mô tả) và cách ghi từng thuộc tính vào `Column` + `Annotation`; `docs/phase-e-evidence/vm-e4/QUAN-SAT.md`; cập nhật R2
- [X] T028 [P] [US3] `Sources/BIPro/Table/ColumnMetadataEditor.swift`, `TableWorkspace.swift` (`ColumnMetadataPanel`): sửa thuộc tính đã quan sát qua `ModelEditor.updateColumn`; thuộc tính chưa quan sát chỉ đọc "(chưa kiểm)"; đổi tên chặn khi còn nơi dùng; sắp xếp theo cột chỉ cho cột cùng bảng theo quy tắc quan sát; áp ngay lên lưới, ngăn Dữ liệu và visual dùng cột
- [X] T029 [P] [US3] Sắp xếp và lọc lưới Table View chỉ trong phiên (dùng `GridFilter` sẵn có), không tạo thay đổi chưa lưu (kịch bản 4 của US3); ribbon Table tools/Column tools theo ngữ cảnh (`Ribbon.swift`)
- [X] T030 [US3] Test `Tests/BIProTests/Model/ColumnEditorTests.swift` (từng thuộc tính, đổi tên bị chặn, hoàn tác, ẩn cột khỏi ngăn Dữ liệu) và test nặng đổi định dạng + ẩn + sắp xếp theo cột trên Nhom6, lưu T2, đọc lại, trục chữ đổi thứ tự trong visual
- [X] T031 [US3] Gate Desktop: `Nhom6_e3.pbix`; VM mở: cùng thuộc tính, thứ tự trục đổi theo; `docs/phase-e-evidence/vm-e4/CHECKLIST-KET-QUA.md`

## Giai đoạn 6: US4, Model View: thẻ bảng, bố cục, ẩn (P2)

- [X] T032 [US4] **VM-E4b** (cần bạn cho phép): quan sát Desktop ghi `DiagramLayout` khi kéo thẻ, thêm/đổi tên tab bố cục, thu phóng (dùng `prlctl send-key-event` hoặc bạn thao tác tay vì `cliclick` kéo không tới Desktop); `docs/phase-e-evidence/vm-e4/QUAN-SAT.md`
- [X] T033 [P] [US4] `Sources/PBIXKit/Writing/DiagramLayoutPatch.swift`: ghép byte `location`/`size` của nút trong `DiagramLayout` (UTF-16LE JSON), giữ khoá khác, thêm nút cho bảng mới thiếu; `PBIXChanges.diagramLayout` (tier T1 nếu chỉ bố cục); test `Tests/PBIXKitTests/DiagramLayoutPatchTests.swift` (không đổi thì byte y hệt)
- [X] T034 [US4] `ModelWorkspace.swift`: kéo thẻ bảng (một bước hoàn tác, đường quan hệ đi theo, dưới 30 ms mỗi khung), tab bố cục (tab mới "(chưa kiểm)" tới khi T032), thu phóng nhớ; ẩn bảng/cột (mờ ở Model View, bỏ khỏi ngăn Dữ liệu ở Report View) qua `updateColumn`/thuộc tính bảng; chỉ bố cục đổi thì lưu không dựng lại ABF
- [X] T035 [US4] Test `Tests/BIProTests/Model/DiagramEditorTests.swift` + gate Desktop `Nhom6_e4.pbix` (thẻ đúng chỗ); `docs/phase-e-evidence/vm-e4/CHECKLIST-KET-QUA.md`

## Giai đoạn 7: US5, TMDL View sửa được (P3)

- [X] T036 [P] [US5] `Sources/PBIXKit/TMDLParser.swift` theo `contracts/tmdl-subset.md`: phân tích văn bản (thụt lề, `measure … = …` nhiều dòng, `formatString`, `displayFolder`, `description`, `isHidden`, `column`, `relationship`), lỗi theo dòng/cột; test `Tests/PBIXKitTests/TMDLParserTests.swift` (vòng `TMDLWriter` → `TMDLParser` trên Nhom6 cho mô hình y hệt)
- [X] T037 [US5] `Sources/BIPro/Query/QueryWorkspaces.swift` (`TMDLWorkspace`): bỏ huy hiệu "Chỉ đọc", `CodeEditor` sửa được, nút "Áp dụng" (so với `TMDLWriter.documents` hiện tại → `ModelEdits`, kiểm nguyên khối, từ chối từng mục ngoài phạm vi kèm lý do), một bước hoàn tác chung; chân trang cập nhật
- [X] T038 [US5] Test `Tests/BIProTests/Model/TMDLApplyTests.swift`: sửa biểu thức measure trong TMDL → card đổi số; TMDL sinh lại khớp văn bản sau chuẩn hoá khoảng trắng (FR-014); sai cú pháp/đối tượng không có/ngoài phạm vi → không áp gì; áp thành công một bước hoàn tác; đo dưới 1 s (R12)
- [X] T039 [US5] Gate Desktop: `Nhom6_e5.pbix` (sửa measure qua TMDL, lưu): Desktop đọc đúng; `docs/phase-e-evidence/vm-e5/CHECKLIST-KET-QUA.md`

## Giai đoạn 8: tích hợp, review, tài liệu

- [x] T040 Chạy `swift test` toàn bộ và golden nặng (`Nhom6|ORA|VIS|Batched|E1`): 30 golden Phase B và 72 truy vấn visual giữ nguyên, D1 đến D7 vẫn qua (SC-002); xử lý trượt
- [x] T041 `/speckit-analyze` rồi, sau khi code xong, `/speckit-converge` và `/code-review` (theo `CLAUDE.md`); sửa phát hiện
- [x] T043 (bổ sung sau T042, 2026-11-15) Xoá tab bố cục, gỡ bảng khỏi tab (kéo đổi thứ tự tab: Desktop không làm được nên bỏ): quan sát VM-E7 (`docs/phase-e-evidence/vm-e7/QUAN-SAT.md`), `DiagramEdits.deleteTab/removeTable` + `DiagramLayoutPatch.Tab/Removal` (đánh lại `ordinal`), menu tab và thẻ ở `ModelWorkspace`, test `DiagramLayoutPatchTests`, `DiagramEditorUndoTests`, `DiagramSaveTests.xoaTabGoBangLuuMoLai`, gate `FGateTests.taoFileGateXoaTab` (Desktop mở `Nhom6_f4.pbix` đúng); bấm thử tay trong app và sửa hai lỗi (nút "…" thẻ bị vùng kéo che, nút "Measure mới" ở Công cụ cột chưa nối)
- [x] T042 Cập nhật `docs/STATE.md`, `docs/BIPRO_BUILD_PLAN.md` (Phase E), `docs/phase-e-ownership.tsv`, `specs/009-.../measurements.md` (SC-004), mục "Khác Desktop có chủ ý" (đổi tên bị chặn, không bắt chước tác dụng phụ `SummarizeBy`); xoá file tạm VM và `~/Desktop/vme*`; build app `zsh scripts/build-app.sh`; **không commit/push trừ khi bạn bảo**

## Phụ thuộc và thứ tự

- Giai đoạn 1 → Giai đoạn 2 (T003 → T004, T005, T006; T007 song song T003; T008, T009, T010 sau T004–T006; T011, T012 song song).
- US1 (P1) cần Giai đoạn 2; US1 là MVP: T013 → T014–T016 → T017 → T018.
- US2 (P1) cần Giai đoạn 2 và T008; 2a (T019 đến T022) độc lập với US1 về kiểu nhưng dùng chung `ModelEditor`; 2b (T023 đến T026) sau 2a, S1 (T024) quyết định T025.
- US3 và US4 (P2) độc lập nhau, sau Giai đoạn 2; US4 dùng `PBIXChanges.diagramLayout` (T006).
- US5 (P3) sau US1 đến US3 (áp dụng gộp các thao tác của chúng).
- Giai đoạn 8 cuối.

## Song song

- T002 ‖ T001; T011 ‖ T012; T019 ‖ T020; T028 ‖ T029; T033 ‖ T036 (khác tệp, khác câu chuyện); các buổi VM-E không chạy song song với nhau (một VM).
- Không giao worker agy (xem đầu tệp).

## Chiến lược

1. MVP = Giai đoạn 1, 2 và US1 (thêm/sửa/xoá measure, lưu T2, Desktop đọc đúng): dùng được ngay và là nửa đầu của "xong khi".
2. US2a (sửa quan hệ) hoàn thành nửa sau; US2b (tạo quan hệ) tuỳ S1, báo bạn nếu bỏ.
3. US3, US4 rồi US5; mỗi câu chuyện là một bản dùng được, có gate Desktop riêng.
4. Mỗi lần dừng cho bạn: sau T018 (US1 xong), sau T024 (kết quả S1), sau T026, cuối cùng T042. Ở mỗi điểm dừng (và sau mỗi buổi VM, mỗi review) cập nhật `docs/STATE.md` trước khi báo bạn (CLAUDE.md).
5. Tên buổi VM: VM-E1 (đã xong), VM-E1b (S0, T007), VM-E2 (T013), VM-E2b (T018), VM-E3 (T023, S1 ở T024), VM-E4a (T027), VM-E4b (T032); các gate Desktop còn lại ghi theo tên task.
