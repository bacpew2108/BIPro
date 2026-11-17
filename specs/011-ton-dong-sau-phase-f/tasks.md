# Nhiệm vụ: Tồn đọng sau Phase F

Định dạng: `- [ ] Txxx [P?] [USn] Mô tả (tệp)`. `[P]` = song song được (khác tệp, không phụ thuộc việc chưa xong). **[LEAD]** = lead tự làm bằng `/tdd`. **[AGY:gói]** = giao agy theo CLAUDE.md (brief `docs/tasks/<gói>.md`, worktree riêng, `git status` sạch trước khi giao). **[VM]** = Claude lái VM (bạn cho phép 2026-11-17), ảnh cắt che tên tài khoản, dọn thư mục VM sau buổi.

Kiểm: `swift build`; `swift test`; golden nặng `BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --no-parallel --filter "Nhom6|ORA|VIS|Batched|F6|T116|F2"`; `zsh scripts/build-app.sh`. Thiết kế: `plan.md`, `research.md` (R1–R9), `data-model.md`, `contracts/`.

Điều kiện chung:
- Không thêm thư viện ngoài (hiến pháp III) và không tải gì từ mạng.
- File gốc chỉ đọc (`~/Downloads/bipro-golden/Nhom6_work.pbix`, `~/Downloads/DWH&BI/w8.3.pbix`). Thử trên bản sao và file sinh ở `build/f2-out/`.
- Quy tắc chưa quan sát ghi `[SUY ĐOÁN]` trong code.
- Mật khẩu không vào `.pbix`, `docs/`, nhật ký hay ảnh.
- Không commit `.pbix` bằng chứng.
- Sau khi đổi struct dùng chung giữa module thì xoá `.build` và `.build-1a-rel` (tránh SIGBUS).

## Giai đoạn 1: Đợt 0, chuẩn bị (lead)

- [X] T001 **(2026-11-17: xong)** [LEAD] `docs/phase-f2-ownership.tsv`: chủ từng tệp theo `plan.md`.
  - Gói F2-DAXTEXT: `Sources/DAXEngine/Functions/Text.swift`, `Sources/DAXEngine/Functions/TextMore.swift`, `Tests/DAXEngineTests/F-TEXT/**`.
  - Gói F2-CONN: `Sources/Connectors/Postgres/**`, `Sources/Connectors/Parquet/**`, `Tests/ConnectorsTests/Postgres*.swift`, `Tests/ConnectorsTests/Parquet*.swift`, `scripts/f-samples/make_parquet.py`.
  - Còn lại thuộc lead.
- [X] T002 **(2026-11-17: xong)** [P] [LEAD] Tạo thư mục bằng chứng `docs/phase-f2-evidence/vm-f10` đến `vm-f15` (mỗi thư mục có `.gitkeep`) và `docs/phase-f2-evidence/README.md`. README ghi: chỉ mục buổi VM ↔ câu chuyện; quy tắc ảnh (cắt `sips -c 900 1500 --cropOffset 130 50`, xoá ảnh gốc); `.pbix` để ngoài git.
- [X] T003 **(2026-11-17: xong; mẫu nhỏ sinh trong 1,3 s; `big_10m.parquet` chỉ sinh với `--large`, ổ đĩa còn 19 GB)** [P] [LEAD] `scripts/f2-samples/make_f2_samples.py` (chỉ thư viện chuẩn Python và pyarrow có sẵn, không `pip`) sinh vào `build/f2-out/samples/`:
  - `sales_2026.xlsx` và `customers.xlsx`: khoá `CustomerID` chung, cột `OrderDate` kiểu ngày, `OrderTime` kiểu ngày giờ;
  - `products.csv`: khoá trùng tên nhưng kiểu khác; một cặp cột trùng tên mà cả hai phía không duy nhất;
  - `text_cases.csv`: chữ Việt dạng NFC và NFD, emoji, chuỗi rỗng, số dạng chữ;
  - `repeat_1m.csv`: 1 triệu dòng có cột lặp dài và cột ngẫu nhiên;
  - `big_10m.parquet`: 10 triệu dòng × 10 cột.
  `nested.parquet` do gói F2-CONN sinh (T042), không sinh ở đây.
  Kèm `README` nêu lệnh sinh.
- [X] T004 **(2026-11-17: xong, thêm `F2Fixtures.w83`, `copy(_:folder:fileName:)`)** [P] [LEAD] `Tests/BIProTests/Model/F2Fixtures.swift` và `Tests/PBIXKitTests/F2Fixtures.swift`:
  - đường tới mẫu T003, `w8.3.pbix` và bản sao Nhom6 ở `build/f2-out/`;
  - bỏ qua test khi thiếu file;
  - test nặng đặt tên chứa `F2`.
- [X] T005 **(2026-11-17: xong, `TableDataTests` 7)** [LEAD] `Sources/ColumnStore/TableData.swift`: thêm `MSourceType` (`time`, `duration`, `dateTimeZone`, `binary`, `list`, `record`) và `TableColumn.sourceType: MSourceType?`, mặc định `nil`, đúng `contracts/sources.md`. Test hình dạng trong `Tests/ColumnStoreTests/TableDataTests.swift`. Xoá `.build` rồi chạy `swift test` cho qua (đổi struct dùng chung).
- [X] T006 **(2026-11-17: xong; thêm `HierarchyLevel`, `HierarchyRef`; mô hình và bộ ghi báo "chưa hỗ trợ"; `ModelEditF2ContractTests` 3)** [LEAD] `Sources/PBIXKit/Writing/ModelEdit.swift`: khung hợp đồng `contracts/model-edits.md`. Thân hàm ở bộ ghi ném "chưa hỗ trợ" cho tới câu chuyện tương ứng.
  - `NewHierarchy`.
  - Case mới: `addHierarchy`, `dropHierarchy`, `addVariation`, `dropVariation`, `setModelAnnotation`.
  - Trường mới: `NewRelationship.joinOnDateBehavior` (mặc định 1); `NewTable.isPrivate`, `showAsVariationsOnly`, `annotations`.
  - `mentionsTable` và `needsData` cho case mới.
  - Test hình dạng ở `Tests/PBIXKitTests/ModelEditsCollapseTests.swift`.
- [X] T007 **(2026-11-17: xong, `F2ModelMetadataTests` 4. Sửa kèm hai lỗi có sẵn: quan hệ tới bảng tính toán của người dùng (`SystemFlags = 2`, như bảng `Ngày` của w8.3) bị bỏ khi đọc; tên cột quan hệ chỉ lấy `ExplicitName` (cột bảng tính toán chỉ có `InferredName`). Quan hệ tới bảng Auto date/time tách ra `dateTableRelationships`)** [LEAD] `Sources/PBIXKit/ModelMetadata.swift` (+ test ở `Tests/PBIXKitTests/`), đọc thêm:
  - `discourageImplicitMeasures` (`Model.DiscourageImplicitMeasures`; Nhom6 = true, file mới BI Pro = false);
  - `variations` (`Variation`: cột → quan hệ → phân cấp mặc định), kiểm trên `w8.3.pbix` có 2 dòng;
  - `Relationship.joinOnDateBehavior`.
- [X] T008 **(2026-11-17: xong)** [LEAD] Cập nhật `docs/STATE.md` (mục "Tồn đọng sau Phase F": Đợt 0 xong, việc kế).

**Điểm dừng**: `swift build` và `swift test` qua. Hợp đồng chốt. Bạn commit trước khi giao gói agy.

## Giai đoạn 2: US1, phép gộp ngầm (P1)

**Mục tiêu**: cột số vào ô giá trị thành trường gộp như Desktop.

**Kiểm độc lập**: tài liệu mới + `sales_2026.xlsx`: card và biểu đồ cột dùng `Amount`, không có measure; mọi phép gộp khớp DAX Desktop; Desktop mở file lưu và ra cùng số.

- [X] T009 **(2026-11-17: xong, `vm-f10/QUAN-SAT.md`; mã Function thật 2 = Count (Distinct), 5 = Count; Desktop dùng `ROW(...)` khi không trục, không lọc)** [US1] [VM] **VM-F10**: Desktop, tài liệu mới, nạp `sales_2026.xlsx`.
  - Kéo `Amount`, `Qty`, `Region`, `OrderDate` vào card, biểu đồ cột và bảng. Ghi:
    - phép gộp mặc định theo kiểu cột;
    - danh sách phép gộp trong menu của từng kiểu;
    - nhãn trường;
    - văn bản Performance Analyzer cho mỗi phép gộp (copy query);
    - trường hợp kéo cùng cột hai lần và "Don't summarize".
  - Lưu `f10-desktop.pbix` (ngoài git). Đọc PBIR hoặc layout: cấu trúc `Aggregation`, mã `Function`, `queryRef`, `nativeQueryRef`.
  - Ghi `docs/phase-f2-evidence/vm-f10/QUAN-SAT.md` cùng ảnh đã cắt.
  - Cập nhật `research.md` R1: bỏ `[SUY ĐOÁN]` ở mục nào đã thấy.
- [X] T010 **(2026-11-17: xong, `ImplicitAggregationTests` golden 3 visual f10 + `FAggStatisticsTests`)** [US1] [LEAD] Test trước (red) `Tests/BIProTests/VisualQuery/ImplicitAggregationTests.swift`:
  - đọc trường `Aggregation` từ PBIR và layout cũ, mẫu chép từ `f10-desktop.pbix`;
  - `DAXQueryBuilder` sinh đúng nguyên văn truy vấn VM-F10 cho từng phép gộp;
  - kết quả chạy engine trên dữ liệu mẫu bằng số Desktop;
  - 72 truy vấn visual cũ không đổi.
- [X] T011 **(2026-11-17: xong; thêm `COUNTA`, `MEDIAN`, `STDEV.P`, `VAR.P` vào engine; `QueryMeasure.aggregation` thay enum Source)** [US1] [LEAD] `Sources/BIPro/Visuals/Query/VisualQuerySpec.swift`, `VisualQuerySpecReader.swift`, `DAXQueryBuilder.swift`, `DataViewMapper.swift`: `AggregateFunction` (mã PBIR theo VM-F10) và `QueryMeasure.Source` (`.measure` | `.aggregation`) đúng `contracts/visual-aggregation.md`. Test T010 xanh.
- [X] T012 **(2026-11-17: xong; chặn gộp cùng cột hai lần trong một visual, tìm ra ở gate)** [US1] [LEAD] `Sources/BIPro/Report/Edit/WellRules.swift`, `FieldRef.swift`, `FieldReferences.swift` + `Tests/BIProTests/Edit/WellRulesTests.swift`:
  - ô giá trị nhận cột khi `!discourageImplicitMeasures`, phép gộp mặc định theo `SummarizeBy` và quan sát VM-F10;
  - Nhom6 vẫn bị chặn với lời báo hiện có.
- [X] T013 **(2026-11-17: xong, menu phép gộp ở Build pane, `LayoutEditor.setAggregation`)** [US1] [LEAD] `Sources/BIPro/Report/Edit/FieldEditor.swift`, `Sources/BIPro/Panes/` (Build pane, menu trường), `LayoutEditor.swift`:
  - menu chọn phép gộp, danh sách theo kiểu cột như Desktop, gồm "Không tóm tắt" khi Desktop có;
  - nhãn tiếng Việt "Tổng của X", "Trung bình của X"… (`data-model.md`);
  - đổi phép gộp là một bước ⌘Z;
  - đổi tên cột đang gộp ngầm thì trường đổi theo (như measure, Phase E); kéo cùng cột hai lần với hai phép gộp.
  Test ở `Tests/BIProTests/Edit/`.
- [X] T014 **(2026-11-17: xong cho PBIR (`PBIRAggregationPatchTests`); báo cáo định dạng cũ vẫn chặn sửa trường như trước)** [US1] [LEAD] Ghi file: `Sources/PBIXKit/Writing/PBIRNewVisual.swift`, `PBIRQueryPatch.swift`, `LegacyLayoutPatch.swift` ghi `Aggregation` y như Desktop (`queryRef`, `nativeQueryRef`, không chuỗi tiếng Việt). Round-trip test ở `Tests/PBIXKitTests/Write/PBIRPatchTests.swift`: file Desktop có trường gộp mở trong BI Pro, lưu lại không đổi trường.
- [X] T015 **(2026-11-17: xong, `F2ImplicitFlowTests`)** [US1] [LEAD] Test đầu-cuối `Tests/BIProTests/Model/F2ImplicitFlowTests.swift`:
  - tài liệu mới → Get Data `sales_2026.xlsx` → card Sum `Amount`, biểu đồ cột Average `Qty` theo `Region` → lưu → mở lại → truy vấn ra đúng số tính độc lập bằng Swift.
  - Để lại `build/f2-out/f10/bipro-f10.pbix`.
- [X] T016 **(2026-11-17: ĐẠT, `vm-f10/KET-QUA.md`)** [US1] [VM] Gate VM-F10: Desktop mở `bipro-f10.pbix` không lỗi. Kiểm card và biểu đồ: cùng số, cùng phép gộp trong menu trường; Performance Analyzer cùng văn bản với BI Pro. Ghi `vm-f10/KET-QUA.md`.
- [x] T017 [US1] [LEAD] Bấm thử app (`zsh scripts/build-app.sh`): kéo cột số vào card, đổi phép gộp, ⌘Z, ⌘S. Ảnh chỉ cửa sổ app. Cập nhật `docs/STATE.md`. (ĐẠT 2026-11-17; sửa nhãn pane Bộ lọc và kiểu cột của bảng vừa nạp.)

## Giai đoạn 3: US3, hàm văn bản DAX (P2, chạy song song với US1 và US2)

**Mục tiêu**: 19 hàm văn bản khớp Desktop.

**Kiểm độc lập**: bộ golden DAX query view, mỗi hàm ít nhất 10 ô.

- [X] T018 **(2026-11-18: xong; 286 ca, 1 198 ô; kết quả lấy từ bảng tính toán đã lưu vì lưới query view không hiện surrogate lẻ)** [US3] [VM] **VM-F12**: nạp `text_cases.csv` vào Desktop.
  - Chạy trong DAX query view truy vấn `EVALUATE ADDCOLUMNS(...)` gọi đủ 19 hàm của FR-020 với các đối số biên:
    - vị trí 0, âm và ngoài độ dài;
    - BLANK, chuỗi rỗng;
    - `SEARCH` với `?`, `*`, `~` và có hoặc không có giá trị dự phòng;
    - `FIND` phân biệt hoa thường;
    - `VALUE` của "1,5", "1.5", " 12 ";
    - `FIXED` với số âm và số chữ số;
    - `UNICHAR`, `UNICODE` của emoji;
    - `LEN` của chuỗi NFD và emoji.
  - Copy table thành `docs/phase-f2-evidence/vm-f12/golden.tsv` (giá trị và kiểu) và ghi nguyên văn các lỗi Desktop báo vào `QUAN-SAT.md`.
- [X] T019 **(2026-11-18: xong; CONCATENATEX lead sửa ở `Iterators.swift`, gói còn 18 hàm; miễn 4 ô UNICODE của surrogate lẻ)** [US3] [LEAD] `docs/tasks/f2-daxtext.md`: brief cho gói F2-DAXTEXT (`/writing-for-agents`).
  - Mục tiêu và danh sách hàm.
  - Tệp được sửa (đúng T001), "không sửa gì ngoài danh sách".
  - Golden `vm-f12/golden.tsv`; test `Tests/DAXEngineTests/F-TEXT/TextFunctionGoldenTests.swift` đọc TSV, không hard-code.
  - Lệnh `swift build`, `swift test --filter "F-TEXT|Text"`.
  - Tiêu chí: 100% ô khớp; golden DAX Phase B không đổi.
  - Báo cáo ở `docs/tasks/f2-daxtext-report.md`.
- [ ] T020 [US3] [AGY:F2-DAXTEXT] `Sources/DAXEngine/Functions/Text.swift`, `TextMore.swift` đăng ký trong mảng `TextFunctions.functions` (đã được `Registry.swift` gộp sẵn, không sửa `Registry.swift`). Gồm `LEN`, `UPPER`, `LOWER`, `MID`, `RIGHT`, `TRIM`, `SUBSTITUTE`, `REPLACE`, `CONCATENATE`, `CONCATENATEX`, `SEARCH` (bổ sung), `FIND`, `REPT`, `VALUE`, `EXACT`, `UNICHAR`, `UNICODE`, `FIXED`, `COMBINEVALUES`, ngữ nghĩa theo `vm-f12`. Test `Tests/DAXEngineTests/F-TEXT/` xanh.
- [ ] T021 [US3] [LEAD] Review gói F2-DAXTEXT (skill `agy-delegation`):
  - chỉ tệp trong phạm vi;
  - `swift test` qua; golden nặng DAX không đổi;
  - không hard-code.
  Chưa đạt thì giao lại một lần. Merge chỉ khi bạn bảo.
- [ ] T022 [US3] [LEAD] Test `Tests/BIProTests/Model/F2TextCalcTests.swift`: cột tính toán dùng `UPPER`, `MID`, `SUBSTITUTE` trên bảng mẫu → lưu → mở lại, giá trị bằng golden. Để lại `build/f2-out/f12/bipro-f12.pbix`.
- [ ] T023 [US3] [VM] Gate VM-F12: Desktop mở `bipro-f12.pbix`; cột tính toán dùng hàm mới có công thức đúng; DAX query view so cột đã lưu với biểu thức tính lại cho 0 dòng lệch. Ghi `vm-f12/KET-QUA.md`.

## Giai đoạn 4: US2, tài liệu mới giống Desktop (P1)

**Mục tiêu**: màn thêm dữ liệu, Enter Data, Auto date/time, tự phát hiện quan hệ.

**Kiểm độc lập**: tài liệu mới → dán bảng 3×5, nạp `Sales` + `Customers` → quan hệ tự tạo, biểu đồ theo Năm → lưu → Desktop mở, cấu trúc như file Desktop tự làm.

- [ ] T024 [US2] [VM] **VM-F11** gồm ba phần, ghi `docs/phase-f2-evidence/vm-f11/QUAN-SAT.md` cùng ảnh:
  - **(a) Màn trống và Enter Data**:
    - các ô của "Add data to your report", bấm từng ô mở hộp thoại nào, màn biến mất khi nào;
    - Enter Data 3 cột × 5 dòng (chữ Việt, số, ô trống): M nguyên văn, tên mặc định, giới hạn cỡ, kiểu sau `Changed Type`;
    - sửa lại qua bánh răng của bước Source.
  - **(b) Auto date/time**:
    - tuỳ chọn mặc định cho file mới và vị trí trong Options ▸ Current file;
    - nạp `sales_2026.xlsx` (cột Date và DateTime): bảng, cột, biểu thức, chú thích, phân cấp, quan hệ, `Variation`;
    - biểu đồ theo Year/Quarter và Performance Analyzer;
    - tắt rồi bật lại tuỳ chọn.
  - **(c) Tự phát hiện quan hệ**:
    - nạp cùng lúc `sales_2026.xlsx`, `customers.xlsx`, `products.csv`: quan hệ nào được tạo, chiều, lực lượng, hoạt động hay không, tên;
    - nạp thêm một bảng vào mô hình đã có quan hệ;
    - vị trí tuỳ chọn "Autodetect new relationships".
  - Lưu `f11-desktop.pbix` (ngoài git).
  - Cập nhật `research.md` R2–R4.
- [ ] T025 [US2] [LEAD] So `f11-desktop.pbix` với `w8.3.pbix` bằng PBIXKit (`Tests/PBIXKitTests/F2AutoDateGoldenTests.swift`, đọc thôi): danh sách cột và biểu thức của `DateTableTemplate_` và `LocalDateTable_`, chú thích, phân cấp, thuộc tính quan hệ và `Variation`. Chốt mẫu trong `Sources/BIPro/Model/Edit/AutoDateTime.swift` (chỉ hằng số và tài liệu, chưa logic).
- [ ] T026 [US2] [LEAD] `Sources/MEngine/Library/Binary.swift` (mới), `TableRows.swift`, `Support.swift`, `Json.swift` + `Tests/MEngineTests/EnterDataMTests.swift`:
  - `Binary.FromText` (Base64), `Binary.Decompress` (`Compression.Deflate` qua `Compression.framework`);
  - `Json.Document` nhận đầu vào nhị phân; `Table.FromRows`;
  - kiểu có `meta`, `type table [...]`.
  - Golden: M Enter Data của `f11-desktop.pbix` chạy ra đúng bảng Desktop lưu.
- [ ] T027 [US2] [LEAD] `Sources/BIPro/Query/EnterDataState.swift` (+ `Tests/BIProTests/Query/EnterDataStateTests.swift`):
  - lưới tên cột và ô; dán TSV; thêm và xoá dòng, cột; tên bảng mặc định và hậu tố khi trùng;
  - giới hạn cỡ theo VM-F11a;
  - sinh M giống nguyên văn Desktop (nén Deflate + Base64, thứ tự cột, `Changed Type`);
  - đọc ngược M thành lưới.
- [ ] T028 [US2] [LEAD] `Sources/BIPro/Query/EnterDataView.swift` (hộp "Tạo bảng"), nối Ribbon Trang chủ ▸ "Nhập dữ liệu" và nối nút bước Source trong Query Editor. Nạp bảng qua đường `addTable` T3 sẵn có, một bước ⌘Z.
- [ ] T029 [US2] [LEAD] `Sources/BIPro/Report/AddDataPanel.swift` + nối vào `ReportCanvas.swift`:
  - màn "Thêm dữ liệu vào báo cáo" khi tài liệu chưa có bảng người dùng;
  - các ô Excel, "Dán dữ liệu vào bảng trống", nguồn khác; SQL Server và dữ liệu mẫu hiện xám kèm lý do;
  - biến mất theo quan sát VM-F11a.
  Test hiển thị và nối nút ở `Tests/BIProTests/Report/AddDataPanelTests.swift`.
- [ ] T030 [US2] [LEAD] Bộ ghi phân cấp:
  - `Sources/PBIXKit/Writing/HierarchyIndexWriter.swift` (mới): dựng `U$` và `HierarchyStorage` từ dữ liệu các cấp, định dạng đọc từ `w8.3.pbix` và Nhom6;
  - `MetadataWriter`: `addHierarchy`, `dropHierarchy` (`Hierarchy`, `Level`).
  - Test `Tests/PBIXKitTests/Write/HierarchyIndexWriterTests.swift`: dựng lại `U$` của Date Hierarchy trong `w8.3.pbix` từ dữ liệu cột, so byte (hoặc so từng ô khi giải mã nếu Desktop có phần thay đổi theo thời điểm). Phân cấp Nhom6 cũng vậy.
- [ ] T031 [US2] [LEAD] `MetadataWriter` + `TableMetadataWriter`:
  - `addVariation`, `dropVariation`, `setModelAnnotation`;
  - `NewRelationship.joinOnDateBehavior`;
  - `NewTable.isPrivate`, `showAsVariationsOnly`, `annotations`.
  Test `Tests/PBIXKitTests/Write/AutoDateWriteTests.swift`: ghi bộ bảng ngày cục bộ cho một cột, đọc lại bằng `ModelMetadata` thấy đúng như `w8.3.pbix`.
- [ ] T032 [US2] [LEAD] `Sources/BIPro/Model/Edit/AutoDateTime.swift` (+ `Tests/BIProTests/Model/AutoDateTimeTests.swift`), sinh `ModelEdit` theo vòng đời ở `data-model.md`:
  - cột ngày thêm, thay hay bỏ; bảng xoá; tắt hay bật tuỳ chọn;
  - GUID mới mỗi bảng; bảng mẫu một lần;
  - dùng `collapsingTableEdits` cho thêm rồi bỏ trong phiên;
  - ca biên: ngày năm 1900 và 9999, cột toàn BLANK, cột ngày giờ (phần giờ bỏ khi so với `Date`), cột ngày ẩn.
  `ModelRuntime` tính bảng ngày cục bộ (bảng tính toán `Calendar`) trong phiên.
- [ ] T033 [US2] [LEAD] `Sources/PBIXKit/Writing/NewDocument.swift`: tài liệu mới đặt `__PBI_TimeIntelligenceEnabled = 1`. Nối Tệp ▸ "Tuỳ chọn tệp" (`Sources/BIPro/Shell/`), gồm Auto date/time và "Tự phát hiện quan hệ mới sau khi nạp" như Desktop, hoàn tác được.
- [ ] T034 [US2] [LEAD] Field list và visual:
  - `Sources/BIPro/Panes/DataPane.swift` hiện "Date Hierarchy" dưới cột ngày qua `variations`;
  - `VisualQuerySpecReader` và `DAXQueryBuilder` hiểu `HierarchyLevel` có `PropertyVariationSource`, văn bản truy vấn theo Performance Analyzer VM-F11b;
  - kéo cột ngày vào trục dùng phân cấp như Desktop.
  Test ở `Tests/BIProTests/VisualQuery/VariationQueryTests.swift`, golden trên `w8.3.pbix` và `f11-desktop.pbix`.
- [ ] T035 [US2] [LEAD] `Sources/BIPro/Model/Edit/RelationshipDetector.swift` (+ `Tests/BIProTests/Model/RelationshipDetectorTests.swift`):
  - quy tắc theo VM-F11c; tên `AutoDetected_<guid>`; thứ tự ổn định;
  - chạy sau Get Data ▸ Tải và Close & Apply, cùng bước ⌘Z;
  - tôn trọng tuỳ chọn tắt;
  - các ca biên của spec: khác kiểu, cả hai phía không duy nhất, đường thứ hai.
- [ ] T066 [US2] [LEAD] FR-015, file Desktop đã bật Auto date/time (bản sao `w8.3.pbix` ở `build/f2-out/`):
  - `MetadataWriter.relationshipsToRebuild`, `requireReplaceable`: cho thay và xoá bảng có quan hệ ngày của Auto date/time (`JoinOnDateBehavior = 2`) và có `Variation`; khi thay thì bảng ngày cục bộ tính lại theo dữ liệu mới, khi xoá thì bỏ kèm;
  - `AutoDateTime.swift` sinh lệnh cho file có sẵn cũng như tài liệu mới;
  - test `Tests/BIProTests/Model/F2AutoDateExistingTests.swift`: nạp thêm bảng có cột ngày, thay `Thông tin nhân viên` (Close & Apply), xoá một bảng có cột ngày → lưu → mở lại, bảng ngày cục bộ đúng khoảng năm mới;
  - để lại `build/f2-out/f11/w83_f2.pbix` cho gate T037.
- [ ] T036 [US2] [LEAD] Test đầu-cuối `Tests/BIProTests/Model/F2NewDocFlowTests.swift`:
  - tài liệu mới → Enter Data 3×5 → Get Data `sales_2026.xlsx` + `customers.xlsx` → quan hệ tự tạo → biểu đồ cột theo Năm của `OrderDate` → lưu → mở lại;
  - cấu trúc bằng `f11-desktop.pbix` (số bảng ngày cục bộ, phân cấp, quan hệ, variation); số liệu đúng.
  - Để lại `build/f2-out/f11/bipro-f11.pbix`.
- [ ] T037 [US2] [VM] Gate VM-F11: Desktop mở `bipro-f11.pbix` không lỗi.
  - Field list có Date Hierarchy; biểu đồ theo Năm ra cùng số.
  - Quan hệ giống file Desktop tự làm.
  - Refresh bảng Enter Data ra cùng dữ liệu.
  - Thêm một visual theo Quý trong Desktop chạy được.
  - Desktop mở `w83_f2.pbix` (T066) không lỗi, phân cấp ngày của bảng thay và bảng mới đúng khoảng năm.
  Ghi `vm-f11/KET-QUA.md`.
- [ ] T038 [US2] [LEAD] Bấm thử app: màn thêm dữ liệu, dán từ Numbers, tắt/bật Auto date/time, ⌘Z quan hệ tự tạo. Ảnh chỉ cửa sổ app. Cập nhật `docs/STATE.md`.

## Giai đoạn 5: US6, nguồn (P3, gói agy chạy song song với US2)

**Mục tiêu**: PostgreSQL năm kiểu mới, driver ODBC chọn được, Parquet lồng.

**Kiểm độc lập**: bảng nạp so với Desktop nạp cùng nguồn; Desktop Refresh chạy M của BI Pro.

- [ ] T039 [US6] [VM] **VM-F15**:
  - **PostgreSQL**: tạo bảng `types_f15` trên `bipro-pg` có timestamptz (nhiều múi giờ), time, interval (âm, tháng), bytea, `int[]`, `text[]` (có NULL, nhiều chiều). Desktop nạp: kiểu trong Power Query và trong mô hình, giá trị, cột bị bỏ hay báo lỗi.
  - **Parquet**: Desktop nạp `nested.parquet`: struct và list hiện ra sao, M sinh ra, mở rộng.
  - **SQLite**: nếu bạn cài driver SQLite thứ hai trong VM, ghi M Desktop với driver đó; không có thì ghi bằng chuỗi kết nối Devart như hiện có.
  - Ghi `docs/phase-f2-evidence/vm-f15/QUAN-SAT.md` và lưu `f15-desktop.pbix` (ngoài git).
  - Mật khẩu không vào docs.
- [ ] T040 [US6] [LEAD] `docs/tasks/f2-conn.md`: brief gói F2-CONN.
  - Tệp đúng T001.
  - Hợp đồng `contracts/sources.md` (`sourceType`, ô `record`/`list` của `TableData.structured`).
  - Golden `f15-desktop.pbix` (đọc bằng `pbix-dump rows`) và `vm-f15/QUAN-SAT.md`.
  - Test cần máy chủ thì dùng `BIPRO_PG`, bỏ qua khi thiếu; không ghi mật khẩu.
  - Tiêu chí: 100% ô khớp; không còn lỗi "chưa hỗ trợ" cho năm kiểu; Parquet phẳng cũ không đổi (`ParquetGoldenTests`).
- [ ] T041 [P] [US6] [AGY:F2-CONN] `Sources/Connectors/Postgres/PostgresSource.swift`, `PostgresConnection.swift`: đọc timestamptz, time, interval, bytea, mảng theo VM-F15, có `sourceType`. Test `Tests/ConnectorsTests/PostgresTypesTests.swift` (máy chủ thử).
- [ ] T042 [P] [US6] [AGY:F2-CONN] `Sources/Connectors/Parquet/ParquetSource.swift`, `ParquetCodec.swift`: dựng lại struct và list từ mức lặp và mức định nghĩa (Dremel), độ sâu đến 3; sâu hơn thì báo "Chưa hỗ trợ" kèm tên cột. `scripts/f-samples/make_parquet.py --nested`. Test `Tests/ConnectorsTests/ParquetNestedTests.swift`, golden bảng Desktop nạp.
- [ ] T043 [US6] [LEAD] Review gói F2-CONN (skill `agy-delegation`); giao lại tối đa một lần; merge khi bạn bảo.
- [ ] T044 [US6] [LEAD] Driver ODBC SQLite:
  - `Sources/BIPro/Query/NavigatorState.swift`, `DatabaseConnectView.swift`, `SourceQuery.swift`: ô chọn driver (danh sách tên phổ biến và nhập tự do), nhớ ở `UserDefaults["bipro.sqlite.odbcDriver"]`, mặc định "Devart ODBC Driver for SQLite";
  - M dựng theo driver đã chọn, chuỗi kết nối theo VM-F15;
  - đọc lại M có driver lạ vẫn chạy được trong BI Pro, vì BI Pro đọc SQLite trực tiếp;
  - tên driver có ký tự đặc biệt (`;`, `{`, `}`, dấu cách) được thoát đúng cách Desktop ghi chuỗi kết nối.
  Test `Tests/BIProTests/Query/SQLiteDriverTests.swift`.
- [ ] T045 [US6] [LEAD] Query Editor và mô hình dùng `sourceType`:
  - hiện kiểu time, duration, datetimezone, binary đúng như Desktop;
  - `Changed Type` và giá trị nạp vào mô hình theo quy tắc VM-F15 (`Sources/BIPro/Query/`, `Sources/BIPro/Model/Edit/TableLoader.swift`).
  Test đầu-cuối `Tests/BIProTests/Query/F2SourcesFlowTests.swift`, để lại `build/f2-out/f15/bipro-f15.pbix`.
- [ ] T046 [US6] [VM] Gate VM-F15: Desktop mở `bipro-f15.pbix`; bảng PostgreSQL, Parquet lồng và SQLite đúng từng ô; Refresh chạy được M của BI Pro. Ghi `vm-f15/KET-QUA.md`.

## Giai đoạn 6: US4, sửa/xoá cột tính toán còn được dùng (P2)

**Mục tiêu**: bỏ chặn của T116 và làm như Desktop.

**Kiểm độc lập**: bản sao Nhom6 và tài liệu thử; Desktop mở và tính đúng.

- [ ] T047 [US4] [VM] **VM-F13**, ghi `docs/phase-f2-evidence/vm-f13/QUAN-SAT.md` và lưu `f13-desktop.pbix`:
  - trên bản sao Nhom6, sửa `Dim_District[branch_label]` (cấp phân cấp) rồi xoá nó: hỏi gì, phân cấp còn lại gì;
  - trên tài liệu thử:
    - cột tính toán làm khoá phía "một" của quan hệ: sửa vẫn duy nhất, sửa thành trùng (Desktop báo gì, quan hệ ra sao), xoá;
    - cột tính toán làm cột sắp xếp của cột khác: sửa giữ một–một, sửa phá một–một, xoá.
  - Đọc `R$`, `U$`, `H$` và `SortByColumnID` trước và sau bằng PBIXKit.
- [ ] T048 [US4] [LEAD] Test trước (red) `Tests/PBIXKitTests/Write/CalculatedIndexRebuildTests.swift`: ba loại phụ thuộc × (sửa, xoá); đọc lại chỉ mục khớp dữ liệu mới; ca Desktop từ chối thì báo lỗi tương ứng.
- [ ] T049 [US4] [LEAD] `Sources/PBIXKit/Writing/MetadataWriter.swift`: thay `requireNoIndexes` bằng dựng lại:
  - quan hệ: `relationshipsToRebuild`, xoá rồi thêm lại cùng tên, `R$` mới;
  - phân cấp: `HierarchyIndexWriter` (T030);
  - cột sắp xếp: `H$` của cột được sắp.
  Xoá cột thì xoá kèm theo VM-F13. Test T048 xanh.
- [ ] T050 [US4] [LEAD] `Sources/PBIXKit/ModelMetadata+TableEdit.swift`, `Sources/BIPro/Model/Edit/CalculatedEditor.swift`, `CalculationPlan.swift`, `Sources/BIPro/Panes/DataPane.swift`:
  - bỏ chặn của T116;
  - hộp xác nhận liệt kê mục bị bỏ kèm (lời như Desktop VM-F13);
  - ca từ chối báo đúng lời;
  - hoàn tác chung.
  Test ở `Tests/BIProTests/Model/CalculatedEditTests.swift`.
- [ ] T051 [US4] [LEAD] Test nặng `Tests/BIProTests/Model/F2CalcIndexNhom6Tests.swift`:
  - bản sao Nhom6: sửa `branch_label`, sửa một cột tính toán khoá quan hệ trên tài liệu thử → lưu hai lần → mở lại;
  - đối chiếu từng dòng và số liệu visual dùng phân cấp;
  - để lại tệp gate trong `build/f2-out/f13/`.
- [ ] T052 [US4] [VM] Gate VM-F13: Desktop mở các tệp gate không lỗi; visual dùng phân cấp, quan hệ, cột sắp xếp ra đúng số và đúng thứ tự (so với Desktop tự làm cùng thao tác). Ghi `vm-f13/KET-QUA.md`.

## Giai đoạn 7: US5, dữ liệu lớn: nhiều đoạn và RLE (P3)

**Mục tiêu**: lưu bảng hơn 8 388 608 dòng; cỡ tệp không quá 125% Desktop.

**Kiểm độc lập**: `big_10m.parquet`, `repeat_1m.csv`; so cỡ, thời gian, bộ nhớ và DAX với file Desktop.

- [ ] T053 [US5] [VM] **VM-F14**: Desktop nạp `big_10m.parquet` và `repeat_1m.csv`, lưu `f14-big-desktop.pbix` và `f14-rle-desktop.pbix` (ngoài git, chép về Mac qua thư mục chia sẻ). Đọc bằng PBIXKit:
  - `SegmentMapStorage` (số đoạn, `RecordsPerSegment`);
  - cỡ và meta `.idf`/`.idfmeta` từng cột (RLE, bit-packing hay lai);
  - thứ tự dòng đọc lại so với nguồn;
  - thống kê từng đoạn, `H$` và `R$` của bảng nhiều đoạn;
  - cỡ tệp làm mốc SC-006.
  Ghi `docs/phase-f2-evidence/vm-f14/QUAN-SAT.md` và cập nhật `research.md` R7.
- [ ] T054 [US5] [LEAD] Test trước `Tests/PBIXKitTests/Write/VertiPaqSegmentTests.swift`:
  - bảng 8 388 609 dòng và bảng chia đúng biên, giải mã từng ô trùng nguồn;
  - RLE: cột lặp được mã hoá đúng loại Desktop dùng, giải mã trùng, cỡ gần Desktop;
  - `WriterLimitTests` cập nhật (bỏ lỗi quá một đoạn).
- [ ] T055 [US5] [LEAD] `Sources/PBIXKit/Writing/VertiPaqWriter.swift`, `TableMetadataWriter.swift`:
  - nhiều đoạn theo `RecordsPerSegment` của VM-F14, mã hoá từng đoạn để giữ bộ nhớ;
  - thống kê từng đoạn; `SegmentMapStorage`;
  - `H$` của bảng nhiều đoạn theo cách Desktop chia;
  - bảng nhiều đoạn bị thay dữ liệu (Close & Apply) hoặc bị xoá: tệp cũ của mọi đoạn được bỏ hết.
  Test T054 (phần nhiều đoạn) xanh.
- [ ] T056 [US5] [LEAD] `VertiPaqWriter.swift`: RLE và lai RLE/bit-packing theo bố cục VM-F14, tiêu chí chọn như Desktop (hoặc `[SUY ĐOÁN]` chọn cách nhỏ hơn). Giữ thứ tự dòng như Desktop. Test T054 (phần RLE) xanh; `DesktopGoldenTests` khớp byte cũ không đổi, hoặc cập nhật kèm giải thích nếu Desktop cũng dùng RLE ở mẫu đó.
- [ ] T057 [US5] [LEAD] `TableMetadataWriter.swift`: bỏ chặn `segments == 1` của cột tính toán; cột tính toán trên bảng nhiều đoạn ghi đúng từng đoạn. Đường ghi `R$` cho quan hệ trên bảng nhiều đoạn. Test ở `Tests/PBIXKitTests/Write/CalculatedWriteTests.swift`.
- [ ] T058 [US5] [LEAD] Test nặng `Tests/BIProTests/Model/F2LargeSaveTests.swift` (release):
  - tài liệu mới + `big_10m.parquet` (10 cột) + cột tính toán + quan hệ tới bảng nhỏ → lưu < 2 phút, đỉnh bộ nhớ < 4 GB (đo `task_info`), đọc lại trùng nguồn;
  - `repeat_1m.csv`: cỡ tệp ≤ 125% `f14-rle-desktop.pbix`;
  - ghi số vào `specs/011-ton-dong-sau-phase-f/measurements.md`.
- [ ] T059 [US5] [VM] Gate VM-F14: Desktop mở tệp 10 triệu dòng và tệp RLE; `COUNTROWS`, `SUM`, `DISTINCTCOUNT` và lọc qua quan hệ khớp. Ghi `vm-f14/KET-QUA.md`.

## Giai đoạn 8: Hoàn thiện

- [ ] T060 [LEAD] Golden nặng đầy đủ (lệnh ở đầu tệp): 30 DAX Phase B, 72 truy vấn visual không đổi; thời gian lưu Nhom6 T2 dưới 4 giây (SC-008). Ghi số vào `measurements.md`.
- [ ] T061 [LEAD] `/code-review` trên toàn bộ thay đổi của đợt; sửa lỗi tìm thấy và thêm test hồi quy.
- [ ] T062 [LEAD] `/speckit-converge` cho `specs/011-ton-dong-sau-phase-f`; làm các task nó thêm.
- [ ] T063 [LEAD] [VM] Gate tổng: luồng SC-002 trên một tài liệu mới, từ Enter Data tới Desktop mở (dưới 3 phút thao tác). Ghi `docs/phase-f2-evidence/CHECKLIST-TONG.md`. Dọn thư mục VM.
- [ ] T064 [LEAD] Tài liệu:
  - `docs/BIPRO_BUILD_PLAN.md`: Phase F hết tồn đọng;
  - `docs/STATE.md`;
  - `WellRules.aggregationReason` và các lời "chưa hỗ trợ" đã lỗi thời trong mã;
  - memory.
- [ ] T065 [LEAD] Báo bạn kết quả từng câu chuyện, gói agy, tệp đã đổi, tồn đọng. Không tự commit, push, merge hay xoá worktree.

## Phụ thuộc và thứ tự

- Giai đoạn 1 chặn mọi giai đoạn sau. T005–T007 đổi kiểu dùng chung, nên phải xong trước khi giao gói agy (bạn commit trước).
- US1 (Giai đoạn 2) trước US2 (Giai đoạn 4), vì T034 dùng chung đường truy vấn visual với T011.
- US3 (Giai đoạn 3) độc lập: T018 và T019 xong thì giao F2-DAXTEXT, chạy song song với US1 và US2.
- US6 (Giai đoạn 5): sau T039 thì giao F2-CONN, chạy song song với US2. T044 và T045 của lead làm sau khi review T043.
- US4 (Giai đoạn 6) sau T030 (bộ ghi `U$` của US2).
- US5 (Giai đoạn 7) sau US4, vì dựng lại `R$` trên bảng nhiều đoạn dùng đường của T049.
- Tối đa 2 gói agy cùng lúc (F2-DAXTEXT, F2-CONN), sửa tập tệp không giao nhau. Lead không sửa tệp của gói khi gói đang chạy.

## Song song

- Đợt 0: T002, T003, T004 song song; T005 → T006 → T007 tuần tự (cùng nhánh kiểu).
- Trong lúc agy làm T020: lead làm T009–T017.
- Trong lúc agy làm T041 và T042: lead làm T024–T038.
- Trong US2: T026 (MEngine), T029 (màn trống), T030 (bộ ghi `U$`) khác tệp nên làm xen được. T066 làm sau T032.

## Chiến lược

- **MVP**: Giai đoạn 1 và US1 (gộp ngầm, gate VM-F10).
- **Tăng dần**: US2 (tài liệu mới) → US3 (merge khi bạn bảo) → US6 → US4 → US5. Mỗi câu chuyện xong gate thì báo bạn và cập nhật `STATE.md`; commit khi bạn bảo.
