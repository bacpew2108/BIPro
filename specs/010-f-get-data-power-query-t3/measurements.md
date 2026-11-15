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

## S3 / T064 (SC-003): Query Editor và Navigator trên 1 triệu dòng, 2026-11-15

Bản release (`BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --filter QueryEditorPerformanceTests`), Mac Apple Silicon. Bảng 1 triệu dòng × 10 cột (2 số nguyên, 2 thập phân, 1 ngày, 4 chuỗi, 1 logic) qua `QueryEditorState`; CSV 1 triệu dòng × 5 cột (≈ 40 MB) qua `NavigatorState`.

| Thao tác | Thời gian | Ngưỡng |
|---|---|---|
| Chuyển qua lại giữa 5 bước đã tính (xem trước 1000 dòng), tệ nhất trong 15 lần | 0,004 s | SC-003: < 0,5 s: **đạt** |
| Navigator mở CSV 1 triệu dòng + xem trước 200 dòng | 0,003 s | SC-003: < 3 s: **đạt** |
| Thêm bước đầu tiên trên 1 triệu dòng (lọc `Region`, tính từ bảng đầy đủ) | 1,18 s | không có ngưỡng trong SC-003 |
| Thêm các bước sau (sắp xếp trên 200 000 dòng, bỏ cột, giữ 500 dòng) | 0,002 đến 0,012 s | không có ngưỡng |

Ghi nhận: bước đầu tiên chạm bảng đầy đủ tốn hơn 1 s (bộ nhớ đệm `MPreviewCache` tính mỗi bước một lần từ kết quả đầy đủ của bước trước), các bước sau rất nhanh vì chỉ còn tập đã lọc. Một bước nặng ngay trên 1 triệu dòng (ví dụ sắp xếp) sẽ chậm hơn 0,5 s; cân nhắc tính trên mẫu khi cần (chưa làm). Navigator chỉ đọc 200 dòng nên không phụ thuộc kích thước file.
