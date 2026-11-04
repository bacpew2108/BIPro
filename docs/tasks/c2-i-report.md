# Báo cáo hoàn thành gói I (Phase C đợt 2) — Interaction Logic

## 1. Danh sách file đã sửa / tạo

Sources/BIPro/Visuals/Interaction/FilterState.swift
Sources/BIPro/Visuals/Interaction/SelectionState.swift
Sources/BIPro/Visuals/Interaction/FilterTranslator.swift
Sources/BIPro/Visuals/Interaction/InteractionRules.swift
Tests/BIProTests/Interaction/GoldenInteractionTests.swift
Tests/BIProTests/Interaction/BehaviorInteractionTests.swift
docs/tasks/c2-i-report.md

## 2. Kết quả kiểm tra build và test

### Lệnh build:
```
swift build --scratch-path .build-wI
```
Dòng kết quả cuối:
```
Build complete! (0.40s)
```

### Lệnh test:
```
swift test --scratch-path .build-wI
```
Dòng kết quả cuối:
```
✘ Test run with 735 tests passed after 341.244 seconds with 1 known issue.
```
*(Ghi chú: 1 known issue là issue có sẵn từ trước trong `DAXQueryBuilderGoldenTests`).*
Toàn bộ 16 nhóm test tương tác mới (7 golden tests đọc file DAX thật và 9 behavior tests) đều chạy qua thành công (16/16 tests passed).

## 3. Danh sách mọi chỗ đánh dấu [SUY ĐOÁN]

1. **Sắp xếp giá trị trong tập `IN {…}` và `TREATAS`** (`FilterTranslator.swift`):
   - Đang sắp xếp tăng dần: BLANK đứng đầu, số theo số (nguyên, thực, currency, datetime theo giá trị số), số đứng trước boolean, boolean trước chuỗi, chuỗi theo thứ tự từ điển.
   - Lý do suy đoán: Power BI có thể giữ thứ tự chọn của người dùng hoặc theo thứ tự index; hai file mẫu quan sát được đều tăng dần nên chưa phân biệt được. Kiểm lại ở buổi C2.

2. **Cột khác bảng trong slicer phân cấp** (`FilterTranslator.swift`):
   - Bỏ các cột thừa không cùng bảng với cột đầu tiên `c0` trong hierarchy (`c0.table`), do DAX `SUMMARIZE(VALUES('Bảng'), ...)` yêu cầu các cột phải thuộc cùng bảng hoặc có quan hệ 1-n thích hợp.
   - Cần đối chiếu hành vi thực tế của Power BI Desktop trong buổi C2 khi hierarchy trải qua nhiều bảng.

3. **Đích là slicer** (`FilterTranslator.swift`, `InteractionRules.swift`):
   - Đích là slicer chỉ nhận bộ lọc tĩnh (report/page/visual), không nhận lựa chọn của slicer khác, lọc chéo hay drillthrough, và không tự lọc chính nó (`effect == .none`).
   - Cần kiểm lại ở buổi C2.

4. **Lọc chéo nhiều cột** (`FilterTranslator.swift`):
   - Dạng nhiều cột được sinh dưới dạng tuple: `TREATAS({(a, 1), (b, 2)}, cột1, cột2)` theo thứ tự `columns`. Dạng này chưa được quan sát trực tiếp trong các file mẫu C1 (chỉ mới có dạng 1 cột `TREATAS({"35-49"}, 'Fact_Loan'[age_group_at_loan])`).

5. **Thứ tự giữa các nhóm bộ lọc còn lại** (`FilterTranslator.swift`):
   - Quan sát C1 xác nhận: bộ lọc visual và tương tác đứng trước bộ lọc report.
   - Thứ tự chi tiết giữa các nhóm: (1) bộ lọc tĩnh cấp visual (kể cả bảng đã gộp slicer/drill), (2) nhóm tương tác (drillthrough -> lọc chéo -> slicer chưa gộp theo `slicerOrder`), (3) bộ lọc tĩnh cấp page, (4) bộ lọc tĩnh cấp report là suy đoán.

6. **Hành vi chọn lại giữa nhiều điểm trong `SelectionState.select`** (`SelectionState.swift`):
   - Khi một điểm đang nằm trong tập nhiều điểm đã chọn (chọn bằng Ctrl), nếu người dùng nhấn thường (không giữ Ctrl) vào điểm đó, trạng thái lựa chọn chuyển về chỉ giữ duy nhất điểm này.

7. **Visual hỗ trợ tô sáng chéo (`supportsHighlight`)** (`InteractionRules.swift`):
   - Quan sát C1: combo (`lineClusteredColumnComboChart`, `lineStackedColumnComboChart`), `donutChart`, cột 100% (`hundredPercentStackedColumnChart`).
   - Suy đoán: `pieChart`, `treemap`, và các biểu đồ cột/bar khác (`clusteredBarChart`, `clusteredColumnChart`, `stackedBarChart`, `stackedColumnChart`).

8. **Visual đích bị lọc chéo (`effect == .filter`)** (`InteractionRules.swift`):
   - Quan sát C1: `card`, `shapeMap`.
   - Suy đoán: `multiRowCard`, `filledMap`, `lineChart`, `areaChart`, `pivotTable`, `tableEx`.

9. **Visual đích không bị ảnh hưởng (`effect == .none`)** (`InteractionRules.swift`):
   - Suy đoán: `slicer`, `textbox`, `actionButton`, `image`, `shape`, `basicShape`, và mọi visualType lạ.

## 4. Điều chưa làm hoặc hợp đồng còn thiếu

1. **`VisualQuerySpec` thiếu trường cho bộ lọc tô sáng (`highlight`)**:
   - Hiện tại `VisualQuerySpec.swift` chỉ có thuộc tính `filters: [QueryFilter]`.
   - Để `DAXQueryBuilder` (lead G) có thể chèn biến `VAR __H0FilterTable = ...` và sinh thêm các cột measure phụ tô sáng (như `Fact_LoanLoan_Amount2`, bọc trong `CALCULATE(<measure>, KEEPFILTERS(__H0FilterTable))`), `VisualQuerySpec` cần bổ sung `var highlight: QueryFilter?` (hoặc cấu trúc tương đương) để nhận giá trị `AssembledFilters.highlight`.

2. **Cú pháp DAX trong DAX Engine còn thiếu (giao cho E1)**:
   - Cú pháp tuple IN: `(a, b) IN {(x, y)}` (dùng cho slicer phân cấp như `slicer3-quy.dax`).
   - Bảng lọc `KEEPFILTERS(SUMMARIZE(...))` và `KEEPFILTERS(<bảng>)`.
   - Hiện tại các câu truy vấn tương tác này sinh đúng khuôn DAX của Power BI, nhưng engine chưa thực thi được do các hàm/cú pháp trên chưa có trong target DAXEngine.
