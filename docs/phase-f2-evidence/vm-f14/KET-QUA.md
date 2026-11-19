# Gate VM-F14 (T059): kết quả

Buổi 2026-11-19, Desktop 2.159 trong VM, mở tệp bằng `prlctl exec`, kiểm bằng DAX qua ADOMD.

**Đạt, với bảng một đoạn.**

1. `bipro-f14-rle.pbix` (`repeat_1m`, một đoạn, có RLE): mở được. Số khớp bảng Desktop tự nạp cùng tệp:
   - `COUNTROWS` 1 000 000;
   - `DISTINCTCOUNT(Batch)` 100;
   - `SUM(Flag)` 20;
   - `SUM(Value)` 500 410 833 607 341.
2. `bipro-f14-big.pbix` (`big_10m` 10 triệu dòng, bảng `Khach`, quan hệ, cột tính toán `Thanh tien`):
   - **lần đầu ghi 10 đoạn: Desktop báo "Database consistency checks (DBCC) failed while checking the data segments"**;
   - khoanh vùng bằng `mid` 2,5 triệu dòng (không ngày, quan hệ hay cột tính toán): ba đoạn hỏng, một đoạn mở được, số đúng;
   - bộ ghi nay ghi bảng mới thành một đoạn. Tệp ghi lại mở được sau 118 s, số khớp bảng Desktop tự nạp:

     | Kiểm | Giá trị |
     |---|---|
     | dòng | 10 000 000 |
     | `SUM(Qty)` | 100 004 320 |
     | `DISTINCTCOUNT(Batch)` | 1 000 |
     | lọc qua quan hệ `Khach[Hang] = "VIP"` | 20 012 105 |
     | `SUM([Thanh tien])` | 3 609 321 116,52 |
     | vùng | 5 |

**Tồn đọng:**
- Bố cục byte nhiều đoạn: cần một tệp nhiều đoạn do Desktop lưu qua giao diện để so.
- Mã hoá VALUE (tệp `.hidx`) và sắp lại dòng.
- SC-006 (cỡ `repeat_1m` ≤ 125 % Desktop) **chưa đạt**: khoảng 27 MB so với ước lượng 7 MB.
