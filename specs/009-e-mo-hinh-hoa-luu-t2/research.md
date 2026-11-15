# Nghiên cứu Phase E

Nguồn quan sát: `docs/phase-e-evidence/vm-e1/QUAN-SAT.md` (Power BI Desktop trong VM, 2026-11-14, bản sao Nhom6) và mã hiện có. Mục nào dựa trên suy đoán ghi `[SUY ĐOÁN]` và có buổi VM-E tương ứng trong `tasks.md`.

## R1. Một mô hình hiệu lực cho giao diện, engine và lưu

- **Quyết định**: mọi sửa mô hình là một giá trị `ModelEdit` trong `ModelEdits` (danh sách có thứ tự). `ModelMetadata.applying(_:)` tạo `ModelMetadata` mới cho giao diện (Table/Model/TMDL View, ngăn Dữ liệu) và cho `Catalog`. Lúc lưu, cũng chính danh sách này được áp lên `metadata.sqlitedb`.
- **Lý do**: không có hai đường (một đường cho hiển thị, một đường cho ghi) nên không lệch nhau; `TMDLWriter.documents(for:)` sinh TMDL từ mô hình hiệu lực nên TMDL View tự cập nhật (FR-014). Giống cách D1 đến D7 giữ `edits` rồi `makeChanges`.
- **Loại**: sửa `Workspace` tại chỗ (bất biến, dùng đa luồng); ghi SQLite ngay từng bước (không hoàn tác được, chậm).

## R2. Ghi metadata: đúng như Desktop (QUAN-SAT mục 1 đến 3)

- **Thêm measure**: giữ `MetadataWriter.addMeasure` (đã được Desktop mở ở W3). Khác Desktop chỉ ở `FormatString` (Desktop đặt `'0'` cho kết quả nguyên) và `DataType` (Desktop suy từ biểu thức): xử lý ở R3.
- **Sửa measure**: `UPDATE` tại chỗ (giữ `ID`, `LineageTag`, `StructureModifiedTime`), đổi `Expression`, `Description`, `DisplayFolder`, `FormatString`, `IsHidden`, `Name`, `ModifiedTime`; cập nhật `DBPROPERTIES` `LASTCUBEDATACHANGE`, `LASTCUBESCHEMACHANGE`, `LASTCOMMITTED`, `LASTMETADATACHANGEFORSYNCCOMMITTED`. Không cần sinh lại `Culture`/`LinguisticMetadata` (W3 chạy được không có).
- **Xoá measure**: `DELETE` dòng `Measure` (và dòng phụ có `ObjectID` đó: `Annotation`, `ExtendedProperty`, `FormatStringDefinition`, ...); quan sát VM-E2: Desktop xoá dòng `Measure`, cập nhật `Table.ModifiedTime` của bảng chứa và bốn `DBPROPERTIES`; thêm measure cũng cập nhật `Table.ModifiedTime`.
- **Sửa quan hệ**: `UPDATE Relationship` (`CrossFilteringBehavior` 1 đơn, 2 hai chiều; `IsActive`; `ModifiedTime`); không đụng `RelationshipStorage`/`RelationshipIndexStorage`. Các dòng `Column` Desktop tự đổi (`SummarizeBy`, `Annotation SummarizationSetBy`) là tác dụng phụ của Desktop, BI Pro **không** bắt chước.
- **Sửa cột**: `UPDATE Column` (tên, `IsHidden`, `FormatString`, `SummarizeBy`, `DataCategory`, `SortByColumnID`, `DisplayFolder`, `Description`). [SUY ĐOÁN] cách ghi từng thuộc tính và `Annotation` kèm (ví dụ `SummarizationSetBy`); kiểm ở VM-E3 trước khi code Câu chuyện 3.
- **Mốc thời gian và `MAXID`**: dùng bộ đếm sẵn của `MetadataWriter` (thêm dòng thì `MAXID`+1; Desktop còn dùng thêm ID cho `Culture`, không bắt buộc).

## R3. Suy kiểu và định dạng của measure

- **Quyết định**: khi áp dụng, chạy `EVALUATE ROW("x", <biểu thức>)` qua engine để biết kiểu kết quả → `DataType` (Int64 6, Double 8, Decimal 10, String 2, Boolean 11, DateTime 9). `FormatString` mặc định theo kết quả như Desktop ghi (VM-E2, `docs/phase-e-evidence/vm-e2/QUAN-SAT.md`): nguyên và `BLANK()` → Int64 `'0'`; số thực → Double không định dạng; chuỗi → String không định dạng; logic → Boolean `"TRUE";"TRUE";"FALSE"`; ngày giờ → DateTime `General Date`; tiền tệ [SUY ĐOÁN] (chưa quan sát). Người dùng đổi định dạng sau bằng chọn "Format" (danh sách đã có ở D4/`FormatCatalog`).
- **Lỗi bind/parse**: chặn áp dụng, báo vị trí. Lỗi chỉ lộ ra khi chạy (chia cho 0, kiểu) thì cho áp dụng với `State`=1 và hiện giá trị lỗi ở vùng xem thử (Desktop cũng cho). Quan sát VM-E2: Desktop vẫn lưu measure sai tên hàm với `State` 5, `DataType` 19, `ErrorMessage` dạng `<Errors><Error><Hresult>…</Hresult><Notes>…`; BI Pro vẫn chặn (không để measure lỗi trong mô hình).
- **Phương án loại**: để `DataType` cố định như `measureDataType` hiện nay (Desktop sẽ tính lại khi mở nhưng giao diện BI Pro hiển thị sai kiểu).

## R4. Engine nạp lại sau thay đổi mô hình

- **Quyết định**: `ModelRuntime` giữ `ColumnStore` đã giải mã từ `Workspace` và bọc nó bằng `DAXEngine(store:catalog:)` mới mỗi khi mô hình hiệu lực đổi. Đổi/thêm/xoá measure chỉ đổi `Catalog` (nhẹ, bộ nhớ đệm đệm của engine mới rỗng). Đổi hoạt động/hướng lọc quan hệ: dùng cơ chế `RelationshipOverride` của `ColumnStore` nếu `Evaluator` cho áp mặc định cho mọi truy vấn; nếu không thì dựng `ColumnStore` mới với `ModelSchema(metadata:)` mới.
- **[SUY ĐOÁN] chi phí**: dựng `ColumnStore` mới có phải giải mã lại cột (Fact_Transaction ~1 triệu hàng) hay dùng lại được cache: đo ở spike S2 (đầu Câu chuyện 2a). Mục tiêu vẽ lại < 1 s (SC-004).
- **Visual**: đã vẽ lại theo `layoutRevision`/khoá nạp lại của `LiveVisual`; thêm khoá "phiên bản mô hình" vào khoá nạp để các visual dùng measure đổi tự nạp lại; visual không dùng measure đổi không cần nạp (so bằng tập tên đã thay đổi).

## R5. Hoàn tác chung với D1 đến D7

- **Quyết định**: `LayoutSnapshot` thêm `model: ModelEdits`; `ModelEditor` luôn đi qua cơ chế `pushUndo` của `LayoutEditor`, gộp các lần sửa liên tiếp cùng một thuộc tính (cửa sổ gộp hiện có). ⌘Z đưa `ModelEdits` về, `ModelRuntime` tạo lại engine. `isDirty` tính cả mô hình.
- **Lý do**: một ngăn xếp (FR-016); người dùng không cần biết sửa nào thuộc báo cáo hay mô hình.
- **Chú ý**: khi hoàn tác một thay đổi mô hình mà báo cáo (visual) đã dùng nó (ví dụ xoá measure rồi hoàn tác) vẫn nhất quán vì xoá bị chặn khi còn dùng (R6); thêm measure → thêm visual dùng nó → ⌘Z hai lần theo thứ tự đúng nhờ ngăn xếp chung.

## R6. Tham chiếu: chặn xoá và đổi tên

- **Quyết định**: `ModelReferences.usages(of:)` quét: (a) mọi visual, bộ lọc, bookmark (mở rộng `FieldReferences.find` cho measure và tên bảng); (b) biểu thức DAX của measure và cột tính toán khác bằng `Lexer` của `DAXEngine` (token `[Tên]`, `Bảng[Tên]`, `'Bảng'[Tên]`, không dùng regex vì chuỗi và chú thích); (c) `Relationship` (hai đầu), `SortByColumnID`, `Hierarchy.Level`. Xoá và đổi tên bị chặn khi có kết quả, lý do liệt kê tối đa 10 nơi kèm "và N nơi nữa" (FR-004, FR-020).
- **[SUY ĐOÁN]** Desktop xử lý ngoại lệ (measure chỉ được dùng ở ẩn) thế nào: chưa quan sát; BI Pro chặn thận trọng.
- **Loại**: tự viết lại tham chiếu như Desktop (đã chốt hoãn).

## R7. Tạo và xoá quan hệ: chỉ mục `R$`

- **Phát hiện** (QUAN-SAT mục 4): mỗi quan hệ có `RelationshipStorage` → `RelationshipIndexStorage` (`RecordCount`, `SystemTableID`) và một bảng hệ thống `R$<bảng>$<guid>` có `INDEX.0.idf`. Tạo quan hệ = thêm dữ liệu VertiPaq, không chỉ metadata.
- **Quyết định**: tách 2a (sửa thuộc tính, T2 thuần, làm trước) và 2b (tạo, xoá). 2b qua spike **S1** gồm ba thử nghiệm trên bản sao: (i) thêm dòng `Relationship` không có storage (`RelationshipStorageID` 0, `State` 1): Desktop mở được không, có tự tính chỉ mục không; (ii) cùng thử nhưng bỏ cờ cần tính lại (`State`/`RefreshedTime`); (iii) viết `INDEX.idf` bằng `VertiPaqWriter` (định dạng đọc từ các `R$…idf` hiện có bằng `pbix-dump`: mỗi hàng bên nhiều → vị trí hàng bên một). Chọn phương án rẻ nhất mà Desktop chấp nhận và đọc lại cho kết quả đúng.
- **Xoá**: tối thiểu xoá dòng `Relationship` (+ `RelationshipStorage` và `RelationshipIndexStorage`); dọn bảng `R$` và tệp `.idf` trong ABF là một phần của S1 (nếu Desktop chấp nhận bảng mồ côi thì để lại, không thì xoá).
- **Kiểm trước khi tạo (FR-007)**: bằng engine: kiểu hai cột cùng loại, bên "một" có giá trị duy nhất (đếm distinct = số hàng) → M:1; ngược lại M:M chỉ khi quan sát; vòng ambiguity: duyệt đồ thị quan hệ hoạt động; quan hệ thứ hai giữa hai bảng tự không hoạt động [SUY ĐOÁN, VM-E4].
- **Kết quả S1 (2026-11-14)**: (i) file chỉ có dòng `Relationship`: Desktop không mở được (`TMProxyRelationship::GetStorageID`, VM-E3); (iii) **ghi đủ chỉ mục thành công**: định dạng `R$…INDEX` giải mã được (một số 0 ×3 rồi số thứ tự dòng 1-based của khoá phía một cho từng mục từ điển cột phía nhiều; nén bit không tràn từ; độ rộng theo số dòng bảng phía một; `.idfmeta` mẫu cố định đổi 3 trường), `RelationshipIndex` dựng lại **đúng từng byte** 14 quan hệ của Nhom6 và quan hệ Desktop tạo ở VM-E3; `MetadataWriter.addRelationship` ghi 18 dòng metadata giống Desktop (sau khi che ID và thời gian). Xoá quan hệ gỡ bảng `R$` và hai tệp ABF (Desktop chưa quan sát việc xoá; file BI Pro xoá cần Desktop mở thử). Chỉ hỗ trợ quan hệ nhiều-một với cột phía nhiều mã hoá từ điển.\n- **(Cũ) Nếu S1 thất bại**: 2b hiện "(chưa hỗ trợ)", ghi lý do vào STATE, và báo bạn; Phase E vẫn đạt "xong khi" theo điều kiện thay thế (thêm measure + sửa quan hệ) chỉ sau khi bạn đồng ý.

## R8. Bố cục Model View

- **Quyết định**: `DiagramLayoutPatch` sửa `location`/`size` của nút trong `DiagramLayout` (UTF-16LE JSON) bằng ghép byte phần số (như `PBIRLayoutPatch`), giữ mọi khoá khác (`scrollPosition`, `zoomValue`, cờ), thêm nút cho bảng mới nếu thiếu; part này đổi không cần dựng lại ABF (đổi bằng `PBIXChanges.diagramLayout`, tier vẫn T1 nếu chỉ bố cục).
- **[SUY ĐOÁN]**: cách Desktop ghi tab bố cục mới, `selectedDiagram`, thứ tự `zIndex`. VM-E4 (cú kéo bằng `cliclick` không tới Desktop nên cần cách khác: dùng `prlctl send-key-event` hoặc người dùng thao tác). Trước đó chỉ làm kéo thẻ trong tab hiện có (cùng cấu trúc đã đọc), tab mới "(chưa kiểm)".

## R9. TMDL View: tập con áp dụng

- **Quyết định**: `TMDLParser` phân tích văn bản TMDL (thụt lề, `measure Tên = biểu thức`, `formatString:`, `displayFolder:`, `description`, `isHidden`, `relationship …`, `column …` với các thuộc tính trong phạm vi) thành mô hình tối thiểu; so với văn bản `TMDLWriter` đang sinh để ra `ModelEdits`. Áp nguyên khối (kiểm lỗi toàn bộ trước, không áp một nửa). Phần ngoài phạm vi (xem `contracts/tmdl-subset.md`) bị từ chối từng mục.
- **Lý do**: dùng lại đúng logic của Câu chuyện 1 đến 3, không có đường ghi thứ hai; `TMDLWriter` đã là chuẩn so sánh (FR-014).
- **[SUY ĐOÁN]** phạm vi TMDL của Desktop "Apply" và thông báo lỗi: VM-E4/E5 nếu cần.

## R10. Lưu T2: kiểm và an toàn

- **Quyết định**: giữ đường D1: dựng và kiểm trong bộ nhớ → ghi tạm → mở lại → sao lưu → thay. `PBIXWriter.verify` mở rộng cho mô hình (`verifyModel`): mô hình đọc lại bằng `ModelMetadata(sqlite:)` bằng mô hình hiệu lực (từng measure, quan hệ, cột đã sửa); `PRAGMA integrity_check`; `MAXID` = ID lớn nhất; các tệp ABF còn lại không đổi byte (chỉ `metadata.sqlitedb` và các tệp quan hệ nếu 2b); `pbix-dump verify` tương đương (distinct count) chạy ở test nặng.
- **`SecurityBindings`**: Desktop từ chối file có `SecurityBindings` cũ khi phần báo cáo đổi (R13 của D1). Với đổi chỉ ở `DataModel` chưa biết: **spike S0** (T2 trên Nhom6 rồi mở ở Desktop). Nếu báo hỏng thì bỏ `SecurityBindings` khi đổi `DataModel` như khi đổi báo cáo.
- **Thời gian**: SC-004 dưới 3 giây; S0 đo. [SUY ĐOÁN] W3 chỉ thử file nhỏ.
- **Lưu liên tiếp hai lần** (ID, `MAXID`): lần thứ hai dựng lại từ file đã lưu (như D1), có test.

## R11. Giao diện: vị trí và cách dùng

- **Table View**: ribbon "Table tools"/"Measure tools"/"Column tools" theo ngữ cảnh (đã có tab ngữ cảnh `tableTools`, `columnTools` trong `RibbonTab`); thanh công thức bật khi chọn measure hoặc cột tính toán (cột tính toán chỉ đọc, FR-012); nút "Measure mới" tạo dòng nháp "Measure" như Desktop (QUAN-SAT mục 1) nhưng **chỉ vào mô hình khi áp dụng** (khác Desktop để không để measure lỗi trong mô hình).
- **Model View**: ngăn Properties bên phải như Desktop (Name, Home table, Description, Synonyms [chưa làm], Display folder, Is hidden, Format).
- **Ngăn Dữ liệu** (chế độ Sửa): nhóm measure theo thư mục hiển thị (`DisplayFolder`), menu chuột phải "Measure mới", "Sửa", "Xoá", "Đổi tên (bị chặn khi còn nơi dùng)".
- **Chế độ Xem**: chỉ đọc (FR-018).

## R12. Chuẩn mực hiệu năng

- Thêm/sửa/xoá measure áp dụng: dưới 300 ms (kiểm bind + chạy thử) + vẽ lại; sửa thuộc tính quan hệ hoặc cột: dưới 1 s gồm vẽ lại; kéo thẻ bảng: dưới 30 ms mỗi khung (như D1); lưu T2 Nhom6: dưới 3 s; TMDL áp dụng: dưới 1 s với mô hình Nhom6 (917 dòng measure).
