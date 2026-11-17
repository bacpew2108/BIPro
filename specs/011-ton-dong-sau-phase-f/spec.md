# Đặc tả tính năng: Tồn đọng sau Phase F

**Nhánh**: `main` (không tạo nhánh riêng)

**Ngày tạo**: 2026-11-17

**Trạng thái**: Nháp, chờ bạn duyệt

**Đầu vào**: "Triển khai các phần tồn đọng đi" = danh sách tồn đọng cuối mục "Phase F, Giai đoạn 11–13" của `docs/STATE.md`: (1) nén RLE khi ghi cột có giá trị lặp (T111); (2) phép gộp ngầm (cột số vào ô giá trị thành Sum, Average, Count…); (3) Auto date/time cho tài liệu mới và tự phát hiện quan hệ khi nạp nhiều bảng; (4) màn "Thêm dữ liệu vào báo cáo" trên khung trống của tài liệu mới; (5) hàm văn bản DAX; (6) sửa/xoá cột tính toán nằm trong quan hệ, là cấp phân cấp hay cột sắp xếp của cột khác; (7) lưu bảng quá 8 388 608 dòng; (8) PostgreSQL kiểu timestamptz, time, interval, bytea, mảng; (9) tên driver ODBC SQLite không ghi cứng; (10) Parquet lược đồ lồng. Mỗi mục quan sát Desktop trước khi viết code và có gate Desktop.

Cấp trên: `docs/BIPRO_BUILD_PLAN.md` (Phase F, mốc M3 đã đạt; Phase G chưa bắt đầu), `specs/010-f-get-data-power-query-t3/` (đường ghi T3, Get Data, cột tính toán), `specs/009-e-mo-hinh-hoa-luu-t2/` và `specs/003-d2-build-pane-field-well/` (field well, quy tắc ô). Mâu thuẫn thì sửa `docs/` trước.

**Phạm vi**: đóng các khoảng hở còn lại của Phase D đến F để BI Pro làm được những việc Desktop làm mặc định trên tài liệu mới và trên dữ liệu lớn. Không lấn sang Phase G (xuất PDF/PNG, dark mode, VoiceOver, tiếng Anh…). Các câu chuyện độc lập, làm và gate riêng từng câu chuyện.

## Làm rõ

### Phiên 2026-11-17

- H: Đợt này Claude có được tự lái VM như Phase F? → Đ: Có, Claude lái VM.
- H: Màn "Thêm dữ liệu vào báo cáo" gồm những lối vào nào? → Đ: Excel và nguồn khác (đã có) cùng "Dán dữ liệu vào bảng trống" (Enter Data, làm mới); SQL Server và dữ liệu mẫu hiện xám kèm lý do.

## Quan sát Power BI

Mỗi mục [SUY ĐOÁN] dưới đây phải được quan sát trên Power BI Desktop 2.159 trong VM trước khi code phần liên quan, ghi vào `docs/phase-f2-evidence/` (thư mục của đợt này). Không dịch ngược; chỉ nhìn giao diện, đọc file Desktop ghi, DAX query view, Performance Analyzer và tài liệu công khai của Microsoft (DAX, M, MS-XLDM). Bạn cho Claude lái VM trong đợt này như Phase F (2026-11-17): ảnh cắt che tên tài khoản, dọn thư mục VM sau mỗi buổi.

**Hiện trạng trong BI Pro** (đọc từ mã và `docs/`):

- **Ghi dữ liệu VertiPaq**: từ điển + bit-packing, chưa RLE; một bảng tối đa một đoạn dữ liệu (8 388 608 dòng), quá thì báo lỗi rõ (`WriterLimitTests`). Cỡ tệp lớn hơn Desktop cho cột có nhiều giá trị lặp (chưa đo con số).
- **Ô giá trị của visual**: cột số bị từ chối kèm lời "BI Pro chưa có phép gộp ngầm" (`WellRules.aggregationReason`). Nhom6 đặt cờ "discourage implicit measures" nên Desktop cũng chặn (VM-D2b); tài liệu mới BI Pro tạo không đặt cờ này nên Desktop cho gộp ngầm, BI Pro chưa.
- **Tài liệu mới**: tắt Auto date/time (`__PBI_TimeIntelligenceEnabled = 0`) vì bộ ghi chưa dựng bảng ngày cục bộ; không tự phát hiện quan hệ khi nạp; khung trống không có màn "Thêm dữ liệu vào báo cáo"; visual chèn bằng lệnh nằm chồng ở cùng vị trí (Desktop cũng vậy, ghi nhận M3).
- **DAX**: hàm văn bản mới có `LEFT`, `FORMAT` (và `&`).
- **Cột tính toán**: sửa/xoá bị chặn khi cột nằm trong quan hệ, là cấp phân cấp, hay là cột sắp xếp của cột khác, vì chưa dựng lại chỉ mục quan hệ và chỉ mục phân cấp.
- **Nguồn**: PostgreSQL báo "chưa hỗ trợ" cho timestamptz, time, interval, bytea, mảng; M SQLite ghi tên driver Devart cố định; Parquet chỉ đọc lược đồ phẳng.

**[SUY ĐOÁN], phải quan sát** (mỗi mục một buổi VM ngắn, ghi kết quả trước khi code):

- **Gộp ngầm**: trên tài liệu không đặt "discourage implicit measures": kéo cột số vào ô Values/Card thì Desktop chọn phép gộp mặc định nào (theo `SummarizeBy` của cột: Sum, Count…, cột ngày, cột chữ thành Count/First?), danh sách phép gộp trong menu của ô (Sum, Average, Minimum, Maximum, Count (Distinct), Count, Standard deviation, Variance, Median; "Don't summarize"), nhãn trường hiện ra ("Sum of Amount"), cách lưu trong PBIR/layout (`Aggregation` với `Function` mã số), truy vấn DAX Performance Analyzer sinh ra (`SUM('T'[c])` trong `SUMMARIZECOLUMNS`, `CALCULATE`…), hành vi khi đổi phép gộp, khi kéo cùng cột hai lần.
- **Auto date/time**: tuỳ chọn mặc định của Desktop cho file mới; khi nạp bảng có cột ngày thì Desktop tạo `DateTableTemplate_…` và `LocalDateTable_…` (biểu thức `CALENDAR`, cột Year/Quarter/Month/Day, phân cấp "Date Hierarchy", quan hệ ẩn, chú thích), dữ liệu VertiPaq của chúng, field list hiện phân cấp ngày dưới cột; visual dùng phân cấp ngày sinh truy vấn gì; tắt tuỳ chọn thì xoá những gì.
- **Tự phát hiện quan hệ**: điều kiện Desktop dùng khi nạp nhiều bảng cùng lúc và khi nạp bảng mới vào mô hình có sẵn (tên cột trùng, kiểu, tính duy nhất, chiều nhiều–một), thứ tự, quan hệ nào bị tắt (không hoạt động) khi có đường thứ hai; tuỳ chọn "Autodetect new relationships after data is loaded".
- **Màn "Add data to your report"**: các ô trên khung trống của file mới (Import data from Excel, Import data from SQL Server, Paste data into a blank table, Use sample data, Get data from another source), khi nào màn này biến mất, bấm từng ô mở hộp thoại nào.
- **Enter Data ("Paste data into a blank table")**: hộp thoại Create Table (lưới, thêm cột/dòng, dán, tên bảng), M Desktop sinh (dữ liệu nén trong biểu thức, kiểu cột, bước `Changed Type`), cách lưu bảng trong mô hình, sửa lại qua nút cài đặt bước Source.
- **Hàm văn bản DAX**: kết quả của từng hàm trong FR-020 trên chuỗi tiếng Việt có dấu, chuỗi rỗng, BLANK, số, vị trí ngoài phạm vi, ký tự đại diện của `SEARCH` (`?`, `*`, `~`), phân biệt hoa thường của `FIND` và `SUBSTITUTE`, lỗi trả về; xác nhận bằng DAX query view trên một bảng mẫu.
- **Sửa/xoá cột tính toán dính quan hệ, phân cấp, cột sắp xếp**: VM-F9 đã thấy Desktop dựng lại `H$` và `U$` khi sửa cột là cấp phân cấp; còn phải xem: sửa cột ở đầu quan hệ (chỉ mục quan hệ `R$` dựng lại, quan hệ giữ hay bị bỏ khi giá trị không còn duy nhất), xoá cột đang ở quan hệ/phân cấp/cột sắp xếp (Desktop hỏi gì, xoá kèm quan hệ hay cấp phân cấp không, phân cấp còn một cấp thì sao), cột sắp xếp (`SortByColumn`) khi cột đích bị sửa giá trị không còn ánh xạ một–một.
- **Bảng nhiều đoạn dữ liệu**: cách Desktop chia đoạn (số dòng mỗi đoạn, đoạn cuối), thống kê từng đoạn, tên tệp, `H$` và chỉ mục quan hệ của bảng nhiều đoạn; bảng thử khoảng 10 triệu dòng.
- **RLE**: cách Desktop chọn giữa RLE và bit-packing theo đoạn, bố cục bảng run và vùng meta, có sắp lại dòng trong đoạn không (ảnh hưởng thứ tự dòng đọc lại), trên cột lặp dài và cột ngẫu nhiên.
- **PostgreSQL kiểu khác**: Desktop đổi timestamptz, time, interval, bytea, mảng thành kiểu nào trong Power Query và trong mô hình (datetimezone, time, duration, binary, chữ?), mảng hiện ra sao, kiểu nào Desktop bỏ.
- **Driver ODBC SQLite**: M Desktop ghi với driver khác Devart (ví dụ "SQLite3 ODBC Driver"), tên DSN và chuỗi kết nối; Refresh khi máy Windows thiếu driver ghi trong M báo lỗi gì.
- **Parquet lồng**: Desktop hiện cột struct và list ra sao (Record/List, tự mở rộng hay không), M sinh ra, kiểu mặc định sau mở rộng.

**Chuẩn so khớp** (hiến pháp II): số liệu, giá trị từng ô và văn bản truy vấn khớp Desktop. Golden gồm (a) kết quả DAX query view của Desktop cho hàm văn bản và truy vấn visual có gộp ngầm; (b) file `.pbix` Desktop lưu cho cùng dữ liệu (Auto date/time, quan hệ tự phát hiện, bảng nhiều đoạn, RLE), đọc bằng PBIXKit để so cấu trúc và từng ô; (c) bảng Desktop nạp từ PostgreSQL, SQLite, Parquet lồng; (d) 30 golden DAX Phase B và 72 truy vấn visual không đổi.

## Kịch bản người dùng và kiểm thử *(bắt buộc)*

### Câu chuyện 1 — Phép gộp ngầm trong visual (Ưu tiên: P1)

Bạn mở tài liệu mới (hoặc file không đặt "discourage implicit measures"), kéo cột số `Amount` vào card hay ô giá trị của biểu đồ cột. BI Pro tự dùng phép gộp mặc định như Desktop (Desktop hiện "Sum of Amount", BI Pro hiện "Tổng của Amount"), bạn đổi sang Average, Count, Count (Distinct)… trong menu của trường, visual tính lại; lưu và mở trong Desktop thấy cùng trường, cùng phép gộp, cùng số.

**Vì sao P1**: đây là thao tác đầu tiên khi dựng báo cáo trên dữ liệu vừa nạp; hiện BI Pro bắt tạo measure trước, khác Desktop và chặn luồng M3 ở bước "report".

**Kiểm độc lập**: tài liệu mới + `sales_2026.xlsx` → card và biểu đồ cột dùng cột số không có measure; so số với DAX Desktop; lưu, Desktop mở đúng.

**Kịch bản chấp nhận**:

1. **Cho** mô hình không đặt "discourage implicit measures", **khi** kéo cột số vào ô giá trị, **thì** trường nhận phép gộp mặc định theo thuộc tính tổng hợp của cột (như Desktop) và nhãn tiếng Việt tương ứng "Sum of Amount" của Desktop ("Tổng của Amount").
2. **Cho** trường đã gộp, **khi** đổi phép gộp trong menu, **thì** visual tính lại và số khớp Desktop cho mọi phép gộp trong danh sách.
3. **Cho** mô hình đặt "discourage implicit measures" (Nhom6), **thì** BI Pro vẫn chặn như hiện nay, cùng lời báo như Desktop.
4. **Cho** visual có trường gộp ngầm, **khi** lưu và mở bằng Desktop, **thì** Desktop hiện cùng trường, phép gộp và số; file Desktop tạo có trường gộp ngầm mở trong BI Pro cũng hiện đúng.
5. **Cho** cột chữ hoặc ngày kéo vào ô giá trị, **thì** BI Pro làm như Desktop (Count hay First/Last tuỳ quan sát).

---

### Câu chuyện 2 — Tài liệu mới giống Desktop: màn thêm dữ liệu, Auto date/time, tự phát hiện quan hệ (Ưu tiên: P1)

Bạn tạo tài liệu mới: khung trống hiện màn "Thêm dữ liệu vào báo cáo" với các lối vào nạp dữ liệu. Bạn nạp hai bảng có cột khoá trùng tên; BI Pro tự tạo quan hệ như Desktop. Cột ngày trong bảng có phân cấp ngày (Năm, Quý, Tháng, Ngày) dùng được ngay trong visual; lưu và Desktop mở thấy cùng bảng ngày cục bộ, quan hệ và phân cấp.

**Vì sao P1**: Desktop làm ba việc này mặc định; thiếu chúng thì file mới BI Pro tạo khác file Desktop và người dùng phải tự làm thêm từng bước.

**Kiểm độc lập**: tài liệu mới → nạp `Sales` và `Customers` (CSV/Excel mẫu) → quan hệ tự tạo, biểu đồ theo Năm của cột ngày → lưu → Desktop mở, so cấu trúc với file Desktop tự làm cùng bước.

**Kịch bản chấp nhận**:

1. **Cho** tài liệu mới chưa có dữ liệu, **thì** khung báo cáo hiện màn "Thêm dữ liệu vào báo cáo"; bấm từng lối vào mở đúng hộp thoại; nạp xong bảng đầu tiên thì màn biến mất như Desktop.
6. **Cho** lối vào "Dán dữ liệu vào bảng trống", **khi** dán vài dòng từ bảng tính, đặt tên bảng và Tải, **thì** bảng vào mô hình với kiểu cột như Desktop; lưu và Desktop mở, Refresh ra cùng dữ liệu.
2. **Cho** tài liệu mới bật Auto date/time (mặc định như Desktop), **khi** nạp bảng có cột ngày, **thì** cột đó có phân cấp ngày dùng được trong field list và visual, số khớp Desktop.
3. **Cho** tuỳ chọn Auto date/time của file, **khi** tắt, **thì** các bảng ngày cục bộ bị bỏ như Desktop; bật lại thì dựng lại.
4. **Cho** nạp nhiều bảng có cột cùng tên và kiểu phù hợp, **khi** tải xong, **thì** BI Pro tạo đúng các quan hệ Desktop tạo trong cùng tình huống (chiều, lực lượng, trạng thái hoạt động), hoàn tác được bằng một bước.
5. **Cho** lưu tài liệu trên, **khi** Desktop mở, **thì** không báo lỗi, bảng ngày cục bộ, phân cấp và quan hệ giống file Desktop tự tạo.

---

### Câu chuyện 3 — Hàm văn bản DAX (Ưu tiên: P2)

Bạn viết measure, cột tính toán hay truy vấn DAX dùng `LEN`, `UPPER`, `MID`, `SUBSTITUTE`, `SEARCH`… Kết quả giống Desktop, kể cả với chữ tiếng Việt có dấu và BLANK.

**Vì sao P2**: cần cho cột tính toán và measure thường gặp; độc lập, không chặn luồng chính.

**Kiểm độc lập**: bộ truy vấn golden DAX query view của Desktop trên bảng mẫu có chữ Việt, chuỗi rỗng, BLANK, số.

**Kịch bản chấp nhận**:

1. **Cho** mỗi hàm trong FR-020, **khi** chạy bộ truy vấn golden, **thì** 100% ô khớp Desktop (giá trị và kiểu).
2. **Cho** đối số sai (vị trí âm, không tìm thấy không có giá trị dự phòng), **thì** BI Pro báo lỗi cùng loại Desktop báo.
3. **Cho** cột tính toán dùng hàm mới, **khi** lưu và mở Desktop, **thì** Desktop nhận công thức và giá trị đã lưu khớp.

---

### Câu chuyện 4 — Sửa và xoá cột tính toán còn được mô hình dùng (Ưu tiên: P2)

Bạn sửa công thức một cột tính toán là đầu quan hệ, là cấp của phân cấp hay là cột sắp xếp của cột khác; hoặc xoá cột đó. BI Pro làm như Desktop: hỏi lại khi cần, dựng lại những gì Desktop dựng lại, lưu được và Desktop mở đúng.

**Vì sao P2**: hoàn tất FR-060 của Phase F; hiện bị chặn kèm lý do.

**Kiểm độc lập**: bản sao Nhom6 (cột `Dim_District[branch_label]` là cấp phân cấp) và tài liệu có quan hệ trên cột tính toán: sửa, xoá, lưu, Desktop mở và tính đúng.

**Kịch bản chấp nhận**:

1. **Cho** cột tính toán là cấp phân cấp, **khi** sửa công thức, **thì** phân cấp dùng giá trị mới; lưu và Desktop mở, visual dùng phân cấp ra số đúng.
2. **Cho** cột tính toán ở đầu quan hệ, **khi** sửa công thức, **thì** quan hệ dùng giá trị mới (hoặc bị chặn/bỏ như Desktop khi đầu "một" không còn duy nhất); lọc chéo qua quan hệ khớp Desktop.
3. **Cho** cột là cột sắp xếp của cột khác, **khi** sửa, **thì** thứ tự sắp xếp dùng giá trị mới; trường hợp Desktop báo lỗi một–một thì BI Pro báo như vậy.
4. **Cho** xoá cột còn ở quan hệ/phân cấp/cột sắp xếp, **thì** BI Pro hỏi và xoá kèm phần liên quan như Desktop; hoàn tác trả lại tất cả.

---

### Câu chuyện 5 — Lưu dữ liệu lớn gọn như Desktop: RLE và bảng nhiều đoạn (Ưu tiên: P3)

Bạn nạp bảng 10 triệu dòng hay bảng có cột lặp nhiều rồi lưu. BI Pro lưu được (không còn giới hạn 8 388 608 dòng), cỡ tệp gần bằng Desktop, Desktop mở và tính đúng.

**Vì sao P3**: các ngưỡng thời gian và bộ nhớ của Phase F đã đạt; việc này mở rộng giới hạn và giảm cỡ tệp.

**Kiểm độc lập**: bảng sinh sẵn 10 triệu dòng (Parquet/CSV) và bảng 1 triệu dòng có cột lặp; so cỡ tệp, thời gian, bộ nhớ và kết quả DAX với file Desktop cùng dữ liệu.

**Kịch bản chấp nhận**:

1. **Cho** bảng hơn 8 388 608 dòng, **khi** lưu, **thì** lưu xong, đọc lại trong BI Pro từng ô trùng nguồn, Desktop mở và đếm đúng số dòng, tổng đúng.
2. **Cho** cột có giá trị lặp, **khi** lưu, **thì** cỡ tệp `.pbix` không quá ngưỡng SC-006 so với Desktop.
3. **Cho** bảng nhiều đoạn có quan hệ hoặc cột tính toán, **thì** quan hệ, cột tính toán và lọc chéo đúng trong BI Pro và Desktop.

---

### Câu chuyện 6 — Nguồn dữ liệu đầy đủ hơn: PostgreSQL, SQLite ODBC, Parquet lồng (Ưu tiên: P3)

Bạn nạp bảng PostgreSQL có cột timestamptz, time, interval, bytea, mảng; nạp SQLite với driver ODBC khác Devart; nạp Parquet có cột struct/list. BI Pro đọc được như Desktop và ghi M mà Desktop Refresh chạy được.

**Vì sao P3**: mở rộng nguồn P3 của Phase F; ít người dùng gặp.

**Kiểm độc lập**: bảng thử trên máy chủ `bipro-pg`, tệp SQLite mẫu, Parquet sinh bằng pyarrow có cột lồng; so bảng với Desktop nạp cùng nguồn.

**Kịch bản chấp nhận**:

1. **Cho** cột PostgreSQL kiểu timestamptz, time, interval, bytea, mảng, **khi** nạp, **thì** kiểu và giá trị khớp Desktop (kiểu Desktop bỏ thì BI Pro cũng bỏ hoặc báo như Desktop).
2. **Cho** nạp SQLite, **khi** chọn hoặc nhập tên driver ODBC, **thì** M ghi đúng driver đó (nhớ lựa chọn lần sau), Desktop có driver đó Refresh chạy được.
3. **Cho** Parquet có cột struct/list, **khi** nạp, **thì** cột hiện và mở rộng được như Desktop, M giống Desktop.

---

### Trường hợp biên

- Gộp ngầm trên cột có `SummarizeBy = None` ("Don't summarize"), cột khoá, cột tính toán, cột của bảng ngày cục bộ; cùng cột kéo hai lần với hai phép gộp khác nhau; đổi tên cột đang được gộp ngầm.
- Auto date/time khi cột ngày có ngày rất xa (năm 1900, 9999), toàn BLANK, hay cột ngày giờ; file mở từ Desktop đã bật Auto date/time (ví dụ `w8.3.pbix`) rồi nạp thêm bảng có cột ngày.
- Tự phát hiện quan hệ khi tên cột trùng nhưng kiểu khác, khi cả hai phía đều không duy nhất, khi tạo vòng hay đường thứ hai giữa hai bảng.
- Hàm văn bản trên chuỗi có ký tự tổ hợp (dấu tiếng Việt dạng NFD), emoji (cặp thay thế UTF-16), chuỗi dài.
- Sửa cột tính toán làm đầu "một" của quan hệ có giá trị trùng; xoá cột là cấp duy nhất của phân cấp.
- Bảng đúng 8 388 608 dòng, 8 388 609 dòng, đoạn cuối rất ngắn; bảng nhiều đoạn bị thay dữ liệu (Close & Apply) hay xoá.
- PostgreSQL mảng nhiều chiều, mảng có NULL, interval âm, timestamptz ở múi giờ khác múi giờ máy.
- Tên driver ODBC có ký tự đặc biệt; Parquet lồng sâu hơn 2 cấp, list of struct.

## Yêu cầu *(bắt buộc)*

### Yêu cầu chức năng

**Gộp ngầm (Câu chuyện 1)**

- **FR-001**: Với mô hình không đặt "discourage implicit measures", hệ thống PHẢI cho kéo cột vào ô giá trị và gán phép gộp mặc định theo quan sát Desktop (theo thuộc tính tổng hợp của cột).
- **FR-002**: Hệ thống PHẢI cho đổi phép gộp của trường trong ô qua menu với đúng danh sách phép gộp Desktop đưa ra cho kiểu cột đó.
- **FR-003**: Truy vấn visual có trường gộp ngầm PHẢI sinh văn bản DAX giống Performance Analyzer của Desktop và cho kết quả khớp Desktop.
- **FR-004**: Trường gộp ngầm PHẢI được lưu vào báo cáo theo định dạng Desktop dùng, và file Desktop lưu có trường gộp ngầm PHẢI được đọc và hiện đúng.
- **FR-005**: Với mô hình đặt "discourage implicit measures", hệ thống PHẢI giữ hành vi chặn như hiện nay.

**Tài liệu mới (Câu chuyện 2)**

- **FR-010**: Khung báo cáo của tài liệu chưa có bảng nào PHẢI hiện màn "Thêm dữ liệu vào báo cáo" với các lối vào theo quan sát Desktop, gồm: nạp từ Excel và lấy dữ liệu từ nguồn khác (nối Get Data sẵn có), dán dữ liệu vào bảng trống (FR-016); nạp từ SQL Server và dùng dữ liệu mẫu hiện xám kèm lý do.
- **FR-011**: Tài liệu mới PHẢI bật Auto date/time như mặc định của Desktop; mỗi cột ngày được nạp PHẢI có bảng ngày cục bộ, phân cấp ngày và quan hệ ẩn giống Desktop, và dùng được trong field list và visual.
- **FR-012**: Người dùng PHẢI bật/tắt được Auto date/time của file hiện tại; tắt thì bỏ, bật thì dựng lại bảng ngày cục bộ như Desktop; thao tác hoàn tác được.
- **FR-013**: Sau khi nạp bảng (Get Data, Close & Apply), hệ thống PHẢI tự tạo quan hệ theo đúng quy tắc phát hiện của Desktop đã quan sát, và cho tắt tuỳ chọn này; quan hệ tự tạo nằm trong cùng bước hoàn tác của lần nạp.
- **FR-014**: File lưu từ các thao tác trên PHẢI mở được trong Desktop không báo lỗi và có cấu trúc (bảng ngày cục bộ, phân cấp, quan hệ, chú thích) giống file Desktop tạo cùng bước.
- **FR-015**: File có sẵn đã bật Auto date/time (Desktop tạo) PHẢI giữ được bảng ngày cục bộ khi BI Pro nạp thêm, thay hay xoá bảng có cột ngày.
- **FR-016**: Hệ thống PHẢI cho tạo bảng bằng cách nhập hoặc dán dữ liệu vào bảng trống (Enter Data: đặt tên bảng, tên cột, sửa ô, dán từ bảng tính), lưu theo đúng dạng Desktop lưu bảng Enter Data, Desktop mở và Refresh được; sửa lại bảng đó qua Query Editor.

**Hàm văn bản DAX (Câu chuyện 3)**

- **FR-020**: Engine DAX PHẢI có các hàm `LEN`, `UPPER`, `LOWER`, `MID`, `RIGHT`, `TRIM`, `SUBSTITUTE`, `REPLACE`, `CONCATENATE`, `CONCATENATEX`, `SEARCH`, `FIND`, `REPT`, `VALUE`, `EXACT`, `UNICHAR`, `UNICODE`, `FIXED`, `COMBINEVALUES` với ngữ nghĩa khớp Desktop (kể cả BLANK, chuỗi rỗng, lỗi).
- **FR-021**: Hàm mới PHẢI dùng được trong measure, cột tính toán, bảng tính toán và DAX query view.

**Sửa/xoá cột tính toán còn được dùng (Câu chuyện 4)**

- **FR-030**: Hệ thống PHẢI cho sửa công thức cột tính toán là đầu quan hệ, cấp phân cấp hay cột sắp xếp, và dựng lại chỉ mục quan hệ, chỉ mục phân cấp, thứ tự sắp xếp như Desktop khi lưu.
- **FR-031**: Hệ thống PHẢI cho xoá cột tính toán còn được dùng theo đúng cách Desktop xử lý (hỏi, xoá kèm quan hệ/cấp phân cấp/tham chiếu sắp xếp), hoàn tác được.
- **FR-032**: Trường hợp Desktop từ chối (ví dụ đầu "một" không còn duy nhất, sắp xếp không một–một) PHẢI bị từ chối với lời báo tương ứng.

**Lưu dữ liệu lớn (Câu chuyện 5)**

- **FR-040**: Hệ thống PHẢI lưu được bảng nhiều hơn 8 388 608 dòng theo cách chia đoạn của Desktop, kể cả khi bảng có quan hệ và cột tính toán.
- **FR-041**: Bộ ghi PHẢI nén cột có giá trị lặp theo cách Desktop dùng (RLE kết hợp bit-packing) khi quan sát cho thấy Desktop làm vậy; thứ tự dòng đọc lại PHẢI giữ như Desktop.
- **FR-042**: Mọi giới hạn còn lại của bộ ghi PHẢI báo lỗi rõ bằng tiếng Việt trước khi ghi, không ghi nửa chừng.

**Nguồn (Câu chuyện 6)**

- **FR-050**: Nguồn PostgreSQL PHẢI đọc được timestamptz, time, interval, bytea và mảng với kiểu và giá trị như Desktop.
- **FR-051**: Get Data ▸ SQLite PHẢI cho chọn hoặc nhập tên driver ODBC ghi vào M, nhớ lựa chọn gần nhất; mặc định là driver đã dùng gần nhất, lần đầu là Devart.
- **FR-052**: Nguồn Parquet PHẢI đọc được cột struct và list (kể cả list of struct đến độ sâu quan sát được) và hiện, mở rộng như Desktop.

**Chung**

- **FR-060**: Mọi thao tác mới PHẢI hoàn tác được trong cùng ngăn hoàn tác của tài liệu.
- **FR-061**: Mỗi câu chuyện PHẢI có buổi quan sát Desktop ghi lại trước khi code và gate Desktop sau khi xong, kết quả ở thư mục bằng chứng của đợt.

### Thực thể chính

- **Trường gộp ngầm**: tham chiếu cột trong một ô của visual kèm phép gộp (Sum, Average, Min, Max, Count, Count (Distinct), StdDev, Var, Median…), có nhãn hiển thị.
- **Bảng ngày cục bộ**: bảng ẩn sinh cho mỗi cột ngày khi bật Auto date/time, gồm khoảng ngày theo dữ liệu, cột Năm/Quý/Tháng/Ngày, phân cấp và quan hệ ẩn tới cột ngày; dựa trên một bảng mẫu chung.
- **Quan hệ tự phát hiện**: quan hệ tạo sau khi nạp, theo quy tắc khớp tên và kiểu cột của Desktop.
- **Đoạn dữ liệu**: một phần dòng của bảng được lưu riêng (từ điển dùng chung, dữ liệu và thống kê riêng).
- **Bảng Enter Data**: bảng nhỏ do người dùng nhập/dán, dữ liệu nằm trong biểu thức M của bảng.
- **Lựa chọn driver ODBC**: tên driver ghi vào M nguồn SQLite, được nhớ giữa các lần.

## Tiêu chí thành công *(bắt buộc)*

### Kết quả đo được

- **SC-001**: Trên tài liệu mới, dựng card và biểu đồ cột từ cột số không cần tạo measure; với mọi phép gộp trong danh sách, 100% số khớp DAX Desktop; Desktop mở file lưu và hiện cùng số.
- **SC-002**: Luồng tài liệu mới → nạp hai bảng có khoá chung và cột ngày → biểu đồ theo Năm → lưu → Desktop mở không lỗi; số quan hệ, bảng ngày cục bộ và phân cấp trùng file Desktop tạo cùng bước; luồng hoàn thành dưới 3 phút thao tác.
- **SC-003**: 100% ô của bộ golden hàm văn bản DAX (ít nhất 10 ô mỗi hàm) khớp Desktop.
- **SC-004**: Sửa và xoá cột tính toán dính quan hệ, phân cấp, cột sắp xếp trên bản sao Nhom6 và tài liệu thử: Desktop mở file không lỗi, số liệu visual dùng các cột đó khớp Desktop sau khi Desktop tự làm cùng thao tác.
- **SC-005**: Bảng 10 triệu dòng, 10 cột lưu xong dưới 2 phút (bản release), dùng không quá 4 GB bộ nhớ; Desktop mở và đếm đúng.
- **SC-006**: Với cùng dữ liệu có cột lặp, cỡ tệp `.pbix` BI Pro lưu không lớn hơn 125% cỡ tệp Desktop lưu.
- **SC-007**: Bảng PostgreSQL đủ năm kiểu mới và Parquet lồng: 100% ô khớp bảng Desktop nạp. SQLite: M ghi đúng tên driver đã chọn (kể cả tên khác Devart) và 100% ô khớp với driver có trong VM. Desktop Refresh chạy được M của BI Pro với driver có trong VM.
- **SC-008**: Golden DAX Phase B (30), truy vấn visual (72) và toàn bộ test hiện có không đổi; thời gian lưu Nhom6 giữ ngưỡng Phase F (T2 dưới 4 giây).
- **SC-009**: Mỗi câu chuyện có gate Desktop ghi kết quả ĐẠT trong thư mục bằng chứng.

## Giả định

- Bảng Enter Data giới hạn cỡ theo quan sát Desktop (hộp Create Table); bảng lớn hơn đi qua Get Data.
- Thứ tự làm theo ưu tiên: Câu chuyện 1 và 2 (P1) trước; 3 và 4 (P2); 5 và 6 (P3). Mỗi câu chuyện tự quan sát, làm và gate.
- Nhãn trường gộp ngầm trong giao diện BI Pro là tiếng Việt (ví dụ "Tổng của Amount", "Trung bình của Amount"), theo ràng buộc "Giao diện tiếng Việt" của hiến pháp; cấu trúc và mọi chuỗi lưu trong file theo đúng Desktop.
- Auto date/time mặc định bật cho tài liệu mới vì Desktop bật mặc định; file mở từ đĩa giữ tuỳ chọn của file đó (Nhom6 tắt, không đổi).
- Không có tuỳ chọn toàn cục kiểu Options của Desktop; tuỳ chọn theo từng file đặt ở chỗ plan chốt.
- Máy chạy test có 16 GB RAM; ngưỡng 4 GB của SC-005 chừa chỗ cho app và hệ thống.
- Bảng 10 triệu dòng và tệp mẫu sinh bằng công cụ có sẵn trên máy (Python, pyarrow đã có), đặt ở `build/`; không tải mạng.
- Máy chủ PostgreSQL thử là container `bipro-pg` đã có; driver ODBC thứ hai trong VM chỉ dùng nếu bạn cài (BI Pro trên Mac đọc SQLite trực tiếp, tên driver chỉ ảnh hưởng M cho Desktop).
- Nhóm "Import data from SQL Server" và các nguồn chưa có (SQL Server, web, đám mây) ngoài phạm vi; nếu màn thêm dữ liệu có lối vào đó thì hiện xám kèm lý do.
- Không thêm thư viện ngoài (hiến pháp III); RLE, Parquet lồng, kiểu PostgreSQL tự viết.
