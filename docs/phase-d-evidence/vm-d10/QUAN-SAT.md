# VM-D10: màu theo điểm dữ liệu, đổi loại với Category chữ, cột tiền tệ (2026-11-14)

Bạn cho phép dùng VM. Claude điều khiển Power BI Desktop (bản sao `Nhom6_work.pbix` trong VM, đã xoá; chỉ thao tác giao diện, lưu, đọc diff `visual.json`). Mẫu: `json/` (visual Q3.6 của D3, `1106a6e5b10c0fc7f175`; s1 → s2 → s3 nối tiếp).

## 1. Đổi bar → cột nhóm với Category chữ (`json/s1.visual.json`)

Q3.6 (`clusteredBarChart`, Category `Dim_Client[age_group_current]` chữ, có Chú giải, không có `sortDefinition`) đổi sang Clustered column: `visualType` đổi, ô `Tooltips` giữ, `dataPoint` giữ, **không thêm `sortDefinition`**. Khớp quy tắc của BI Pro (chỉ cột ngày mới được thêm sắp tăng dần theo Category; VM-D9 mục 1).

## 2. Màu theo điểm dữ liệu (`json/s2.visual.json`)

Bỏ trường Chú giải (còn Category + một measure) thì thẻ Columns > "Apply settings to" đổi nhãn thành **Categories** và liệt kê giá trị của Category (`<25`, `25-34`, …). Chọn `25-34` rồi đổi màu (theme màu 3) **tạo mục `dataPoint` mới**:
`{"properties":{"fill":{"solid":{"color":{"expr":{"ThemeDataColor":{"ColorId":3,"Percent":0}}}}}},"selector":{"data":[{"scopeId":{"Comparison":{"ComparisonKind":0,"Left":{"Column":{… "Entity":"Dim_Client" … "Property":"age_group_current"}},"Right":{"Literal":{"Value":"'25-34'"}}}}}]}}`.
Cùng dạng với màu theo giá trị Chú giải (VM-D9 mục 2), chỉ khác cột so sánh là cột Category. Mục `dataPoint` của giá trị Chú giải cũ (Female, Male) vẫn còn trong file. Chưa quan sát: chart có Chú giải (điểm = chuỗi × danh mục), nhiều measure, loại khác.

## 3. Bộ lọc Advanced trên cột tiền tệ (`json/s3.visual.json`)

Đổi `Fact_Loan[monthly_payment]` sang "Fixed decimal number" ở Table view (hộp thoại "Data type change" > Yes; chỉ trên bản sao), thêm vào Visual-level filters (thẻ `Advanced`), "is greater than" 1500: toán hạng `Right.Literal.Value` = **`1500M`**. Vậy: số nguyên `…L`, số thực `…D`, tiền tệ `…M`.

## Quan sát phụ

- Menu chuột phải của trường có "Add to filters" > Visual-level / Page-level / Report-level filters (không có menu chọn ô cho Legend).
- Mở bảng Filters đổi một cờ Literal trong `report.json` (như VM-D9).
