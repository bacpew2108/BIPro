# Nhiệm vụ Phase F: Get Data, Power Query và lưu tầng T3

Định dạng: `- [ ] Txxx [P?] [USn] Mô tả (tệp)`. `[P]` = song song được (khác tệp, không phụ thuộc việc chưa xong). Nhãn **[LEAD]** = lead tự làm bằng `/tdd` (ngữ cảnh sâu, đụng chung). Nhãn **[AGY:gói]** = giao agy theo CLAUDE.md, gói đúng tên trong `docs/phase-f-ownership.tsv` (F-CONN1, F-MFUN, F-UI); chỉ giao khi hợp đồng đã chốt và `git status` sạch, tối đa 3 worker, brief ở `docs/tasks/<tên>.md`, báo cáo `docs/tasks/<tên>-report.md`. Nhãn **[VM]** = buổi quan sát/kiểm trên Power BI Desktop: **bạn làm tay** (hiến pháp, memory `user-tests-vm-manually`); Claude chỉ điều khiển VM khi bạn cho phép lần đó; Claude chuẩn bị file và `CHECKLIST.md`.

Kiểm: `swift build`; `swift test`; golden nặng `BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --no-parallel --filter "Nhom6|ORA|VIS|Batched"`; `zsh scripts/build-app.sh`. Thiết kế xem `plan.md`; hợp đồng `contracts/`; thực thể `data-model.md`.

Điều kiện chung: không thêm thư viện ngoài (hiến pháp III); không tải gì từ mạng; file gốc `~/Downloads` chỉ đọc, thử trên bản sao và file sinh ở `build/f-out/`; mật khẩu không vào `.pbix`/`docs/`/nhật ký/ảnh; hàm M và quy tắc chưa quan sát đánh dấu `[SUY ĐOÁN]`; ảnh VM chỉ lưu bản cắt không lộ dòng tài khoản; dọn mọi thư mục VM và file tạm sau mỗi buổi; không commit/push khi bạn chưa yêu cầu.

## Giai đoạn 1: Đợt 0, hợp đồng và chuẩn bị (lead)

- [X] T001 [LEAD] `docs/phase-f-ownership.tsv` chốt lần cuối, liệt kê đủ tệp lead sở hữu (thêm `Sources/BIPro/Query/QueryEditorState.swift`, `NavigatorState.swift`, `Sources/ColumnStore/OverlayColumnSource.swift`, `Sources/PBIXKit/Writing/EnterDataTable.swift`, `Sources/MEngine/Query.swift`, `StepFactory.swift`, `Profile.swift`, `Preview.swift`, `Contracts.swift`, `Sources/MEngine/Library/Json.swift`, `Sources/BIPro/Model/Edit/CalculatedEditor.swift`, `Sources/Connectors/Credentials.swift`, `Sources/BIPro/Shell/Ribbon.swift`, `Sources/BIPro/Workspace.swift`, `App.swift`); quy tắc: tệp của gói agy chỉ được lead sửa sau khi worker bàn giao và lead review xong, không sửa song song; `docs/BIPRO_BUILD_PLAN.md` đánh dấu Phase F "đang làm", ghi mốc spec/plan đã duyệt
- [X] T002 [LEAD] `Package.swift`: thêm target `Connectors` (phụ thuộc `ColumnStore`, `PBIXKit`), `MEngine` (phụ thuộc `ColumnStore`), `ConnectorsTests`, `MEngineTests`; BIPro phụ thuộc cả hai; KHÔNG thêm package ngoài; `swift build` qua
- [X] T003 [LEAD] `Sources/ColumnStore/TableData.swift` + `Tests/ColumnStoreTests/TableDataTests.swift`: `TableData` (cột `ColumnData`, `rowCount`, `errorMask` thưa), bất biến "mọi cột cùng `rowCount`; tên cột duy nhất; `null` là BLANK", dựng từ `ColumnBuilder`, đọc ô, cắt N dòng đầu
- [X] T004 [P] [LEAD] `Sources/Connectors/DataSource.swift`: `DataSource`, `SourceItem`, `SourceKind`, `SourceError` đúng `contracts/data-source.md` (chưa có nguồn cụ thể); test hình dạng hợp đồng bằng nguồn giả
- [X] T005 [P] [LEAD] `Sources/MEngine/Value.swift`, `Sources/MEngine/Contracts.swift`: `MValue`, `MError`, `MFunction`, `MEnvironment`, chữ ký `MParser`/`MEvaluator`/`MLibrary` đúng `contracts/m-engine.md` (thân hàm ném "chưa hỗ trợ")
- [X] T006 [P] [LEAD] `Sources/PBIXKit/Writing/ModelEdit.swift`: (đã làm: `NewTable` lớp tham chiếu thay `LoadedTable` vì PBIXKit không phụ thuộc ColumnStore; BIPro đổi `TableData` → `NewTable`) thêm case `addTable`, `replaceTable`, `dropTable`, `addCalculatedColumn`, `addCalculatedTable` và `LoadedTable` (chưa áp dụng; `applying` ném `unsupported`); `Sources/BIPro/Query/QueryEditorState.swift`, `NavigatorState.swift`: trạng thái `@Observable` cho giao diện (truy vấn, bước, bước đang chọn, bảng xem trước, profile, tiến độ, lỗi) để agy-ui vẽ
- [X] T007 [P] [LEAD] `scripts/f-samples/make_samples.py` (chỉ thư viện chuẩn Python, không `pip`): sinh `build/f-out/samples/` gồm `sales_2026.xlsx` (nhiều trang tính, bảng đặt tên, ô ngày, ô công thức, ô trống, hàng đầu trống), `sales_2026.csv` (UTF-8, thêm biến thể dấu `;` và UTF-16), `customers.csv`, `orders.json` (mảng bản ghi lồng), `sales_2026.sqlite`; cột `OrderID, OrderDate, Region, CustomerID, Product, Qty, Price, Amount` (+ ca xấu: số lẫn chữ, chuỗi rỗng, `null`, dòng trùng); số dòng chọn 100, 10 000, 1 000 000 (biến thể lớn). Parquet: kiểm có công cụ chuẩn trên máy không; nếu không thì T089 tự lo
- [X] T008 [P] [LEAD] `Tests/BIProTests/Model/FFixtures.swift`, `Tests/PBIXKitTests/FFixtures.swift`: chép `Nhom6_work.pbix` (`BIPRO_NHOM6`) và mẫu ra `build/f-out/`, bỏ qua test khi thiếu file; tạo `docs/phase-f-evidence/` (vm-f0…vm-f7)
- [X] T009 [LEAD] `docs/phase-f-evidence/vm-f0/CHECKLIST.md`: checklist mở `build/w-out/W4/tuan6.2_W4_table.pbix` trong Desktop (đã có `build/w-out/W4/CHECKLIST.md`, đối chiếu và bổ sung ô "đủ 100 dòng, kiểu cột, tổng"); báo bạn

## Giai đoạn 2: Gate F-T3 (S0, chặn T3 nấc 2 trở đi; không chặn đọc nguồn và M)

- [ ] T010 [VM] S0 / F-T3: bạn mở `build/w-out/W4/tuan6.2_W4_table.pbix` trong Desktop theo T009, ghi kết quả vào `docs/phase-f-evidence/vm-f0/CHECKLIST-KET-QUA.md` (đạt/trượt, thông báo lỗi nguyên văn nếu trượt)
- [ ] T011 [LEAD] Quyết định theo T010: **đạt** → làm T3 đầy đủ (Giai đoạn 3); **trượt** → ghi `docs/phase-f-evidence/vm-f0/QUYET-DINH.md`, bật nhánh dự phòng Enter Data (T029–T031) và mở lại nghiên cứu T3 song song; cập nhật `docs/STATE.md`, `docs/PHASE_W_PLAN.md` (gate W4)

Trong lúc chờ T010, được làm song song: Giai đoạn 4 (đọc nguồn) và phần M lõi (T048 trở đi) vì không phụ thuộc kết quả gate.

## Giai đoạn 3: US3, lưu tầng T3 (P1)

**Mục tiêu**: bảng nạp từ truy vấn vào `.pbix` và Desktop mở đúng. **Kiểm độc lập**: file Nhom6 có thêm bảng mới đủ kiểu, có `null`, có quan hệ; Desktop mở, số dòng/tổng/kiểu khớp; golden Nhom6 không đổi.

- [ ] T012 [US3] [VM] **VM-F1** (bạn làm tay hoặc cho phép Claude điều khiển): trong Desktop nạp `build/f-out/samples/sales_2026.csv` và `.xlsx` vào một bản sao Nhom6, lưu; Claude đọc file bằng PBIXKit và ghi `docs/phase-f-evidence/vm-f1/QUAN-SAT.md`: dòng `Table/Column/Partition/ColumnStorage/DictionaryStorage/Segment/AttributeHierarchy/Relationship` của bảng mới, `H$`, bảng hệ thống, kiểu `DataType` từng loại cột, `Partition.QueryDefinition` (M), `DataMashup`, thống kê min/max/distinct; so với `VertiPaqWriter` hiện tại
- [ ] T013 [US3] [LEAD] Test trước (red) `Tests/PBIXKitTests/VertiPaqWriterV2Tests.swift`: bảng đủ kiểu `int64`, `currency`, `double`, `dateTime`, `boolean`, `string` có `null` ở mọi kiểu, 100 và 100 000 dòng; `VertiPaq.decodeTable` đọc lại từng ô trùng nguồn (không hard-code); RLE khi giá trị lặp; quá 8 triệu dòng/segment ném lỗi rõ
- [ ] T014 [US3] [LEAD] `Sources/PBIXKit/Writing/VertiPaqWriter.swift`: mở rộng `Values` (`currency`, `dateTime`, `boolean`, `int64/double` có `nil`), RLE (bề rộng bit và lớp nén theo `bitWidthAndClass`), thống kê, đúng bản quan sát T012; `Tests` T013 xanh
- [ ] T015 [US3] [LEAD] `Sources/PBIXKit/Writing/TableMetadataWriter.swift`: `addTable` ghi cột mọi kiểu, `Partition` có biểu thức M (`QueryDefinition`, kiểu "M"), `DictionaryStorage`, `ColumnStorage`, `Segment`, `AttributeHierarchy` (+ `H$` nếu T012 cho thấy cần), `MAXID`; test `Tests/PBIXKitTests/TableMetadataWriterV2Tests.swift` đọc lại bằng `ModelMetadata`
- [ ] T016 [US3] [LEAD] `Sources/PBIXKit/Writing/ModelEdit.swift`, `ModelMetadata+Edit.swift`, `MetadataWriter.swift`: `ModelMetadata.applying(.addTable/.replaceTable/.dropTable)` kiểm hợp lệ (tên bảng/cột duy nhất không phân biệt hoa thường, không NUL, không trùng measure); `replaceTable` giữ quan hệ và measure khi cột còn, trả danh sách chỗ dùng khi cột mất (FR-054); test `ModelEditTableTests.swift`
- [ ] T017 [US3] [LEAD] `Sources/PBIXKit/Writing/RelationshipIndex.swift`, `PBIXWriter.swift`, `Contracts.swift`: chỉ mục `R$` và quan hệ từ/đến bảng mới (nấc 3), `PBIXChanges.tier = .data` và `PBIXChanges.tables: [LoadedTable]`; `PBIXWriter.build` ghi bảng, giữ nguyên byte phần không đụng; test `PBIXWriterTableTests.swift` (bảng mới + quan hệ tới `Dim_*`; đọc lại khớp)
- [ ] T018 [US3] [LEAD] `Sources/PBIXKit/DataMashup.swift` + `Tests/PBIXKitTests/DataMashupTests.swift`: **Spike S2** đọc `DataMashup` của file Desktop (Nhom6 và file T012) theo MS-QDEFF công khai: phiên bản, gói ZIP (`Formulas/Section1.m`, `Config/Package.xml`), phần quyền, metadata XML, `PermissionBindings` chép nguyên byte; ghi `docs/phase-f-evidence/vm-f1/DATAMASHUP.md`
- [ ] T019 [US3] [LEAD] `Sources/PBIXKit/DataMashup.swift`: `write` (cập nhật `Section1.m` và metadata theo danh sách truy vấn, giữ `PermissionBindings`); `PBIXFile`/`PBIXWriter` ghi `DataMashup` khi có truy vấn; test round-trip: đọc → ghi → đọc ra cùng danh sách truy vấn và cùng byte phần quyền
- [ ] T020 [US3] [LEAD] `Sources/BIPro/Model/Edit/ModelRuntime.swift`, `Sources/ColumnStore/OverlayColumnSource.swift`: nguồn cột chồng (`ColumnSource` gốc + `TableData` mới/thay); engine tạo lại khi `.addTable/.replaceTable/.dropTable`, dùng chung `ColumnStore` đã giải mã; test `Tests/BIProTests/Model/TableOverlayTests.swift` (DAX `SUM` trên bảng mới; quan hệ tới bảng mới)
- [ ] T021 [US3] [LEAD] `Sources/BIPro/Model/Edit/TableLoader.swift`, `ModelEditor`, `LayoutEditor.swift`: `TableLoader.apply(LoadedTable)` qua `ModelEditor.commit` (một bước ⌘Z, `TableData` giữ tham chiếu không sao chép mỗi snapshot); test hoàn tác/làm lại bảng mới, bảng thay thế, bảng xoá (FR-004, FR-080)
- [ ] T022 [US3] [LEAD] `Sources/BIPro/Report/Edit/DocumentSaver.swift`: nhánh T3 (ghi tệp tạm → `verifyModel` mở rộng: đọc lại từng ô, distinct count, metadata, `DataMashup` phân tích lại, `Report/**` nguyên byte, `integrity_check`, `MAXID` → thay file); thất bại giữ file gốc (FR-051); test `DocumentSaverT3Tests.swift` gồm lưu hai lần liên tiếp (ID/`MAXID`/mốc thời gian lần hai)
- [ ] T023 [US3] [LEAD] **Spike S5** hiệu năng: bảng sinh 100 000 và 1 000 000 dòng (10 cột): đo mã hoá + ghi + đọc lại + bộ nhớ đỉnh (bản release); ghi `specs/010-f-get-data-power-query-t3/measurements.md`; nếu vượt SC-004 (1 triệu dòng < 15 s, 100 000 dòng < 4 s) hoặc SC-005 (2 GB) thì chuyển ghi nền có thanh tiến trình
- [ ] T024 [US3] [LEAD] Test nặng `Tests/BIProTests/Model/F3Nhom6Tests.swift` (`BIPRO_HEAVY`): thêm bảng mới (từ `sales_2026.csv` 10 000 dòng đủ kiểu, có `null`) vào bản sao Nhom6, quan hệ tới `Dim_*`, một measure `SUM` trên cột mới; lưu T3 qua `DocumentSaver`; mở lại: từng ô, tổng, số dòng khớp; golden Nhom6 (30 DAX) không đổi; thêm ca file có RLS/`SecurityBindings`: sau khi lưu T3, `SecurityBindings` và phần quyền `DataMashup` giữ nguyên byte, mở lại đọc được
- [ ] T025 [US3] [LEAD] `build/f-out/F3/Nhom6_f1.pbix` + `docs/phase-f-evidence/vm-f1/CHECKLIST.md`: bộ ≥ 5 file F-T3 (nhiều kiểu và `null`; một bảng; ba bảng cùng lúc; có quan hệ và measure; 100 000 dòng), mỗi file một mục kiểm trong Desktop (mở không báo lỗi, số dòng, kiểu, tổng, quan hệ hoạt động) (SC-006)
- [ ] T026 [US3] [VM] Gate F-T3 đầy đủ: bạn mở các file ở T025, ghi `docs/phase-f-evidence/vm-f1/CHECKLIST-KET-QUA.md` (ảnh cắt không lộ tài khoản)
- [ ] T027 [US3] [LEAD] Dọn: xoá file thử trên VM và `build/f-out/F3` sau buổi; `docs/STATE.md` ghi kết quả gate; nếu trượt một phần, tạo task sửa theo `CHECKLIST-KET-QUA.md` rồi lặp T025–T026
- [ ] T028 [US3] [LEAD] Test nhận diện giới hạn: bảng > 8 triệu dòng, tên cột trùng không phân biệt hoa thường, ký tự NUL, bề rộng bit > 32, cột kiểu chưa hỗ trợ: báo lỗi tiếng Việt, không ghi nửa chừng (`Tests/BIProTests/Model/DocumentSaverT3Tests.swift`)

### Nhánh dự phòng Enter Data (chỉ làm khi T011 ghi "trượt")

- [ ] T029 [US3] [VM] Quan sát bảng Enter Data của Desktop (nhập 5 dòng tay, lưu): đọc `Partition.QueryDefinition`, `Section1.m`, cách nén dữ liệu trong M; ghi `docs/phase-f-evidence/vm-f1/ENTER-DATA.md`
- [ ] T030 [US3] [LEAD] `Sources/PBIXKit/Writing/EnterDataTable.swift` + test: sinh biểu thức Enter Data từ `TableData` (≤ 10 000 dòng, FR-052), `PBIXChanges.tier = .metadata` thay vì `.data`; bảng lớn hơn giữ trong phiên và cảnh báo khi lưu
- [ ] T031 [US3] [VM] Gate Enter Data: file bảng 100 và 10 000 dòng mở trong Desktop, Refresh chạy được; ghi kết quả vào `docs/phase-f-evidence/vm-f1/CHECKLIST-KET-QUA.md`

## Giai đoạn 4: US1, Get Data, Navigator, nạp bảng (P1)

**Mục tiêu**: Get Data → chọn CSV/Excel → Navigator → Load → bảng mới trong mô hình. **Kiểm độc lập**: nạp `sales_2026.csv` vào bản sao Nhom6, thêm card `SUM`, lưu, mở lại BI Pro và Desktop: cùng số dòng/kiểu/tổng.

- [ ] T032 [US1] [VM] **VM-F2**: bạn làm tay trong Desktop (hoặc cho phép Claude điều khiển): Get Data → Text/CSV và Excel với `sales_2026.*`; quan sát Navigator (cây, xem trước, nút), kiểu dò, tiêu đề tự thăng cấp, dấu phân cách/mã hoá mặc định, đặt tên bảng và hậu tố khi trùng, Load nhiều mục, Excel bảng đặt tên so trang tính; ghi `docs/phase-f-evidence/vm-f2/QUAN-SAT.md` và xuất bảng đã nạp (golden)
- [X] T033 [US1] [LEAD] `docs/tasks/f-conn1.md`: brief cho gói F-CONN1 (mục tiêu, file được sửa `Sources/Connectors/{CSV,Excel,JSON,SQLite}/**` và `Tests/ConnectorsTests/**`, "không sửa gì ngoài danh sách", lệnh `swift build`/`swift test`, tiêu chí: xem trước ≤ 200 dòng, kiểu dò theo T032, golden từ file mẫu T007, không hard-code, không thư viện ngoài/mạng, báo cáo `docs/tasks/f-conn1-report.md`) **Trước khi giao**: `git status` phải sạch; nếu lead còn thay đổi dở thì dừng và hỏi bạn commit trước (worktree con chỉ có phần đã commit, CLAUDE.md).
- [X] T034 [US1] [AGY:F-CONN1] [P] `Sources/Connectors/CSV/CSVSource.swift`: đọc CSV (tự dò UTF-8/UTF-16/Windows-1252 và dấu phân cách `,` `;` tab, ngoặc kép, ô nhiều dòng, tiêu đề), kiểu cột theo quy tắc T032, `preview` không đọc hết file; `Tests/ConnectorsTests/CSVSourceTests.swift` (file mẫu T007, ca xấu: số lẫn chữ, chuỗi rỗng, `null`)
- [X] T035 [US1] [AGY:F-CONN1] [P] `Sources/Connectors/Excel/ExcelSource.swift`: đọc `.xlsx` (ZIP qua `ZipArchive`, `deflate` qua `Compression`, XML qua `XMLParser`): `workbook.xml`, `sharedStrings`, `sheetN`, `styles` (nhận ô ngày), bảng đặt tên, hệ ngày 1900/1904, ô công thức lấy giá trị đã tính, ô trống/gộp; `preview` đọc theo luồng; `Tests/ConnectorsTests/ExcelSourceTests.swift`
- [X] T036 [US1] [AGY:F-CONN1] [P] `Sources/Connectors/SQLite/SQLiteSource.swift`: liệt kê bảng/khung nhìn, `preview`, `load` bằng `sqlite3` đã liên kết, ánh xạ kiểu; `Tests/ConnectorsTests/SQLiteSourceTests.swift`
- [X] T037 [US1] [AGY:F-CONN1] [P] `Sources/Connectors/JSON/JSONSource.swift`: mảng bản ghi → bảng (cột `Record`/`List` cho phần lồng); `Tests/ConnectorsTests/JSONSourceTests.swift`
- [X] T038 [US1] [LEAD] Chạy worker F-CONN1 (orca, worktree riêng, `agy` không `--dangerously-skip-permissions`, cấp danh sách lệnh), đặt MỘT lệnh nền chờ `"event":"result"`, cập nhật `docs/STATE.md`, rồi review: `git diff --stat` chỉ file được giao, đọc báo cáo, chạy `swift build`/`swift test`; không tự merge
- [X] T039 [US1] [LEAD] `Sources/BIPro/Query/NavigatorState.swift`, `Sources/BIPro/Model/Edit/TableLoader.swift`: luồng chọn nguồn → liệt kê mục → xem trước → "Load": mỗi mục thành `LoadedTable` (tên từ trang tính/tên file, hậu tố khi trùng như T032, FR-004), tiến độ và huỷ (`Task` cancellation), lỗi tiếng Việt, không đổi mô hình khi lỗi (FR-005)
- [X] T040 [US1] [LEAD] `docs/tasks/f-ui-navigator.md`: brief gói F-UI cho Get Data + Navigator (file `Sources/BIPro/Shell/GetDataDialog.swift`, `Sources/BIPro/Query/Editor/Navigator*.swift`, test `Tests/BIProTests/Query/Editor/`), vẽ từ `NavigatorState`, màu hệ thống `#0A84FF`, đặt cạnh `UIdesign/get_data_dialog` và `navigator_dialog_fixed` (lệch < 4 px), xuất PNG `build/f-out/ui/` và tự xem, tiếng Việt **Trước khi giao**: `git status` phải sạch; nếu lead còn thay đổi dở thì dừng và hỏi bạn commit trước (worktree con chỉ có phần đã commit, CLAUDE.md).
- [ ] T041 [US1] [AGY:F-UI] `Sources/BIPro/Shell/GetDataDialog.swift`, `Sources/BIPro/Query/Editor/NavigatorView.swift`: hộp thoại Get Data (danh mục: Text/CSV và Excel dùng được; JSON, SQLite, Parquet, PostgreSQL hiện xám "P3" cho đến khi làm T088 và T093 mới bật; reader JSON và SQLite viết sớm ở T036–T037 nhưng chưa nối giao diện) và Navigator (cây mục, xem trước, Load / Transform Data / Cancel); chạy cùng worker hoặc sau T038 (tuần tự nếu cùng worktree)
- [ ] T042 [US1] [LEAD] Review F-UI (như T038): `git diff --stat`, ảnh PNG so thiết kế, build/test
- [ ] T043 [US1] [LEAD] `Sources/BIPro/Shell/Ribbon.swift`: nút "Get data" (Home, Report/Table/Model) mở `GetDataDialog`; "Load" gọi `TableLoader`; bảng mới hiện ở Data pane, Table View, Model View (thẻ mới trong `DiagramLayout` tab "All tables"); cột "Bảng mới" vẫn là Phase F (US6)
- [ ] T044 [US1] [LEAD] Test `Tests/BIProTests/Model/GetDataTests.swift`: CSV và Excel nhiều trang tính → nhiều bảng; ⌘Z/⇧⌘Z; lỗi file hỏng/trống/sai mã hoá; truy vấn DAX trên bảng mới (`SUM`, `COUNTROWS`); card trong Report dùng cột mới
- [ ] T045 [US1] [LEAD] Bấm thử trong app (bản sao Nhom6 và tài liệu mới): Get Data CSV, Excel nhiều mục, Load, xem Table View, thêm card, ⌘S, mở lại; ghi `docs/STATE.md` "Đã bấm thử"
- [ ] T046 [US1] [VM] Gate: file `Nhom6_f2.pbix` (bảng từ CSV và Excel) mở trong Desktop, so số dòng, kiểu, tổng với bản Desktop tự nạp (T032); kết quả `docs/phase-f-evidence/vm-f2/CHECKLIST-KET-QUA.md`

## Giai đoạn 5: US2, Query Editor, ngôn ngữ M, Close & Apply (P1)

**Mục tiêu**: Transform Data → Applied Steps → Close & Apply. **Kiểm độc lập**: `sales_2026.xlsx`, thăng tiêu đề, đổi kiểu, lọc `Region = "North"`, bỏ cột, Close & Apply; số dòng và tổng khớp bản Desktop cùng bước.

- [ ] T047 [US2] [VM] **VM-F3**: trong Desktop làm luồng `sales_2026.xlsx` → Transform: thăng tiêu đề, đổi kiểu, đổi tên cột, bỏ cột, lọc dòng, sắp xếp, tách cột, thay giá trị, xoá trùng, xoay/bỏ xoay, điền xuống; Claude đọc `DataMashup`/`Section1.m` từ file lưu và ghi mỗi lệnh ribbon ↔ biểu thức M ↔ tên bước ("Source", "Navigation", "Promoted Headers", "Changed Type", …); quan sát column profile ("dựa trên 1000 dòng đầu"), thông báo lỗi bước, `Error` trong ô, chèn bước giữa (hộp thoại), Close & Apply ("Pending changes", "Enable load"), nạp lại bảng đã có quan hệ/measure; xuất bảng sau mỗi bước làm golden; `docs/phase-f-evidence/vm-f3/QUAN-SAT.md`
- [X] T048 [US2] [LEAD] `Tests/MEngineTests/ParserTests.swift` (red) rồi `Sources/MEngine/Lexer.swift`, `Parser.swift`: `let … in`, bản ghi, danh sách, `each`/`_`, hàm `(x) => …`, `if/then/else`, toán tử, `#table`, `#date`, `type table [..]`, chuỗi/định danh có `#"…"`; lỗi cú pháp kèm dòng/cột (FR-031); `[SUY ĐOÁN]` cho cú pháp chưa quan sát
- [X] T049 [US2] [LEAD] `Tests/MEngineTests/EvaluatorTests.swift` (red) rồi `Sources/MEngine/Evaluator.swift`, `Value.swift`: đánh giá lười theo môi trường bước, `null`, lỗi theo ô (giá trị, không ném), phép toán và so sánh theo kiểu, `rowLimit` (cắt sớm đúng 1000 dòng đầu), huỷ giữa chừng; hàm ngoài thư viện ném `MError.unsupported(tên, dòng)`
- [ ] T050 [US2] [LEAD] `docs/tasks/f-mfun.md`: brief gói F-MFUN: file `Sources/MEngine/Library/{TableColumns,TableRows,TextNumberDateList}.swift`, `Tests/MEngineTests/Library/**`; danh sách hàm: cột (`Table.PromoteHeaders`, `TransformColumnTypes`, `RenameColumns`, `RemoveColumns`, `SelectColumns`, `ReorderColumns`, `DuplicateColumn`, `AddColumn`, `AddIndexColumn`, `SplitColumn`, `CombineColumns`), dòng (`SelectRows`, `Sort`, `FirstN`, `LastN`, `Skip`, `RemoveFirstN`, `Distinct`, `ReplaceValue`, `FillDown`, `FillUp`, `ReplaceErrorValues`, `RemoveRowsWithErrors`), giá trị (`Text.*`, `Number.*`, `Date.*`, `List.*` cơ bản); mỗi hàm một test golden từ `docs/phase-f-evidence/vm-f3/` (bảng Desktop), đánh dấu `observed`; không sửa Evaluator/Parser (lead) **Trước khi giao**: `git status` phải sạch; nếu lead còn thay đổi dở thì dừng và hỏi bạn commit trước (worktree con chỉ có phần đã commit, CLAUDE.md).
- [ ] T051 [US2] [AGY:F-MFUN] [P] `Sources/MEngine/Library/TableColumns.swift`: các hàm cột theo T050, kiểu và `null` đúng golden; `Tests/MEngineTests/Library/TableColumnsTests.swift`
- [ ] T052 [US2] [AGY:F-MFUN] [P] `Sources/MEngine/Library/TableRows.swift`: các hàm dòng theo T050; `Tests/MEngineTests/Library/TableRowsTests.swift`
- [ ] T053 [US2] [AGY:F-MFUN] [P] `Sources/MEngine/Library/TextNumberDateList.swift`: hàm giá trị cơ bản (văn hoá `en-US` trừ khi quan sát khác); `Tests/MEngineTests/Library/ValueFunctionsTests.swift`
- [ ] T054 [US2] [LEAD] Chạy và review worker F-MFUN (như T038); so từng bảng với golden Desktop; hàm trượt ghi lại để lead sửa
- [ ] T055 [US2] [LEAD] `Sources/MEngine/Query.swift`: `MQuery` (tách `let … in` thành bước và dựng lại), `StepFactory` (mỗi lệnh ribbon cơ bản → đúng một bước, tên và biểu thức khớp T047); test `Tests/MEngineTests/StepFactoryTests.swift`
- [ ] T056 [US2] [LEAD] `Sources/MEngine/Profile.swift`, `Preview.swift`: `Table.Profile`/column profile (Valid/Error/Empty, Distinct/Unique, min/max/trung bình, phân bố, 1000 dòng đầu), cache xem trước theo bước và đánh giá lại từ bước bị đổi; test độ chính xác và `rowLimit`
- [ ] T057 [US2] [LEAD] `Sources/BIPro/Query/QueryEditorState.swift`: danh sách truy vấn, bước đang chọn, thêm/sửa/xoá/đổi thứ tự/chèn bước (hỏi như Desktop), xem trước, profile, lỗi bước, hoàn tác theo bước, "Pending changes"; test `Tests/BIProTests/Query/QueryEditorStateTests.swift`
- [ ] T058 [US2] [LEAD] `docs/tasks/f-ui-query-editor.md`: brief gói F-UI cho Query Editor: `Sources/BIPro/Query/Editor/**` (cửa sổ, cột Queries, lưới xem trước, Query Settings với Applied Steps, thanh công thức M, column profile, ribbon Home/Transform/Add Column/View), vẽ từ `QueryEditorState`; giao diện tiếng Việt, PNG kiểm; không sửa trạng thái **Trước khi giao**: `git status` phải sạch; nếu lead còn thay đổi dở thì dừng và hỏi bạn commit trước (worktree con chỉ có phần đã commit, CLAUDE.md).
- [ ] T059 [US2] [AGY:F-UI] `Sources/BIPro/Query/Editor/QueryEditorWindow.swift`, `AppliedStepsView.swift`, `PreviewGridView.swift`, `ColumnProfileView.swift`, `QueryRibbonView.swift`, `FormulaBarView.swift`; test `Tests/BIProTests/Query/Editor/` (xuất PNG `build/f-out/ui/`)
- [ ] T060 [US2] [LEAD] Review F-UI (như T038) và nối: "Transform Data" (Navigator, ribbon) mở Query Editor; mỗi lệnh ribbon gọi `StepFactory` qua `QueryEditorState`
- [ ] T061 [US2] [LEAD] `Sources/PBIXKit/DataMashup.swift`, `PBIXWriter`: ghi/đọc truy vấn M thật (mỗi truy vấn một mục trong `Section1.m`, `Partition.QueryDefinition`, cờ Enable load); mở file Desktop tạo (Nhom6) liệt kê đúng truy vấn và biểu thức (FR-014); test `DataMashupQueryTests.swift`
- [ ] T062 [US2] [LEAD] `Sources/BIPro/Model/Edit/TableLoader.swift`, `ModelEditor`: "Close & Apply" → `.addTable` hoặc `.replaceTable` (một bước ⌘Z chung với D/E, FR-080), tôn trọng "Enable load", cảnh báo cột mất kèm danh sách nơi dùng (FR-054); "Close" khi chưa áp dụng hỏi như T047
- [ ] T063 [US2] [LEAD] Test `Tests/BIProTests/Model/QueryApplyTests.swift`: luồng `sales_2026.xlsx` (thăng tiêu đề, đổi kiểu, lọc, bỏ cột) → Close & Apply → bảng đúng so golden Desktop; sửa truy vấn rồi Apply lần hai giữ quan hệ/measure; đổi bước ở giữa đánh giá lại; ⌘Z; lưu T3 và đọc lại cả `DataMashup`; ca nguồn bị xoá hoặc di chuyển sau khi lưu: mở file vẫn đọc dữ liệu đã lưu, Refresh báo lỗi nguồn rõ ràng, không mất bảng
- [ ] T064 [US2] [LEAD] Test nặng `F3Nhom6Tests`: truy vấn trên file lớn (1 triệu dòng) đo thời gian xem trước < 500 ms mỗi lần chuyển bước và Navigator xem trước < 3 s (SC-003); ghi `measurements.md`
- [ ] T065 [US2] [LEAD] Bấm thử trong app: Transform Data → bước → hộp thoại "Pending changes" → Close & Apply → report → ⌘S → mở lại; ghi `docs/STATE.md`
- [ ] T066 [US2] [VM] Gate F-Query: (a) Desktop mở file BI Pro lưu có truy vấn M (Power Query Editor hiện đúng truy vấn/bước; Refresh khi đường dẫn nguồn còn hợp lệ, ghi nhận kết quả), (b) BI Pro mở file Desktop tạo và liệt kê truy vấn; so golden; `docs/phase-f-evidence/vm-f3/CHECKLIST-KET-QUA.md`

## Giai đoạn 6: US4, biến đổi nâng cao (P2)

**Mục tiêu**: Custom Column, Merge, Append, Group By, Advanced Editor, Query Dependencies. **Kiểm độc lập**: Merge Left Outer theo `CustomerID` rồi mở rộng `Segment`; Append; Group By `Region` (`Sum(Amount)`, `Count rows`); Custom Column `[Qty] * [Price]`; khớp số liệu Desktop xuất.

- [ ] T067 [US4] [VM] **VM-F4**: quan sát trong Desktop: Custom Column, Merge (6 kiểu join, mở rộng cột bảng lồng, tên cột), Append (hai và nhiều truy vấn, khác tập cột), Group By (cơ bản, nâng cao nhiều phép), Advanced Editor, Query Dependencies; biểu thức M từng lệnh; xuất golden; `docs/phase-f-evidence/vm-f4/QUAN-SAT.md`
- [ ] T068 [US4] [LEAD] `Tests/MEngineTests/Library/JoinGroupTests.swift` (red) rồi `Sources/MEngine/Library/TableJoinGroup.swift`: `Table.Join`, `NestedJoin`, `ExpandTableColumn`, `Combine`, `Group`, `Pivot`, `Unpivot`, `UnpivotOtherColumns`, `Table.AddColumn` với công thức tuỳ ý; 6 kiểu join với khoá `null`/khác kiểu/hoa thường; khớp golden T067
- [ ] T069 [US4] [LEAD] `Sources/MEngine/Query.swift`, `StepFactory.swift`: sinh bước cho Custom Column, Merge, Append, Group By; Advanced Editor phân tích lại thành bước (phần không phân tích được giữ một bước `custom`); hàm ngoài danh sách báo "chưa hỗ trợ" kèm tên (FR-031); đồ thị `Dependencies` (tham chiếu, Merge, Append, nguồn), phát hiện vòng
- [ ] T070 [US4] [LEAD] `docs/tasks/f-ui-dialogs.md`: brief gói F-UI vòng 2: hộp thoại Custom Column, Merge Queries, Append Queries, Group By (cơ bản + nâng cao), Advanced Editor (có kiểm cú pháp), cửa sổ Query Dependencies; `Sources/BIPro/Query/Editor/Dialogs/**`; vẽ từ `QueryEditorState`; PNG kiểm **Trước khi giao**: `git status` phải sạch; nếu lead còn thay đổi dở thì dừng và hỏi bạn commit trước (worktree con chỉ có phần đã commit, CLAUDE.md).
- [ ] T071 [US4] [AGY:F-UI] `Sources/BIPro/Query/Editor/Dialogs/CustomColumnDialog.swift`, `MergeDialog.swift`, `AppendDialog.swift`, `GroupByDialog.swift`, `AdvancedEditorView.swift`, `QueryDependenciesView.swift`; test PNG
- [ ] T072 [US4] [LEAD] Review F-UI vòng 2 (như T038) và nối vào `QueryEditorState`
- [ ] T073 [US4] [LEAD] Test `Tests/BIProTests/Model/AdvancedQueryTests.swift`: Merge→mở rộng→Apply; Append hai bảng; Group By; Custom Column; Advanced Editor sửa tay làm lại bước; truy vấn tham chiếu truy vấn khác lan thay đổi; vòng tham chiếu báo lỗi
- [ ] T074 [US4] [VM] Gate: file `Nhom6_f3.pbix` có các truy vấn nâng cao mở trong Desktop (Power Query Editor, bảng nạp); `docs/phase-f-evidence/vm-f4/CHECKLIST-KET-QUA.md`

## Giai đoạn 7: US5, tạo `.pbix` mới từ đầu (P2)

**Mục tiêu**: File → Mới → Get Data → báo cáo → lưu. **Kiểm độc lập**: mới, nạp `sales_2026.xlsx`, card + cột, lưu; Desktop mở đúng.

- [ ] T075 [US5] [VM] **VM-F5** (S3): Desktop tạo file trống, lưu; và file chỉ có một bảng; Claude đọc, ghi tập thành phần tối thiểu, phiên bản, mô hình trống, `DataMashup` trống vào `docs/phase-f-evidence/vm-f5/QUAN-SAT.md` (không lưu file vào git)
- [ ] T076 [US5] [LEAD] `Sources/PBIXKit/Writing/NewDocument.swift` + `Tests/PBIXKitTests/NewDocumentTests.swift`: dựng tài liệu trống theo T075 (hoặc từ mẫu trống do Desktop tạo, đóng trong tài nguyên nếu dựng tay bị từ chối); `PBIXFile` đọc lại được
- [ ] T077 [US5] [LEAD] `Sources/BIPro/Workspace.swift`, `DocumentState.swift`, `App.swift`, `Ribbon.swift`: "File → Mới" (⌘N), `Workspace` chưa có file, hộp thoại lưu lần đầu (tên, vị trí, không ghi đè file khác), tài liệu trống lưu và mở lại được (FR-053); test `NewDocumentFlowTests.swift`
- [ ] T078 [US5] [LEAD] Test luồng đầy đủ `Tests/BIProTests/Model/F5NewDocTests.swift`: mới → Get Data → Close & Apply → thêm card và biểu đồ cột → lưu → đọc lại; bấm thử trong app
- [ ] T079 [US5] [VM] Gate: file mới mở trong Desktop (cùng bảng, visual, số); `docs/phase-f-evidence/vm-f5/CHECKLIST-KET-QUA.md`; ghi tập thành phần tối thiểu vào `docs/` (spec mục 3 kịch bản 5.3)

## Giai đoạn 8: US6, cột và bảng tính toán DAX (P2)

**Mục tiêu**: "Cột mới", "Bảng mới" ở Table View, lưu T3. **Kiểm độc lập**: `Doanh_thu = Fact[Qty] * Fact[Price]`; `Top_Region = SUMMARIZE(...)`; lưu; Desktop thấy cùng giá trị.

- [ ] T080 [US6] [VM] **VM-F6** (S4): trong Desktop thêm cột tính toán và bảng tính toán vào bản sao có bảng từ T046; Claude đọc dòng `Column` (kiểu Calculated, `Expression`, `State`), `Partition` kiểu Calculated, dữ liệu VertiPaq của cột/bảng (có ghi sẵn không), thứ tự tính; `docs/phase-f-evidence/vm-f6/QUAN-SAT.md`
- [ ] T081 [US6] [LEAD] `Sources/DAXEngine/**`: đánh giá biểu thức theo ngữ cảnh hàng cho cột tính toán (kiểm `EARLIER`, `RELATED`, `RELATEDTABLE`) và ra bảng cho bảng tính toán; kết quả thành `TableData`/`ColumnData`; test `Tests/DAXEngineTests/CalculatedColumnTests.swift` (so từng dòng với golden Desktop T080, không hard-code)
- [ ] T082 [US6] [LEAD] `Sources/BIPro/Model/Edit/CalculatedEditor.swift`, `ModelEdit`, `ModelRuntime`: `.addCalculatedColumn/.addCalculatedTable`, đồ thị phụ thuộc, thứ tự tính (tô-pô), vòng phụ thuộc báo lỗi, tính lại khi dữ liệu nguồn đổi, hoàn tác; test `Tests/BIProTests/Model/CalculatedTests.swift` (gồm ca cột tính toán tham chiếu cột của bảng bị nạp lại bằng Query Editor: cột còn thì tính lại, cột mất thì chặn và báo danh sách)
- [ ] T083 [US6] [LEAD] `Sources/BIPro/Table/FormulaBar*`, `Ribbon.swift`: nối "Cột mới" và "Bảng mới" (đang là nút giữ chỗ) vào thanh công thức `Tên = DAX`; hiển thị cột tính toán ở Data pane (biểu tượng riêng) và Table View
- [ ] T084 [US6] [LEAD] `PBIXWriter`/`TableMetadataWriter`: ghi cột/bảng tính toán theo T080 (T3, có dữ liệu VertiPaq nếu Desktop ghi sẵn); test lưu và đọc lại; test nặng trên Nhom6 (golden không đổi)
- [ ] T085 [US6] [VM] Gate: file `Nhom6_f4.pbix` có cột và bảng tính toán mở trong Desktop, cùng giá trị từng dòng và số dòng, không cần Refresh; `docs/phase-f-evidence/vm-f6/CHECKLIST-KET-QUA.md`

## Giai đoạn 9: US7, Parquet và JSON (P3, làm sau cùng, cắt được)

**Mục tiêu**: Get Data nhận Parquet và JSON (tập con tự viết). **Kiểm độc lập**: nạp `sales_2026.parquet` và `orders.json` (mảng lồng); số dòng và giá trị khớp bản Desktop.

- [ ] T086 [US7] [VM] **VM-F7a**: Desktop nạp `orders.json` (mảng lồng) và `sales_2026.parquet` (nếu có tệp từ T089); ghi biểu thức M (`Json.Document`, `Table.FromRecords`, `Table.ExpandRecordColumn`, `Table.ExpandListColumn`, `Parquet.Document`), kiểu ánh xạ; `docs/phase-f-evidence/vm-f7/QUAN-SAT.md`
- [ ] T087 [US7] [LEAD] `Sources/MEngine/Library/Json.swift` (`Json.Document`, `Table.FromRecords`, `Table.ExpandRecordColumn`, `Table.ExpandListColumn`, `Record.*`, `List.*` còn thiếu) + test golden T086
- [ ] T088 [US7] [LEAD] `Sources/Connectors/JSON/JSONSource.swift` nối Navigator, bước "Expand" trong Query Editor; test `GetDataJSONTests.swift`
- [ ] T089 [US7] [LEAD] `Sources/Connectors/Parquet/ParquetSource.swift`: tập con (footer Thrift compact, trang `PLAIN`/`RLE_DICTIONARY`, nén `UNCOMPRESSED`/`SNAPPY`/`GZIP`; `zstd`/`brotli` báo "chưa hỗ trợ" kèm tên); tệp mẫu: dùng công cụ chuẩn trên máy nếu có, hoặc tệp Parquet thật do bạn cung cấp; nếu không có thì tự dựng bằng bộ ghi tối giản trong test và GHI RÕ giới hạn: đối chứng yếu vì chỉ so với mã tự viết, không thay được golden thật; ánh xạ kiểu như T086; `Tests/ConnectorsTests/ParquetSourceTests.swift`
- [ ] T090 [US7] [LEAD] Test lớn (1 triệu dòng) Navigator và xem trước < 3 s (SC-003); bấm thử và gate Desktop `docs/phase-f-evidence/vm-f7/CHECKLIST-KET-QUA.md`

## Giai đoạn 10: US8, SQLite và PostgreSQL trong Get Data (P3, làm sau cùng, cắt được)

- [ ] T091 [US8] [VM] **VM-F7b**: Desktop nạp `sales_2026.sqlite` (ODBC/Sqlite) và PostgreSQL cục bộ nếu bạn có máy chủ (không tải gì từ mạng); biểu thức M kết nối, hộp thoại, kiểu xác thực; `docs/phase-f-evidence/vm-f7/QUAN-SAT-DB.md` (không ghi mật khẩu, tên máy chủ thật có thể thay bằng `localhost`)
- [ ] T092 [US8] [LEAD] `Sources/Connectors/Postgres/PostgresSource.swift`, `Sources/Connectors/Credentials.swift`: giao thức v3 đơn giản qua `Network.framework`, xác thực SCRAM-SHA-256 (CryptoKit), kiểu cơ bản (int2/4/8, numeric, float, text/varchar, boolean, date/timestamp); liệt kê lược đồ/bảng/khung nhìn; mật khẩu CHỈ ở Keychain (FR-071); kiểu khác báo "chưa hỗ trợ" kèm tên; test `PostgresSourceTests.swift` với máy chủ cục bộ do bạn cho phép, bỏ qua khi thiếu
- [ ] T093 [US8] [LEAD] `Sources/BIPro/Shell/GetDataDialog.swift`, `Navigator` (tệp của gói F-UI: chỉ sửa sau khi worker F-UI đã bàn giao và T042 xong, hoặc đưa phần nối này vào brief F-UI): nối SQLite (đợt 1, đã có nguồn ở T036) và PostgreSQL vào hộp thoại, biểu mẫu kết nối, lỗi xác thực tiếng Việt không lộ mật khẩu; test không có mật khẩu trong `.pbix`/nhật ký (`GetDataSecretsTests.swift` quét kết quả lưu)
- [ ] T094 [US8] [VM] Gate: SQLite và PostgreSQL nạp vào bản sao Nhom6, mở trong Desktop; `docs/phase-f-evidence/vm-f7/CHECKLIST-KET-QUA.md`

## Giai đoạn 11: Hoàn thiện, tích hợp, review (không có nhãn câu chuyện)

- [ ] T095 [LEAD] Chạy golden nặng đầy đủ `BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --no-parallel --filter "Nhom6|ORA|VIS|Batched"` và `swift test`: 30 DAX và 72 truy vấn visual không đổi (SC-007), không test nào bị tắt; ghi số vào `docs/STATE.md`
- [ ] T096 [LEAD] `/code-review` toàn bộ thay đổi Phase F (hai trục Chuẩn và Đặc tả), sửa lỗi tìm được; ghi kết quả
- [ ] T097 [LEAD] `/speckit-converge` đối chiếu mã với `spec.md`, `plan.md`, `tasks.md`; thêm task cho phần chưa dựng
- [ ] T098 [LEAD] Rà `FR-001…FR-082` ↔ test; bổ sung test còn thiếu; kiểm SC-001 (luồng `sales_2026.xlsx` đầy đủ < 5 phút thao tác, số khớp 100%), SC-004, SC-005, SC-006, SC-008 (không mất thay đổi âm thầm khi đóng Query Editor)
- [ ] T099 [LEAD] `zsh scripts/build-app.sh` dựng lại `build/BI Pro.app`; bấm thử toàn bộ luồng chính (Get Data, Query Editor, Close & Apply, cột tính toán, file mới) và ghi vào `docs/STATE.md`
- [ ] T100 [VM] Gate tổng M3: luồng `sales_2026.xlsx` → Query Editor → Close & Apply → report → lưu `.pbix` → mở trong Desktop (SC-001, SC-009); `docs/phase-f-evidence/CHECKLIST-M3.md`
- [ ] T101 [LEAD] `docs/STATE.md`, `docs/BIPRO_BUILD_PLAN.md` (đánh dấu từng mục Phase F và mốc M3), `docs/PHASE_W_PLAN.md` (kết quả gate W4), memory `project-phase-f-status.md` + `vm-driving-notes.md` (điều mới học), `docs/phase-f-evidence/` (ảnh cắt, QUAN-SAT); dọn mọi thư mục VM và file tạm (`build/f-out`, `~/Desktop/*out`, ảnh chụp); mục "Tồn đọng" cho phần chưa xong
- [ ] T102 [LEAD] Báo bạn kết quả từng gói/worker, file đã đổi, việc tồn đọng; không tự commit/push/merge/xoá worktree, chỉ làm khi bạn yêu cầu

## Phụ thuộc và thứ tự

- Giai đoạn 1 → mọi giai đoạn sau. T010 (gate F-T3) chặn T014 trở đi trong Giai đoạn 3 từ nấc 2 (kiểu đầy đủ, RLE) nhưng T013 và các test viết trước vẫn làm được; **không chặn** Giai đoạn 4 (đọc nguồn) và T048–T056 (M lõi).
- Giai đoạn 3 (US3) → Giai đoạn 4 (US1) cần `TableLoader`/`ModelRuntime` (T020, T021); US1 → US2 (Query Editor mở từ Navigator); US2 → US4; US3 + US2 → US5; US3 → US6 (cùng đường ghi); US7 sau US2; US8 sau US1 và US7.
- VM-F1…F7 đặt ngay trước phần code tương ứng, nhưng khi đợi bạn làm tay thì làm tiếp phần không phụ thuộc quan sát đó.
- Gói agy chạy sau Đợt 0: F-CONN1 (T033–T038) song song được với F-MFUN (T050–T054) vì sở hữu file không giao nhau; F-UI (T040–T042, T058–T060, T070–T072) làm sau khi `NavigatorState`/`QueryEditorState` ổn định; tối đa 3 worker, `git status` phải sạch trước khi giao.

## Song song điển hình

- T004, T005, T006, T007, T008 sau T002/T003.
- T034 đến T037 (bốn nguồn, bốn thư mục) trong cùng gói F-CONN1; T051, T052, T053 (ba tệp hàm M) trong cùng gói F-MFUN; hai gói chạy cùng lúc, lead làm T013–T022 và T048–T049.
- Hộp thoại UI (T071) song song với M nâng cao (T068) vì tệp khác nhau.

## Chiến lược triển khai

- **MVP = Giai đoạn 1 đến 5** (US3 → US1 → US2): đạt điều kiện "xong khi" của phase (luồng `sales_2026.xlsx` mở được trong Desktop). Sau T066 là điểm dừng được.
- Tăng dần: US4 → US5 → US6 (P2), rồi US7, US8 (P3). Nếu M3 trễ thì cắt P3 trước, không cắt P1/P2 (plan, "Cần bạn quyết" 4).
- Mọi lát kết thúc bằng gate Desktop (do bạn làm tay), kiểm golden nặng ở lát đụng engine, và cập nhật `docs/STATE.md`.
