# Gate VM-F15 (T046): kết quả

Buổi 2026-11-19, Power BI Desktop 2.159 trên VM. Chạy không bấm chuột: mở tệp bằng `prlctl exec explorer.exe`, kiểm bằng DAX/TMSL qua ADOMD
(`build/vm-tools/daxq.ps1`, `tmsl.ps1`), vì máy Mac đang được dùng.

## Kết luận

**Đạt** phần PostgreSQL. `bipro-f15.pbix` (do `F2SourcesFlowTests` sinh: tài liệu mới + `f15.public.types_f15` + SQLite `Customers` với driver
"SQLite3 ODBC Driver") mở trong Desktop không lỗi.

- **So với bảng Desktop tự nạp** cùng nguồn (`INFO.VIEW.COLUMNS` và giá trị từng ô của 6 dòng, `FORMAT` tới mili giây, giá trị số gốc):
  - trùng hết kiểu, định dạng (`General Date`, `Long Time`, `0`), giá trị;
  - cột `bytea` không có ở cả hai;
  - chỉ khác chữ hoa tên cột `id`/`ID`: tệp nền Desktop có cột `ID` ở bảng khác, Desktop dùng lại cách viết đó (không phải lỗi BI Pro).
- Lần so đầu lệch hai điểm, đã sửa rồi so lại:
  1. định dạng `tz` (Desktop `General Date`);
  2. `12:34:56.789` (Desktop làm tròn 1/100 giây).
- **Refresh** bảng PostgreSQL (TMSL `refresh full`) chạy được M của BI Pro, dùng thông tin đăng nhập đã lưu trong Desktop.
- Bảng SQLite: M ghi `Driver={SQLite3 ODBC Driver}` đúng lựa chọn. Desktop làm mới thì hỏi/báo lỗi vì đường dẫn tệp là đường dẫn trên Mac và VM
  chưa cài driver đó: đúng như mong đợi, không kiểm thêm.
- Parquet lồng: theo quan sát ở `QUAN-SAT.md`, mô hình không nạp cột Record/List; BI Pro bỏ các cột đó khi nạp (`TableLoader.modelData`).

## Bổ sung 2026-11-20 (T072: Gate Refresh SQLite trong VM với driver Devart)
**Đạt.** Tệp `build/f2-out/f15/bipro-t072-sqlite.pbix` (do BI Pro sinh với hai bảng `Customers` và `Sales` từ `sales_2026.sqlite`, M ghi `Driver={Devart ODBC Driver for SQLite};Database=C:\Users\bacpew\f15\sales_2026.sqlite`) mở trong Desktop không lỗi:
- Bấm **Refresh** trên ribbon → hộp thoại `ODBC driver` hiện ra → chọn tab **Default or Custom** → gửi kết nối (**Enter** / **Connect**).
- `INFO.PARTITIONS()` xác nhận cả `Customers` và `Sales` chuyển `RefreshedTime` từ `17:28:38` (lúc BI Pro lưu) sang `17:47:00` (lúc Desktop Refresh), `State = 1`.
- Đối chiếu từng ô trước và sau Refresh:
  - `Customers` (50 dòng × 3 cột): **50/50 dòng khớp tuyệt đối (0 ô lệch)**.
  - `Sales` (1 000 dòng × 8 cột): **7 000/7 000 ô** ở 7 cột (`OrderID`, `OrderDate`, `Region`, `CustomerID`, `Qty`, `Price`, `Amount`) **khớp tuyệt đối (0 ô lệch)**. Ở cột `Product`, các chuỗi Latin-1 (`Áo thun`, `Giày`, `Túi xách`) khớp tuyệt đối; chỉ 3 chuỗi tiếng Việt ngoài bảng mã Latin-1 (`Mũ`, `Quần jean`, `Đồng hồ`) bị chính driver Devart ODBC bản thử chuyển theo Windows-1252 ANSI (`Mu`, `Qu?n jean`, `Ð?ng h?`), còn BI Pro đọc trực tiếp UTF-8 giữ đúng Unicode.
- Ảnh sau khi Refresh (đã cắt che thanh tài khoản): `p3-sqlite-refresh.png`. **SC-007 ĐẠT đầy đủ.**
