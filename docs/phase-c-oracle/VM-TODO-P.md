# Việc cần làm trên VM cho đợt 3 (gói P: Filters pane, Selection pane, Bookmarks)

Bạn làm tay trong Power BI Desktop trên VM, không gấp: đợt 3 đã chạy được bằng giả định ghi ở cột "BI Pro đang làm gì". Làm xong thì báo, mình sửa theo (gộp vào buổi C2). File dùng: `Nhom6_Dashboard.pbix`, trang D1.

| # | Việc trên Power BI | Lưu | BI Pro đang làm gì (nếu khác thì sửa) |
|---|---|---|---|
| P1 | Filters pane, trang D1, mở thẻ `year` (bộ lọc report "không phải 9999"): chụp danh sách giá trị. Các giá trị khác 9999 có được đánh dấu không? Có ô "Select all" không? Có "Require single selection" không? | `p1-year-basic.png` | Hiện danh sách giá trị với chế độ "là / không phải"; thẻ `không phải 9999` hiện 9999 được đánh dấu ở chế độ "không phải" [SUY ĐOÁN] |
| P2 | Ở thẻ `year`, bỏ chọn 9999 rồi chọn chỉ 2016. Mở Performance Analyzer, Refresh, copy query của card "Tiền vào" | `p2-year2016-card.dax` | Bộ lọc report thành `year IN {2016}`, giữ vị trí cũ trong danh sách bộ lọc, các visual nạp lại |
| P3 | Ở thẻ `client_region`: chọn "Select all" rồi copy query của một card | `p3-region-all-card.dax` | Chọn tất cả = bỏ bộ lọc, không sinh bảng lọc cho cột đó. Cần xem Power BI có giữ lại một bảng lọc rỗng không |
| P4 | Chọn visual bar ở D2, mở thẻ một field trong Filters pane (thẻ ngầm "là (Tất cả)"), chọn 1 giá trị, copy query của chính visual đó và một visual khác | `p4-visual-filter-*.dax` | Thẻ ngầm thêm bộ lọc cấp visual, chỉ áp cho visual đó, đứng trước bộ lọc report |
| P5 | Filters pane, matrix D1, thẻ `trans_hour` (bộ lọc visual có sẵn): chụp, mở xem là kiểu gì (Basic hay Advanced) | `p5-trans-hour.png` | Nếu không phải `In/Not In` thì BI Pro chỉ hiện, chưa sửa được |
| P6 | Selection pane: ẩn matrix (bấm mắt), rồi bấm bookmark "Q1.3 · Giờ × Thứ". Matrix có hiện lại không? Rồi ẩn tay line ở bookmark "Tháng trong năm", bấm lại bookmark đó: line có hiện lại không? | ghi chú, `p6-*.png` | Bookmark ghi đè ẩn/hiện của đúng 6 visual đích, visual ngoài danh sách giữ nguyên |
| P7 | Bấm bookmark đang ở trang khác (D2): có nhảy về D1 không? (cả hai bookmark có `suppressActiveSection`) | ghi chú | Không chuyển trang khi `suppressActiveSection`; ngược lại thì chuyển |
| P8 | Performance Analyzer, Start recording, bấm bookmark "Tháng trong năm": visual nào chạy truy vấn lại (line, matrix, hay không cái nào)? | `p8-bookmark-pa.png` hoặc ghi chú | Visual vừa hiện thì chạy truy vấn, visual vừa ẩn thì không; cache theo văn bản DAX nên bấm lại là tức thì |
| P9 | Bấm nút "Giờ × Thứ" / "Tháng trong năm" trên canvas ở chế độ đọc (Reading view): có cần Ctrl+click không? | ghi chú | Bấm thường là áp bookmark |
| P10 | Bấm một slicer chọn 2016, rồi bấm bookmark "Tháng trong năm": slicer có bị đổi không? (suppressData nên lẽ ra không) | ghi chú | Không đụng slicer và lọc chéo |

## Việc bạn tự bấm thử trong BI Pro (không cần VM)

Mình chưa bấm được giao diện này (không có công cụ điều khiển chuột trong phiên). Khi mở `build/BI Pro.app` với `Nhom6_Dashboard.pbix`, trang D1:

1. Bộ lọc → thẻ `year` → bấm mở: có danh sách giá trị; chọn 2016 thì card và chart đổi số; "Đặt lại" thì về như cũ.
2. Chuyển "là / không phải"; ô tìm kiếm lọc danh sách; "Chọn tất cả" bỏ lọc.
3. Chọn một visual, mở thẻ field của visual, chọn giá trị: chỉ visual đó đổi.
4. Xem → Lựa chọn: bấm mắt ẩn/hiện từng visual; canvas cập nhật; chân pane đếm số visual ẩn.
5. Xem → Bookmark: bấm hai bookmark, matrix và line đổi chỗ như `bookmark-thang.png`; bookmark vừa bấm được tô; bấm nút "Giờ × Thứ" trên canvas cũng đổi.

## Kết quả (2026-11-06, bạn làm tay; file ở `~/Downloads/VM-P/`)

| # | Kết quả | So với giả định của BI Pro |
|---|---|---|
| P1 | Thẻ `year`: Filter type = Basic (có thêm Advanced), "Select all" ba trạng thái (■), có ô "Require single selection". `Not In 9999` hiện mọi năm khác 9999 được đánh dấu. Thẻ `client_region` thêm ô tìm kiếm (danh sách ngắn) | Khớp ý. BI Pro dùng nút "là / không phải" thay cho đánh dấu phần bù; chưa có Advanced, Require single selection |
| P2 | `year` = 2016 sinh `TREATAS({2016}, Dim_Date[year])`; thẻ `client_region` giữ nguyên dạng `FILTER(KEEPFILTERS(VALUES(..)), NOT(.. IN {"Unknown"}))` | Khớp về ngữ nghĩa. Văn bản DAX của bộ lọc người dùng sửa (`col IN {..}`) chưa trùng `TREATAS`; chỉ ảnh hưởng nếu so golden theo văn bản |
| P3 | Select all: không còn bảng lọc nào cho cột (truy vấn thành `ROW(..)` trần, không có `client_region`) | Khớp: bỏ bộ lọc |
| P4 | Bộ lọc cấp visual `South` = `TREATAS({"South"}, Dim_Client[client_region])` đứng thành VAR | Khớp |
| P5 | `trans_hour` ở matrix: "Giờ is not 17:00", Basic filtering | Khớp (`Not In`, sửa được) |
| P6 | Ẩn tay rồi bấm bookmark: visual hiện lại hết | Khớp |
| P7 | Bookmark khi đang ở D2 không chuyển về D1 | Khớp (`suppressActiveSection`) |
| P8 | Chỉ line ("Tháng nào trong năm…", 82 ms) chạy lại, cộng hai Button (12 ms); matrix vừa ẩn không chạy | Khớp |
| P9 | Ở Power BI Desktop nút cần Ctrl+click | Khác: BI Pro bấm thường là áp bookmark (chế độ xem). Giữ nguyên, vì BI Pro là viewer |
| P10 | Slicer không đổi | Khớp |

Bấm thử trong BI Pro: mục 1, 2, 4, 5 đạt. **Mục 3 không đạt**: chọn một visual rồi chọn giá trị ở thẻ cấp visual thì visual không đổi, và sau 1–2 lần bấm thẻ thì mọi biểu đồ đứng im. Mình đã kiểm cấp engine (test `boLocCapVisualTrenMoiThe`: mọi thẻ cấp visual của D1, đặt một giá trị rồi nạp lại, 12 visual đều ra số trong 0,01–0,31 s), nên lỗi nằm ở lớp giao diện. Chưa tái hiện được vì tự bấm app cần quyền Accessibility.

Ghi chú: `NewMeasure.txt` (Define new measure) vẫn trống ("Measure = ").
