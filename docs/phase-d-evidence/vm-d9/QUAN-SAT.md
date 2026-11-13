# VM-D9: sáu mục còn lại của D3b/D4/D6 (2026-11-14)

Bạn cho phép dùng VM. Claude điều khiển Power BI Desktop (bản sao `Nhom6_work.pbix` trong VM, đã xoá; chỉ thao tác giao diện, lưu, đọc diff `visual.json`). Mẫu: `json/` (chuỗi s1 đến s5 nối tiếp nhau trên cùng visual `c36625920078b7e0c75a`, biểu đồ đường "Giá trị giao dịch…" của D1).

## 1. Đổi đường → cột (`json/s1.visual.json`)

Chọn biểu đồ đường (Category `Dim_Date[month_start]`, không có `sortDefinition`) rồi bấm "Clustered column chart": `visualType` đổi, `query.sortDefinition` **mới**: `[{field: Column Dim_Date.month_start, direction: "Ascending"}]` với `isDefaultSort: true`. Cột Category giữ `active: true`. Khoá `objects.forecast` (chỉ có ở đường) bị bỏ; các khoá còn lại giữ (khớp `TypeChange.keepsObjectKey`). `$schema` nâng lên 2.14.0.

## 2. Màu cho giá trị Chú giải chưa có mục (`json/s2.visual.json`)

Kéo `Dim_Trans_Type[trans_type]` vào ô Legend (vai trò `Series`, projection không có `displayName`). Thẻ Columns > "Apply settings to" > Series liệt kê `All`, `Credit`, `Debit`. Chọn Credit rồi đổi màu (theme màu 3) **tạo mới** `objects.dataPoint[0]`:
`{"properties":{"fill":{"solid":{"color":{"expr":{"ThemeDataColor":{"ColorId":3,"Percent":0}}}}}},"selector":{"data":[{"scopeId":{"Comparison":{"ComparisonKind":0,"Left":{"Column":{"Expression":{"SourceRef":{"Entity":"Dim_Trans_Type"}},"Property":"trans_type"}},"Right":{"Literal":{"Value":"'Credit'"}}}}}]}}`.
Cùng cấu trúc BI Pro đã đọc ở VM-D8c; Debit không có mục. Cùng lần lưu Desktop thêm `filterConfig.filters` cho mọi trường trong visual (Category `Categorical`, mỗi measure `Advanced`, chưa có `filter`).

## 3. Bộ lọc Advanced trên measure (`json/s3.visual.json`)

Thẻ của measure `Trans Amount` > "is greater than" 50000000 > Apply: thẻ `type: "Advanced"` có `filter` dạng `Comparison` `ComparisonKind: 1`, vế trái `Measure` (`From` chỉ có `Fact_Transaction` bí danh `f`), vế phải `Literal "50000000L"` (số nguyên → `L`, measure không dùng `D`). Bấm nhầm biểu tượng khoá của thẻ thì thẻ có `isLockedInViewMode: true`; bấm mở bảng Filters đổi một cờ Literal trong `report.json`.

## 4. Bottom N (`json/s4.visual.json`)

Thẻ `month_start` > Filter type "Top N" > Show items "Bottom" 3 > By value `Trans Amount` > Apply: `type: "TopN"`, `filter.From` = truy vấn con (`Name:"subquery"`, `Type:2`, `Select` cột tên `field`, `OrderBy` `Direction: 1` (Bottom; Top là 2), `Top: 3`, `From` gồm `Dim_Date` `d` và `Fact_Transaction` `f`) rồi `Dim_Date` `d`; `Where` là `In` bảng `subquery`. **Giống từng chi tiết** với `PBIRFilterPatch.topNFilter(bottom: true)`. Danh sách "By value" liệt kê dữ liệu của visual (cột và measure), không phải mọi measure của mô hình.

## 5. Cột ngày vào X-axis (`json/s5.visual.json`)

Bỏ `month_start` khỏi X-axis rồi tick `Dim_Date[full_date]`: Category là `Column` thường (`queryRef Dim_Date.full_date`, `nativeQueryRef full_date`, `active: true`, không `displayName`), **không có phân cấp** (mô hình Nhom6 có bảng ngày riêng). `sortDefinition` mặc định tự chuyển sang cột mới (vẫn Ascending, `isDefaultSort: true`). Thẻ lọc của trường đã bỏ khỏi ô (`month_start` TopN) vẫn còn và nay có `howCreated: "User"`; thẻ mới cho `full_date` thêm `Categorical`.

## 6. Nhãn danh mục xoay dọc quá dài (ảnh `desktop-pareto-d3-380.png`, `…-220.png`)

Pareto D3 (38 vấn đề, tên tới ~50 ký tự). Desktop **cắt nhãn bằng "…"**: ở cao 380 còn ~19 ký tự (vùng nhãn ≈ 40% chiều cao visual); ở cao 220 còn ~8 ký tự (≈ 32%). Hai điểm khớp "vùng nhãn ≈ 50% chiều cao vùng chart" (BI Pro đo H = 292 và 132): `CategoryLabelFit.heightShare` đổi 0,3 → 0,5.

## Không quan sát được

Cột tiền tệ (`decimal`) cho thẻ Advanced: Nhom6 chỉ có cột `double` (`amount`, `balance_after`, `loan_amount`, `monthly_payment`), không có cột tiền tệ; cần file khác.
