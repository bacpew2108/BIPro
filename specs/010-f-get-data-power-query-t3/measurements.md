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

## T106 (SC-004, SC-005): lưu T3 qua đường app đầy đủ, 2026-11-17

Bản release (`BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --no-parallel --filter SavePerformanceTests`), Mac Apple Silicon. Đường đo: `DocumentState.loadFromGetData` (Get Data ▸ Tải) → `DocumentSaver` (`TableData` → `NewTable` → VertiPaq → `PBIXWriter.build` gồm kiểm sau ghi → `verifyModel`, `verifyTables` đọc lại từng ô → ghi tạm, mở lại, thay). Bảng 10 cột như S5.

| Trường hợp | Lưu | File | Bộ nhớ đỉnh | Ngưỡng |
|---|---|---|---|---|
| Tài liệu mới, 100 000 dòng | 0,97 s | 1 MB | 178 MB | < 4 s: **đạt** |
| Tài liệu mới, 1 triệu dòng | 5,44 s | 27 MB | 702 MB | < 15 s, < 2 GB: **đạt** |
| Nền Nhom6 (54 MB), thêm bảng 100 000 dòng | 3,96 s | 53 MB | 1 160 MB | không có ngưỡng riêng |
| Nhom6 chỉ đổi T2 (thêm một measure), 3 lần | 2,22 / 2,34 / 2,26 s | | | Phase E < 3 s: **đạt** |

Trước khi sửa, lưu Nhom6 chỉ T2 mất 3,03 đến 3,78 s (trượt nhẹ ngưỡng Phase E). Tách bước (`BIPRO_TIMING=1`): giải nén nguồn 0,24 s, dựng lại ABF 0,21 s, **nén XPress9 1,62 s**, kiểm sau ghi giải nén lại bản mới 0,29 s và bản cũ 0,29 s, `verifyModel` và `verifyTables` mỗi hàm giải nén lại thêm một lần (0,3 s). Hai sửa:

1. Giải nén mỗi bản một lần: `PBIXWriter.build` đưa ABF nguồn đã giải nén vào `verify`, và trả ABF đọc lại từ byte mới (`Result.model`) để `DocumentSaver.verifyModel`/`verifyTables` dùng lại. Mọi phép kiểm vẫn đọc từ byte của file mới.
2. Bộ nén XPress9 tìm khớp với độ sâu 4 thay vì 9 (`cxpress9.c`). Trên ABF 90 MB của Nhom6, thời gian nén 1,8 s còn 1,3 s, luồng nén to hơn 12 KB (53 946 150 so với 53 934 517 byte; Desktop tự ghi 54 180 916). Độ sâu chỉ ảnh hưởng cách bộ nén tìm khớp, không đổi định dạng luồng. Desktop mở tệp Nhom6 do BI Pro lưu sau thay đổi này: kiểm ở gate T100.

Định dạng nén của Desktop với Nhom6 là XPress9 đơn luồng: mọi khối dùng chung cửa sổ lịch sử, nên không nén song song theo khối mà vẫn giữ định dạng ấy.

## T116: sửa và xoá cột, bảng tính toán trên Nhom6 (2026-11-17, release)

`T116Nhom6Tests`, `DocumentSaver.save` đầy đủ (dựng, kiểm sau ghi, ghi tạm, thay):
- Lần 1, thêm 3 cột tính toán và 2 bảng tính toán: 2,6 s.
- Lần 2, sửa công thức 3 cột (gồm `Fact_Transaction[trans_hour]` 1 056 320 dòng) cùng 1 cột phụ thuộc ghi lại, xoá 1 cột, sửa và xoá 1 bảng: 3,4 s.

