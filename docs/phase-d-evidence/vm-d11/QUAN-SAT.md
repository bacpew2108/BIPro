# VM-D11: phân cấp ngày và Category kiểu số (2026-11-14)

Bạn cho phép dùng VM. Claude điều khiển Power BI Desktop (bản sao `Nhom6_work.pbix` trong VM, đã xoá). Mẫu: `json/` (biểu đồ đường "Giá trị giao dịch…" của D1, `c36625920078b7e0c75a`; s1 → s2 → s3 nối tiếp).

## 1. Phân cấp ngày vào X-axis (`json/s1.visual.json`)

Bỏ `Dim_Date[month_start]` rồi tick phân cấp `Dim_Date` > "Thời gian" (Năm, Quý, Tháng, Ngày) trong ngăn Dữ liệu: ô `Category` nhận **bốn projection `HierarchyLevel` theo thứ tự cấp**, mỗi cái:
`{"field":{"HierarchyLevel":{"Expression":{"Hierarchy":{"Expression":{"SourceRef":{"Entity":"Dim_Date"}},"Hierarchy":"Thời gian"}},"Level":"Năm"}},"queryRef":"Dim_Date.Thời gian.Năm","nativeQueryRef":"Thời gian Năm","active":true}`
**cả bốn cấp đều `active: true`** (khác cột thường: cột đầu `true`, các cột sau `false`). Không thêm `sortDefinition`, `objects` không đổi. Tick lại hàng phân cấp thì gỡ cả bốn cấp.

## 2. Category kiểu số (`json/s2`, `json/s3`)

Sau khi gỡ phân cấp, visual chỉ còn measure: Desktop tự thêm `sortDefinition` giảm dần theo measure (quy tắc "chỉ measure" đã có ở BI Pro). Thêm `Dim_Date[year]` (số nguyên) vào `Category`: sắp xếp giữ nguyên (khớp VM-D8c); đổi sang Clustered column (s3): sắp xếp vẫn giữ, không đổi gì thêm. Chưa tách được "Category số khi đổi loại" khỏi quy tắc có sẵn nên không đổi code.

## Không quan sát

Đích combo/vùng khi đổi loại; giá trị thẻ Format từng visual (vùng quá rộng, cần chọn mẫu cụ thể).
