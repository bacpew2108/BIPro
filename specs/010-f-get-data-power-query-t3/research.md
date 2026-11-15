# Nghiên cứu và quyết định Phase F

Định dạng: Quyết định · Lý do · Phương án đã xét. Mục đánh dấu **[Cần duyệt]** nằm trong plan "Cần bạn quyết". Số liệu kích thước/thời gian ghi "ước tính" là chưa đo; sẽ đo ở spike S5.

## R1. Thực thi dữ liệu và M: tự viết (A) hay DuckDB (B) **[Cần duyệt]**

**Quyết định đề xuất: (A) tự viết trên `ColumnStore`, chỉ framework hệ thống, cho P1 và P2.**

| Tiêu chí | (A) Tự viết | (B) DuckDB (`duckdb-swift`) |
|---|---|---|
| Thư viện ngoài | Không (hiến pháp III) | Có: phải hỏi và duyệt trong plan |
| Giấy phép | n/a | MIT (theo `docs/BIPRO_BUILD_PLAN.md`), cần kiểm lại khi cài |
| Kích thước app | Không đổi | Ước tính thêm 30–50 MB, thời gian build lâu hơn (C++ lớn), chưa đo |
| Chạy ngôn ngữ M | Có: bộ đánh giá M tự viết | **Không**: DuckDB chạy SQL, vẫn phải có parser M và bộ dịch M → SQL |
| Ngữ nghĩa khớp Desktop (`null`, `Error` theo ô, kiểu số, so khớp chuỗi) | Kiểm soát hoàn toàn, đối chiếu golden từng hàm | Phải ép SQL theo ngữ nghĩa M; lỗi theo ô khó biểu diễn |
| Dạng dữ liệu | Cột từ điển như `ColumnStore` và VertiPaq, không chuyển đổi | Kết quả phải chuyển lại sang cột từ điển để vẽ và ghi VertiPaq (thêm một lần sao chép) |
| Đọc nguồn | Tự viết CSV, xlsx (ZIP + XML), JSON, SQLite (đã có `sqlite3`) | CSV, Parquet, JSON, Excel (qua extension), Postgres, SQLite có sẵn |
| Parquet | Tập con (không nén, Snappy, gzip); `zstd` không có | Đủ |
| PostgreSQL | Giao thức đơn giản qua `Network.framework`, xác thực SCRAM bằng CryptoKit | Có (extension có thể phải tải từ mạng, vi phạm hiến pháp IV nếu không đóng sẵn) |
| Hiệu năng 1 triệu dòng | Cần S5 đo | Rất tốt cho SQL lớn |
| Rủi ro | Khối lượng công việc đọc nguồn và hàm M | Rủi ro chọn sai nền: tưởng nó giải bài M nhưng không; extension; kích thước |

Lý do chọn A: phần khó nhất của Phase F (ngữ nghĩa M và ghi VertiPaq) không được DuckDB giải; hầu hết thư viện hệ thống cần cho P1 và P2 đã có (`Compression`, `XMLParser`, `JSONSerialization`, `sqlite3`). DuckDB chỉ đáng giá ở Parquet đủ nén và nguồn lớn, tức là P3, nên quyết sau (R2).

Phương án đã xét thêm: thư viện đọc xlsx bên thứ ba (CoreXLSX…): bỏ, xlsx chỉ là ZIP + XML đã có `ZipArchive`; `libxlsxwriter` không cần (không ghi Excel).

## R2. Parquet và PostgreSQL (P3) **[Cần duyệt]**

**Quyết định: hoãn, đề xuất tập con tự viết.** Parquet: footer Thrift compact, trang `PLAIN`/`RLE_DICTIONARY`, nén `UNCOMPRESSED`/`SNAPPY`/`GZIP`; không `zstd`, không `brotli`. PostgreSQL: giao thức v3 đơn giản (không dùng extended query), SCRAM-SHA-256, kiểu cơ bản. Thiếu thì báo "chưa hỗ trợ" kèm tên, không sai im lặng. Nếu bạn cần zstd hoặc nhiều kiểu hơn, lúc làm P3 sẽ hỏi lại việc thêm DuckDB hoặc `libpq`.

## R3. Cách đọc xlsx

**Quyết định: ZIP bằng `ZipArchive` hiện có + `Compression` (`deflate`) + `XMLParser` (SAX).** Đọc `workbook.xml`, `sharedStrings.xml`, `sheetN.xml`, `styles.xml` (nhận ra ô ngày theo định dạng), bảng đặt tên (`tables/*.xml`) để Navigator liệt kê "trang tính" và "bảng". Đọc dòng theo luồng cho xem trước 200 dòng. Ngày dạng số: hệ 1900 và 1904 theo `workbook.xml`.

## R4. Biểu diễn bảng và đường thực thi M

**Quyết định: `TableData` = danh sách `ColumnData` (từ điển + mã) của `ColumnStore`; M thao tác theo cột/chỉ số hàng, không bung ra chuỗi.** Ô lỗi lưu ở cột phụ "mặt nạ lỗi" (hàng → thông điệp) để cột kiểu giữ nguyên (`null`/`Error` phân biệt). Kết quả giao cho `ModelRuntime` qua nguồn cột chồng. Xem trước dùng cắt sớm ở nguồn (đọc ≤ 1000 dòng) khi các bước cho phép (không có `Sort`, `Group`, `Distinct` ở giữa; nếu có thì chạy đủ).

## R5. Ngôn ngữ M: phạm vi và cách kiểm

**Quyết định: theo FR-030; hàm ngoài danh sách báo "chưa hỗ trợ".** Bước sinh từ ribbon dùng đúng biểu thức Desktop (ghi ở F4: tên bước, cú pháp `each`, kiểu `type text`, tham số ngôn ngữ). Mỗi hàm có golden riêng: file Desktop xuất bảng sau bước, đọc bằng PBIXKit. Hàm mới phải có quan sát trước khi viết (hiến pháp I). Định dạng và so sánh theo văn hoá `en-US` trừ khi quan sát khác.

## R6. Lưu T3 và phương án dự phòng

**Quyết định: làm T3 theo nấc, gate F-T3 trước.** Nấc 1: một bảng mới, ba kiểu (đã có). Nấc 2: đủ kiểu (decimal/currency, dateTime, boolean, `null`), RLE. Nấc 3: nhiều bảng và quan hệ từ/đến bảng mới (chỉ mục `R$`). Nấc 4: bảng lớn (đến 8 triệu dòng/segment). Nếu nấc 1 trượt ở Desktop: chuyển Enter Data (R7) và mở lại nghiên cứu T3 song song. Ghi vào tệp tạm, đọc lại kiểm rồi thay (như T1/T2).

## R7. Enter Data làm dự phòng

**Quyết định: chỉ khi F-T3 trượt.** Dữ liệu nằm trong biểu thức M của bảng (`#table(type table [...], {{...}})` nén theo cách Desktop làm, ghi ở F1), Desktop nạp lại khi Refresh; BI Pro giữ `TableData` trong phiên. Giới hạn ≤ 10 000 dòng cho ngưỡng thực dụng; bảng lớn cảnh báo.

## R8. `DataMashup` (MS-QDEFF)

**Quyết định: đọc và ghi theo tài liệu công khai MS-QDEFF.** Cấu trúc: phiên bản, kích thước gói, gói ZIP (`Formulas/Section1.m`, `Config/Package.xml`, `[Content_Types].xml`), kích thước và nội dung phần quyền, kích thước và nội dung metadata (XML `LocalPackageMetadataFile`, danh sách mục `[Formulas]`), `PermissionBindings` (DPAPI) **chép nguyên byte, không đọc**. Spike S2 xác nhận bằng file Desktop; khi lưu T3, cập nhật `Section1.m` và metadata, chép phần quyền; nếu file không có `DataMashup` (file Desktop xuất bản mới) thì tạo theo mẫu quan sát.

## R9. Tập thành phần `.pbix` mới

**Quyết định: dựng theo tập tối thiểu quan sát ở S3.** Dự kiến: `[Content_Types].xml`, `Version`, `Metadata`, `Settings`, `Report/Layout` hoặc PBIR, `DataModel` (ABF có metadata rỗng), `DataMashup`, `DiagramLayout`, `SecurityBindings` không cần. Phương án dự phòng: đóng sẵn tệp mẫu trống do Desktop tạo trong tài nguyên app (đã được Desktop chấp nhận) rồi sửa.

## R10. Cột và bảng tính toán

**Quyết định: tính bằng engine DAX hiện có, lưu T3.** Cột: `Column.Type = Calculated` + `Expression`, dữ liệu ghi VertiPaq như cột thường (kiểm S4: Desktop có ghi sẵn hay tính lại). Bảng: `Partition` kiểu Calculated với biểu thức, dữ liệu ghi VertiPaq. Thứ tự tính theo đồ thị phụ thuộc; vòng phụ thuộc báo lỗi. Cần engine đánh giá ngữ cảnh hàng (đã có cho `FILTER`/`ADDCOLUMNS`; kiểm `EARLIER`).

## R11. Hoàn tác và quan hệ với Phase E

**Quyết định: dùng ngăn xếp chung của D/E.** `ModelEdit.addTable/replaceTable/dropTable` mang theo `TableData` (tham chiếu, không sao chép mỗi snapshot; bộ nhớ chia sẻ cho bảng chưa lưu). Close & Apply là một bước hoàn tác. Query Editor có ngăn xếp riêng theo bước (sửa/xoá/đổi thứ tự).

## R12. Bảo mật nguồn và thông tin đăng nhập

**Quyết định: mật khẩu ở Keychain; không vào `.pbix`, `docs/`, nhật ký, ảnh chụp.** Chuỗi kết nối ghi vào M không có mật khẩu (như Desktop). Đường dẫn nguồn là đường dẫn máy; nếu mở trên VM không có đường dẫn đó thì Refresh lỗi nhưng dữ liệu đã lưu vẫn đọc được.
