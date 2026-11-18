# Nghiên cứu (Giai đoạn 0): Tồn đọng sau Phase F

Mỗi mục gồm: quyết định, lý do, cách khác đã xét. "Quan sát" là phần VM-F1x phải xác nhận trước khi code. Quyết định ghi `[SUY ĐOÁN]` thì có thể đổi theo kết quả quan sát, và khi đổi thì ghi lại ở đây.

## Đã đọc sẵn từ file Desktop (không cần VM, 2026-11-17)

- **Nhom6 (`metadata.sqlitedb`)**: `Fact_Transaction` 1 056 320 dòng là **một** đoạn (`SegmentCount 1`, `RecordsPerSegment 1056320`). Các bảng `H$` của cột trong bảng này có 1 056 323 dòng, chia **hai** đoạn, `RecordsPerSegment 1056320`. Vậy cỡ đoạn của Desktop lớn hơn 1 048 576. Giới hạn 8 388 608 của BI Pro lấy từ tài liệu, chưa thấy file Desktop có bảng vượt mức đó.
- **`~/Downloads/DWH&BI/w8.3.pbix`** (Desktop bật Auto date/time):
  - Chú thích mô hình `__PBI_TimeIntelligenceEnabled = 1`.
  - Bảng `DateTableTemplate_<guid>`: ẩn, `IsPrivate = 1`.
  - Mỗi cột ngày có bảng `LocalDateTable_<guid>`: ẩn, `ShowAsVariationsOnly = 1`. Phân vùng tính toán là `Calendar(Date(Year(MIN('T'[c])), 1, 1), Date(Year(MAX('T'[c])), 12, 31))`.
  - Mỗi bảng ngày cục bộ có phân cấp `Date Hierarchy` kèm tệp `U$` (24 tệp `U$` trong ABF).
  - Có quan hệ tới bảng ngày cục bộ với `JoinOnDateBehavior = 2` (chỉ so phần ngày).
  - Có dòng `Variation` (`ColumnID`, `RelationshipID`, `DefaultHierarchyID`, `IsDefault = 1`).
  - Quan hệ tự phát hiện mang tên `AutoDetected_<guid>`. Trong file có một quan hệ như vậy ở trạng thái không hoạt động, `CrossFilteringBehavior = 2`.

## R1. Gộp ngầm (US1)

- **Quyết định**: thêm vào `QueryMeasure` một nguồn dạng `.aggregation(table, column, function)`, bên cạnh `.measure`.
  - `VisualQuerySpecReader` đọc trường `Aggregation` của PBIR và layout cũ (`Function` là mã số; `[SUY ĐOÁN]` 0 Sum, 1 Avg, 2 CountNonNull, 3 Min, 4 Max, 5 DistinctCount, 6 Median, 7 StdDev, 8 Variance, xác nhận ở VM-F10).
  - `DAXQueryBuilder` sinh biểu thức như Performance Analyzer: `[SUY ĐOÁN]` `"SumAmount", CALCULATE(SUM('Sales'[Amount]))`; tên cột kết quả và `queryRef` `Sum(Sales.Amount)` theo quan sát.
  - Phép gộp mặc định lấy từ `Column.SummarizeBy`; cột chữ và cột ngày theo quan sát.
  - Cờ "discourage implicit measures" đọc từ `Model.DiscourageImplicitMeasures`.
- **Lý do**: một đường tính duy nhất (hiến pháp II: visual sinh DAX giống Performance Analyzer rồi chạy qua engine). Engine đã có sẵn SUM, AVERAGE, MIN, MAX, COUNT, DISTINCTCOUNT, MEDIAN, STDEV.P, VAR.P.
- **Đã xét**: tạo measure ẩn thay cho trường gộp. Bị loại: file khác Desktop, làm bẩn mô hình.
- **Quan sát VM-F10**:
  - Tài liệu mới với `sales_2026.xlsx`. Kéo `Amount`, `Qty`, `Region`, `OrderDate` vào card, biểu đồ cột và bảng.
  - Đổi lần lượt từng phép gộp; ghi Performance Analyzer và đọc PBIR đã lưu.
  - Kiểm thêm: kéo cùng cột hai lần, chọn "Don't summarize" trong bảng.

## R2. Màn "Thêm dữ liệu vào báo cáo" và Enter Data (US2)

- **Quyết định về màn**:
  - `Report/AddDataPanel.swift` hiện khi tài liệu chưa có bảng người dùng nào.
  - Các ô: Excel, Dán dữ liệu vào bảng trống, nguồn khác. SQL Server và dữ liệu mẫu hiện xám kèm lý do.
  - Bấm ô thì mở Get Data hoặc hộp Tạo bảng có sẵn.
- **Quyết định về Enter Data**:
  - Hộp "Tạo bảng" (`Query/EnterDataState.swift` + `EnterDataView.swift`): lưới sửa được, dán TSV từ bảng tính, thêm và xoá cột, dòng, tên bảng.
  - Bảng sinh M như Desktop, nạp vào mô hình qua đường T3 có sẵn (`addTable`). Desktop không cần Refresh.
  - `[SUY ĐOÁN]` M có dạng `Table.FromRows(Json.Document(Binary.Decompress(Binary.FromText("…", BinaryEncoding.Base64), Compression.Deflate)), let _t = ((type nullable text) meta [Serialized.Text = true]) in type table [A = _t, …])` rồi `Changed Type`.
  - MEngine thêm `Binary.FromText`, `Binary.Decompress` (deflate thô qua `Compression.framework`, `COMPRESSION_ZLIB`), `Table.FromRows`, và kiểu có `meta`. `Json.Document` đã có, cần nhận đầu vào nhị phân.
  - Sửa lại bảng: Query Editor mở bước Source thì hiện lại hộp Tạo bảng.
- **Lý do**: dùng lại Get Data, T3 và MEngine; M giống Desktop nên Desktop Refresh được.
- **Đã xét**: lưu dữ liệu chỉ ở VertiPaq, M rỗng. Bị loại: Desktop Refresh mất bảng.
- **Quan sát VM-F11a (xong 2026-11-18, `docs/phase-f2-evidence/vm-f11/QUAN-SAT.md` mục a)**:
  - **Màn trống** có 4 ô: Excel (hộp Open lọc Excel), SQL Server, "Paste data into a blank table" (Create Table), "Use sample data", và liên kết "Get data from another source →" (Get Data).
    - Màn biến mất khi có bảng đầu tiên.
    - Quyết định trên giữ nguyên: SQL Server và dữ liệu mẫu hiện xám.
  - **M** khớp phần `[SUY ĐOÁN]` ở trên (nay đã xác nhận):
    - JSON mảng dòng, mọi ô là chuỗi, ô trống là `""`;
    - Deflate thô mức mặc định của zlib cho đúng từng byte;
    - `Changed Type`: cột toàn số thành `type number`, còn lại `type text`.
  - **Hộp Create Table:**
    - dòng đầu tự thành tiêu đề, có "Undo Headers";
    - tên mặc định "Table", rồi "Table (2)";
    - giới hạn ≤ 3 000 ô trong clipboard, đếm cả tiêu đề, kèm thông báo nguyên văn;
    - Cancel khi có dữ liệu thì hỏi xác nhận;
    - sửa lại qua bánh răng bước Source, khi đó hộp có OK/Cancel và không có ô Name.

## R3. Auto date/time (US2)

- **Quyết định**:
  - Tài liệu mới đặt `__PBI_TimeIntelligenceEnabled = 1` (`NewDocument.swift`).
  - Khi bảng có cột ngày hoặc ngày giờ được nạp, thêm, thay hay xoá, `AutoDateTime.swift` (BIPro) sinh các `ModelEdit`:
    - `addCalculatedTable` cho `DateTableTemplate_<guid>`, một lần cho mỗi mô hình;
    - `addCalculatedTable` cho `LocalDateTable_<guid>`, ẩn, `ShowAsVariationsOnly`;
    - `addHierarchy` "Date Hierarchy" gồm Year, Quarter, Month, Day (mới);
    - `addRelationship` với `joinOnDateBehavior: .datePartOnly`, không hoạt động lọc ngược;
    - `addVariation` (mới).
  - Cột và biểu thức của bảng mẫu, chú thích (`__PBI_LocalDateTable`, `__PBI_TemplateDateTable`, `TemplateId`…) chép đúng như `w8.3.pbix` và kiểm lại bằng VM-F11b.
  - Tuỳ chọn "Auto date/time" của file nằm ở menu Tệp ▸ Tuỳ chọn tệp; tắt thì sinh lệnh xoá ngược lại.
- **Engine và giao diện**:
  - Field list hiện "Date Hierarchy" dưới cột ngày, đọc qua `Variation`; bảng ngày cục bộ ẩn khỏi danh sách bảng (đã có).
  - Visual dùng `HierarchyLevel` có `PropertyVariationSource`: reader dịch sang cột của bảng ngày cục bộ. Kiểm truy vấn so với Performance Analyzer ở VM-F11b.
- **Lý do**: giữ cấu trúc giống Desktop thì Desktop mở được và tự làm mới bảng ngày được. Có golden đọc sẵn (`w8.3.pbix`).
- **Đã xét**: tắt Auto date/time như hiện nay. Bị loại vì spec FR-011 đòi giống Desktop.
- **Quan sát VM-F11b (xong 2026-11-18, QUAN-SAT mục b)**:
  - Mỗi cột Date **và** DateTime có một `LocalDateTable_<guid>`; mỗi mô hình có một `DateTableTemplate_<guid>` (IsPrivate).
  - Cột, biểu thức, chú thích, `Date Hierarchy`, quan hệ (tên là GUID trần, `JoinOnDateBehavior` 2) và `Variation` như bảng trong QUAN-SAT.
  - **Truy vấn visual** dùng cột của bảng cục bộ: mức Year `SUMMARIZECOLUMNS(…[Year], …)` + `SAMPLE(3502, …)`; mức Quarter nhóm thêm cột sắp theo `[QuarterNo]` + `TOPN(1001, …)`.
  - **Tắt tuỳ chọn:** xoá hết bảng ngày, quan hệ ngày, `Variation`, chú thích thành 0, và **viết lại visual** từ `HierarchyLevel` thành `Column`.
  - **Bật lại:** sinh mới với GUID mới; visual không đổi lại.
  - Tuỳ chọn ở Desktop: Options ▸ Current File ▸ Data Load ▸ Time intelligence. BI Pro đặt ở Tệp ▸ Tuỳ chọn tệp.

## R4. Tự phát hiện quan hệ (US2)

- **Quyết định**:
  - `RelationshipDetector` (BIPro, thuần, test được) chạy sau Close & Apply và Get Data ▸ Tải. Đầu vào là mô hình và các bảng vừa nạp; đầu ra là danh sách `NewRelationship` tên `AutoDetected_<guid>`.
  - Quy tắc (VM-F11c đã xác nhận phần không đánh dấu):
    - tên cột trùng (`[SUY ĐOÁN]` không phân biệt hoa thường);
    - cùng kiểu: số với chữ thì bỏ;
    - đúng một phía có giá trị duy nhất thì thành nhiều–một, lọc một chiều, hoạt động. Cả hai phía lặp thì bỏ.
    - Quan hệ mới làm xuất hiện đường thứ hai giữa hai bảng thì vẫn tạo nhưng **không hoạt động**.
      - Ví dụ: `Sales[Region]→Table (2)` hoạt động, còn `Customers[Region]→Table (2)` tắt vì đã có Sales→Customers.
      - `[SUY ĐOÁN]` thứ tự xét theo thứ tự bảng trong mô hình.
    - `[SUY ĐOÁN]` bỏ qua cột số thực; hai phía cùng duy nhất.
  - Desktop không có hoàn tác cho lần nạp; BI Pro gộp quan hệ tự tạo vào cùng bước ⌘Z với lần nạp (thêm của BI Pro).
  - Tuỳ chọn tắt nằm cùng chỗ với Auto date/time. Quan hệ tự tạo vào cùng bước hoàn tác với lần nạp.
- **Lý do**: Desktop làm mặc định; tên `AutoDetected_` thấy trong `w8.3.pbix`.
- **Quan sát VM-F11c (xong 2026-11-18, QUAN-SAT mục c)**:
  - Nạp ba bảng cùng lúc: chỉ `Sales[CustomerID]→Customers[CustomerID]`.
    - ProductID khác kiểu: bỏ.
    - Region cả hai phía lặp: bỏ.
  - Nạp thêm `Table (2)` có Region duy nhất: hai quan hệ, một hoạt động, một tắt.
  - Tuỳ chọn "Autodetect new relationships after data is loaded" ở Current File ▸ Data Load ▸ Relationships, mặc định bật.

## R5. Hàm văn bản DAX (US3, gói agy F2-DAXTEXT)

- **Quyết định**:
  - Thêm 19 hàm của FR-020 vào `Functions/Text.swift`, chuyển sang `TextMore.swift` nếu tệp quá dài, đăng ký qua `Registry`.
  - Độ dài và vị trí tính theo đơn vị Desktop dùng (`[SUY ĐOÁN]` UTF-16, như .NET), xác nhận bằng chữ có dấu dạng NFD và emoji.
  - `SEARCH` không phân biệt hoa thường và có ký tự đại diện, như đã làm. `FIND`, `SUBSTITUTE`, `EXACT` phân biệt hoa thường.
  - `VALUE` và `FIXED` theo locale của mô hình (`Culture`).
- **Golden**: VM-F12 chạy một truy vấn `EVALUATE` trả bảng nhiều dòng × cột (mỗi hàm ít nhất 10 ô) trên bảng mẫu, rồi Copy table. Lưu thành `docs/phase-f2-evidence/vm-f12/golden.tsv` cho test của worker.
- **Lý do giao agy**: một thư mục riêng, nhiều code lặp, có golden rõ.

## R6. Sửa và xoá cột tính toán còn được dùng (US4)

- **Quyết định**:
  - **Quan hệ**: dùng lại `relationshipsToRebuild`: xoá quan hệ kèm `R$`, ghi lại cột, thêm lại quan hệ cùng tên, cùng thuộc tính, `R$` theo dữ liệu mới. Đầu "một" không còn duy nhất thì làm như Desktop (từ chối hay đổi lực lượng, theo VM-F13).
  - **Phân cấp**: bộ ghi mới `HierarchyIndexWriter` dựng `U$` và `HierarchyStorage` từ dữ liệu các cấp. Định dạng `U$` đọc từ file Desktop (Nhom6 có phân cấp, `w8.3` có Date Hierarchy) và có test đọc lại. Dùng chung với R3.
  - **Cột sắp xếp**: dựng lại `H$` của cột được sắp theo thứ tự cột sắp (đường `HierarchyEncoding` sẵn có).
  - **Xoá**: hỏi như Desktop (VM-F13), xoá kèm quan hệ, cấp phân cấp (bỏ phân cấp khi hết cấp) và tham chiếu `SortByColumn`; hoàn tác chung.
- **Lý do**: VM-F9 đã cho thấy Desktop dựng lại `H$` và `U$` khi sửa cột là cấp phân cấp.
- **Quan sát VM-F13**:
  - Trên bản sao Nhom6, sửa `Dim_District[branch_label]` (cấp phân cấp).
  - Trên tài liệu thử: một cột tính toán làm khoá quan hệ (sửa còn duy nhất, sửa thành trùng) và một cột tính toán làm cột sắp xếp.
  - Xoá từng loại cột đó.

## R7. Bảng nhiều đoạn và RLE (US5)

- **Quyết định**:
  - **Nhiều đoạn**: `VertiPaqWriter.encodeTable` chia theo `RecordsPerSegment` của Desktop (VM-F14 đo trên bảng 10 triệu dòng; `[SUY ĐOÁN]` 8 388 608). Ghi mỗi đoạn một bộ `.idf`/`.idfmeta`, thống kê từng đoạn, `SegmentMapStorage.SegmentCount`. Mã hoá từng đoạn để giữ bộ nhớ dưới 4 GB.
  - **Cột tính toán trên bảng nhiều đoạn**: bỏ chặn `segments == 1` ở `TableMetadataWriter`.
  - **RLE**: bố cục run và meta (`.idfmeta` lớp hybrid RLE) theo VM-F14. Quyết định RLE hay bit-packing theo đoạn bằng cùng tiêu chí với Desktop nếu thấy được; nếu không, chọn cách cho tệp nhỏ hơn và đánh dấu `[SUY ĐOÁN]`. Không sắp lại dòng nếu Desktop không sắp: thứ tự dòng đọc lại phải bằng thứ tự nguồn.
- **Lý do**: SC-005, SC-006.
- **Đã xét**: tự sắp dòng để RLE tốt hơn. Bị loại nếu khác Desktop: thứ tự dòng lộ ra ở bảng không sắp.
- **Quan sát VM-F14**:
  - Desktop nạp Parquet 10 triệu dòng và CSV 1 triệu dòng có cột lặp dài.
  - Đọc `SegmentMapStorage`, cỡ `.idf`, meta và thứ tự dòng bằng PBIXKit.
  - Đo cỡ tệp Desktop làm mốc cho SC-006.

## R8. Nguồn (US6)

- **PostgreSQL** (gói agy F2-CONN):
  - Ánh xạ theo VM-F15. `[SUY ĐOÁN]`: timestamptz thành datetimezone, Desktop đưa vào mô hình là ngày giờ (đổi về UTC hay giờ máy?); time thành time; interval thành duration; bytea thành binary (mô hình bỏ?); mảng thành chữ.
  - Thêm kiểu `time`, `duration`, `datetimezone`, `binary` vào `TableData` nếu chưa có. Đây là hợp đồng trong `contracts/`, do lead làm ở Đợt 0.
- **Parquet lồng** (gói agy F2-CONN):
  - Dựng lại bản ghi và danh sách từ mức lặp và mức định nghĩa (Dremel).
  - struct thành ô bản ghi, list thành ô danh sách (`TableData.structured`); độ sâu đến 3.
  - Việc Desktop có tự mở rộng hay không xác nhận ở VM-F15. Phần Navigator và Query Editor đã có, nhờ JSON ở Phase F.
- **Driver ODBC SQLite** (lead):
  - Thêm ô chọn driver trong hộp SQLite: danh sách tên phổ biến ("Devart ODBC Driver for SQLite", "SQLite3 ODBC Driver") và cho nhập tự do.
  - Lưu vào `UserDefaults` khoá `bipro.sqlite.odbcDriver`; `SourceQuery` dựng M bằng tên đó.
  - Chuỗi kết nối với driver khác theo VM-F15 (bạn cài driver thứ hai trong VM nếu muốn gate SC-007 với driver đó; không có thì gate bằng Devart và chỉ kiểm văn bản M).
- **Quan sát VM-F15**:
  - Bảng PostgreSQL có đủ năm kiểu.
  - Parquet có struct, list, list of struct (sinh bằng pyarrow).
  - Nếu có driver SQLite thứ hai: M Desktop ghi khi dùng driver đó.

## R9. Gate và đo

- Mỗi câu chuyện để lại tệp ở `build/f2-out/<câu chuyện>/` và checklist kết quả ở `docs/phase-f2-evidence/vm-f1x/KET-QUA.md`. Claude lái VM bằng `build/vm-tools/` (`gate.sh`, `pcu.sh`, `paste.sh`). Ảnh cắt che tên tài khoản; dọn thư mục VM sau buổi.
- Test nặng mới đặt tên chứa `F2` để chạy bằng lọc `Nhom6|ORA|VIS|F2`.
