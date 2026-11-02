# Phase C, buổi C1: quan sát truy vấn và tương tác của visual

Bạn tự làm tay trong Power BI Desktop trên VM Windows 11, giống các buổi của Phase B.

**Thời lượng:** khoảng 60–75 phút. Phần ★ (mục 2 và 3) cần làm trước. Các phần khác có thể làm ở một lần mở VM sau, nhưng phải xong trước đợt 2.

**Mục đích:** BI Pro sẽ sinh truy vấn DAX cho từng visual **giống hệt Power BI**. Vì vậy mình cần văn bản truy vấn thật của mọi visual, và cần biết truy vấn đổi thế nào khi bạn chọn slicer, bấm vào cột, drill, drillthrough.

## 0. Chuẩn bị trên Mac (1 phút)

```
mkdir -p ~/Downloads/bipro-c1/{pa,results,interact,shots}
```

- Mở `Nhom6_work.pbix` (bản làm việc của buổi trước), **không mở file gốc**. Nếu không còn bản này, copy `Nhom6_Dashboard.pbix` thành `Nhom6_work.pbix` rồi mở bản copy.
- Không lưu file `.pbix` sau buổi này (khi đóng, chọn **Don't save**).
- Zoom của report: **View → Fit to page**.

## 1. Cách copy một truy vấn (dùng cho cả buổi)

1. **Optimize → Performance analyzer** (hoặc View → Performance analyzer). Bấm **Start recording**.
2. Làm thao tác cần đo, hoặc bấm **Refresh visuals**.
3. Trong danh sách, mở dòng của visual (tên là tiêu đề visual), bấm **Copy query**.
4. Dán vào Notepad, **Save As** với tên ghi trong bảng, Encoding **UTF-8**.
5. Khi chuyển sang thao tác mới, bấm **Clear** trong Performance analyzer để danh sách gọn.

Visual không có tiêu đề (slicer, card): Performance analyzer ghi tên theo loại, ví dụ "Slicer", "Card". Khi rê chuột lên dòng đó, visual tương ứng được đánh dấu trên trang; dùng cách này để nhận ra visual nào.

## 2. ★ Truy vấn ở trạng thái mặc định (O-C1), khoảng 30 phút

Ở mỗi trang D1, D2, D3: Start recording → **Refresh visuals** → copy query của **mọi visual trong bảng dưới**. Lưu vào `~/Downloads/bipro-c1/pa/`.

Card: mỗi trang chỉ cần 2 card, là card số đầu tiên bên trái ("Tiền vào", "Tổng giải ngân", "Tổng khách hàng") và card "Δ Label" ngay dưới nó.

### D1 · Giao dịch

| Tên file | Visual |
|---|---|
| `D1-slicer-nam.dax` | slicer thứ 1 (Năm/Quý/Tháng) |
| `D1-slicer-vung.dax` | slicer thứ 2 (Vùng/Bang/Chi nhánh) |
| `D1-slicer-loaigd.dax` | slicer thứ 3 (Loại GD/Nghiệp vụ) |
| `D1-slicer-loaithe.dax` | slicer thứ 4 (Loại thẻ) |
| `D1-slicer-nhomtuoi.dax` | slicer thứ 5 (Nhóm tuổi) |
| `D1-card-tienvao.dax` | card "Tiền vào" |
| `D1-card-tienvao-delta.dax` | card nhỏ ngay dưới "Tiền vào" (dòng Δ có màu) |
| `D1-line-thang.dax` | "Giá trị giao dịch biến động thế nào theo tháng?" (đã có PA-D1-1; copy lại để đối chiếu) |
| `D1-donut.dax` | "Tiền vào / ra theo nghiệp vụ và mục đích nào?" |
| `D1-matrix-gio-thu.dax` | "Giao dịch tập trung vào giờ nào, thứ nào?" |
| `D1-combo-dongtien.dax` | "Tiền vào, tiền ra và dòng tiền ròng biến động thế nào?" |
| `D1-combo-thauchi.dax` | "Rủi ro thấu chi và số dư bình quân ra sao?" |
| `D1-matrix-nhomtuoi.dax` | "Nhóm tuổi, địa bàn nào giao dịch nhiều nhất?" (đã có PA-D1-2; copy lại) |

Thêm: bấm nút bookmark "Tháng trong năm" (góc phải trên của matrix) để hiện line "Tháng nào trong năm giao dịch nhiều nhất?" → copy → `D1-line-thangtrongnam.dax`. Sau đó bấm nút "Giờ × Thứ" để trả lại như cũ.

### D2 · Khoản vay

| Tên file | Visual |
|---|---|
| `D2-slicer-1.dax` … `D2-slicer-6.dax` | 6 slicer, đánh số từ trái sang phải |
| `D2-card-giaingan.dax` | card "Tổng giải ngân" |
| `D2-card-giaingan-delta.dax` | card Δ ngay dưới |
| `D2-combo-thoigian.dax` | "Giải ngân thay đổi thế nào theo thời gian?" (đã có PA-D2-1; copy lại) |
| `D2-donut.dax` | "Danh mục cho vay phân bổ theo mục đích, kỳ hạn?" |
| `D2-100pct.dax` | "Chất lượng nợ A/B/C/D thay đổi theo năm giải ngân?" |
| `D2-shapemap.dax` | "Bang / chi nhánh nào cho vay nhiều, nợ xấu cao?" |
| `D2-bar-nhomtuoi.dax` | "Nhóm tuổi lúc vay nào có tỷ lệ nợ xấu cao?" (đã có PA-D2-2; copy lại) |
| `D2-combo-nhomkh.dax` | "Nhóm khách hàng nào vay nhiều, nợ xấu cao?" |

### D3 · Chăm sóc KH

| Tên file | Visual |
|---|---|
| `D3-slicer-1.dax` … `D3-slicer-6.dax` | 6 slicer, đánh số từ trái sang phải |
| `D3-card-khachhang.dax` | card "Tổng khách hàng" |
| `D3-card-khachhang-sub.dax` | card nhỏ ngay dưới |
| `D3-combo-kenh.dax` | "Khiếu nại thay đổi theo thời gian và kênh nào?" (đã có PA-D3-1; copy lại) |
| `D3-combo-pareto.dax` | "Vấn đề nào gây 80% khiếu nại?" |
| `D3-bar-sanpham.dax` | "Khiếu nại theo sản phẩm được xử lý tốt không?" (đã có PA-D3-2; copy lại) |
| `D3-combo-phanhoi.dax` | "Mỗi kênh được phản hồi ra sao, tranh chấp bao nhiêu?" |
| `D3-treemap.dax` | "Sản phẩm nào nhận nhiều khiếu nại nhất?" |
| `D3-bar-nhomkh.dax` | "Nhóm khách hàng nào khiếu nại nhiều?" |

**O-C9:** khi copy lại `D3-combo-kenh.dax`, mở bằng Notepad và xem dòng `VAR __DS0BodyLimited =` có dấu `\` ở cuối không. Ghi "có" hoặc "không" vào `~/Downloads/bipro-c1/ghichu.txt`.

## 3. ★ Kết quả của các truy vấn phức tạp (O-C2), khoảng 10 phút

Với từng file dưới đây: mở file `.dax` vừa lưu → **DAX query view** → tab mới → dán → **Run**.

Có truy vấn trả **nhiều bảng kết quả**. Khi đó dùng nút **"Result 1 of n ⌄"** để chuyển bảng, rồi **Copy** từng bảng và dán **nối tiếp** vào cùng một Notepad. Giữa hai bảng, gõ thêm một dòng `#RESULT 2` (rồi `#RESULT 3`…).

Lưu vào `~/Downloads/bipro-c1/results/` với cùng tên nhưng đuôi `.tsv`:

`D1-matrix-gio-thu`, `D1-donut`, `D1-combo-thauchi`, `D1-line-thangtrongnam`, `D2-donut`, `D2-100pct`, `D2-shapemap`, `D3-combo-pareto`, `D3-combo-phanhoi`, `D3-treemap`, `D3-bar-nhomkh`, `D1-slicer-nam`.

Nếu truy vấn báo lỗi khi chạy trong DAX query view: lưu thông báo thành `<tên>.error.txt`.

## 4. Slicer, lọc chéo, drill (O-C3, O-C4, O-C5, O-C12), khoảng 15 phút

Lưu vào `~/Downloads/bipro-c1/interact/`. Trước mỗi thao tác bấm **Clear** trong Performance analyzer, sau thao tác thì copy query của các visual được ghi.

| # | Thao tác | Copy query của | Lưu thành |
|---|---|---|---|
| 1 | D1, slicer Năm: mở dropdown, chọn **2016** | card "Tiền vào", "Giá trị giao dịch… theo tháng?" | `slicer1-card.dax`, `slicer1-line.dax` |
| 2 | Giữ Ctrl, chọn thêm **2017** | 2 visual như trên | `slicer2-card.dax`, `slicer2-line.dax` |
| 3 | Mở ▸ của 2016 trong dropdown, chỉ chọn **Q1** (bỏ 2017) | card "Tiền vào" | `slicer3-quy.dax` |
| 4 | Xoá lựa chọn slicer (biểu tượng tẩy ở đầu slicer). Sang **D2**, bấm **một cột** "35-49" của bar "Nhóm tuổi lúc vay nào có tỷ lệ nợ xấu cao?" | donut, combo "Giải ngân…", cột 100%, combo "Nhóm khách hàng…", card "Tổng giải ngân" | `xf-donut.dax`, `xf-combo.dax`, `xf-100pct.dax`, `xf-combo2.dax`, `xf-card.dax` |
| 5 | Chụp cả trang D2 lúc đang chọn cột đó | — | `shots/xf-D2.png` |
| 6 | Bấm vào chỗ trống trong bar để bỏ chọn. Combo "Giải ngân…": bật **drill mode** (mũi tên ↓ một nút ở góc trên visual), bấm cột **2016** | combo đó | `drill-down-2016.dax` |
| 7 | Bấm **Drill up** (↑), rồi **Expand all down one level** (↓↓ hai mũi tên phân nhánh) | combo đó | `drill-expand.dax` |
| 8 | Sang D1, matrix "Nhóm tuổi, địa bàn…": bấm **+** cạnh một vùng ở tiêu đề cột (nếu không thấy +, chuột phải tiêu đề cột → Expand → Selection) | matrix đó | `matrix-expand.dax` |

## 5. Drillthrough và tooltip (O-C6, O-C7), khoảng 5 phút

Trang "Chi tiết chi nhánh" nhận drillthrough theo 4 trường: `Dim_Account[branch_city]`, `Dim_Account[branch_state_name]`, `Dim_District[city]`, `Dim_District[state_name]`.

1. Sang D2, chuột phải **một bang** trên shape map "Bang / chi nhánh nào cho vay nhiều, nợ xấu cao?" → **Drill through → Chi tiết chi nhánh**. Nếu shape map không có menu này, thử matrix "Nhóm tuổi, địa bàn…" ở D1 (mở tới cấp Bang hoặc Chi nhánh). Không được ở đâu thì ghi vào `ghichu.txt`.
2. Chụp màn hình trang vừa mở → `shots/drillthrough.png`.
3. Trên trang đó: Clear → Refresh visuals → copy query của card **tiêu đề chi nhánh** (dòng chữ lớn trên cùng) và của line "Giá trị giao dịch theo tháng" → `interact/dt-title.dax`, `interact/dt-line.dax`.
4. Quay lại D2, rê chuột lên một cột của bar "Nhóm tuổi lúc vay…" cho hiện tooltip → chụp → `shots/tooltip-bar.png`.

## 6. Ảnh đối chiếu, bookmark, tương tác mặc định (O-C8, O-C10, O-C11), khoảng 10 phút

Lưu vào `~/Downloads/bipro-c1/shots/`:

1. Mỗi trang D1, D2, D3 ở trạng thái mặc định (không chọn gì, Fit to page). Ẩn các pane bên phải nếu được, để trang to nhất. → `page-D1.png`, `page-D2.png`, `page-D3.png`.
2. D1: **View → Selection** và **View → Bookmarks** mở cùng lúc → chụp → `panes-D1.png`. Bấm nút "Tháng trong năm" trên trang → chụp → `bookmark-thang.png`.
3. D2: chọn bar "Nhóm tuổi lúc vay…" → **Format → Edit interactions** → chụp cả trang (thấy các icon lọc/tô sáng/không ở góc mỗi visual) → `interactions-D2.png`. Bấm Edit interactions lần nữa để tắt.

## 7. Khi xong

Báo lại cho mình. Nếu có mục không làm được (không thấy menu, truy vấn lỗi…), chỉ cần ghi một dòng vào `ghichu.txt`; mình sẽ đổi cách đo.

Mình sẽ đọc các file trong `~/Downloads/bipro-c1/` (chỉ đọc), chép vào `docs/phase-c-evidence/observe-c1/`, rồi ghi phần quan sát vào `docs/phase-c-evidence/C1.md`.
