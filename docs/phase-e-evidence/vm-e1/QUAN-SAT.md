# VM-E1: quan sát Power BI Desktop cho Phase E (2026-11-14)

Bạn cho phép dùng VM ("Ok, có thể dùng VM") sau khi duyệt `specs/009-e-mo-hinh-hoa-luu-t2/spec.md`. Claude điều khiển Desktop trong VM "Windows 11" trên một **bản sao** `Nhom6_work.pbix` (thư mục VM `vme1`, đã xoá; bản sao Mac `~/Desktop/vme1` đã xoá; không import dữ liệu, không đụng file khác). Sau mỗi thao tác bấm biểu tượng Lưu, chép file ra Mac, `pbix-dump extract metadata.sqlitedb`, `sqlite3 .dump`, `diff`. Dòng liên quan ở `rows.txt` cùng thư mục. Ảnh chụp toàn cửa sổ có địa chỉ tài khoản nên không đưa vào git.

## Đã quan sát

**1. Tạo measure (Table view → New measure).** Desktop tạo measure `Measure` có lỗi ngay khi bấm nút (chưa có biểu thức), nhập biểu thức vào thanh công thức rồi Enter. Đổi tên bằng F2 trong ngăn Data. Dòng `Measure` Desktop ghi (so với `MetadataWriter.addMeasure` của BI Pro, đã được Desktop mở được ở W3):

`11892|25|E_Test|NULL|6|COUNTROWS(Dim_Account)+1|'0'|0|1|ts|ts|0|0|NULL|NULL|0|NULL|0|<guid>|NULL`

- Khác BI Pro chỉ ở `FormatString`: Desktop tự đặt `'0'` ("Whole number") từ kiểu của biểu thức; BI Pro mặc định `NULL`.
- `DataType` = 6 (Int64) do Desktop suy từ biểu thức (BI Pro đặt kiểu cố định `measureDataType`; cần suy kiểu theo biểu thức hoặc chấp nhận).
- `State` = 1, `IsHidden` 0, `ErrorMessage` NULL, `DetailRowsDefinitionID` 0, `FormatStringDefinitionID` 0, `SourceLineageTag` NULL. `ID` = `MAXID`+1 (11892 khi `MAXID` là 11890 và 11891 dành cho `LinguisticMetadata`); sau lưu `MAXID` = 11895 (Desktop dùng thêm ID cho Culture/Linguistic).
- `Table` chứa nó: `ModifiedTime` cập nhật, `StructureModifiedTime` không đổi ở dòng `Table`. `DBPROPERTIES` `LASTCUBEDATACHANGE`, `LASTCUBESCHEMACHANGE`, `LASTCOMMITTED`, `LASTMETADATACHANGEFORSYNCCOMMITTED` cập nhật.
- `Culture` và `LinguisticMetadata` (ID, mốc thời gian, JSON gợi ý từ đồng nghĩa) được Desktop sinh lại; không bắt buộc cho BI Pro (W3 đã mở được không có).

**2. Sửa measure** (biểu thức, mô tả, thư mục hiển thị ở ngăn Properties của Model view): chỉ `UPDATE` dòng cũ tại chỗ (cùng `ID`, `LineageTag`, `StructureModifiedTime`); đổi `Expression`, `Description` (`'mo ta E'`), `DisplayFolder` (`'Thu muc E'`), `ModifiedTime`; `DataType` và `FormatString` giữ. Ngăn Properties của Model view có Name, Home table, Description, Synonyms, Display folder, Is hidden, Format; thanh công thức cũng sửa được measure ở Model view. Ngăn Data nhóm measure theo `DisplayFolder`.

**3. Quan hệ (hộp thoại Manage relationships → Edit).** Có: From/To table (kèm bản xem trước dữ liệu để chọn cột), Cardinality (Many to one (\*:1) …), Cross-filter direction (Single, Both), Make this relationship active, Apply security filter in both directions (mờ khi Single), Assume referential integrity. Đổi Cross-filter sang Both cho `Fact_Loan[client_key] → Dim_Client[client_key]` (ID 42) ghi:

- `Relationship`: `CrossFilteringBehavior` 1 → 2, `ModifiedTime` mới; mọi cột khác giữ.
- Tác dụng phụ của Desktop: 7 cột (`Fact_Loan` và `Dim_Client`) `SummarizeBy` 2 → 3 kèm `Annotation 'SummarizationSetBy'='Automatic'`, `ModifiedTime` mới. BI Pro không cần bắt chước.
- Không đổi `RelationshipStorage`, `RelationshipIndexStorage`, ABF.

**4. Cấu trúc lưu trữ của quan hệ (từ file gốc, không cần thao tác).** Mỗi quan hệ trong `Relationship` có `RelationshipStorageID` → `RelationshipStorage` → `RelationshipIndexStorage` (`RecordCount`, `SystemTableID`), và mỗi quan hệ có một bảng hệ thống ẩn `R$<bảng nguồn>$<guid>` (28 tệp `R$…INDEX.0.idf`/`.idfmeta` trong ABF; 14 quan hệ). **Tạo quan hệ mới nghĩa là tạo thêm chỉ mục dữ liệu VertiPaq**, không phải chỉ thêm dòng metadata. Đổi thuộc tính (hướng lọc, hoạt động) không đụng phần này. Hệ quả cho plan: tạo quan hệ cần một spike riêng (xem `plan.md`); sửa thuộc tính quan hệ thì là T2 thuần.

**5. DiagramLayout.** Định dạng trùng `DiagramLayout.swift` hiện có (UTF-16LE, `diagrams[].nodes[].location/size`, `scrollPosition`, `zoomValue`). Không quan sát được cách Desktop ghi khi kéo thẻ (cú kéo bằng `cliclick` không tới Desktop; file không đổi).

## Chưa quan sát (còn [SUY ĐOÁN] trong spec)

- Tạo quan hệ mới (hộp thoại New, dò cardinality/hướng lọc, kéo cột), xoá quan hệ (dọn `R$` thế nào), quan hệ thứ hai tự không hoạt động, các thông báo lỗi.
- Xoá measure, measure lỗi cú pháp (Desktop có cho lưu), đổi tên có lan truyền tham chiếu.
- Thuộc tính cột (định dạng, ẩn, tổng hợp mặc định, loại dữ liệu, sắp xếp theo cột, thư mục) và cách ghi.
- Ghi `DiagramLayout` khi kéo thẻ; TMDL View và nút Apply.

Kiểm soát an toàn: các thao tác chỉ trên bản sao đã xoá; Desktop đã thoát bằng `taskkill`. Lần đầu bấm vào cửa sổ VM chỉ lấy tiêu điểm; cú kéo không tới Desktop.
