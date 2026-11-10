# Quan sát VM-D2 (bạn làm tay 2026-11-10, Claude đọc)

File: `R-D2-*.pbix`, `R-D2-*-query.txt`, `ghichu.txt`, `7_G.png`. So với `Nhom6_work.pbix`. Desktop khi lưu còn: nâng `$schema` visual lên 2.14.0, đánh lại `z` và `tabOrder` toàn trang, đổi thứ tự khoá phần tử (`active` trước `displayName`), và **tự thêm `filterConfig`** (thẻ lọc không điều kiện) cho các trường của visual. BI Pro không cần bắt chước các thay đổi này.

| Mục | Quan sát | Nguồn |
|---|---|---|
| Cột số vào card | Card mới (`cardVisual`): kéo cột `amount` vào ô giá trị không được; vào ô "Categories" (khoá `Rows`) thì thành danh sách (`DISTINCT`, `TOPN 21`); không có Sum | `R-D2-a-card-numeric`, `ghichu.txt` 1, 3 |
| Phép gộp | **Chưa quan sát được**: người làm không kéo được `amount` vào ô giá trị của biểu đồ cột (ghichu 4, 5), nên không có file `Aggregation`; `Nhom6` không có mẫu | `ghichu.txt` 2, 4, 5 |
| Bỏ trường có định dạng riêng | Desktop **không chặn**; xoá mục `objects.<tên>[]` có `selector.metadata` = `queryRef` của trường (cả `columnWidth` lẫn `values` có `FillRule`); mục không có selector giữ | `R-D2-f-remove-filter`, `R-D2-f-remove-format` |
| Bỏ trường có thẻ lọc cấp visual | Không chặn; thẻ lọc (`filterConfig`) **giữ nguyên** và bộ lọc vẫn áp (truy vấn còn `__DS0FilterTable3`); thêm `"howCreated":"User"` | `R-D2-f-remove-filter(-query)` |
| Bỏ trường là ô cuối của Category | Khoá ô bị xoá khỏi `queryState`; Desktop ghi `sortDefinition` mặc định (measure giảm dần, `isDefaultSort:true`) | `R-D2-f-remove-sort`, `R-D2-g-empty-well` |
| Bỏ trường có `sortDefinition` tường minh | Chưa quan sát (bản gốc không có sắp xếp tường minh ở các visual đã thử): BI Pro vẫn chặn trường hợp này | |
| Ô trống | Khoá ô bị xoá, không để `projections` rỗng | `R-D2-g-empty-well` |
| Thêm trùng | Desktop **cho** thêm cùng measure hai lần vào một ô (hai phần tử cùng `queryRef`); truy vấn chỉ tính một cột (`"Loan_Amount2"` một lần) | `R-D2-h-dup(-query)` |
| Chuyển ô | Phần tử sang **cuối** ô đích, giữ nguyên | `R-D2-h-move` |
| Đổi thứ tự | Đổi chỗ phần tử trong ô | `R-D2-h-reorder` |
| Đổi tên cho visual này | Ghi **cả** `displayName` và `nativeQueryRef` = tên mới; `queryRef` giữ; tên cột trong truy vấn DAX không đổi | `R-D2-h-rename(-reset)(-query)` |
| Ô chưa kiểm của Build pane | Không có quan sát mới cho loại cũ (mục E không lưu file) | |

## Bổ sung (2026-11-10, Claude điều khiển VM): phép gộp

Cột số vào ô giá trị: Desktop **từ chối** ở mô hình Nhom6 với thông báo "This field can't be used here because the data model has discourage implicit measures property enabled, and a measure is required here" (ảnh `vm-d2b-discourage-implicit-measures.png`). Cờ `DiscourageImplicitMeasures` = 1 trong `metadata.sqlitedb` của Nhom6. Tick cột `amount` thì Desktop đặt nó vào ô trục X (danh mục), không vào ô giá trị. Vì vậy **không có phép gộp ngầm ở Nhom6**; BI Pro từ chối đúng như Desktop (`WellRules.aggregationReason`). Phép gộp cho mô hình không đặt cờ này chưa quan sát.
