# Số đo: tồn đọng sau Phase F (specs/011)

Máy: MacBook Pro M-series, macOS 15 (Darwin 24.6). Bản release (`-c release -Xswiftc -enable-testing --scratch-path .build-1a-rel`).

## US5: bảng lớn (T058, `F2LargeSaveTests`, 2026-11-19)

| Ca | Tải | Lưu | Tệp | Bộ nhớ đỉnh | Kiểm |
|---|---|---|---|---|---|
| Tài liệu mới + `big_10m.parquet` (10 triệu dòng × 10 cột, 2 đoạn 8 388 608 + 1 611 392) + bảng `Khach` (quan hệ tự phát hiện) + cột tính toán `Thanh tien` | 16,2 s | 78,7 s | 473 MB | 2 314 MB | mở lại: `COUNTROWS`, `SUM`, `DISTINCTCOUNT`, lọc qua quan hệ, cột tính toán trùng nguồn |
| `repeat_1m.csv` (1 triệu dòng × 5 cột) | | 3,3 s | 27 431 949 byte | | `Batch` 100 run RLE; số dòng, đếm khác nhau, tổng `Flag` đúng |

- SC-007 (lưu < 2 phút, bộ nhớ < 4 GB): đạt.
- SC-006 (cỡ tệp `repeat_1m` ≤ 125 % Desktop): chưa so, chờ `f14-rle-desktop.pbix` của buổi VM-F14. Cột `Value` (1 triệu số ngẫu nhiên) chiếm phần lớn tệp; RLE chỉ giúp cột lặp liền nhau vì BI Pro giữ thứ tự dòng nguồn (Desktop sắp lại dòng, `[SUY ĐOÁN]` chưa làm).

## Mã hoá RLE so với Desktop (T056)

Với cùng thứ tự dòng, bộ ghi ra đúng run (RLE và bit-packing), số giá trị bit-packing, độ rộng bit và từ bit-packing như Desktop:
- 4 cột `Marketing` của `tuan6.2.pbix` (1 363 dòng, `VertiPaqWriteTests.agreesWithRealMarketingColumns`);
- 5 cột `Fact_Transaction` của Nhom6 (1 056 320 dòng, `VertiPaqSegmentTests.runTrungDesktopTrenNhom6`).

Quy tắc rút ra: run lặp từ 64 giá trị trở lên thành mục RLE; độ rộng bit theo cả khoảng mã của đoạn; bảng run là luỹ thừa của 2 lớn hơn số run dùng (tối thiểu 16).
