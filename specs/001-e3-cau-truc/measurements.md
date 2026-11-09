# Số đo: E3-cấu-trúc

Máy: Apple M1 Pro 8 nhân, bản release (`.build-1a-rel`). File: `~/Downloads/bipro-golden/Nhom6_work.pbix` (`~/Downloads/Nhom6_Dashboard.pbix` không còn; bản này khớp cả dữ liệu lẫn bố cục báo cáo: ba truy vấn đo khớp byte và test sinh truy vấn qua hết. `~/Desktop/Mo rong/Nhom6_Dashboard.pbix` khớp dữ liệu nhưng khác bố cục báo cáo ở shape map nên không dùng). Ngày 2026-11-09.

## Trước khi sửa (commit `c8409e9`)

`zsh scripts/e3-loop.sh` (5 lần, trung vị; lần đo đầu trên bản Desktop cho 2,273 / 1,802 / 0,737 s, cùng dữ liệu):

| Truy vấn | Trung vị | Min–Max | So với bản chuẩn |
|---|---|---|---|
| D1 combo thấu chi | 2,148 s | 2,118–2,355 | khớp byte |
| D1 matrix Giờ × Thứ | 1,721 s | 1,696–1,768 | khớp byte |
| D3 combo kênh | 0,725 s | 0,711–0,740 | khớp byte |

`dax-run profile --parallel 8` (một lần chạy; file `build/e3-out/baseline-profile.txt`):

| Trang | Tuần tự | Song song 8 |
|---|---|---|
| D1 · Giao dịch | 4,26 s | 3,32 s |
| D2 · Khoản vay | 0,05 s | 0,03 s |
| D3 · Chăm sóc KH | 0,54 s | 0,42 s |
| Chi tiết chi nhánh | 0,31 s | 0,22 s |

Bộ nhớ của cả lần chạy `profile` (mọi trang, kèm nạp model): peak memory footprint 342 MB, maximum resident set size 579 MB.

## Thử nghiệm T004: giới hạn dưới của tính gộp (Avg_Account_Balance, không có bộ lọc báo cáo)

Fact_Transaction 1 056 320 dòng, 4 501 mã tài khoản, 72 tháng có giao dịch (96 mã tháng trong Dim_Date).

| Cách | Trung vị 5 lần |
|---|---|
| Đường cũ (engine, `SUMMARIZECOLUMNS(year_month, Avg_Account_Balance)`) | 1,92–2,29 s |
| (b) một lần quét phẳng tháng × tài khoản | 0,004 s |
| (a) theo tháng, 1 luồng | 0,004 s |
| (a) theo tháng, 8 luồng | 0,001 s |

Cả ba cách khớp đường cũ ở cả 72 tháng (sai số tương đối lớn nhất 4,8e-15); 24 tháng không có giao dịch ra BLANK ở cả ba cách. Chuẩn bị mảng (đọc cột, ánh xạ dòng → tháng): 0,005 s.

Phần còn lại của combo khi bỏ `Avg_Account_Balance`: 0,43 s (hai lần đo sau lần khởi động), nên dự báo combo sau khi gộp khoảng 0,5–0,6 s. [SUY ĐOÁN: chưa tính chi phí nhận mẫu và áp bộ lọc báo cáo trong engine.]

## Sau khi sửa (2026-11-09)

`zsh scripts/e3-loop.sh` (5 lần, trung vị), cả ba khớp byte với bản chuẩn:

| Truy vấn | Trước | Sau | Công tắc tắt (`BIPRO_BATCH=0`) |
|---|---|---|---|
| D1 combo thấu chi | 2,148 s | **0,529 s** | 2,11 s |
| D1 matrix Giờ × Thứ | 1,721 s | **0,421 s** | 1,66 s (trước các sửa khác) |
| D3 combo kênh | 0,725 s | 0,096 s | 0,715 s (trước các sửa khác) |

(Công tắc `BIPRO_BATCH` chỉ tắt đường gộp. Các sửa ở `ColumnStore`, `FilterContext`, `SummarizeColumns` và `Aggregation` luôn bật; riêng matrix và combo kênh nhanh nhờ các sửa đó, không nhờ đường gộp.)

`dax-run profile --parallel 8`:

| Trang | Tuần tự trước → sau | Song song 8 trước → sau |
|---|---|---|
| D1 · Giao dịch | 4,26 → 1,55 s | 3,32 → **1,04 s** |
| D2 · Khoản vay | 0,05 → 0,04 s | 0,03 → 0,02 s |
| D3 · Chăm sóc KH | 0,54 → 0,17 s | 0,42 → 0,13 s |
| Chi tiết chi nhánh | 0,31 → 0,26 s | 0,22 → 0,18 s |

Bộ nhớ của cả lần chạy `profile`: peak memory footprint 342 → 197 MB; maximum resident set size 579 → 634 MB (+9,5%).

Có slicer năm (năm 2018, 322 277 dòng giao dịch; `__DS0FilterTable` thay bằng `'Dim_Date'[year] IN {2018}`, trung vị 5 lần, khớp byte giữa hai chế độ):

| Truy vấn | Đường gộp bật | Đường gộp tắt |
|---|---|---|
| D1 combo thấu chi | 0,25 s | 0,79 s |
| D1 matrix Giờ × Thứ | 0,27 s | 0,28 s |

Kiểm trên app (`zsh scripts/build-app.sh`, trang D1 của `Nhom6_work.pbix`, ảnh `build/e3-out/app-d1.png`): combo thấu chi, matrix Giờ × Thứ, matrix nhóm tuổi × vùng đều hiện số liệu và hình đúng.

Test (cuối, sau T028–T034): `swift test` 819 qua (ổn định 3 lần liên tiếp); golden nặng và test gộp 79 qua (gồm 67 test golden cũ, các test đường gộp và các trường hợp biên); `huyTruyVanNangDungNhanh` 6/6 lần qua sau khi đổi khối lượng của test (xem research.md R9).
