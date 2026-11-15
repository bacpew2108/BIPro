# Đặc tả tính năng: Phase E, mô hình hoá và lưu tầng T2

**Nhánh**: `main` (không tạo nhánh riêng)

**Ngày tạo**: 2026-11-14

**Trạng thái**: Nháp, chờ bạn duyệt (đã chốt 2 điểm làm rõ, 2026-11-14)

**Đầu vào**: "Triển khai phase E" = mục Phase E của `docs/BIPRO_BUILD_PLAN.md`: Table View đầy đủ (Column tools, formula bar, sắp xếp/lọc, Column metadata); Model View sửa được (kéo thẻ bảng, tạo quan hệ bằng cách kéo cột, Relationship properties); Measure (tạo, sửa, xoá, định dạng, thư mục hiển thị) và TMDL View sửa được; lưu tầng T2. **Xong khi:** thêm measure và quan hệ trong BI Pro, lưu, rồi Power BI Desktop đọc đúng.

Cấp trên: `docs/BIPRO_BUILD_PLAN.md` (Phase E, §2 tầng lưu, §6 kiểm thử), `docs/PHASE_W_PLAN.md` (WP4 `MetadataWriter`, gate W3), `specs/002-d1-canvas-luu-t1/` (cách lưu, hoàn tác theo ảnh chụp, R13 bỏ `SecurityBindings`). Mâu thuẫn thì sửa `docs/` trước.

## Quan sát Power BI

Mục [SUY ĐOÁN] phải được kiểm ở buổi VM-E trước khi code phần đó. Claude chỉ điều khiển VM khi bạn cho phép lần đó (quy tắc "agent không điều khiển VM" của hiến pháp vẫn giữ); nếu không thì bạn làm tay theo checklist Claude chuẩn bị. Không dịch ngược; chỉ đọc file Desktop ghi và nhìn giao diện.

**Hiện trạng trong BI Pro** (đọc từ mã):

- Table View (`Table/TableWorkspace.swift`): lưới dữ liệu và thanh công thức chỉ đọc, bảng "Column metadata" chỉ đọc. Model View (`Model/ModelWorkspace.swift`): thẻ bảng, đường quan hệ có ký hiệu 1/\*, bảng thuộc tính quan hệ chỉ đọc, cây Semantic Model chỉ đọc; vị trí thẻ đọc từ phần `DiagramLayout` (nhiều tab bố cục, thu phóng). TMDL View (`Query/QueryWorkspaces.swift`, `PBIXKit/TMDLWriter.swift`): sinh TMDL từ metadata, huy hiệu "Chỉ đọc", chân trang ghi "Sửa và áp dụng TMDL: Phase E".
- `ModelMetadata` đọc đủ bảng, cột (kiểu, định dạng, `sortByColumn`, `summarizeBy`, `dataCategory`, `displayFolder`, mô tả, ẩn), measure, quan hệ (tên, hai đầu, `isActive`, cardinality, `crossFilteringBehavior`).
- Đường ghi (Phase W, gate W3 đã được bạn xác nhận): `PBIXChanges.measures` (T2) thêm measure qua `MetadataWriter.addMeasure` (đặt ID, `LineageTag`, mốc thời gian, `MAXID`), dựng lại ABF và nén lại, dữ liệu VertiPaq giữ nguyên. **Chưa có** sửa/xoá measure, sửa thuộc tính cột/bảng, thêm/sửa/xoá quan hệ, ghi `DiagramLayout`.
- Engine DAX (`DAXEngine`) đã đọc quan hệ và measure; mô hình đổi thì `MeasureCache` phải bị xoá (`architecture.md`), chưa có đường nạp lại model trong phiên.
- `docs/measures.nhom6.dax`: 917 dòng, các measure của Nhom6 (nguồn thử cho cú pháp và hàm).

**[SUY ĐOÁN], phải quan sát ở VM-E** (mỗi mục ghi kết quả vào `docs/phase-e-evidence/` trước khi code phần liên quan):

- **Measure**: dòng nào của `Measure` mà Desktop ghi khi tạo measure ở Table View so với khi tạo ở Report View; `DataType` tự suy từ biểu thức; khi Desktop tự đặt `FormatString` hoặc để trống; `DisplayFolder` lồng nhau dấu `\`; `IsHidden`; `State` và `ErrorMessage` khi biểu thức lỗi; Desktop có chặn lưu measure lỗi cú pháp không; đổi tên measure có sửa biểu thức của measure khác và visual trong báo cáo không.
- **Quan hệ**: dòng `Relationship` Desktop ghi khi kéo cột (tên GUID, `FromCardinality`/`ToCardinality`, `CrossFilteringBehavior` mặc định, `IsActive`, `RelyOnReferentialIntegrity`, `SecurityFilteringBehavior`, `JoinOnDateBehavior`); kéo từ cột khoá bên "nhiều" hay bên "một" đều được; cách Desktop tự dò cardinality và hướng lọc; quan hệ thứ hai giữa hai bảng tự thành không hoạt động; từ chối khi kiểu cột khác nhau, khi vòng lặp (ambiguity), khi cột bên "một" có giá trị trùng; hộp thoại "Create relationship" ngoài việc kéo.
- **Cột**: các thuộc tính sửa được mà không đụng dữ liệu (tên, ẩn, định dạng, tổng hợp mặc định, loại dữ liệu hiển thị tức `DataCategory`, sắp xếp theo cột, thư mục, mô tả) và cách ghi từng thuộc tính vào `Column`; đổi kiểu dữ liệu ở Desktop có ghi lại dữ liệu VertiPaq không (nếu có thì thuộc T3, ngoài phạm vi).
- **Model View**: cách Desktop ghi `DiagramLayout` khi kéo thẻ, thêm tab bố cục, thu phóng; có dùng tab "All tables" mặc định không; ghi trong cùng lần lưu T2 hay thành phần riêng.
- **TMDL View**: phần nào của TMDL Desktop cho áp dụng ("Apply"), thông báo lỗi, kết quả khi áp dụng làm đổi ID, thứ tự cột.
- **Sửa tay lúc Desktop đang mở file** (xung đột) không thuộc phạm vi.

**Đã có từ trước, dùng làm chuẩn so**: 30 golden DAX trên Nhom6 (Phase B) và 72 truy vấn visual; file `Nhom6_work.pbix` làm bản gốc, mọi thử nghiệm làm trên bản sao.

## Kịch bản người dùng và kiểm thử *(bắt buộc)*

### Câu chuyện 1 — Tạo, sửa, xoá measure (Ưu tiên: P1)

Ở Table View (và ngăn Dữ liệu của chế độ Sửa) người dùng chọn một bảng, bấm "Measure mới", gõ `Tên = biểu thức DAX` vào thanh công thức, đặt định dạng, thư mục hiển thị, mô tả, ẩn; kiểm tra lỗi ngay; áp dụng thì measure xuất hiện trong ngăn Dữ liệu, dùng được trong visual và cho ra số đúng. Sửa biểu thức hoặc xoá được measure đã có. ⌘S lưu T2; Power BI Desktop mở file thấy đúng measure và số.

**Vì sao P1**: là điều kiện "xong khi" của Phase E, và đường ghi `addMeasure` đã có từ Phase W.

**Kiểm thử độc lập**: trên bản sao Nhom6, thêm measure `= SUM(Fact_Loan[loan_amount])` (hoặc measure trong `measures.nhom6.dax`), lưu, mở lại trong BI Pro và trong Desktop: cùng tên, biểu thức, định dạng, thư mục; card dùng measure ra cùng số trên cả hai; golden Phase B không đổi.

**Kịch bản chấp nhận**:

1. **Cho** Table View của một bảng, **khi** người dùng nhập tên và biểu thức hợp lệ rồi áp dụng, **thì** measure có mặt trong cây Dữ liệu, thanh công thức hiện lại đúng biểu thức, giá trị xem thử (card hoặc kết quả ngay dưới thanh công thức) khớp truy vấn DAX viết tay.
2. **Cho** biểu thức sai cú pháp, hàm không có, hoặc cột không tồn tại, **khi** áp dụng, **thì** báo lỗi kèm vị trí và không thay đổi mô hình; ⌘S không có gì để lưu.
3. **Cho** tên trùng measure hoặc cột cùng bảng, **thì** từ chối kèm lý do.
4. **Cho** measure đang được visual hoặc measure khác dùng, **khi** xoá, **thì** báo danh sách nơi dùng và chặn (hoặc theo quy tắc quan sát được ở VM-E).
5. **Cho** measure đã sửa biểu thức, **thì** mọi visual dùng nó vẽ lại ngay với số mới và `MeasureCache` không giữ số cũ.
6. **Cho** thay đổi chưa lưu, **khi** ⌘Z, **thì** hoàn tác một bước, chung ngăn xếp với D1 đến D7.
7. **Cho** file đã lưu, **khi** mở lại trong BI Pro và Desktop, **thì** measure còn nguyên (kể cả `FormatString`, `DisplayFolder`, mô tả, ẩn) và Desktop không báo file hỏng.

---

### Câu chuyện 2 — Tạo và sửa quan hệ ở Model View (Ưu tiên: P1)

Ở Model View người dùng kéo một cột của bảng này thả lên cột của bảng kia để tạo quan hệ; BI Pro dò cardinality và hướng lọc như Desktop, hiện hộp thoại xác nhận; chọn đường quan hệ thì sửa được thuộc tính (cardinality, hướng lọc chéo, hoạt động hay không) và xoá được. Engine và các visual dùng quan hệ mới ngay. ⌘S lưu T2.

**Vì sao P1**: nửa còn lại của điều kiện "xong khi"; quan hệ quyết định kết quả mọi truy vấn nên cần đúng và an toàn.

**Kiểm thử độc lập**: trên bản sao Nhom6, xoá một quan hệ rồi tạo lại bằng cách kéo cột; số liệu của các visual dùng nó quay về đúng như trước (khớp golden); lưu, Desktop mở thấy đúng quan hệ và cùng số.

**Kịch bản chấp nhận**:

1. **Cho** hai cột cùng kiểu, bên "một" có giá trị duy nhất, **khi** kéo cột này sang cột kia, **thì** hiện hộp thoại với cardinality và hướng lọc đã dò, xác nhận thì quan hệ mới có đường nối và ký hiệu đúng.
2. **Cho** hai cột khác kiểu, hoặc cả hai bên đều có giá trị trùng mà người dùng chọn 1:\*, hoặc tạo vòng ambiguity, **thì** từ chối hoặc đặt không hoạt động theo quy tắc Desktop, kèm lý do.
3. **Cho** đã có quan hệ hoạt động giữa hai bảng, **khi** tạo quan hệ thứ hai, **thì** quan hệ mới không hoạt động (theo quan sát).
4. **Cho** quan hệ được chọn, **khi** đổi hướng lọc chéo, cardinality hay bật/tắt hoạt động trong bảng Relationship properties, **thì** đường nối đổi theo, engine dùng thuộc tính mới, các visual vẽ lại với số khớp Desktop.
5. **Cho** xoá quan hệ, **thì** visual dùng nó đổi kết quả (như Desktop), có xác nhận và ⌘Z đưa lại.
6. **Cho** lưu rồi mở trong Desktop, **thì** quan hệ có đúng hai đầu, cardinality, hướng lọc, trạng thái hoạt động.

---

### Câu chuyện 3 — Table View đầy đủ: Column tools và Column metadata (Ưu tiên: P2)

Ở Table View chọn cột thì sửa được các thuộc tính không đụng dữ liệu: tên, ẩn/hiện, định dạng số, tổng hợp mặc định, loại dữ liệu hiển thị (data category), sắp xếp theo cột khác, thư mục hiển thị, mô tả. Lưới cho sắp xếp và lọc để xem (chỉ trong phiên, không ghi vào file). Cột tính toán và bảng tính toán chỉ xem; xem Ngoài phạm vi.

**Vì sao P2**: cùng đường ghi T2 với P1 nhưng không chặn điều kiện "xong khi".

**Kiểm thử độc lập**: đổi định dạng của một cột số, ẩn một cột, đặt sắp xếp theo cột; lưu; Desktop mở thấy cùng thuộc tính và thứ tự trục đổi theo; mở lại trong BI Pro giữ nguyên.

**Kịch bản chấp nhận**:

1. **Cho** cột được chọn, **khi** sửa một thuộc tính trong bảng Column metadata, **thì** thay đổi áp ngay (lưới, ngăn Dữ liệu, các visual dùng cột) và vào ngăn xếp hoàn tác.
2. **Cho** đổi tên cột đang dùng trong visual, measure khác, quan hệ, bộ lọc, hoặc cột sắp xếp theo nó, **thì** bị chặn kèm danh sách nơi dùng (FR-020).
3. **Cho** sắp xếp theo cột khác, **thì** chỉ cho chọn cột của cùng bảng có quan hệ một-một với giá trị cột (theo quy tắc Desktop) và trục chữ trong visual đổi thứ tự.
4. **Cho** sắp xếp hoặc lọc lưới, **thì** không đổi mô hình và không tạo thay đổi chưa lưu.

---

### Câu chuyện 4 — Model View: kéo thẻ bảng, ẩn, thư mục, bố cục (Ưu tiên: P2)

Kéo thẻ bảng đổi vị trí, đổi cỡ, thu phóng, thêm/xoá/đổi tên tab bố cục; ẩn bảng hoặc cột khỏi Report View; vị trí lưu vào `DiagramLayout` và nhớ khi mở lại ở cả BI Pro và Desktop.

**Vì sao P2**: tiện dụng và nhỏ, không đổi kết quả truy vấn.

**Kiểm thử độc lập**: kéo hai thẻ, lưu, mở trong Desktop: thẻ ở đúng chỗ; mở lại BI Pro: giữ nguyên.

**Kịch bản chấp nhận**:

1. **Cho** kéo thẻ bảng, **khi** thả, **thì** thẻ và các đường quan hệ đi theo, một bước hoàn tác, ⌘S ghi vị trí.
2. **Cho** thêm tab bố cục chứa tập bảng con, **thì** tab hiện đúng tập thẻ đó và lưu lại.
3. **Cho** ẩn một cột hoặc bảng, **thì** ngăn Dữ liệu ở Report View không còn nó, thẻ ở Model View vẫn thấy ở dạng mờ.
4. **Cho** chỉ đổi bố cục, **thì** lưu chỉ ghi `DiagramLayout` và không dựng lại ABF (nếu quan sát cho phép).

---

### Câu chuyện 5 — TMDL View sửa được (Ưu tiên: P3)

Người dùng sửa văn bản TMDL của mô hình ngay trong TMDL View, bấm "Áp dụng": BI Pro phân tích, báo lỗi theo dòng, rồi áp các thay đổi vào mô hình (measure, thuộc tính cột và bảng, quan hệ) như khi sửa bằng giao diện; lưu T2.

**Vì sao P3**: dùng lại logic của P1 và P2, nhưng cần bộ phân tích TMDL.

**Kiểm thử độc lập**: sửa biểu thức một measure trong TMDL, áp dụng: card đổi số; sinh lại TMDL từ mô hình đã sửa rồi so thì khớp văn bản vừa nhập (sau chuẩn hoá); lưu, Desktop đọc đúng.

**Kịch bản chấp nhận**:

1. **Cho** văn bản TMDL hợp lệ chỉ đổi các đối tượng nằm trong phạm vi, **khi** áp dụng, **thì** mô hình đổi đúng những chỗ đó và TMDL sinh lại khớp văn bản.
2. **Cho** TMDL sai cú pháp hoặc nhắc tới đối tượng không tồn tại, **thì** báo lỗi theo dòng và không áp gì (áp dụng nguyên khối).
3. **Cho** TMDL đổi thứ gì ngoài phạm vi (bảng mới có dữ liệu, cột tính toán, phân vùng, nguồn dữ liệu), **thì** từ chối từng phần kèm lý do, không áp một nửa.
4. **Cho** áp dụng thành công, **thì** một bước hoàn tác chung.

---

### Trường hợp biên

- Mô hình có thay đổi T2 chưa lưu mà đồng thời có thay đổi T1: một lần lưu ghi cả hai, tầng lưu là T2 (`PBIXChanges.tier`).
- File chưa bật ghi ABF được (không có `DataModel`, hoặc mô hình nhỏ dạng cũ `Report/Layout`): các lệnh sửa mô hình tắt kèm lý do.
- Tên measure có ký tự đặc biệt, dài, trùng khác hoa thường, trùng tên bảng.
- Tạo measure ở bảng ẩn hoặc bảng tính toán tự động ngày (`LocalDateTable_*`).
- Xoá bảng, cột, hay measure mà mô hình có dùng ở nơi khác (RLS, `SecurityBindings`, bookmark, drillthrough): chặn hoặc báo theo quan sát.
- Mô hình có RLS vai trò: sửa mô hình giữ nguyên vai trò, không làm hỏng `SecurityBindings` (đã bỏ khi sửa T1; kiểm lại cho T2).
- Mở trong Desktop một file BI Pro vừa lưu T2 khi Desktop báo "file corrupted": giữ bản sao lưu, lỗi ghi rõ nguyên nhân (như D1, R13).
- Lưu liên tiếp hai lần trong một phiên (ID, `MAXID`, mốc thời gian phải đúng ở lần hai).
- Hai measure phụ thuộc nhau, xoá hoặc đổi tên một cái.
- Quan hệ giữa cột kiểu ngày với bảng ngày tự động của Desktop.

## Yêu cầu *(bắt buộc)*

### Yêu cầu chức năng

**Measure**

- **FR-001**: Hệ thống PHẢI cho tạo measure trong một bảng đã có (tên, biểu thức DAX, định dạng, thư mục hiển thị, mô tả, ẩn) và lưu T2 bằng `MetadataWriter`.
- **FR-002**: Hệ thống PHẢI kiểm biểu thức bằng engine DAX trước khi áp dụng (phân tích cú pháp và chạy thử), báo lỗi kèm vị trí, và không đổi mô hình khi lỗi.
- **FR-003**: Hệ thống PHẢI cho sửa biểu thức, tên, định dạng, thư mục, mô tả, ẩn, và xoá measure đã có, bằng thao tác UPDATE/DELETE trên `Measure` kèm cập nhật mốc thời gian như Desktop.
- **FR-004**: Hệ thống PHẢI từ chối tên trùng measure hoặc cột cùng bảng, và chặn xoá khi measure còn được visual hoặc measure khác dùng (liệt kê nơi dùng).
- **FR-005**: Sau mỗi thay đổi mô hình, engine PHẢI nạp lại phần đổi, xoá `MeasureCache`, và các visual dùng nó PHẢI vẽ lại với số mới.

**Quan hệ**

- **FR-006**: Hệ thống PHẢI cho tạo quan hệ bằng kéo cột sang cột ở Model View (và qua hộp thoại), dò cardinality và hướng lọc theo quan sát Desktop, hiện hộp thoại xác nhận.
- **FR-007**: Hệ thống PHẢI kiểm kiểu cột, tính duy nhất bên "một", vòng ambiguity và trạng thái hoạt động trước khi tạo, theo quy tắc quan sát được.
- **FR-008**: Hệ thống PHẢI cho sửa cardinality, hướng lọc chéo, hoạt động hay không, và xoá quan hệ, ghi vào `Relationship` đúng như Desktop.
- **FR-009**: Engine PHẢI dùng quan hệ mới và đã sửa cho mọi truy vấn sau thay đổi (tương đương Desktop).

**Table View và Model View**

- **FR-010**: Table View PHẢI sửa được các thuộc tính cột không đụng dữ liệu nêu ở Câu chuyện 3 và ghi vào `Column`; lưới có sắp xếp và lọc chỉ để xem.
- **FR-011**: Model View PHẢI kéo được thẻ bảng, đổi cỡ, thu phóng, quản lý tab bố cục, ẩn bảng/cột, và ghi `DiagramLayout`.
- **FR-012**: Cột tính toán và bảng tính toán PHẢI hiện chỉ đọc (giá trị đã lưu sẵn trong VertiPaq) và lệnh tạo chúng tắt kèm lý do.

**TMDL View**

- **FR-013**: TMDL View PHẢI cho sửa văn bản, phân tích, báo lỗi theo dòng, và áp dụng nguyên khối các thay đổi nằm trong phạm vi (measure, thuộc tính cột và bảng, quan hệ); phần ngoài phạm vi bị từ chối từng mục kèm lý do.
- **FR-014**: TMDL sinh ra từ mô hình đã sửa PHẢI khớp văn bản đã áp dụng sau chuẩn hoá khoảng trắng.

**Lưu, hoàn tác, an toàn**

- **FR-015**: Lưu PHẢI chọn tầng thấp nhất đủ dùng (T1 chỉ khi mô hình không đổi, T2 khi metadata đổi), ghi file tạm, đọc lại và kiểm trong bộ nhớ rồi mới thay file, giữ bản sao lưu, như D1.
- **FR-016**: Mọi thay đổi mô hình PHẢI vào ngăn xếp hoàn tác chung với D1 đến D7 (ảnh chụp mô hình cùng ảnh chụp báo cáo), và ⌘Z PHẢI đưa mô hình lẫn engine về trạng thái trước.
- **FR-017**: Sau khi sửa mô hình, `verify` trong bộ nhớ PHẢI so đủ: số bảng, cột, measure, quan hệ, dữ liệu VertiPaq nguyên vẹn (distinct count khớp), `PRAGMA integrity_check` ok, `MAXID` khớp ID lớn nhất.
- **FR-018**: Chế độ Xem PHẢI không cho sửa mô hình; sửa mô hình chỉ ở Sửa (⌘E) hoặc ở Table/Model/TMDL View khi mở tài liệu `.pbix` có `DataModel`.
- **FR-019**: Phần chưa quan sát từ Desktop PHẢI hiện "(chưa kiểm)" chỉ đọc, như D2 và D4, cho tới khi VM-E ghi nhận.

- **FR-020**: Khi đổi tên bảng, cột hoặc measure đang được nơi khác nhắc tới (visual, bộ lọc, biểu thức DAX của measure khác, quan hệ, cột sắp xếp, bookmark), hệ thống PHẢI chặn việc đổi tên và liệt kê các nơi đang dùng; không tự viết lại tham chiếu. (Khác Desktop, vốn tự viết lại; ghi vào "Khác Desktop có chủ ý", có thể làm ở lát sau.)
- **FR-021**: Cột tính toán và bảng tính toán chỉ xem (FR-012); tạo mới nằm ngoài Phase E.

### Thực thể chính

- **Measure**: tên, bảng chứa, biểu thức DAX, kiểu dữ liệu suy ra, định dạng, thư mục hiển thị, mô tả, ẩn, trạng thái và thông báo lỗi.
- **Quan hệ**: hai đầu (bảng, cột), cardinality, hướng lọc chéo, hoạt động hay không, tên.
- **Cột** (thuộc tính chỉ metadata): tên, ẩn, định dạng, tổng hợp mặc định, loại dữ liệu hiển thị, sắp xếp theo cột, thư mục, mô tả.
- **Bố cục mô hình**: tab, thu phóng, vị trí và cỡ thẻ bảng.
- **Thay đổi mô hình**: danh sách thao tác (thêm, sửa, xoá) trên các thực thể trên, gom cho một lần lưu.
- **Tài liệu TMDL**: mô hình, quan hệ, từng bảng (đã có `TMDLWriter.Document`).

## Tiêu chí thành công *(bắt buộc)*

### Kết quả đo được

- **SC-001**: Trên bản sao Nhom6, người dùng thêm một measure và một quan hệ (hoặc, nếu spike S1 ở `research.md` R7 cho thấy không tạo được quan hệ mới, đổi một thuộc tính của quan hệ đã có; bạn đã duyệt phương án này ngày 2026-11-14 và sẽ được báo trước khi áp dụng), lưu, rồi Power BI Desktop mở được và hiện đúng cả hai (tên, biểu thức, định dạng, hai đầu quan hệ, hướng lọc); card dùng measure ra cùng số trên BI Pro và Desktop.
- **SC-002**: 30 golden DAX Phase B và 72 truy vấn visual Phase C giữ nguyên khớp sau mọi thay đổi (chạy golden nặng); sau khi tạo lại một quan hệ đã xoá, số liệu các visual trở về đúng như trước.
- **SC-003**: Mọi file BI Pro lưu ở T2 mở được trong Power BI Desktop không báo "file is corrupted", dữ liệu bảng và distinct count giữ nguyên (kiểm bằng `pbix-dump verify`: 110 cột, 0 lệch trên Nhom6).
- **SC-004**: Lưu T2 trên Nhom6 dưới 3 giây (dựng lại ABF và nén; số đo hiện tại sẽ ghi ở `measurements.md`); áp dụng một measure hoặc quan hệ mới thấy visual vẽ lại trong 1 giây.
- **SC-005**: Mọi thao tác sửa mô hình hoàn tác được một bước và sau hoàn tác, lưu ra file giống byte với file trước khi sửa (trừ mốc thời gian).
- **SC-006**: Mọi quy tắc suy đoán (mục Quan sát) có bằng chứng ở `docs/phase-e-evidence/` trước khi được coi là chốt; ô chưa quan sát hiện "(chưa kiểm)".
- **SC-007**: Không thư viện ngoài nào được thêm (SQLite dùng bản của hệ điều hành như Phase W).

## Ngoài phạm vi

- Tạo cột tính toán, bảng tính toán, bảng mới có dữ liệu, đổi kiểu dữ liệu, đổi nguồn dữ liệu (tầng T3, Phase F).
- Sửa Power Query, M, phân vùng, RLS (tạo/sửa vai trò), perspective, ngôn ngữ dịch, hierarchy mới (quan sát sau nếu cần).
- Ghi lại sắp xếp/lọc của lưới Table View vào file.
- Mở file đang được Desktop giữ khoá ghi, hay đồng bộ hai chiều.

## Giả định

- Tạo và xoá quan hệ mới cần chỉ mục dữ liệu VertiPaq riêng cho từng quan hệ (QUAN-SAT mục 4), nên làm sau việc sửa thuộc tính quan hệ và tuỳ vào kết quả spike S1; Câu chuyện 2 kịch bản 1 đến 3 và 5 áp dụng khi spike thành công. Nếu không, các kịch bản đó hiện "(chưa hỗ trợ)" kèm lý do và Phase E vẫn xong theo SC-001 (phương án thay thế), sau khi báo bạn.
- Một lát Spec Kit duy nhất `009-e-mo-hinh-hoa-luu-t2` nhưng `tasks.md` chia theo Câu chuyện để mỗi câu chuyện là một bản dùng được (P1 trước).
- Thứ tự quan sát và làm: Câu chuyện 1 (measure sửa/xoá, vì thêm đã xong ở W3), rồi 2 (quan hệ), rồi 3, 4, 5; mỗi cái cần một buổi VM-E ngắn.
- Dùng bản sao Nhom6 (`~/Downloads/bipro-golden/Nhom6_work.pbix`) và `Nhom2 - Financial Service` (Nhom6 bật `DiscourageImplicitMeasures`, Nhom2 chưa) cho test và quan sát; không đụng file gốc.
- Dùng được lại: `MetadataWriter` (mở rộng sang UPDATE/DELETE, thêm `Relationship`), `PBIXWriter` tầng T2, `ABFWriter`, `DiagramLayout`, `TMDLWriter` (sinh), engine DAX; engine cần thêm đường nạp lại model trong phiên (chưa có).
- Hiệu năng và độ đúng của engine không đổi; phép tính của measure mới đi qua engine hiện có.
- Cú pháp TMDL của Desktop có thể rộng hơn phần BI Pro sinh; phạm vi áp dụng ở Câu chuyện 5 chỉ gồm phần quan sát và sinh được.
