# Phase B, buổi 1: checklist cho người dùng

Buổi này chạy trong Power BI Desktop trên VM Windows 11. Bạn làm tay mọi bước. Không cài thêm phần mềm, không dùng DAX Studio.

**Thời lượng:** ước tính khoảng 1 giờ 30 phút. Phần golden tối thiểu (12 file) mất khoảng 25 phút. Nếu thiếu thời gian, hãy báo lead trước khi bắt đầu, để lead quyết định chuyển O8 và O10 sang buổi 2.

**Rủi ro số 1: O1 và O2.** Làm hai bước này trước. Nếu định dạng khi Copy (dấu thập phân, ngày, BLANK, Infinity) khác với giả định, toàn bộ golden phải đọc theo cách khác. Nếu O1 hoặc O2 chưa rõ, dừng lại và báo lead trước khi làm các bước sau.

## 0. Chuẩn bị

### 0.1 Đưa gói sang VM
- Đưa thư mục `docs/phase-b-oracle/` từ Mac sang VM qua thư mục chia sẻ Parallels, để VM mở được các file `.dax`.
- Kiểm tra: `queries/` có 16 file `.dax`, `observe/` có 16 file `.dax`, và có file `manifest.template.tsv`.

### 0.2 Thư mục ghi kết quả
- Golden: `~/Downloads/bipro-golden/nhom6/`
- Quan sát: `~/Downloads/bipro-golden/observe/`
- Quy ước tên file:
  - Kết quả đúng: `<tên>.tsv` (UTF-8). Ví dụ `G1-year__FT.tsv`, `O1-copy.tsv`.
  - Lỗi: `<tên>.error.txt`. Dán nguyên văn thông báo lỗi.
  - Ảnh chụp: `<tên>.png`.
- Đường dẫn trên theo quy ước của `phase-b-research/oracle-ui.md` mục 1.3. Nếu thư mục này không hiện trong Downloads của Mac qua Parallels, báo lead trước khi ghi.

### 0.3 Manifest
1. Copy `docs/phase-b-oracle/manifest.template.tsv` thành `manifest.tsv` trong `~/Downloads/bipro-golden/nhom6/`. Mở bằng Notepad, lưu UTF-8.
2. Ghi **Windows regional format**: Settings > Time & language > Region > Regional format. Lấy nguyên văn tên hiển thị trong ô chọn.
3. Ghi **phiên bản Power BI** (Help > About). Lấy nguyên văn số phiên bản.
4. Các giá trị ở bước 2 và 3 giống nhau cho mọi dòng. Dòng nào chạy xong thì điền thêm `ngày` (yyyy-mm-dd), `số_dòng` (số dòng kết quả, không tính header), và `ghi_chú_lỗi` nếu có lỗi.
5. Với O2, ghi thêm locale đọc được vào cột `Windows regional format`.

### 0.4 Mở file mô hình
- Mở bản sao file Nhom6 trong Power BI Desktop. Chỉ dùng bản sao, không mở file gốc để làm việc.
- Mở DAX Query View (biểu tượng DAX Query View trên thanh bên trái).
- Khi thoát, nếu Power BI hỏi có lưu không, chọn **Don't save**, trừ khi bước O7 yêu cầu Save As.

### 0.5 Cách làm chung cho mỗi truy vấn
1. Mở file `.dax` bằng Notepad. Ctrl+A, Ctrl+C.
2. Trong DAX Query View, bấm **+** để tạo tab mới. Ctrl+V, rồi bấm **Run**.
3. Kết quả đúng: Copy kết quả (Ctrl+C trên lưới) > Notepad > lưu `<tên>.tsv` (UTF-8).
4. Có lỗi: copy thông báo lỗi > Notepad > lưu `<tên>.error.txt`. Ghi thêm vị trí (dòng, cột) nếu thông báo có.

## 1. Thứ tự

| Bước | Nội dung | Thời lượng | File mở | Kết quả |
|---|---|---|---|---|
| 1 | O1 | 3 phút | `observe/O1-format.dax` | `O1-grid.png` |
| 2 | O2 | 5 phút | (từ kết quả O1) | `O1-copy.tsv` và ghi locale |
| 3 | O3 (a đến e) | 8 phút | `observe/O3a..O3e` | `.error.txt` và ảnh |
| 4 | O4 (a đến c) | 10 phút | `observe/O4a..O4c` | ảnh |
| 5 | O5 | 3 phút | `observe/O5-multi-evaluate.dax` | ảnh và `.error.txt` |
| 6 | O7 | 10 phút | (tạo tab mới) | `nhom6-daxq.pbix` |
| 7 | O8 | 6 phút | (quick queries) | `O8-01.dax` ... |
| 8 | O9 | 3 phút | `observe/O9-before.dax` | `O9-after.dax` |
| 9 | O10 | 5 phút | (gõ trong tab tạm) | 4 ảnh |
| 10 | O12 | 4 phút | `observe/O12-cancel.dax` | ảnh |
| 11 | Golden G0 (4 file) | 8 phút | `queries/G0-total__*.dax` | `G0-total__*.tsv` |
| 12 | Golden G1 (4 file) | 8 phút | `queries/G1-year__*.dax` | `G1-year__*.tsv` |
| 13 | Golden G3 (4 file) | 9 phút | `queries/G3-rf-year__*.dax` | `G3-rf-year__*.tsv` |
| 14 | Cuối buổi | 5 phút | `manifest.tsv` | báo lead |

Các bước còn lại (G2, G4, G5, G6, PA, bộ tí hon và O6, O11, O13 đến O18) làm ở buổi 2.

## 2. Các bước chi tiết

### Bước 1: O1 (rủi ro số 1)
- **Mở:** `observe/O1-format.dax`.
- **Thao tác:** Ctrl+A, Ctrl+C. Trong DAX Query View, tab mới, Ctrl+V, Run.
- **Ghi lại:** chụp lưới, lưu `observe/O1-grid.png`. Ghi nhận từng ô: `1/3` hiển thị bao nhiêu chữ số, `big` có dấu phân cách gì, `date` và `dt` hiển thị kiểu nào, `inf` và `nan` hiện thế nào.
- **Lỗi:** nếu lỗi, lưu `observe/O1-format.error.txt` và báo lead ngay.

### Bước 2: O2 (rủi ro số 1)
- **Mở:** kết quả O1 đang hiển thị.
- **Thao tác:** Copy kết quả (Ctrl+C trên lưới) > Notepad > Ctrl+V > Save As `observe/O1-copy.tsv`, Encoding UTF-8.
- **Ghi lại:** Windows regional format (Settings > Time & language > Region) vào manifest, theo bước 0.3. Ghi cả dấu thập phân và dấu phân nhóm đang dùng trong `O1-copy.tsv`.
- **Lưu ý:** Copy có kèm header cột không. Có kèm BLANK và chuỗi rỗng khác nhau không. Ghi nguyên văn.

### Bước 3: O3 (năm file, lỗi có chủ đích)
Với mỗi file, Ctrl+A, Ctrl+C từ file `.dax`, dán vào tab mới, Run. Các file này cố ý lỗi. Lưu thông báo lỗi và chụp ảnh.

| File | Lỗi | Lưu |
|---|---|---|
| `observe/O3a-missing-paren.dax` | thiếu `)` ở dòng 3 | `O3a-missing-paren.error.txt` |
| `observe/O3b-bad-column.dax` | cột `'Dim_Date'[yearx]` ở dòng 4 | `O3b-bad-column.error.txt` |
| `observe/O3c-runtime-convert.dax` | lỗi lúc chạy, `CONVERT` | `O3c-runtime-convert.error.txt` |
| `observe/O3d-leading-tab.dax` | dòng 3 có một tab đầu dòng | `O3d-leading-tab.error.txt` |
| `observe/O3e-two-errors.dax` | hai lỗi cột ở dòng 4 và 5 | `O3e-two-errors.error.txt` |

- **Ghi lại thêm:** vị trí lỗi (dòng, cột) mà Power BI báo, và ảnh chụp mỗi lỗi lưu `<tên>.png`.
- **Lưu ý:** O3e có thể chỉ báo một lỗi. Ghi đúng những gì hiển thị, không suy đoán.

### Bước 4: O4 (giới hạn dòng và chuỗi dài)
- **O4a** (`observe/O4a-generateseries.dax`): Run. Chụp ảnh số dòng hiển thị, câu cảnh báo cắt, thanh trạng thái (`O4a-generateseries.png`).
- **O4b** (`observe/O4b-topn-fact.dax`): Run. Có thể mất vài chục giây. Chụp ảnh tương tự (`O4b-topn-fact.png`). Nếu quá lâu, bấm Cancel rồi ghi lại.
- **O4c** (`observe/O4c-long-string.dax`): truy vấn nặng, chỉ chạy một lần. Chụp ảnh thông báo, nếu có (`O4c-long-string.png`). Nếu lỗi, lưu `O4c-long-string.error.txt`.

### Bước 5: O5 (nhiều EVALUATE)
- **Mở:** `observe/O5-multi-evaluate.dax`. Ctrl+A, Ctrl+C, dán vào tab mới, Run.
- **Ghi lại:** chụp dropdown Result (`O5-multi-evaluate.png`), kiểm tra Result 1 và Result 3 có kết quả hay không.
- **Lỗi:** thông báo của Result 2 lưu `observe/O5-multi-evaluate.error.txt`.

### Bước 6: O7 (nơi lưu tab truy vấn trong `.pbix`) — bước đặc biệt
1. Trong bản sao Nhom6 đang mở (bước 0.4), vào DAX Query View.
2. Tạo tab thứ nhất bằng **+**. Đặt tên tab `BIPRO_A` (chuột phải lên tab, chọn Rename; nếu không có, thử double-click). Nội dung: `EVALUATE ROW ( "a", 1 )`. Run một lần.
3. Tạo tab thứ hai bằng **+**. Đặt tên `BIPRO_B`. Nội dung: `EVALUATE ROW ( "b", 2 )`. Run một lần.
4. Không bấm Ctrl+S. Vào File > **Save as**, đặt tên `nhom6-daxq.pbix`, lưu vào `~/Downloads/bipro-golden/observe/`.
5. Chỉ lưu bản sao. Không ghi đè file Nhom6 gốc.
6. Nếu Power BI hỏi lưu khi đóng, chọn **Don't save** cho file gốc.
- **Chép về Mac:** nếu thư mục `~/Downloads/bipro-golden/` đã ánh xạ với Mac qua Parallels, file xuất hiện ngay trên Mac. Nếu không, chép `nhom6-daxq.pbix` thủ công qua thư mục chia sẻ, rồi kiểm tra file có trong `observe/` trên Mac.
- **Lưu ý:** O7 không có ảnh bắt buộc. Nếu Save As lỗi, ghi thông báo vào `O7-save-as.error.txt`.

### Bước 7: O8 (quick queries)
Chuột phải vào các đối tượng sau. Với mỗi mục sinh ra một tab truy vấn:
- Measure `Net_Cashflow`: chọn Quick queries và lần lượt 3 mục.
- Bảng `Dim_Date`: chọn Show top 100 rows, rồi Show column statistics.
- Cột `year` của `Dim_Date`: chọn Show data preview.

Với mỗi tab sinh ra: Ctrl+A, Ctrl+C trong tab, rồi dán vào Notepad. Dòng đầu file ghi tên mục menu, sau đó lưu `observe/O8-01.dax`, `O8-02.dax`, ... theo thứ tự tạo. Dòng đầu là comment, bắt đầu bằng `//`.

### Bước 8: O9 (Format query)
- **Mở:** `observe/O9-before.dax`. Ctrl+A, Ctrl+C.
- Dán vào tab mới trong DAX Query View. Bấm **Shift+Alt+F** để format (xác nhận phím tắt trên màn hình; trên Mac là ⇧⌥F).
- **Thao tác:** Ctrl+A, Ctrl+C trong editor sau khi format. Dán vào Notepad, lưu `observe/O9-after.dax`, UTF-8.
- **Ghi lại:** nếu Format không đổi gì, ghi rõ trong `O9-after.dax` dòng đầu bằng comment `// không đổi`.

### Bước 9: O10 (IntelliSense)
Trong một tab tạm, KHÔNG lưu. Gõ lần lượt và chụp ảnh danh sách gợi ý:
1. `'Dim_` (`observe/O10-a.png`)
2. `'Dim_Date'[` (`observe/O10-b.png`)
3. `SUMM` (`observe/O10-c.png`)
4. `[Tra` (`observe/O10-d.png`)
- Ngoài ra, rê chuột lên một hàm trong gợi ý để thấy tooltip chữ ký, chụp thêm `O10-tooltip.png`.

### Bước 10: O12 (Cancel)
- **Mở:** `observe/O12-cancel.dax`. Ctrl+A, Ctrl+C, dán vào tab mới.
- **Thao tác:** Run. Khi truy vấn đang chạy, bấm **Cancel**.
- **Ghi lại:** chụp icon tab và thông báo (`O12-cancel.png`). Ghi thời gian từ lúc bấm Cancel đến lúc dừng hẳn, bằng đồng hồ, chỉ là ước lượng.

### Bước 11 đến 13: Golden tối thiểu (12 file)
Làm theo thứ tự G0, G1, G3. Mỗi file làm theo mục 0.5.

| Nhóm | File `.dax` (trong `queries/`) | Kết quả |
|---|---|---|
| G0 | `G0-total__FT.dax`, `G0-total__LN.dax`, `G0-total__CR.dax`, `G0-total__DIM.dax` | `G0-total__<phần>.tsv` |
| G1 | `G1-year__FT.dax`, `G1-year__LN.dax`, `G1-year__CR.dax`, `G1-year__DIM.dax` | `G1-year__<phần>.tsv` |
| G3 | `G3-rf-year__FT.dax`, `G3-rf-year__LN.dax`, `G3-rf-year__CR.dax`, `G3-rf-year__DIM.dax` | `G3-rf-year__<phần>.tsv` |

- Mỗi file `.dax` có dòng đầu là comment, ghi tên file và số measure. Dòng này không ảnh hưởng kết quả.
- Mỗi measure có một cột thăm dò `<tên> · ISBLANK`. Không xoá các cột này. Chúng giúp phân biệt ô rỗng là BLANK hay chuỗi rỗng.
- Sau mỗi file, điền dòng tương ứng trong `manifest.tsv` (ngày, số dòng, ghi chú lỗi).
- **Điểm cần kiểm:** Copy có lấy đủ mọi cột và mọi dòng không, khi lưới có hơn 70 cột. Nếu nghi ngờ Copy bị thiếu, ghi vào `ghi_chú_lỗi` và báo lead. Không sửa tay kết quả.

### Bước 14: Cuối buổi
1. Đếm: 12 file golden (`.tsv` hoặc `.error.txt`) trong `~/Downloads/bipro-golden/nhom6/`.
2. Mở `manifest.tsv`. Kiểm tra 12 dòng golden đã có ngày, Windows regional format, phiên bản Power BI, số dòng hoặc ghi chú lỗi.
3. Kiểm tra `~/Downloads/bipro-golden/observe/` có đủ ảnh, `.tsv`, `.error.txt`, `O8-*.dax`, `O9-after.dax` và `nhom6-daxq.pbix`.
4. Báo lead: đã làm bước nào, bước nào lỗi, và danh sách điểm chưa chắc.

## 3. Điểm cần lead xác nhận
- Đường dẫn `~/Downloads/bipro-golden/` có khớp với thư mục chia sẻ Parallels trên Mac không.
- Phím tắt Format query trên Windows (bước 8).
- Copy có lấy đủ mọi cột khi lưới rộng hay không (bước 11 đến 13).
