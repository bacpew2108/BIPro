# Việc bạn tự làm (buổi C2 và đợt A)

Cập nhật 2026-11-06. File dùng: `Nhom6_Dashboard.pbix`. Phần P (đợt 3) đã xong, kết quả ở cuối `VM-TODO-P.md`.

## A. Trên VM, Power BI Desktop (đợt A cần để khớp văn bản truy vấn)

| # | Việc | Lưu | BI Pro đang làm gì (nếu khác thì sửa) |
|---|---|---|---|
| A1 | Filters pane, thẻ `client_region` của một visual có cột này: đổi Filter type thành **Advanced**, "contains" `east`, Apply. Performance Analyzer: copy query của visual đó | `a1-advanced-contains.dax` | `CONTAINSSTRING(col, "east")` trong `FILTER(KEEPFILTERS(VALUES(col)), …)` |
| A2 | Như A1 với "starts with" `Mid`; rồi hai điều kiện "is `South`" **Or** "is `West`" | `a2-starts-with.dax`, `a2-or.dax` | `LEFT(col, 3) = "Mid"`; `OR(col = "South", col = "West")` |
| A3 | Cột số (`year`): Advanced "is greater than or equal to" 2014 **And** "is less than" 2017 | `a3-number.dax` | `AND(col >= 2014, col < 2017)` |
| A4 | Visual cấp bộ lọc **Top N**: Top 3, By value = `Trans Count`, Apply, copy query | `a4-topn.dax` | `col IN TOPN(3, FILTER(ALL(col), NOT(ISBLANK(m))), m, DESC)` (kết quả đúng nghĩa, văn bản có thể khác). Chỉ cấp visual có Top N |
| A5 | Cùng thẻ Top N: Bottom 3 | `a5-bottom.dax` | Như trên với ASC |
| B1 | Tạo bookmark **bật Data** (mặc định): đặt slicer `trans_type` = Credit và `year` = 2016, Add bookmark, Save. Gửi file `.pbix` đã lưu | `bookmark-data.pbix` | Đọc `explorationState.filters.byExpr` / `sections` / `visualContainers` theo schema PBIR; lựa chọn slicer ở `singleVisual.objects.general[0].properties.filter.filter`. Chưa có mẫu thật |
| B2 | Với bookmark ở B1, bấm ở trang khác rồi bấm bookmark: slicer và bộ lọc có về đúng như lúc lưu không? Bộ lọc không ghi trong bookmark có bị xoá không? | ghi chú | Đặt lại bộ lọc người dùng sửa ở phạm vi bookmark, áp phần đã lưu; bộ lọc trong file mà bookmark không nhắc giữ nguyên |

## B. Buổi C2: các mục [SUY ĐOÁN] của `C1.md` §2.6

Mỗi mục một ảnh (chụp riêng cửa sổ) và, nếu có truy vấn, một file `.dax` từ Performance Analyzer.

1. **Tương tác mặc định:** bấm một cột của bar Q2.5 (D2): treemap và các cột/bar khác bị **tô sáng** hay bị lọc? Line, matrix bị **lọc**? Slicer có bị lọc chéo không (danh sách slicer có đổi không)?
2. **Drill:** drill down và drill up trên donut D1 (Credit/Debit → nghiệp vụ → mục đích): truy vấn từng cấp, nhãn trục.
3. **Drillthrough:** chuột phải vào một điểm trên visual có drillthrough, vào trang đích; copy query của card ở trang đích.
4. **Tô sáng chéo:** ảnh và truy vấn của visual bị tô sáng khi bấm một điểm ở visual khác.
5. **Mở nút:** matrix cột (bấm +) và slicer hierarchy ở nhiều hơn một cấp; matrix mở theo hàng.
6. **Dự báo** của line D1 ("Dự báo 6 tháng"): ảnh gần, rê chuột vào vùng dự báo (tooltip), và nếu được, lọc về một năm xem có còn dự báo không (BI Pro ẩn dự báo khi có dưới 24 tháng).

## C. Việc khác

- **Quyết định E3:** chấp nhận hiệu năng hiện tại (combo thấu chi 2,15 s, matrix Giờ × Thứ 1,75 s) hay mở đợt riêng cho engine.
- **Bấm thử BI Pro** những gì đợt A thêm: thẻ bộ lọc Advanced/Top N, thêm field (ô "Thêm field dữ liệu vào đây"), nút × bỏ thẻ, bookmark.

## Kết quả (2026-11-07, file ở `~/Downloads/C2_A/`)

| Mục | Quan sát từ Power BI | BI Pro đã làm |
|---|---|---|
| A1, A2 (contains, không chứa) | `FILTER(KEEPFILTERS(VALUES(col)), SEARCH("east", col, 1, 0) >= 1)`; không chứa: `AND(SEARCH(...) >= 1, NOT(SEARCH("Mid", col, 1, 0) >= 1))`. Hai điều kiện hiện thành `AND(...)` | Văn bản đổi sang `SEARCH(...)`; engine thêm `SEARCH` (hoa thường không phân biệt, `?` `*` `~`, tham số not_found). "Starts with" và Or vẫn [SUY ĐOÁN] (file a2-starts-with thực ra là contains + không chứa; a2-or là chọn Basic South, West: `TREATAS({"South","West"}, col)`) |
| A3 | `FILTER(KEEPFILTERS(VALUES('Dim_Date'[year])), AND(year >= 2014, year < 2017))` | Khớp văn bản đang sinh |
| A4, A5 | Top N là bảng nửa nối trong `SUMMARIZECOLUMNS`: `__SQDS0BodyLimited = TOPN(3, SUMMARIZECOLUMNS(col, "m", measure), [m], 0)` (Bottom: tham số cuối `1`), đưa vào lõi như một bảng lọc | Kết quả đúng nghĩa (đã test); văn bản khác (`col IN TOPN(...)`). Chỉ lệch khi so golden theo văn bản |
| B1, B2 | Bookmark có Data ghi `explorationState.filters.byExpr`, `sections.<trang>.visualContainers.<id>.filters.byExpr` và **lựa chọn slicer ở `singleVisual.objects.merge.general[0].properties.filter.filter`** (không phải `objects.general`). Thẻ không đổi chỉ có `name`, `type`, `expression` (không có `filter`). Slicer ở "Tất cả" thì không có `general`. Slicer hierarchy (Năm › Quý) ghi lựa chọn là giá trị cấp Năm: `year IN {2016L}` | Đã sửa đọc `objects.merge.general`; slicer hierarchy quy cấp về cột. Test dùng chính `bookmark-data.pbix` (trans_type = Credit, năm = 2016 khôi phục đúng, slicer khác về Tất cả) |
| C2-1 (`b1.png`) | Bấm cột Q2.5: card, bản đồ, matrix lọc; donut, 100% và combo tô sáng; slicer không đổi | Khớp mặc định hiện có (`C1.md` §2.6). Ghi chú của bạn nói Q2.1 "bị lọc", nhưng ảnh cho thấy cột có phần đậm = tô sáng như combo đã xác nhận; giữ tô sáng |
| C2-2 (q1.2-1..3) | Drill donut mỗi cấp là một truy vấn `ROLLUPADDISSUBTOTAL(col)` độc lập (trans_type, operation, trans_purpose), không kèm bộ lọc cấp cha: đây là "đi xuống cấp kế" (next level), không phải drill-down vào một giá trị | Khớp `nextLevel` |
| C2-3 (`b_c2_3.dax`) | Trang đích drillthrough: `TREATAS({"Wyoming"}, 'Dim_District'[state_name])` đứng đầu, rồi bộ lọc báo cáo | Khớp |
| C2-4, C2-5 (`q1.6`, `b5-1`, `b5-2`) | Matrix mở nút theo cột: lõi thêm `ROLLUPADDISSUBTOTAL(branch_region, "IsGrandTotalColumnTotal", branch_state_name, "IsDM2Total", branch_city, "IsDM4Total")`; bộ lọc mở nút nằm trong `__DS0CoreWithInstanceFilters` (OR theo cấp: `[IsGrandTotalColumnTotal]`, `AND(NOT(..), [IsDM2Total])`, `AND(NOT([IsDM2Total]), branch_region IN {"Midwest"})` …). Ảnh `b5.png`: Midwest mở xuống Iowa, mở tiếp Des Moines; có cột Total ở mỗi nút đã mở | Chưa làm nhiều cấp (mở nút hiện chỉ một cấp); đây là mẫu cho mục "mở nút nhiều cấp" |
| C2-6 (b6-1..6) | Dự báo 6 tháng của line D1 (Trans Amount theo tháng): tháng cuối thật Dec 2018 = 171.697.094 thì dải = đúng giá trị (rộng 0). Dự báo (Power BI): Jan 165,2M [142,9M–187,5M]; Feb 148,6M; Mar 156,9M; Apr 160,5M; Jun 199,6M [174,0M–225,2M]. Tooltip ở vùng dự báo: tiêu đề tháng, tên dự báo, Upper bound, Lower bound; ở điểm neo thêm "Giá trị GD" và "Số GD" | BI Pro: 188 / 134 / 155 / 157 / 163 / 216 (triệu); độ rộng dải 42–51M so với 44,6–51,2M của Power BI. Tooltip vùng dự báo làm theo mẫu. Số từng tháng chưa khớp (Power BI san mùa vụ mạnh hơn, Jan thấp hơn Jan 2018); thuật toán không công bố, thử ETS (statsmodels) các dạng AAA/AAM cũng không khớp |
