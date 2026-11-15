# Kế hoạch triển khai Phase F: Get Data, Power Query và lưu tầng T3

**Đặc tả**: [spec.md](spec.md) · **Quyết định**: [research.md](research.md) R1–R12 · **Dữ liệu**: [data-model.md](data-model.md) · **Hợp đồng**: [contracts/](contracts/) · **Kiểm chạy**: [quickstart.md](quickstart.md) · **Sở hữu file**: `docs/phase-f-ownership.tsv`

**Trạng thái**: Nháp, chờ bạn duyệt. Chưa thêm thư viện nào vào `Package.swift`.

## Bối cảnh kỹ thuật

- Swift 6 (module mới) / SwiftUI, macOS 15, Apple Silicon. Module hiện có: `PBIXKit` (đọc/ghi `.pbix`, ABF, VertiPaq, `MetadataWriter`, `VertiPaqWriter`, `TableMetadataWriter`), `ColumnStore` (cột mã hoá từ điển `ColumnData`, `ColumnBuilder`, `InMemoryColumnSource`, `ReschematedColumnSource`), `DAXEngine`, `BIPro` (UI, `DocumentSaver`, `ModelRuntime`, hoàn tác chung).
- **Hiện trạng ghi T3** (đọc từ mã): `VertiPaqWriter.encodeTable` chỉ nhận ba kiểu (`int64`, `double`, `string`), `null` chỉ cho chuỗi, một segment, mọi dòng là một khối bit-packed (chưa RLE), bề rộng bit tối đa 32. `TableMetadataWriter.addTable` ghi dòng `Table/Column/Partition/ColumnStorage/...`. Chưa có `H$`, chỉ mục quan hệ cho bảng mới (có `RelationshipIndex` cho quan hệ của Phase E), chưa có bảng hệ thống. File thử `build/w-out/W4/tuan6.2_W4_table.pbix` (bảng 100 dòng) **chưa ai mở trong Desktop**.
- `DataMashup` (nơi Desktop lưu truy vấn M) **chưa được đọc hay ghi ở đâu** trong mã.
- Chưa có parser/bộ chạy ngôn ngữ M, chưa có đọc CSV/Excel/Parquet/JSON/PostgreSQL. `sqlite3` đã được liên kết sẵn (`PBIXKit` dùng để đọc metadata).
- Ràng buộc: chỉ ghi phần đã quan sát; golden DAX (30) và truy vấn visual (72) giữ nguyên; D1 đến D7 và E vẫn qua; mở Nhom6 dưới 2 s; lưu T2 trên Nhom6 giữ ≤ 3 s (SC-004 của E).

## Kiểm tra theo hiến pháp

- **I. Quan sát trước**: mỗi lát đặt buổi VM-F (F1…F7) ngay trước phần code tương ứng; hàm M và quy tắc chưa quan sát đánh dấu `[SUY ĐOÁN]`. Nguồn dùng: file Desktop tạo, tài liệu công khai Microsoft (ngôn ngữ M, MS-QDEFF cho `DataMashup`, MS-XLDM). Không dịch ngược.
- **II. Golden**: golden M là bảng kết quả Desktop (export hoặc đọc lại từ VertiPaq Desktop ghi) trên file mẫu; golden DAX Nhom6 giữ nguyên, chạy lại ở cuối mỗi lát đụng engine.
- **III. Thư viện ngoài**: **kế hoạch này không thêm thư viện**. Phương án đề xuất (A) chỉ dùng framework hệ thống. Phương án DuckDB (B) được so sánh ở research R1 và nằm ở mục "Cần bạn quyết" bên dưới.
- **IV. Dữ liệu và mạng**: nguồn trong `~/Downloads` chỉ đọc; file mẫu và đầu ra ở `build/f-out/`; không tải gì từ mạng. Kết nối PostgreSQL (P3) chỉ tới máy chủ bạn chỉ định; mật khẩu chỉ ở Keychain, không vào `.pbix`/`docs/`/nhật ký; `SecurityBindings` và phần `DataMashup` không đụng chỉ chép byte.
- **V. Hợp đồng và sở hữu file**: đợt 0 (lead) chốt hợp đồng `contracts/` và `docs/phase-f-ownership.tsv` trước khi giao worker.
- **Ràng buộc sản phẩm**: giao diện tiếng Việt, màu hệ thống `#0A84FF`; VM chỉ khi bạn cho phép từng lần.

## Cần bạn quyết (trước khi `/speckit-tasks`)

1. **Phương án thực thi dữ liệu và M**: đề xuất **(A) tự viết, chỉ framework hệ thống** cho P1 và P2 (xem R1). DuckDB (B) không cần để làm luồng `sales_2026.xlsx` và không giúp chạy M. Duyệt A?
2. **P3 Parquet và PostgreSQL**: chưa quyết ở đây. Đề xuất làm tập con tự viết (Parquet: không nén, Snappy, gzip; PostgreSQL: giao thức đơn giản qua `Network.framework`). Nếu bạn muốn Parquet đủ nén `zstd`, hoặc nhiều kiểu PostgreSQL, thì lúc đó mới hỏi lại việc thêm thư viện (DuckDB hoặc `libpq`). Đồng ý hoãn đến khi làm P3?
3. **Gate F-T3 (W4)**: file thử `tuan6.2_W4_table.pbix` đã có. Bạn tự mở trong Desktop theo `build/w-out/W4/CHECKLIST.md`, hay cho phép Claude điều khiển VM một lần?
4. **Cắt phạm vi**: giữ cả 8 câu chuyện (đã chốt); nếu M3 trễ thì cắt P3 trước, không cắt P1/P2.

## Thiết kế

1. **Mô hình dữ liệu nạp** (`ColumnStore`, mới `TableData`): bảng trong bộ nhớ gồm danh sách cột `ColumnData` (từ điển + mã) đúng kiểu mô hình (`integer`, `double`, `currency`, `dateTime`, `boolean`, `string`). Nguồn đọc ra `TableData`; M chạy trên `TableData`; kết quả Close & Apply đưa vào mô hình.
2. **Đọc nguồn** (`Connectors`, module mới, framework hệ thống): CSV (tự viết, tự dò mã hoá/dấu phân cách), Excel `.xlsx` (đọc ZIP bằng `ZipArchive` đã có, nén `deflate` qua `Compression`, XML bằng `XMLParser`; `sharedStrings`, kiểu ô, ngày dạng số), JSON (`JSONSerialization`), SQLite (`sqlite3` đã liên kết), Parquet và PostgreSQL ở P3. Mỗi nguồn trả danh sách "mục" (bảng/trang tính/bảng đặt tên) và `TableData`, tuỳ chọn xem trước (≤ 200 dòng) không đọc hết file.
3. **Ngôn ngữ M** (`MEngine`, module mới): lexer, parser (`let … in`, bản ghi, danh sách, `each`, `_`, hàm, `if`, toán tử, `#table`, `#date`…), bộ đánh giá lười có ngữ cảnh môi trường theo bước, kiểu giá trị M (number, text, logical, date, datetime, null, list, record, table, function, error). Thư viện hàm chia nhóm: `Table.*` (≈ 30 hàm, FR-030), `Text.*`, `Number.*`, `Date.*`, `List.*`. Bảng M giữ lỗi theo ô (`Error` là giá trị). Chạy trên `TableData` (cột từ điển) bằng thao tác cột/chỉ số hàng, không bung chuỗi.
4. **Truy vấn và bước** (`MEngine`/`BIPro/Query/Editor`): `Query` = danh sách `Step` (tên, biểu thức M) sinh bởi lệnh ribbon/hộp thoại; biểu thức đầy đủ `let … in` dựng từ các bước; sửa Advanced Editor phân tích lại thành bước. Xem trước chạy ≤ 1000 dòng đầu (cắt sớm ở nguồn khi bước cho phép), cache theo bước, đánh giá lại từ bước bị đổi.
5. **Query Editor UI** (`BIPro/Query/Editor`, mới): cửa sổ riêng (hoặc chế độ toàn màn hình) gồm Queries, lưới xem trước, Query Settings (Applied Steps), thanh công thức, column profile (`Table.Profile` tự viết trên 1000 dòng), ribbon Home/Transform/Add Column/View, hộp thoại (Custom Column, Merge, Append, Group By, Advanced Editor), Query Dependencies. Hoàn tác trong Query Editor theo từng bước; "Close & Apply" đẩy một thao tác vào ngăn xếp hoàn tác chung.
6. **Nạp vào mô hình** (`ModelEdit.addTable/replaceTable/dropTable`, mở rộng `ModelEdits` của E): metadata (`TableMetadataWriter` mở rộng: cột, `ColumnStorage`, `Partition` với biểu thức M, `DictionaryStorage`, `RelationshipStorage` nếu có), dữ liệu (`TableData` giữ trong bộ nhớ đến lúc lưu). `ModelRuntime` nạp lại: engine DAX dùng nguồn cột chồng (`ColumnSource` gốc + `TableData` mới, theo `ReschematedColumnSource`).
7. **Ghi T3** (`PBIXKit/Writing`, mở rộng): `VertiPaqWriter` v2 (nhiều kiểu: int, decimal/currency, double, dateTime, boolean, string; `null` mọi kiểu; RLE; nhiều bảng một lần; giữ đúng bề rộng bit; giới hạn một segment đến 8 triệu dòng, quá thì báo), `H$`/chỉ mục quan hệ nếu quan sát cần, thống kê. `DataMashup` (`DataMashup.swift`, đọc và ghi theo MS-QDEFF công khai: gói ZIP `Formulas/Section1.m`, `Config/Package.xml`, metadata; phần `PermissionBindings` chép nguyên byte). `PBIXChanges.tier = .data` (T3), `DocumentSaver` ghi ra tệp tạm → đọc lại kiểm (so từng cột, distinct count, metadata, `DataMashup` phân tích lại) → thay file.
8. **Phương án dự phòng** (nếu gate F-T3 trượt): bảng "Enter Data" (dữ liệu trong biểu thức M, đã có trong `docs/BIPRO_BUILD_PLAN.md` §2), chỉ cho bảng nhỏ (≤ 10 000 dòng), báo giới hạn trong UI (FR-052). Bảng lớn hơn: giữ trong phiên và cảnh báo khi lưu.
9. **Tạo `.pbix` mới** (`PBIXWriter.newDocument`): tập thành phần tối thiểu quan sát ở F6; `Workspace` có chế độ chưa có file; hộp thoại lưu lần đầu.
10. **Cột và bảng tính toán** (BIPro + `DAXEngine`): đánh giá biểu thức theo ngữ cảnh hàng (cột) hoặc ra bảng (bảng), vào mô hình như bảng/cột mới; thứ tự tính theo đồ thị phụ thuộc; lưu T3 cùng đường ghi dữ liệu.
11. **Bằng chứng**: `docs/phase-f-evidence/vm-f*/` (QUAN-SAT.md, ảnh cắt không lộ tài khoản), `CHECKLIST-KET-QUA.md` mỗi gate.

## Spike (làm trước câu chuyện tương ứng; kết quả ghi `docs/phase-f-evidence/`)

| Spike | Câu hỏi | Cách làm | Nếu trượt |
|---|---|---|---|
| **S0 / F-T3 (W4)** | Desktop có mở file bảng mới 100 dòng do BI Pro ghi không? | Bạn (hoặc VM khi cho phép) mở `build/w-out/W4/tuan6.2_W4_table.pbix` | Chuyển phương án dự phòng; dừng viết T3 đầy đủ; xem R6 |
| **S1 VertiPaqWriter v2** | Đủ kiểu, `null`, RLE, nhiều bảng, mô hình có sẵn (Nhom6) | Đối chiếu từng byte với bảng Desktop ghi (đã có trong Nhom6 và file Desktop tạo cho `sales_2026`), `VertiPaq.decodeTable` đọc lại | Giảm kiểu hỗ trợ, ghi rõ |
| **S2 DataMashup** | Cấu trúc gói, quan hệ `Partition` ↔ truy vấn, Desktop có cần `DataMashup` hợp lệ không | Đọc `DataMashup` của file Desktop (Nhom6 và file `sales_2026` Desktop tạo); thử ghi và mở Desktop | Bảng chỉ có `Partition` kiểu "M" tối thiểu hoặc Enter Data |
| **S3 `.pbix` mới** | Tập thành phần tối thiểu Desktop chấp nhận | Desktop tạo file trống rồi lưu, so với file BI Pro dựng | Bắt đầu từ mẫu trống do Desktop tạo, đóng gói trong app |
| **S4 Cột tính toán** | Cách Desktop ghi `Column` loại Calculated và dữ liệu | Đọc file Desktop có cột tính toán, so với tính bằng engine | Cột tính toán lưu dưới dạng biểu thức, Desktop tính lại khi mở (nếu Desktop cho phép) |
| **S5 Hiệu năng** | Nạp, chạy M, ghi 1 triệu dòng | Đo trên bảng sinh 1 triệu dòng | Ghi nền có thanh tiến trình; giảm ngưỡng SC-004/SC-005 |

## Thứ tự và phụ thuộc (đúng thứ tự bạn đã duyệt)

0. **Đợt 0 (lead)**: hợp đồng `TableData`, `DataSource`, `MValue`, `ModelEdit.addTable`, `docs/phase-f-ownership.tsv`; sinh file mẫu `build/f-out/` (xlsx, csv, parquet, json, sqlite) bằng công cụ có sẵn; chạy S0 (gate F-T3, bạn test) song song với S1.
1. **Câu chuyện 3 (lưu T3) mức lõi**: `VertiPaqWriter` v2, `TableMetadataWriter`, `DocumentSaver` T3, kiểm Desktop. Đây là lát rủi ro nhất nên đi đầu.
2. **Câu chuyện 1 (Get Data/Navigator)**: đọc CSV và Excel, Navigator, Load, bảng mới trong mô hình, hoàn tác.
3. **Câu chuyện 2 (Query Editor + M engine)**: S2; lõi M (parser/evaluator), hàm cơ bản, UI Query Editor, `DataMashup` ghi/đọc, Close & Apply, nạp lại.
4. **Câu chuyện 4 (biến đổi nâng cao)**: hàm M còn lại, hộp thoại, Advanced Editor, Query Dependencies.
5. **Câu chuyện 5 (file mới)**: S3.
6. **Câu chuyện 6 (cột/bảng tính toán)**: S4.
7. **Câu chuyện 7, 8 (P3)**: Parquet, JSON, SQLite, PostgreSQL.
8. Tích hợp, `/speckit-converge`, `/code-review`, golden nặng, VM-F cuối, cập nhật `STATE.md`.

## Giao việc cho agy (thoả điều kiện CLAUDE.md: tách được, ≥ 3 file, yêu cầu rõ, tối đa 3 worker)

Giao **sau đợt 0** và chỉ khi `git status` sạch; mỗi worker một nhóm file riêng, đợt tuần tự khi giao nhau:

| Gói | Nội dung | File (xem tsv) | Điều kiện giao |
|---|---|---|---|
| F-CONN1 | Đọc CSV + xlsx + JSON + SQLite → `TableData`, test bằng file mẫu | `Sources/Connectors/**`, `Tests/ConnectorsTests/**` | Hợp đồng `DataSource` đã chốt |
| F-MFUN | Hàm `Table.*` nhóm A (cột, dòng, sắp xếp), `Text/Number/Date/List.*` | `Sources/MEngine/Library/**` | Evaluator và `MValue` đã chốt, golden Desktop có |
| F-UI | Ngăn Query Editor (lưới, Applied Steps, profile, hộp thoại) vẽ từ `QueryEditorState` | `Sources/BIPro/Query/Editor/**` | `QueryEditorState` đã chốt; xuất PNG kiểm |
| (lead) | VertiPaqWriter v2, `DataMashup`, `DocumentSaver`, `ModelRuntime`, hoàn tác chung, parser/evaluator M, `Table.Join/Group/Pivot`, cột tính toán | còn lại | không giao: ngữ cảnh sâu, đụng chung |

## Tệp dự kiến

- Mới: `Sources/Connectors/**` (CSV, Excel, JSON, SQLite, Parquet, PostgreSQL), `Sources/MEngine/**` (Lexer, Parser, Evaluator, Value, Library), `Sources/ColumnStore/TableData.swift`, `Sources/PBIXKit/DataMashup.swift`, `Sources/PBIXKit/Writing/NewDocument.swift`, `Sources/BIPro/Query/Editor/**`, `Sources/BIPro/Model/Edit/TableLoader.swift`, `Sources/BIPro/Shell/GetDataDialog.swift`, test tương ứng.
- Sửa: `Package.swift` (hai target mới, không thư viện ngoài), `VertiPaqWriter.swift`, `TableMetadataWriter.swift`, `PBIXWriter.swift`, `ModelEdit.swift`, `Contracts.swift`, `ModelRuntime.swift`, `DocumentSaver.swift`, `Workspace.swift`, `DocumentState*.swift`, `Ribbon.swift`, `DAXEngine` (cột/bảng tính toán).

## Rủi ro

- **Gate F-T3 trượt** (cao nhất): Desktop có thể đòi chỉ mục/bảng hệ thống mà ta chưa biết. Giảm nhẹ: S0 làm đầu tiên; dự phòng Enter Data ghi sẵn; làm T3 theo từng nấc (1 bảng, nhiều bảng, quan hệ).
- **Ngữ nghĩa M** rộng và nhiều ngoại lệ (kiểu, `null`, lỗi theo ô, văn hoá/ngôn ngữ): chỉ nhận hàm đã quan sát, còn lại "chưa hỗ trợ" (FR-031); đối chiếu golden Desktop từng hàm.
- **`DataMashup`**: định dạng công khai (MS-QDEFF) nhưng Desktop có thể kiểm chữ ký/quyền; phần quyền (DPAPI) chỉ chép byte. Nếu tạo mới bị từ chối, bảng nạp lưu như Enter Data.
- **Excel và CSV thực tế bẩn**: ô gộp, mã hoá, ngày dạng số. Giảm nhẹ: bộ file mẫu có ca xấu, golden Desktop.
- **Hiệu năng** bảng 1 triệu dòng khi chạy M trên cột từ điển: S5 đo sớm; xem trước 1000 dòng cắt ở nguồn.
- **Phạm vi 8–10 tuần**: giữ P3 làm cuối để cắt được (Cần bạn quyết 4).
