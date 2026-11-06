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
