# Đo hiệu năng Phase F

## S5 / T023: ghi bảng nạp vào `.pbix` (T3), 2026-11-15

Bản release (`BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --filter WriterPerformanceTests`), Mac Apple Silicon, bảng 10 cột (2 số nguyên, 2 thập phân, 1 ngày, 4 chuỗi gồm một cột ~200 000 giá trị khác nhau, có ô trống), nền là `tuan6.2.pbix` (160 KB).

| Số dòng | Mã hoá + ghi + xác minh (`PBIXWriter.build`) | Đọc lại | File | Bộ nhớ đỉnh |
|---|---|---|---|---|
| 100 000 | 1,06 s | 0,10 s | 1 MB | 174 MB |
| 1 000 000 | 4,68 s | 0,35 s | 27 MB | 668 MB |

Mục tiêu: SC-004 (1 triệu dòng < 15 s, 100 000 dòng < 4 s) và SC-005 (< 2 GB): **đạt**. Chưa gồm đổi `TableData` → dữ liệu mã hoá và bước đọc lại từng ô của `DocumentSaver.verifyTables` (phía ứng dụng).

Điểm nghẽn đã sửa: ban đầu 1 triệu dòng mất 40,8 s vì `textStatistics` sắp cả triệu chuỗi bằng so sánh văn hoá; nay quét min/max trên các giá trị khác nhau (4,5 s). So sánh văn hoá của 200 000 chuỗi khác nhau chỉ 0,75 s.

Chưa đo: file nền Nhom6 (54 MB, giải nén cả mô hình): lưu 100 000 dòng khoảng 14 s ở bản debug (gồm mở mô hình, nén lại và xác minh); cần đo bản release nếu muốn con số cho SC-004 trên mô hình lớn.
