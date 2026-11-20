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

**Tồn đọng (2026-11-19) — ĐÃ GIẢI QUYẾT NGÀY 2026-11-20 (Phase 9: T067, T068, T069):**
- **T067 (nhiều đoạn) ĐẠT:** sau khi sửa `SegmentMapStorage.Type = 1` cho bảng nhiều đoạn (`TableMetadataWriter.swift`), nén `RowNumber` theo `C123` (`sub = 703067`, 144 B/đoạn) và bật lại `segmentSizeForNewTables = recordsPerSegment` (2^20):
  - `bipro-f14-mid-nhieu.pbix` (2,5 triệu dòng, 3 đoạn): Desktop mở không lỗi DBCC, DMV xác nhận 3 đoạn `1 048 576 / 1 048 576 / 402 848` `COMPLETED`, `n = 2 500 000`, `SUM(Grp) = 44 999 832`, `SUM(Lo) = 30 000 000`, `DISTINCTCOUNT(Ten) = 5`.
  - `bipro-f14-big.pbix` (10 triệu dòng, **10 đoạn**: 9 × `1 048 576` + `562 816`, có quan hệ `Khach` và cột tính toán `Thanh tien`, cỡ tệp 423 MB, lưu 99,8 s, bộ nhớ đỉnh 1 545 MB): Desktop mở không lỗi DBCC, DMV xác nhận đủ 10 đoạn `COMPLETED` cho cả cột dữ liệu, `RowNumber` (`C123`, 128 B/đoạn) và cột tính toán `Thanh tien`; mọi giá trị DAX khớp nguyên văn (`n = 10 000 000`, `SUM(Qty) = 100 004 320`, `DISTINCTCOUNT(Batch) = 1 000`, `VIP = 20 012 105`, `SUM(Thanh tien) = 3 609 321 116,52`, `region = 5`).
- **T068 (cột tính toán trên bảng nhiều đoạn do Desktop ghi) ĐẠT:** trên `f14-mid-desktop.pbix` (3 đoạn do Desktop lưu):
  - `bipro-t068-add.pbix` (thêm `Tong = [Grp] + [Lo] * 10`): Desktop mở không lỗi, `COUNTROWS = 2 500 000`, `SUM(Tong) = 344 999 832`, 0 dòng lệch, DMV 3 đoạn `COMPLETED`.
  - `bipro-t068-edit.pbix` (sửa `Tong = [Grp] * 2 + [Lo]`): Desktop mở không lỗi, `COUNTROWS = 2 500 000`, `SUM(Tong) = 119 999 664`, 0 dòng lệch, giữ nguyên ID cột và 3 đoạn `COMPLETED`.
- **T069 / SC-006 ĐẠT:** tệp thật `f14-rle-desktop.pbix` do Desktop lưu nặng **27 326 985 byte** (gồm hai tệp `.hidx` 16,8 MB + 17,1 MB). Tệp `bipro-f14-rle.pbix` của BI Pro nặng **24 724 908 byte** (**90,5 %** cỡ Desktop ≤ 125 %). `F2LargeSaveTests.repeat1mRLE` so trực tiếp với tệp Desktop và qua.
