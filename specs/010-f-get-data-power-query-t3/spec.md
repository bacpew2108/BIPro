# Đặc tả tính năng: Phase F, Get Data, Power Query và lưu tầng T3

**Nhánh**: `main` (không tạo nhánh riêng)

**Ngày tạo**: 2026-11-15

**Trạng thái**: Nháp, chờ bạn duyệt

**Đầu vào**: "Triển khai phase F" = mục Phase F của `docs/BIPRO_BUILD_PLAN.md`: Get Data → Navigator → nạp Excel, CSV, Parquet, JSON (đợt 1), PostgreSQL, SQLite (đợt 2); Query Editor (Applied Steps, thanh công thức, column profile, ribbon) → Close & Apply; ngôn ngữ M với khoảng 30 hàm `Table.*`, Advanced Editor, Custom Column, Merge, Append, Group By, Query Dependencies; **lưu tầng T3** (dữ liệu mới vào VertiPaq) và tạo `.pbix` mới từ đầu; cột và bảng tính toán (hoãn từ Phase E). **Xong khi:** đi hết luồng `sales_2026.xlsx` → Query Editor → Close & Apply → report → lưu `.pbix` → mở được trong Power BI Desktop.

Cấp trên: `docs/BIPRO_BUILD_PLAN.md` (Phase F, §2 tầng lưu và phương án dự phòng T3, §6 kiểm thử), `docs/PHASE_W_PLAN.md` (WP5 `VertiPaqWriter`, gate W4 chưa đạt), `specs/009-e-mo-hinh-hoa-luu-t2/` (đường ghi T2, hoàn tác chung, tách `DocumentSaver`). Mâu thuẫn thì sửa `docs/` trước.

**Phạm vi lớn (8 đến 10 tuần)**: spec chia thành các câu chuyện độc lập, mỗi câu chuyện là một lát có thể làm, kiểm và giao riêng. Phase F dừng ở mốc **M3**; không lấn sang Phase G (xuất PDF/PNG, dark mode, VoiceOver…).

## Quan sát Power BI

Mục [SUY ĐOÁN] phải được kiểm ở buổi VM-F trước khi code phần liên quan, ghi kết quả vào `docs/phase-f-evidence/`. Claude chỉ điều khiển VM khi bạn cho phép lần đó (quy tắc "agent không điều khiển VM" của hiến pháp vẫn giữ); nếu không thì bạn làm tay theo checklist Claude chuẩn bị. Không dịch ngược; chỉ đọc file Desktop ghi, tài liệu công khai của Microsoft (ngôn ngữ M, MS-XLDM) và nhìn giao diện.

**Hiện trạng trong BI Pro** (đọc từ mã và `docs/`):

- Đọc: `PBIXKit` đọc đủ `DataModel` (ABF, VertiPaq, metadata), `DataMashup` chưa đọc. Engine DAX đọc cột dạng từ điển, chưa có đường nạp bảng mới trong phiên.
- Ghi T2: `MetadataWriter`, `PBIXChanges.modelEdits`, `DocumentSaver` (Phase E). Ghi T3 mới ở mức thư viện: `VertiPaqWriter.encodeTable` (từ điển, bit-packing, chưa RLE), `TableMetadataWriter`, `RelationshipIndex`. **Gate W4 (bảng mới 100 dòng, Desktop đọc đúng) chưa được bạn test tay**; đây là rủi ro lớn nhất của phase (`docs/PHASE_W_PLAN.md`). Phương án dự phòng đã ghi ở `docs/BIPRO_BUILD_PLAN.md` §2: bảng "Enter Data" (dữ liệu nằm trong biểu thức M, Desktop nạp lại khi Refresh).
- Giao diện: ribbon có nút Get Data/Transform data là chỗ giữ chỗ (nhãn "Phase F"); `Query/QueryWorkspaces.swift` chỉ có TMDL View và DAX Query View, chưa có Query Editor. "Cột mới" và "Bảng mới" đang là nút giữ chỗ.
- Không có `sales_2026.xlsx` trong máy: file mẫu do Claude sinh ra (Excel, CSV, Parquet, JSON, SQLite nhỏ) đặt ở `build/f-out/`, không đụng file gốc của bạn.

**[SUY ĐOÁN], phải quan sát ở VM-F** (mỗi mục ghi vào `docs/phase-f-evidence/` trước khi code phần liên quan):

- **Cách Desktop lưu truy vấn trong `.pbix`**: nội dung `DataMashup` (gói M `Section1.m`, `Formulas`), cách mỗi bảng liên kết với truy vấn (biểu thức M trong `Partition`, `Source`), tên bước, siêu dữ liệu `[LastAnalysisServicesFormulaText]`, cờ "Enable load", "Include in report refresh"; có cần `DataMashup` hợp lệ để Desktop mở file có bảng mới không (quyết định T3 hay Enter Data).
- **Get Data và Navigator**: danh mục connector, hộp thoại Navigator (cây bảng/trang tính, xem trước, nút Load / Transform Data / Cancel), kiểu dữ liệu tự dò, dòng tiêu đề tự thăng cấp khi nạp CSV/Excel, mã hoá và dấu phân cách CSV mặc định.
- **Query Editor**: bố cục (cột Queries, lưới, Query Settings: Properties và Applied Steps), tên bước mặc định ("Source", "Navigation", "Promoted Headers", "Changed Type"), biểu thức M sinh ra cho từng lệnh ribbon, xem trước 1000 dòng, column profile (Column quality/distribution/profile, "based on top 1000 rows"), thanh công thức, thông báo lỗi bước, hiển thị `Error` trong ô.
- **Ngôn ngữ M**: ngữ nghĩa từng hàm `Table.*` trong FR-030 trên dữ liệu thật, kiểu mặc định, xử lý `null`, lỗi theo ô, thứ tự cột, so khớp kiểu trong `Table.Join`, `Table.Group`, `Table.Combine`; ghi lại mỗi hàm khi quan sát được kèm ví dụ.
- **Hộp thoại**: Custom Column (cú pháp M, tên cột mới), Merge Queries (kiểu join: Left Outer, Right Outer, Full Outer, Inner, Left Anti, Right Anti; "Fuzzy matching" ngoài phạm vi), Append Queries, Group By (cơ bản và nâng cao), Advanced Editor (sửa toàn bộ truy vấn), Query Dependencies (đồ thị nguồn → truy vấn).
- **Close & Apply**: Desktop xoá/tạo bảng nào, thứ tự nạp, ghi lại dữ liệu VertiPaq ra sao (từ điển, nén, `H$`), cách đặt tên bảng và cột, giữ hay mất quan hệ, measure và `DiagramLayout` khi bảng nạp lại, hộp thoại "Pending changes".
- **Cột tính toán và bảng tính toán**: dòng `Column` kiểu `Calculated` và `Partition` kiểu `Calculated` Desktop ghi (biểu thức DAX, `State`, kiểu dữ liệu suy ra), dữ liệu VertiPaq của cột tính toán có được ghi sẵn không, thứ tự tính và phụ thuộc.
- **Tạo `.pbix` mới**: tập thành phần tối thiểu Desktop chấp nhận (`Version`, `Metadata`, `Settings`, `Report/Layout` hoặc PBIR, `DataModel`, `DataMashup`, `[Content_Types].xml`), phiên bản, mô hình trống ban đầu.
- **PostgreSQL và SQLite** (đợt 2): hộp thoại kết nối, kiểu xác thực, truy vấn gốc Desktop sinh (`PostgreSQL.Database`, `Sqlite.Database` hoặc ODBC), query folding (ngoài phạm vi ở đợt này).
- **Làm mới (Refresh)** và đường dẫn nguồn trên máy khác (Windows so với macOS): Desktop làm mới thế nào khi file Excel nằm ở đường dẫn Mac không tồn tại trong VM.

**Chuẩn so khớp**: dữ liệu và số liệu phải khớp Power BI Desktop (hiến pháp II). Golden của phase này gồm (a) kết quả bảng sau mỗi bước M trên file mẫu, do Desktop xuất (Export data) hoặc đọc lại từ VertiPaq Desktop ghi; (b) các file `.pbix` do Desktop tạo từ cùng `sales_2026.xlsx`, mở được bằng PBIXKit để so từng cột; (c) 30 golden DAX trên Nhom6 giữ nguyên.

## Kịch bản người dùng và kiểm thử *(bắt buộc)*

### Câu chuyện 1 — Nạp một bảng mới vào mô hình đang mở, từ CSV và Excel (Ưu tiên: P1)

Người dùng bấm "Get data" → chọn Text/CSV hoặc Excel Workbook → chọn file → Navigator hiện bảng/trang tính kèm xem trước → bấm "Load". Bảng mới xuất hiện trong ngăn Dữ liệu, Table View và Model View, dùng được trong visual và DAX; ⌘S lưu vào `.pbix`; Power BI Desktop mở thấy bảng với đúng dữ liệu.

**Vì sao P1**: là xương sống của phase và là lát đầu tiên chạm rủi ro lớn nhất (W4: Desktop có chấp nhận bảng VertiPaq do BI Pro ghi không). Làm xong là biết T3 hay Enter Data.

**Kiểm thử độc lập**: trên bản sao Nhom6, nạp `sales_2026.csv` (khoảng 100 đến 10 000 dòng) làm bảng mới; thêm card `SUM` trên cột số; lưu; mở lại trong BI Pro và Desktop: cùng số dòng, cùng kiểu cột, cùng tổng; golden DAX Nhom6 không đổi.

**Kịch bản chấp nhận**:

1. **Cho** file CSV hợp lệ, **khi** chọn trong Get Data, **thì** Navigator hiện xem trước tối đa 200 dòng với kiểu cột tự dò và tiêu đề tự thăng cấp (theo quan sát Desktop).
2. **Cho** file Excel nhiều trang tính hoặc bảng, **thì** Navigator liệt kê từng trang tính và bảng; chọn nhiều mục thì nạp nhiều bảng một lần.
3. **Cho** bấm "Load", **thì** mỗi mục chọn thành một bảng, tên bảng lấy từ tên trang tính hoặc tên file, trùng tên thì thêm hậu tố như Desktop, và dữ liệu hiện ngay trong Table View.
4. **Cho** bảng mới, **khi** ⌘Z, **thì** bảng biến mất cùng quan hệ, measure phụ thuộc (hoặc bị chặn theo quy tắc ghi ở FR-004).
5. **Cho** lưu rồi mở lại trong BI Pro và Desktop, **thì** bảng còn nguyên và Desktop không báo file hỏng (hoặc, nếu W4 trượt, bảng mở ở dạng Enter Data theo FR-052).
6. **Cho** file không đọc được, sai mã hoá, trống, hoặc trang tính trống, **thì** báo lỗi rõ và không đổi mô hình.

---

### Câu chuyện 2 — Query Editor và Close & Apply (Ưu tiên: P1)

Từ Navigator bấm "Transform Data" (hoặc ribbon "Transform data") mở cửa sổ Query Editor: danh sách truy vấn bên trái, lưới xem trước, Query Settings với danh sách Applied Steps, thanh công thức M, column profile. Người dùng thăng cấp tiêu đề, đổi kiểu cột, đổi tên, bỏ cột, lọc dòng, sắp xếp, tách cột, thay giá trị, xoá dòng trùng, xoay/bỏ xoay cột (các lệnh cơ bản của ribbon), mỗi lệnh thêm một bước, sửa/xoá/đổi thứ tự bước được, lưới cập nhật. "Close & Apply" nạp kết quả vào mô hình như Câu chuyện 1.

**Vì sao P1**: điều kiện "xong khi" của phase là đi qua Query Editor; luồng `sales_2026.xlsx` bắt buộc có nó.

**Kiểm thử độc lập**: nạp `sales_2026.xlsx`, trong Query Editor thăng tiêu đề, đổi kiểu cột ngày và số, lọc `Region = "North"`, bỏ một cột, Close & Apply; số dòng và tổng khớp bản Desktop làm cùng các bước trên cùng file.

**Kịch bản chấp nhận**:

1. **Cho** truy vấn mới từ Navigator, **khi** mở Query Editor, **thì** Applied Steps có "Source", "Navigation" (Excel) hoặc "Source" và "Promoted Headers", "Changed Type" như Desktop, tên bước và biểu thức M sinh ra khớp bản quan sát.
2. **Cho** một lệnh ribbon, **thì** sinh đúng một bước mới (biểu thức M hiển thị trên thanh công thức), lưới xem trước tối đa 1000 dòng cập nhật, bước lỗi hiện biểu tượng cảnh báo và thông báo.
3. **Cho** chọn bước giữa danh sách, **thì** lưới hiện dữ liệu tại bước đó; chèn bước giữa chừng thì hỏi như Desktop; xoá bước thì các bước sau đánh giá lại.
4. **Cho** column profile, **thì** hiện Valid/Error/Empty, Distinct/Unique, min/max/trung bình (cột số) và phân bố giá trị dựa trên 1000 dòng đầu (theo quan sát).
5. **Cho** "Close & Apply", **thì** bảng được nạp vào mô hình, ngăn Dữ liệu cập nhật, truy vấn tắt "Enable load" không nạp; "Close" không áp dụng thì hỏi như Desktop ("Pending changes").
6. **Cho** sửa truy vấn đã nạp rồi Close & Apply lần hai, **thì** bảng được thay dữ liệu mới, quan hệ và measure còn nguyên khi cột còn tồn tại, mất cột thì cảnh báo danh sách chỗ dùng.
7. **Cho** toàn bộ thay đổi từ lúc mở Query Editor, **thì** một bước ⌘Z hoàn tác chung với D1 đến D7 và E.

---

### Câu chuyện 3 — Lưu tầng T3 và mở được trong Power BI Desktop (Ưu tiên: P1)

⌘S sau khi nạp hoặc sửa truy vấn ghi đủ thứ Desktop cần: dữ liệu bảng (VertiPaq: từ điển, IDF, `H$`, thống kê), metadata, chỉ mục quan hệ, và truy vấn M trong `DataMashup`. Bảng nạp từ Excel/CSV mở được trong Desktop, Refresh chạy lại được khi đường dẫn nguồn còn hợp lệ.

**Vì sao P1**: không có lát này, mọi thứ chỉ sống trong phiên. Phụ thuộc kết quả W4; nếu W4 trượt thì làm phương án dự phòng "Enter Data" và ghi rõ trong spec bản sửa.

**Kiểm thử độc lập**: gate **F-T3** trên VM: file do BI Pro lưu (Nhom6 có thêm bảng mới 100 dòng đến 100 000 dòng, đủ kiểu int, decimal, string, date, boolean, có `null`) → Desktop mở không báo lỗi, Data view đủ dòng, card `SUM` bằng số trong BI Pro; quan hệ từ bảng mới tới `Dim_*` hoạt động.

**Kịch bản chấp nhận**:

1. **Cho** bảng mới có kiểu int, decimal, string, ngày, boolean và `null`, **khi** lưu rồi đọc lại bằng PBIXKit, **thì** từng giá trị trùng bản gốc (không hard-code số liệu).
2. **Cho** file lưu, **khi** mở trong Desktop, **thì** không báo "file corrupted", bảng có đúng số dòng, kiểu dữ liệu và tổng; DAX Query View chạy đúng.
3. **Cho** mô hình cũ có quan hệ và measure, **thì** sau khi thêm bảng mới và lưu, tất cả còn nguyên và số golden Nhom6 không đổi.
4. **Cho** lưu liên tiếp hai lần (thêm bảng, rồi sửa truy vấn), **thì** ID, `MAXID`, mốc thời gian, chỉ mục đúng ở lần hai.
5. **Cho** bảng lớn (đến 1 triệu dòng), **thì** lưu xong trong ngưỡng SC-004 và bộ nhớ không vượt ngưỡng SC-005.
6. **Cho** lưu thất bại giữa chừng, **thì** file gốc nguyên vẹn (ghi ra tệp tạm, đọc lại kiểm, mới thay như T1/T2).
7. **Cho** W4 trượt ở VM-F-T3, **thì** BI Pro tự chuyển sang phương án dự phòng "Enter Data" (dữ liệu nằm trong biểu thức M) cho bảng mới nhỏ (đến 10 000 dòng) và báo bảng lớn hơn cần Desktop làm mới.

---

### Câu chuyện 4 — Biến đổi nâng cao: Custom Column, Merge, Append, Group By, Advanced Editor, Query Dependencies (Ưu tiên: P2)

Ngoài lệnh cơ bản, người dùng dùng các hộp thoại: Custom Column (công thức M), Merge Queries (chọn hai truy vấn, chọn cột khoá, kiểu join, mở rộng cột bảng lồng), Append Queries (nối hai hoặc nhiều truy vấn), Group By (cơ bản và nâng cao với nhiều phép tổng hợp), Advanced Editor (sửa toàn bộ biểu thức M, có kiểm cú pháp), cửa sổ Query Dependencies (đồ thị nguồn → truy vấn → bảng nạp).

**Vì sao P2**: cần ngôn ngữ M đủ rộng; không chặn luồng `sales_2026.xlsx` cơ bản.

**Kiểm thử độc lập**: trên `sales_2026.xlsx` và `customers.csv`: Merge (Left Outer) theo `CustomerID` rồi mở rộng cột `Segment`; Append hai bảng cùng cột; Group By `Region` với `Sum(Amount)`, `Count rows`; Custom Column `[Qty] * [Price]`; mỗi kết quả khớp số liệu Desktop xuất.

**Kịch bản chấp nhận**:

1. **Cho** Custom Column với biểu thức M hợp lệ, **thì** thêm cột, kiểu suy ra như Desktop; biểu thức sai thì báo lỗi cú pháp kèm vị trí và không thêm bước.
2. **Cho** Merge với từng kiểu join, **thì** số dòng và giá trị khớp golden Desktop (kể cả khoá `null`, khác kiểu, khác hoa thường).
3. **Cho** Append hai bảng khác tập cột, **thì** hợp cột theo quy tắc Desktop, ô thiếu là `null`.
4. **Cho** Group By nhiều phép tổng hợp, **thì** tên cột mặc định và kiểu kết quả khớp Desktop.
5. **Cho** Advanced Editor, **thì** hiện toàn bộ `let … in`, sửa rồi "Done" làm lại Applied Steps; biểu thức dùng hàm ngoài phạm vi thì báo "chưa hỗ trợ" kèm tên hàm, không im lặng cho sai.
6. **Cho** Query Dependencies, **thì** vẽ đồ thị đúng quan hệ giữa các truy vấn (Merge/Append/tham chiếu) và nguồn.
7. **Cho** truy vấn tham chiếu một truy vấn khác, **thì** thay đổi ở truy vấn gốc lan sang truy vấn con.

---

### Câu chuyện 5 — Tạo `.pbix` mới từ đầu (Ưu tiên: P2)

"File → New" tạo tài liệu trống (một trang báo cáo trống, mô hình trống); người dùng Get Data, dựng báo cáo, lưu thành `.pbix`; Desktop mở đúng.

**Vì sao P2**: phụ thuộc Câu chuyện 1 đến 3 và quan sát tập thành phần tối thiểu.

**Kiểm thử độc lập**: tạo mới, nạp `sales_2026.xlsx`, thêm một card và một biểu đồ cột, lưu; Desktop mở thấy cùng bảng, visual, số liệu.

**Kịch bản chấp nhận**:

1. **Cho** tài liệu mới, **khi** ⌘S lần đầu, **thì** hộp thoại lưu hỏi tên và vị trí, ghi file mới, không đụng file khác.
2. **Cho** tài liệu mới chưa có dữ liệu, **thì** báo cáo và mô hình trống vẫn lưu và mở lại được.
3. **Cho** file mới, **thì** `docs/` ghi lại phiên bản và tập thành phần tối thiểu Desktop chấp nhận.

---

### Câu chuyện 6 — Cột tính toán và bảng tính toán DAX (Ưu tiên: P2)

Người dùng bấm "Cột mới" hoặc "Bảng mới" ở Table View, gõ `Tên = biểu thức DAX`; engine tính giá trị theo từng dòng (cột) hoặc ra bảng (bảng); dữ liệu hiện ngay và lưu theo T3 (cột có dữ liệu VertiPaq sẵn như Desktop ghi).

**Vì sao P2**: hoãn từ Phase E, cần cùng đường ghi T3 với Câu chuyện 3.

**Kiểm thử độc lập**: thêm cột `Doanh_thu = Fact[Qty] * Fact[Price]` và bảng `Top_Region = SUMMARIZE(...)`; lưu; Desktop mở thấy cùng giá trị từng dòng và cùng số dòng.

**Kịch bản chấp nhận**:

1. **Cho** biểu thức hợp lệ, **thì** cột hoặc bảng hiện ở Data pane và Table View với giá trị khớp Desktop (so từng dòng trên mẫu).
2. **Cho** biểu thức lỗi hoặc vòng phụ thuộc, **thì** báo lỗi rõ, không đổi mô hình.
3. **Cho** đổi dữ liệu gốc, **thì** cột và bảng tính toán tính lại theo thứ tự phụ thuộc.
4. **Cho** lưu rồi mở lại trong Desktop, **thì** cùng biểu thức và giá trị, không cần Refresh để thấy dữ liệu.

---

### Câu chuyện 7 — Parquet và JSON (Ưu tiên: P3)

Get Data nhận thêm Parquet và JSON; Navigator liệt kê bảng/bản ghi, Query Editor có bước mở rộng bản ghi và danh sách cho JSON lồng nhau.

**Vì sao P3**: cùng đường nạp, thêm định dạng; không có trong luồng "xong khi".

**Kiểm thử độc lập**: nạp `sales_2026.parquet` và `orders.json` (có mảng lồng); số dòng và giá trị khớp bản Desktop.

**Kịch bản chấp nhận**:

1. **Cho** file Parquet, **thì** kiểu cột (int, double, string, ngày giờ, decimal) được ánh xạ như Desktop.
2. **Cho** JSON gốc là mảng bản ghi, **thì** thành bảng có cột `Record`/`List` và mở rộng được như Desktop.
3. **Cho** file lớn (đến 1 triệu dòng), **thì** Navigator và xem trước vẫn phản hồi nhanh (SC-003).

---

### Câu chuyện 8 — PostgreSQL và SQLite (Ưu tiên: P3)

Get Data nhận thêm PostgreSQL (máy chủ, cơ sở dữ liệu, tên đăng nhập, mật khẩu) và SQLite (file); Navigator liệt kê bảng, khung nhìn, lược đồ; có thể nhập truy vấn SQL gốc.

**Vì sao P3**: phụ thuộc đợt 1; cần kết nối mạng và quản lý thông tin đăng nhập.

**Kiểm thử độc lập**: SQLite nhỏ (file mẫu); PostgreSQL cục bộ nếu có (do bạn cho phép, không tải từ mạng); số dòng và giá trị khớp truy vấn trực tiếp.

**Kịch bản chấp nhận**:

1. **Cho** file SQLite, **thì** liệt kê bảng và nạp được như Câu chuyện 1.
2. **Cho** PostgreSQL với thông tin đúng, **thì** liệt kê lược đồ, bảng, xem trước, nạp; thông tin sai thì báo lỗi xác thực mà không lộ mật khẩu trong nhật ký.
3. **Cho** mật khẩu, **thì** không bao giờ ghi vào `.pbix` hay `docs/` (hiến pháp IV); lưu ở Keychain khi người dùng đồng ý.

---

### Trường hợp biên

- Tên bảng hoặc cột trùng, có dấu tiếng Việt, ký tự đặc biệt, quá dài, hoặc trùng tên measure có sẵn.
- CSV có dấu phân cách `;`, mã hoá không phải UTF-8, dòng tiêu đề thiếu, ô nhiều dòng trong ngoặc kép; Excel có ô gộp, công thức, ngày kiểu số, hàng đầu trống.
- Cột kiểu số có chữ lẫn lộn: ô lỗi hiển thị `Error` (theo Desktop), không làm sập nạp.
- Truy vấn tham chiếu vòng, tên bước trùng, truy vấn tắt Enable load nhưng truy vấn khác dùng.
- Nạp lại bảng đã có quan hệ khi cột khoá đổi kiểu hoặc biến mất.
- Bảng rất lớn: hạn chế bộ nhớ, hủy giữa chừng (nút Cancel).
- Nguồn dữ liệu bị xoá hoặc di chuyển sau khi lưu; mở file trên máy khác (đường dẫn Windows so với macOS).
- File `.pbix` có RLS, `SecurityBindings`, hoặc DataMashup riêng của Desktop khi BI Pro lưu T3 (phải giữ nguyên byte phần không đụng).
- Lưu T3 khi Desktop đang mở cùng file (ngoài phạm vi).
- Cột tính toán tham chiếu cột bảng được nạp lại bằng Query Editor.

## Yêu cầu *(bắt buộc)*

### Yêu cầu chức năng

**Get Data và Navigator**

- **FR-001**: Hệ thống PHẢI có lệnh Get Data nhận file Text/CSV và Excel Workbook (đợt 1), mở Navigator xem trước và cho chọn nhiều mục.
- **FR-002**: Hệ thống PHẢI nạp được bảng từ Navigator vào mô hình đang mở (nút "Load") hoặc mở Query Editor (nút "Transform Data") theo quan sát Desktop.
- **FR-003**: Hệ thống PHẢI tự dò kiểu cột và thăng cấp tiêu đề khi nạp CSV/Excel theo quan sát Desktop.
- **FR-004**: Bảng mới PHẢI hoàn tác được (⌘Z) trong ngăn xếp chung; nếu có measure/quan hệ/visual phụ thuộc thì chặn hoặc báo theo quan sát (như quy tắc chặn tham chiếu FR-020 của Phase E, `specs/009-e-mo-hinh-hoa-luu-t2/spec.md`).
- **FR-005**: Hệ thống PHẢI báo lỗi rõ (kèm nguyên nhân) khi file không đọc được và KHÔNG đổi mô hình.

**Query Editor**

- **FR-010**: Hệ thống PHẢI có cửa sổ Query Editor với danh sách truy vấn, lưới xem trước, Query Settings (Properties, Applied Steps), thanh công thức M, column profile và ribbon tab Home, Transform, Add Column, View.
- **FR-011**: Mỗi lệnh ribbon trong danh sách ở FR-030 PHẢI sinh đúng một bước M có tên và biểu thức khớp quan sát Desktop; người dùng PHẢI sửa, xoá, đổi thứ tự, chèn bước được.
- **FR-012**: Xem trước PHẢI giới hạn 1000 dòng đầu như Desktop; column profile PHẢI nêu rõ "dựa trên 1000 dòng đầu".
- **FR-013**: Hệ thống PHẢI có "Close & Apply" nạp dữ liệu đã biến đổi vào mô hình, tôn trọng cờ "Enable load", và hỏi "Pending changes" khi đóng chưa áp dụng.
- **FR-014**: Truy vấn PHẢI lưu dưới dạng biểu thức M hợp lệ để Desktop đọc lại (`DataMashup`), và PHẢI được đọc lại khi mở file do Desktop tạo (ít nhất liệt kê truy vấn và hiển thị biểu thức).

**Ngôn ngữ M**

- **FR-030**: Hệ thống PHẢI hỗ trợ khoảng 30 hàm sau với ngữ nghĩa khớp Desktop trên dữ liệu mẫu: `Table.PromoteHeaders`, `Table.TransformColumnTypes`, `Table.RenameColumns`, `Table.RemoveColumns`, `Table.SelectColumns`, `Table.ReorderColumns`, `Table.SelectRows`, `Table.Sort`, `Table.FirstN`, `Table.LastN`, `Table.Skip`, `Table.RemoveFirstN`, `Table.Distinct`, `Table.ReplaceValue`, `Table.AddColumn`, `Table.AddIndexColumn`, `Table.DuplicateColumn`, `Table.SplitColumn`, `Table.CombineColumns`, `Table.Group`, `Table.Join`, `Table.NestedJoin`, `Table.ExpandTableColumn`, `Table.Combine`, `Table.Pivot`, `Table.UnpivotOtherColumns`, `Table.Unpivot`, `Table.FillDown`, `Table.FillUp`, `Table.ReplaceErrorValues`, `Table.RemoveRowsWithErrors`, `Table.Profile` (cho column profile), cùng hàm giá trị cơ bản (`Text.*`, `Number.*`, `Date.*`, `List.*`, `each`, `_`).
- **FR-031**: Hàm hoặc cú pháp ngoài danh sách PHẢI báo "chưa hỗ trợ" kèm tên và dòng, KHÔNG trả kết quả sai, và PHẢI được đánh dấu [SUY ĐOÁN] nếu chưa có quan sát.
- **FR-032**: Lỗi ở ô PHẢI giữ dạng `Error` theo ô (không làm hỏng cả bảng) như Desktop; kiểu và `null` PHẢI đúng.

**Biến đổi nâng cao**

- **FR-040**: Hệ thống PHẢI có hộp thoại Custom Column, Merge Queries (Left Outer, Right Outer, Full Outer, Inner, Left Anti, Right Anti), Append Queries (hai hoặc nhiều), Group By (cơ bản và nâng cao), Advanced Editor.
- **FR-041**: Hệ thống PHẢI có cửa sổ Query Dependencies vẽ đồ thị truy vấn và nguồn.

**Lưu T3 và tài liệu mới**

- **FR-050**: Hệ thống PHẢI ghi bảng mới vào VertiPaq trong cùng lần lưu (từ điển, IDF, `H$` hoặc tương đương Desktop chấp nhận, thống kê, metadata, chỉ mục quan hệ), và `DataMashup` chứa các truy vấn.
- **FR-051**: Lưu PHẢI ghi ra tệp tạm, đọc lại kiểm (so từng cột, distinct count, metadata) rồi mới thay file thật; thất bại thì file gốc nguyên vẹn.
- **FR-052**: Nếu gate W4 hoặc F-T3 trượt, hệ thống PHẢI dùng phương án dự phòng Enter Data cho bảng nhỏ và ghi rõ giới hạn trong giao diện.
- **FR-053**: Hệ thống PHẢI có "File → Mới" tạo `.pbix` trống và lưu ra file mới mở được trong Desktop.
- **FR-054**: Bảng nạp lại bằng Query Editor PHẢI giữ quan hệ, measure, `DiagramLayout` khi cột còn tồn tại; cột mất PHẢI cảnh báo kèm danh sách chỗ dùng.

**Cột và bảng tính toán**

- **FR-060**: Hệ thống PHẢI tạo, sửa, xoá cột tính toán và bảng tính toán DAX; giá trị tính bằng engine DAX hiện có, khớp Desktop, và lưu theo T3.

**Đợt 2 và 3**

- **FR-070**: Hệ thống PHẢI nạp được Parquet và JSON (P3).
- **FR-071**: Hệ thống PHẢI nạp được SQLite và PostgreSQL (P3); mật khẩu KHÔNG BAO GIỜ ghi vào `.pbix`, `docs/` hay nhật ký.

**Chung**

- **FR-080**: Mọi thao tác ở Query Editor và Get Data PHẢI vào ngăn xếp hoàn tác chung; ghi T3 KHÔNG được làm hỏng phần T1/T2 đã có.
- **FR-081**: Mọi quan sát Desktop PHẢI được ghi vào `docs/phase-f-evidence/` trước khi code phần liên quan; hàm/quy tắc chưa quan sát PHẢI đánh dấu [SUY ĐOÁN].
- **FR-082**: Hệ thống KHÔNG được ghi đè file gốc của người dùng; file mẫu do Claude sinh và các tệp ra nằm trong `build/f-out/`.

### Thực thể chính

- **Truy vấn (Query)**: tên, biểu thức M, danh sách bước (tên, biểu thức), cờ Enable load, nguồn, bảng nạp (nếu có), trạng thái lỗi.
- **Bước áp dụng (Applied Step)**: tên, biểu thức M, kiểu lệnh, trạng thái, bảng kết quả xem trước.
- **Nguồn dữ liệu (Data Source)**: loại (CSV, Excel, Parquet, JSON, SQLite, PostgreSQL), vị trí hoặc kết nối, tuỳ chọn, thông tin đăng nhập (chỉ ở Keychain).
- **Bảng nạp (Loaded Table)**: bảng mô hình ứng với một truy vấn, cột, kiểu, dữ liệu, ánh xạ sang `Partition`/`DataMashup`.
- **Cột/bảng tính toán**: biểu thức DAX, kiểu, giá trị, thứ tự phụ thuộc.
- **Tài liệu mới**: tập thành phần tối thiểu của `.pbix`.

## Tiêu chí thành công *(bắt buộc)*

### Kết quả đo được

- **SC-001**: Luồng đầy đủ `sales_2026.xlsx` → Query Editor → Close & Apply → report → lưu `.pbix` → Desktop mở được, hoàn thành trong dưới 5 phút thao tác, số dòng và tổng các cột số khớp 100% với bản Desktop làm cùng các bước.
- **SC-002**: Với 30 hàm M và các hộp thoại đã nêu, 100% test golden khớp bảng kết quả Desktop (so từng ô, kể cả `null` và `Error`).
- **SC-003**: Navigator mở xem trước một file 1 triệu dòng trong dưới 3 giây; chuyển giữa các bước Applied Steps phản hồi dưới 500 ms với bảng xem trước 1000 dòng.
- **SC-004**: Lưu T3 cho bảng mới 1 triệu dòng, 10 cột trong dưới 15 giây (bản release); bảng 100 000 dòng dưới 4 giây; lưu Nhom6 chỉ thay đổi T2/T1 giữ ngưỡng của Phase E.
- **SC-005**: Nạp và lưu bảng 1 triệu dòng dùng không quá 2 GB bộ nhớ.
- **SC-006**: Gate F-T3: Desktop mở file có bảng mới do BI Pro lưu không báo lỗi trên ít nhất 5 bộ (nhiều kiểu cột, có `null`, có quan hệ, có measure, 3 bảng cùng lúc); mọi ô khớp.
- **SC-007**: Golden DAX Phase B (30) và truy vấn visual (72) không đổi sau Phase F.
- **SC-008**: Mọi thao tác ở Query Editor hoàn tác được; không có thay đổi mất âm thầm khi đóng cửa sổ.
- **SC-009**: Bạn xác nhận bằng tay trên VM rằng ba gate F-T3, F-Query (Query Editor mở file Desktop tạo, liệt kê đúng truy vấn) và F-Mới (file tạo mới) đạt.

## Giả định

- File mẫu `sales_2026.xlsx` (cùng CSV, Parquet, JSON, SQLite) do Claude sinh ra bằng công cụ có sẵn trên máy (không tải mạng) và đặt ở `build/f-out/`; nếu bạn có file thật thì dùng file đó.
- Mọi thử nghiệm làm trên bản sao Nhom6 hoặc file mới; không ghi đè file gốc ở `~/Downloads`.
- Desktop không cần Refresh để thấy dữ liệu T3; nếu Refresh thì cần đường dẫn nguồn hợp lệ trong VM (ngoài phạm vi kiểm, ghi lại thôi).
- Query folding, fuzzy matching, parameters, function, dataflow, DirectQuery, gateway, nguồn đám mây (SharePoint, OneDrive, web) và tuỳ chọn riêng tư (privacy levels) ngoài phạm vi Phase F.
- Chọn công cụ thực thi dữ liệu (tự viết hay thư viện ngoài như DuckDB đã nêu trong `docs/BIPRO_BUILD_PLAN.md`) thuộc bước `/speckit-plan`; theo hiến pháp III và CLAUDE.md, không thêm thư viện nào khi chưa hỏi bạn và được duyệt trong plan.
- Chỉ Excel `.xlsx` và CSV ở lát P1; `.xls`, `.xlsb`, Excel có mật khẩu ngoài phạm vi.
- Test Desktop trên VM do bạn làm tay hoặc cho phép Claude điều khiển từng lần; kết quả ghi vào `docs/phase-f-evidence/`.
- Giao diện tiếng Việt, theo `UIdesign/*/screen.png` (màn `get_data_dialog`, `navigator_dialog_fixed`, Query Editor) và quan sát Desktop.
- Phase này tách thành nhiều lát nên `tasks.md` sẽ chia theo câu chuyện, đánh dấu phần giao được cho agy theo CLAUDE.md.
