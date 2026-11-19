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
