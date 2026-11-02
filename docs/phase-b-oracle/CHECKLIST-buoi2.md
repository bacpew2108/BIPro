# Phase B, buổi 2: checklist cho người dùng

Buổi này chạy trong Power BI Desktop trên VM Windows 11, giống buổi 1. Bạn làm tay mọi bước, không cài thêm phần mềm.

**Thời lượng:** khoảng 1 giờ. Phần golden (17 file) khoảng 35 phút; phần quan sát khoảng 15 phút; Performance Analyzer khoảng 10 phút.

**Thứ tự ưu tiên:** golden G2, G5, G6 (bắt buộc để đóng Phase B) → T1–T4 → G4 → quan sát → Performance Analyzer. Hết thời gian thì dừng ở đâu cũng được, báo lại phần đã làm.

## 0. Chuẩn bị trên Mac (1 phút)

Chạy trong Terminal (hoặc gõ trong Claude Code với tiền tố `!`):

```
mkdir -p ~/Downloads/bipro-golden/{pack2,nhom6,observe2}
cp -R ~/Desktop/PowerBINative/docs/phase-b-oracle/queries-buoi2/ ~/Downloads/bipro-golden/pack2/
cp ~/Desktop/PowerBINative/docs/phase-b-oracle/queries/G2-region__*.dax ~/Downloads/bipro-golden/pack2/
cp ~/Desktop/PowerBINative/docs/phase-b-oracle/observe/O1{1,5,7,8}*.dax ~/Downloads/bipro-golden/pack2/
cp ~/Desktop/PowerBINative/docs/phase-b-oracle/manifest-buoi2.template.tsv ~/Downloads/bipro-golden/nhom6/manifest-buoi2.tsv
```

- `pack2/` chứa mọi file `.dax` của buổi này.
- Golden lưu vào `nhom6/` (cùng chỗ với buổi 1). Quan sát lưu vào `observe2/`.
- Dùng lại `Nhom6_work.pbix` từ buổi 1. Không mở file gốc.

## 1. Cách chạy mỗi file (giống buổi 1)

1. Mở file `.dax` bằng Notepad, Ctrl+A, Ctrl+C.
2. DAX Query View: bấm **+** tạo tab mới, Ctrl+V, **Run**.
3. Thành công: bấm nút **Copy** ở thanh Results, dán vào Notepad mới, **Save As** tên `<tên file>.tsv`, **Encoding UTF-8**.
4. Lỗi: copy thông báo lỗi, lưu `<tên file>.error.txt`.

**Đặt tên đúng từng ký tự như tên file `.dax`** (ví dụ `G6e-heatmap.tsv`, `T1-blank-arith.tsv`, `O15-format.tsv`). Tên quan sát bắt đầu bằng chữ **O**, không phải số 0.

## 2. Golden (lưu vào `nhom6/`)

| # | File (trong `pack2\`) | Số dòng kết quả dự kiến | Ghi chú |
|---|---|---|---|
| 1 | `G2-region__FT.dax`, `__LN`, `__CR`, `__DIM` | 5 dòng mỗi file | theo vùng của khách |
| 2 | `G5-month.dax` | 96 dòng | theo tháng, khoảng 10 giây |
| 3 | `G6a-issue-pareto.dax` | 38 dòng | |
| 4 | `G6b-channel.dax` | 6 dòng | |
| 5 | `G6c-channel-response.dax` | 42 dòng | |
| 6 | `G6d-trans-type.dax` | 6 dòng | |
| 7 | `G6e-heatmap.dax` | 70 dòng | |
| 8 | `G6f1-district.dax` | 77 dòng | |
| 9 | `G6f2-account-branch.dax` | 76 dòng | có thể chậm |
| 10 | `T1-blank-arith.dax` … `T4-count-empty.dax` | 1–2 dòng mỗi file | bộ ca nhỏ về BLANK, ngày cuối tháng, ALLSELECTED |
| 11 | `G4-inactive.dax` | 8 dòng | quan hệ inactive |

"Số dòng dự kiến" là số engine của BI Pro ra. Nếu Power BI ra số dòng khác, **không sửa gì**, chỉ ghi vào cột ghi chú của manifest. Đó chính là thông tin cần tìm.

Sau mỗi file, điền một dòng trong `nhom6/manifest-buoi2.tsv`: ngày, phiên bản Power BI (2.159.883.0 64-bit (October 2026)), regional format (United States), số dòng.

## 3. Quan sát (lưu vào `observe2/`)

| Mã | Làm gì | Lưu |
|---|---|---|
| O6 | Chạy lại `G5-month.dax`. Chụp thanh trạng thái phía dưới (thời gian chạy, số dòng). | `O6-statusbar.png` |
| O11 | Mở `O11-run-selection.dax`. Bôi đen **chỉ** dòng `EVALUATE ROW ( "khoi", "thứ hai" )`, bấm Run. | `O11-run-selection.png` (thấy kết quả là khối nào) |
| O13 | Trên lưới kết quả của G5, bấm vào tiêu đề một cột, rồi thử mở bộ lọc cột (nếu có). | `O13-sort.png`, `O13-filter.png` |
| O14 | Trong editor, rê chuột lên chữ `[Complaints]` của một truy vấn. | `O14-hover.png` |
| O15 | Chạy `O15-format.dax`, Copy kết quả. | `O15-format.tsv` |
| O17 | Chạy `O17-text-compare.dax`. | `O17-text-compare.tsv` hoặc `.error.txt` |
| O18 | Chạy `O18a-addcolumns.dax` và `O18b-topn.dax`. | `O18a-addcolumns.tsv`, `O18b-topn.tsv` |
| O8 | Làm lại quick query, lần này copy **văn bản truy vấn** trong tab mới sinh (Ctrl+A, Ctrl+C trong editor), không copy kết quả. Chuột phải measure `Net_Cashflow` > Quick queries > lần lượt 3 mục; bảng `Dim_Date` > Show top 100 rows; cột `year` > Show data preview. | `O8-query-1.dax` … `O8-query-5.dax` |

## 4. Performance Analyzer (PA, lưu vào `observe2/`)

Mục đích: lấy đúng truy vấn mà mỗi visual gửi đi, để làm đặc tả cho Phase C.

1. Chuyển sang **Report view**. Ribbon **Optimize** (hoặc **View**) > **Performance analyzer** > **Start recording** > **Refresh visuals**.
2. Với khoảng 8 visual (khoảng 2 visual mỗi trang: một thẻ KPI có Δ và một bảng hoặc biểu đồ), mở visual trong khung Performance analyzer, bấm **Copy query**.
3. Dán vào Notepad, lưu `PA-<trang>-<tên ngắn>.dax` (ví dụ `PA-d1-card-tienvao.dax`).
4. Dán truy vấn đó vào một tab DAX Query View mới, Run, Copy kết quả, lưu `PA-<trang>-<tên ngắn>.tsv`.
5. Bấm **Stop** khi xong.

## 5. Cuối buổi

1. Kiểm tra `nhom6/` có các file `.tsv` (hoặc `.error.txt`) của mục 2, và `manifest-buoi2.tsv` đã điền.
2. Kiểm tra `observe2/` có ảnh và file của mục 3, 4.
3. Khi đóng Power BI, chọn **Don't save**.
4. Báo lead: đã làm mục nào, mục nào lỗi.
