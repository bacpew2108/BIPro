# Số đo: tồn đọng sau Phase F (specs/011)

Máy: MacBook Pro M-series, macOS 15 (Darwin 24.6). Bản release (`-c release -Xswiftc -enable-testing --scratch-path .build-1a-rel`).

## US5: bảng lớn (T058, `F2LargeSaveTests`, 2026-11-19)

| Ca | Tải | Lưu | Tệp | Bộ nhớ đỉnh | Kiểm |
|---|---|---|---|---|---|
| Tài liệu mới + `big_10m.parquet` (10 triệu dòng × 10 cột, 2 đoạn 8 388 608 + 1 611 392) + bảng `Khach` (quan hệ tự phát hiện) + cột tính toán `Thanh tien` | 16,2 s | 78,7 s | 473 MB | 2 314 MB | mở lại: `COUNTROWS`, `SUM`, `DISTINCTCOUNT`, lọc qua quan hệ, cột tính toán trùng nguồn |
| `repeat_1m.csv` (1 triệu dòng × 5 cột) | | 3,3 s | 27 431 949 byte | | `Batch` 100 run RLE; số dòng, đếm khác nhau, tổng `Flag` đúng |

- SC-007 (lưu < 2 phút, bộ nhớ < 4 GB): đạt. Lần đo sau khi đổi sang một đoạn (gate VM-F14): lưu 82,2 s, 474 MB, đỉnh 1 902 MB.
- SC-006 (cỡ tệp `repeat_1m` ≤ 125 % Desktop): **chưa đạt**. Desktop ước lượng khoảng 6,7 MB phần dữ liệu (DMV, `vm-f14/QUAN-SAT.md`), BI Pro 27,4 MB: Desktop mã hoá VALUE cho `ID`, `Value` và sắp lại dòng. Cột `Value` (1 triệu số ngẫu nhiên) chiếm phần lớn tệp; RLE chỉ giúp cột lặp liền nhau vì BI Pro giữ thứ tự dòng nguồn (Desktop sắp lại dòng, `[SUY ĐOÁN]` chưa làm).

## Mã hoá RLE so với Desktop (T056)

Với cùng thứ tự dòng, bộ ghi ra đúng run (RLE và bit-packing), số giá trị bit-packing, độ rộng bit và từ bit-packing như Desktop:
- 4 cột `Marketing` của `tuan6.2.pbix` (1 363 dòng, `VertiPaqWriteTests.agreesWithRealMarketingColumns`);
- 5 cột `Fact_Transaction` của Nhom6 (1 056 320 dòng, `VertiPaqSegmentTests.runTrungDesktopTrenNhom6`).

Quy tắc rút ra: run lặp từ 64 giá trị trở lên thành mục RLE; độ rộng bit theo cả khoảng mã của đoạn; bảng run là luỹ thừa của 2 lớn hơn số run dùng (tối thiểu 16).

## T060: golden nặng đầy đủ (2026-11-19, release, `BIPRO_HEAVY=1`, không lọc, có `BIPRO_PG`)

- 2 385 test; 3 trượt rồi xử lý:
  - `T116Nhom6Tests` còn kỳ vọng chặn sửa cột là cấp phân cấp (nay sửa được): đã sửa test;
  - `TableDataTests` thiếu `MSourceType.dateTime`: đã sửa test;
  - `F2LargeSaveTests` lưu 124 s (> 120 s) khi chạy cùng lúc với Desktop trong VM và người dùng đang dùng máy; chạy riêng 78–82 s.
- Golden DAX Phase B và truy vấn visual (`VIS-BENCHMARK` KHỚP) không đổi.
- SC-008: Nhom6 chỉ T2 lưu 2,36 / 2,56 / 2,40 s (< 4 s).
